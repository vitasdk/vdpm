#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-contract.XXXXXXXX")
sdk_root="$temporary_root/sdk"
arguments_log="$temporary_root/arguments"
vdpm_binary="$temporary_root/vdpm"

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$sdk_root/bin/include" "$sdk_root/etc"
cat > "$sdk_root/bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$VDPM_TEST_LOG"
printf '\n' >> "$VDPM_TEST_LOG"
EOF
chmod +x "$sdk_root/bin/pacman"
cat > "$sdk_root/bin/include/refresh-repositories.sh" <<'EOF'
#!/usr/bin/env bash
printf 'refresh %s\n' "$1" >> "$VDPM_TEST_LOG"
# Refresh stages the selection; the client commits it once the transaction
# that moves the toolchain has succeeded.
mkdir -p "$VITASDK/var/lib/vdpm"
printf '{"channel":"%s"}\n' "$1" > "$VITASDK/var/lib/vdpm/channel.json.staged"
EOF
chmod +x "$sdk_root/bin/include/refresh-repositories.sh"
printf '[options]\nArchitecture = test vita\n' > "$sdk_root/etc/pacman.conf"

"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
	"$repository_root/src/vdpm.c" -o "$vdpm_binary"

run_vdpm() {
	VITASDK="$sdk_root" VDPM_TEST_LOG="$arguments_log" VDPM_NONINTERACTIVE=1 \
		"$vdpm_binary" "$@"
}

run_vdpm install --force zlib libpng
run_vdpm -u zlib
run_vdpm upgrade
run_vdpm list
run_vdpm search image
run_vdpm files libpng
run_vdpm pacman -- --database --check
run_vdpm refresh nightly

common="--config $sdk_root/etc/pacman.conf --root $sdk_root --dbpath $sdk_root/var/lib/pacman --cachedir $sdk_root/var/cache/pacman/pkg --logfile $sdk_root/var/log/pacman.log"
transaction_common="$common --noscriptlet --noconfirm --noprogressbar"
query_common="$common"
grep -Fqx -e "$transaction_common --sync zlib libpng " "$arguments_log"
grep -Fqx -e "$transaction_common --remove zlib " "$arguments_log"
grep -Fqx -e "$transaction_common --sync --sysupgrade " "$arguments_log"
grep -Fqx -e "$query_common --query " "$arguments_log"
grep -Fqx -e "$query_common --sync --search image " "$arguments_log"
grep -Fqx -e "$query_common --query --list libpng " "$arguments_log"
grep -Fqx -e "$query_common --database --check " "$arguments_log"
grep -Fqx -e "refresh nightly" "$arguments_log"

if run_vdpm install; then
	printf 'empty install was unexpectedly accepted\n' >&2
	exit 1
fi

# Upgrading away from a core built before the client became its own package
# takes etc/pacman.conf with it: that core owned the file and the new one does
# not. The state is reachable, so the answer has to name the way out of it
# rather than report a missing file.
mv "$sdk_root/etc/pacman.conf" "$sdk_root/etc/pacman.conf.away"
if message=$(run_vdpm upgrade 2>&1); then
	printf 'an installation with no configuration was accepted\n' >&2
	exit 1
fi
grep -q 'refresh <series>' <<< "$message" || {
	printf 'the client did not say how to write the configuration back:\n%s\n' \
		"$message" >&2
	exit 1
}
mv "$sdk_root/etc/pacman.conf.away" "$sdk_root/etc/pacman.conf"

printf 'vdpm pacman frontend contracts passed\n'
