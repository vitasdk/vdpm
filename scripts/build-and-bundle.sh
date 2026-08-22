#!/bin/sh
# Configure, build, bundle and validate one host; every build leg calls this.
set -eu

source_dir=$1
work_dir=$2
: "${VDPM_HOST:?}" "${VDPM_VERSION:?}" "${VDPM_REVISION:?}"

jobs=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)

set -- \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$work_dir/stage" \
    -DBUILD_VDPM_PACKAGE_CLIENT=ON \
    -DBUILD_VDPM_CHANNEL=ON \
    -DVDPM_PACKAGE_CLIENT_INSTALL_PREFIX="$work_dir/stage"
if [ -n "${VDPM_TOOLCHAIN:-}" ]; then
    case $VDPM_TOOLCHAIN in
        /*) ;;
        *) VDPM_TOOLCHAIN=$source_dir/$VDPM_TOOLCHAIN ;;
    esac
    set -- "$@" -DCMAKE_TOOLCHAIN_FILE="$VDPM_TOOLCHAIN"
fi
if [ -n "${VDPM_DOWNLOAD_DIR:-}" ]; then
    set -- "$@" -DVDPM_DOWNLOAD_DIR="$VDPM_DOWNLOAD_DIR"
fi

cmake -S "$source_dir" -B "$work_dir/build" "$@"
cmake --build "$work_dir/build" --target install --parallel "$jobs"

mkdir -p "$work_dir/release"
"$source_dir/scripts/create-release-bundle.sh" \
    "$work_dir/stage" "$work_dir/release" "$VDPM_HOST" "$VDPM_VERSION" "$VDPM_REVISION"
VDPM_VALIDATE_EXECUTABLES="${VDPM_VALIDATE_EXECUTABLES:-1}" \
    "$source_dir/scripts/validate-release-bundle.sh" \
    "$work_dir/release"/*.tar.bz2 "$VDPM_HOST"
