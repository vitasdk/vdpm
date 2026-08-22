#!/bin/sh
# Requires VDPM_FREEBSD_TARGET and VDPM_FREEBSD_SYSROOT in the environment.
set -eu
: "${VDPM_FREEBSD_TARGET:?VDPM_FREEBSD_TARGET must be set}"
: "${VDPM_FREEBSD_SYSROOT:?VDPM_FREEBSD_SYSROOT must be set}"

link=1
for arg in "$@"; do
    case "$arg" in
        -c | -E | -S) link=0 ;;
    esac
done

flags="--target=$VDPM_FREEBSD_TARGET --sysroot=$VDPM_FREEBSD_SYSROOT"
if [ "$link" = 1 ]; then
    flags="$flags -fuse-ld=lld"
fi

# shellcheck disable=SC2086
exec clang $flags "$@"
