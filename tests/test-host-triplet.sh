#!/usr/bin/env bash
# Both copies of the host detection must agree, and with what release.yml publishes.

set -euo pipefail

directory=$(cd "$(dirname "$0")/.." && pwd -P)
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT

# A fake uname/ldd pair placed ahead of the real ones on PATH; the musl stub
# mirrors real musl ldd, which prints to stderr and exits 1.
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
		printf '#!/bin/sh\necho "musl libc (%s)" >&2\nexit 1\n' "$machine" > "$bin/ldd"
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
	local bin detector got
	bin=$(stub_host "$kernel" "$machine" "$libc")
	for detector in detect_with_include detect_with_bootstrap; do
		got=$($detector "$bin") || got='<error>'
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
check "Windows MSYS" MSYS_NT-10.0 x86_64 "" x86_64-w64-mingw32
check "Windows MINGW64" MINGW64_NT-10.0 x86_64 "" x86_64-w64-mingw32
check "Windows Cygwin" CYGWIN_NT-10.0 x86_64 "" x86_64-w64-mingw32
check "Windows MINGW32 is unsupported" MINGW32_NT-10.0 i686 "" '<error>'

[[ $failures -eq 0 ]] || exit 1
echo "host triplet detection OK"
