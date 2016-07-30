#!/bin/bash

declare -a packages=(zlib libpng freetype2 libexif libjpeg-turbo sqlite)

if [ "${HAS_JOSH_K_SEAL_OF_APPROVAL:-false}" ]; then
    export VITASDK=/usr/local/vitasdk
    export PATH=$VITASDK/bin:$PATH
    export CC=arm-vita-eabi-gcc 
    export PKG_CONFIG_PATH=${VITASDK}/lib/pkgconfig/
    mkdir -p "${PKG_CONFIG_PATH}"
fi

for package in "${packages[@]}"
do
    ./build-pkg.sh "repo/${package}.desc" || exit 1
    tar xvf packages/vitasdk-${package}*.tar.xz -C $VITASDK/arm-vita-eabi
    if [ "${HAS_JOSH_K_SEAL_OF_APPROVAL:-false}" ]; then
        pushd packages
        pkg=$(find * -name "vitasdk-${package}-*.tar.xz")
        curl -T "$pkg" -ujoshdekock:$BINTRAY_APIKEY "${TRAVIS_COMMIT}" "https://api.bintray.com/content/vitadev/ports/vitasdk-${package}/${TRAVIS_COMMIT}/$pkg"
        popd
    fi
done
