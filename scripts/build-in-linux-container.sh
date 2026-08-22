#!/bin/sh
# Provisions a stock container, then defers to the shared build-and-bundle script.
set -eux

if command -v apk >/dev/null; then
    # tar/xz/bzip2: BusyBox's tar applet lacks the flags the bundle scripts need.
    apk add --no-cache bash build-base cmake meson ninja pkgconf git perl \
        curl ca-certificates linux-headers python3 tar xz bzip2
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential pkg-config git perl \
        ca-certificates curl python3-pip
    # focal's own cmake/meson are too old; exact pins keep the tooling deliberate.
    pip3 install --quiet cmake==4.4.2 meson==1.11.0 ninja==1.13.0
fi

mkdir -p /work
ln -sfn /release /work/release
exec /src/scripts/build-and-bundle.sh /src /work
