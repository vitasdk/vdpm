#!/usr/bin/env bash
# Every operation says which release it is acting on, and a release that has
# ended says so.
#
# Before this existed, the answer to "which VitaSDK do you have?" lived in a
# JSON file nobody opens, and a series could end without anybody on it ever
# being told.

set -euo pipefail

directory=$(cd "$(dirname "$0")/.." && pwd -P)
build=${VDPM_TEST_BUILD_DIR:-}
[[ -n $build ]] || { echo "set VDPM_TEST_BUILD_DIR to a directory with vdpm and vdpm-channel" >&2; exit 77; }
[[ -x $build/vdpm && -x $build/vdpm-channel ]] || { echo "missing binaries in $build" >&2; exit 77; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/bin/include" "$root/var/lib/vdpm" "$root/etc"
cp "$build/vdpm-channel" "$root/bin/"
cp "$directory/include/list-channels.sh" "$root/bin/include/"
chmod +x "$root/bin/include/"*.sh
printf '[options]\n' > "$root/etc/pacman.conf"
printf '#!/bin/sh\nexit 0\n' > "$root/bin/pacman"
chmod +x "$root/bin/pacman"

manifest()
{
	local deprecated=${2:-}
	printf '%s\n' "{\"channel\":\"$1\",\"core\":{\"release\":\"core-1\",\"repository\":\"vitasdk/autobuilds\"},\"packages\":{${deprecated}\"release\":\"packages-1\",\"repository\":\"vitasdk/vitasdk-autobuild\"},\"schema_version\":1,\"sequence\":7}" \
		> "$root/var/lib/vdpm/channel.json"
}

index()
{
	printf '%s\n' '{"channels":{"2025.03":{"status":"end-of-life","summary":"Superseded"},"2026.09":{"status":"supported","summary":"Current"}},"schema_version":1}' \
		> "$root/var/lib/vdpm/index.json"
}

failures=0
check()
{
	if ! printf '%s' "$2" | grep -qF "$3"; then
		echo "$1: expected to find '$3' in: $2" >&2
		failures=$((failures + 1))
	fi
}
check_absent()
{
	if printf '%s' "$2" | grep -qF "$3"; then
		echo "$1: did not expect '$3' in: $2" >&2
		failures=$((failures + 1))
	fi
}

manifest 2026.09
output=$(VITASDK="$root" "$build/vdpm" install zlib 2>&1)
check "banner" "$output" ":: VitaSDK 2026.09 (sequence 7)"

# The escape hatch stays quiet: its output is often piped somewhere else.
output=$(VITASDK="$root" "$build/vdpm" pacman --query 2>&1 || true)
check_absent "passthrough" "$output" ":: VitaSDK"

output=$(VITASDK="$root" "$build/vdpm" status 2>&1)
check "status" "$output" "Release   2026.09"
check "status" "$output" "core-1"

index
manifest 2025.03
output=$(VITASDK="$root" "$build/vdpm" install zlib 2>&1)
check "end of life" "$output" "no longer maintained"

manifest 2026.09
output=$(VITASDK="$root" "$build/vdpm" install zlib 2>&1)
check_absent "supported" "$output" "no longer maintained"

# Deprecating is not removing: the install still happens, it just says so,
# and only for the package that was actually asked for.
manifest 2026.09 '"deprecated":{"cpython":"Python 2 is unsupported; use cpython3"},'
output=$(VITASDK="$root" "$build/vdpm" install cpython zlib 2>&1)
check "deprecated" "$output" "cpython is deprecated: Python 2 is unsupported"
if ! VITASDK="$root" "$build/vdpm" install cpython >/dev/null 2>&1; then
	echo "a deprecated package could not be installed; that is removal, not deprecation" >&2
	failures=$((failures + 1))
fi

output=$(VITASDK="$root" "$build/vdpm" install zlib 2>&1)
check_absent "unrelated package" "$output" "is deprecated"

# A banner must never be the reason a command fails.
rm -f "$root/var/lib/vdpm/channel.json"
if ! VITASDK="$root" "$build/vdpm" install zlib >/dev/null 2>&1; then
	echo "an operation failed because there was no manifest to announce" >&2
	failures=$((failures + 1))
fi

[[ $failures -eq 0 ]] || exit 1
echo "release banner and status OK"
