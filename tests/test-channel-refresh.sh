#!/usr/bin/env bash
# Refresh is what moves an installation between series, so it has to move the
# toolchain and not just the repositories it reads.
#
# Before this, refresh reapointed the repositories and wrote the selection, and
# the compiler stayed where it was: `vdpm status` then named a series whose
# toolchain was not installed, which is the one failure a package client must
# never produce.

set -euo pipefail

directory=$(cd "$(dirname "$0")/.." && pwd -P)
build=${VDPM_TEST_BUILD_DIR:-}
[[ -n $build ]] || { echo "set VDPM_TEST_BUILD_DIR to a directory with vdpm" >&2; exit 77; }
[[ -x $build/vdpm ]] || { echo "missing vdpm in $build" >&2; exit 77; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/bin/include" "$root/var/lib/vdpm" "$root/etc"
printf '[options]\n' > "$root/etc/pacman.conf"
printf '{"channel":"2026.08","sequence":1,"core":{"release":"core-1"},"packages":{"release":"packages-1"}}\n' \
	> "$root/var/lib/vdpm/channel.json"

# Stands in for the helper: verifies nothing, stages what a real refresh would
# have staged.
cat > "$root/bin/include/refresh-repositories.sh" <<'EOF'
#!/bin/sh
printf '{"channel":"%s","sequence":9,"core":{"release":"core-9"},"packages":{"release":"packages-9"}}\n' \
	"$1" > "$VITASDK/var/lib/vdpm/channel.json.staged"
printf 'refreshed %s channel sequence 9\n' "$1"
EOF
chmod +x "$root/bin/include/refresh-repositories.sh"

pacman_stub() {
	cat > "$root/bin/pacman" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$root/pacman-arguments"
exit $1
EOF
	chmod +x "$root/bin/pacman"
}

selected_channel() {
	sed -n 's/.*"channel":"\([^"]*\)".*/\1/p' "$root/var/lib/vdpm/channel.json"
}

failures=0
check() {
	if [[ $2 == "$3" ]]; then
		printf 'ok: %s\n' "$1"
	else
		printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2" >&2
		failures=$((failures + 1))
	fi
}

# --- the transaction succeeds: the series is selected --------------------
pacman_stub 0
VITASDK=$root "$build/vdpm" refresh nightly > "$root/output" 2>&1
check 'the selection is committed' "$(selected_channel)" nightly
check 'nothing is left staged' \
	"$(test -e "$root/var/lib/vdpm/channel.json.staged" && echo present || echo absent)" absent

arguments=$(tr '\n' ' ' < "$root/pacman-arguments")
case $arguments in
	*--sync*--sysupgrade*--sysupgrade*) result=asked ;;
	*) result="$arguments" ;;
esac
check 'the move is a sysupgrade that may go backwards' "$result" asked
case $arguments in
	*--refresh*) result=refetched ;;
	*) result=kept ;;
esac
# The databases in the sync directory are the ones the signed manifest named
# and vdpm hashed; fetching them again would replace them with unverified
# copies from the same servers.
check 'the verified databases are not fetched again' "$result" kept

# --- the transaction fails: the series is not selected -------------------
pacman_stub 1
set +e
VITASDK=$root "$build/vdpm" refresh 2026.09 > "$root/output" 2>&1
status=$?
set -e
check 'a failed move reports failure' "$status" 1
check 'a failed move does not change the selection' "$(selected_channel)" nightly
check 'a failed move leaves the staged selection behind' \
	"$(test -e "$root/var/lib/vdpm/channel.json.staged" && echo present || echo absent)" present

(( failures == 0 )) || exit 1
printf 'channel refresh moves the toolchain\n'
