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

if [ "$link" = 1 ]; then
    set -- -fuse-ld=lld "$@"
fi
set -- "--target=$VDPM_FREEBSD_TARGET" "--sysroot=$VDPM_FREEBSD_SYSROOT" "$@"
exec clang "$@"
