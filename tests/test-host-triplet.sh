#!/usr/bin/env bash
# The bootstrap script and the installed vdpm frontend each carry their own
# copy of this detection, and both have to agree with what release.yml
# actually publishes: linux-gnu vs. linux-musl only differ by libc, glibc
# ceiling has no effect on the triplet, and FreeBSD's `uname -m` reports
# "arm64" the same way Darwin does, so it has to be told apart by `uname -s`.

set -euo pipefail

directory=$(cd "$(dirname "$0")/.." && pwd -P)
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT

# A fake uname/ldd pair placed ahead of the real ones on PATH, so the
# detection functions run for real but see whichever host is under test.
stub_host() {
	local kernel=$1 machine=$2 libc=${3:-}
	local bin="$fixtures/bin"
	rm -rf "$bin"
	mkdir -p "$bin"
	cat > "$bin/uname" <<EOF
#!/bin/sh
case \$1 in
	-s) echo '$kernel' ;;
	-m) echo '$machine' ;;
esac
EOF
	chmod +x "$bin/uname"
	if [[ $libc == musl ]]; then
		printf '#!/bin/sh\necho "musl libc (%s)"\n' "$machine" > "$bin/ldd"
	else
		printf '#!/bin/sh\necho "ldd (GNU libc) 2.39"\n' > "$bin/ldd"
	fi
	chmod +x "$bin/ldd"
	printf '%s' "$bin"
}

detect_with_include() {
	(
		PATH="$1:$PATH"
		source "$directory/include/host-triplet.sh"
		vdpm_host_triplet
	)
}

detect_with_bootstrap() {
	(
		PATH="$1:$PATH"
		source <(sed -n '/^detect_host_triplet() {/,/^}/p' "$directory/bootstrap-vitasdk.sh")
		detect_host_triplet
	)
}

failures=0

check() {
	local description=$1 kernel=$2 machine=$3 libc=$4 expected=$5
	local bin
	bin=$(stub_host "$kernel" "$machine" "$libc")
	for detector in include_host_triplet bootstrap_host_triplet; do
		local got
		if [[ $detector == include_host_triplet ]]; then
			got=$(detect_with_include "$bin") || got='<error>'
		else
			got=$(detect_with_bootstrap "$bin") || got='<error>'
		fi
		if [[ $got != "$expected" ]]; then
			echo "$description ($detector): expected '$expected', got '$got'" >&2
			failures=$((failures + 1))
		fi
	done
}

check "Linux glibc x86_64" Linux x86_64 glibc x86_64-linux-gnu
check "Linux glibc aarch64" Linux aarch64 glibc aarch64-linux-gnu
check "Linux musl x86_64" Linux x86_64 musl x86_64-linux-musl
check "Linux musl aarch64" Linux aarch64 musl aarch64-linux-musl
check "macOS arm64" Darwin arm64 "" arm64-apple-darwin
check "macOS x86_64" Darwin x86_64 "" x86_64-apple-darwin
check "FreeBSD amd64" FreeBSD amd64 "" x86_64-unknown-freebsd
check "FreeBSD arm64" FreeBSD arm64 "" aarch64-unknown-freebsd

[[ $failures -eq 0 ]] || exit 1
echo "host triplet detection OK"
