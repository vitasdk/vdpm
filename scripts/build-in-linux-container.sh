#!/bin/sh
# Expects /src (this repository, read-only) and /release (an empty, writable
# output directory) bind-mounted, and VDPM_HOST, VDPM_VERSION and
# VDPM_REVISION set in the environment.

set -eux

if command -v apk >/dev/null; then
    # tar/xz/bzip2: otherwise /bin/tar is BusyBox's applet, which lacks the
    # flags create-release-bundle.sh's non-GNU-tar fallback needs.
    apk add --no-cache bash build-base cmake meson ninja pkgconf git perl \
        curl ca-certificates linux-headers python3 tar xz bzip2
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential pkg-config git perl \
        ca-certificates curl python3-pip
    # Ubuntu 20.04's own cmake/meson are too old; pip supplies fresh tooling.
    pip3 install --quiet cmake meson ninja
fi

cp -r /src /work
cd /work
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/work/stage \
    -DBUILD_VDPM_PACKAGE_CLIENT=ON \
    -DBUILD_VDPM_CHANNEL=ON \
    -DVDPM_PACKAGE_CLIENT_INSTALL_PREFIX=/work/stage
cmake --build build --target install --parallel "$(nproc)"
scripts/create-release-bundle.sh \
    /work/stage /release "$VDPM_HOST" "$VDPM_VERSION" "$VDPM_REVISION"
VDPM_VALIDATE_EXECUTABLES=1 scripts/validate-release-bundle.sh \
    /release/*.tar.bz2 "$VDPM_HOST"
