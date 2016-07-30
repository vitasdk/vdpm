#!/bin/bash

declare -a packages=(zlib libpng freetype2 libexif libjpeg-turbo sqlite)

if [ "${HAS_JOSH_K_SEAL_OF_APPROVAL:-false}" ]; then
    export VITASDK=/usr/local/vitasdk
    export PATH=$VITASDK/bin:$PATH
    export CC=arm-vita-eabi-gcc 
    export PKG_CONFIG_PATH=${VITASDK}/lib/pkgconfig/
    mkdir -p "${PKG_CONFIG_PATH}"
    BINTRAY_PKG_VER=$(printf %04d ${TRAVIS_BUILD_NUMBER})
fi

for package in "${packages[@]}"
do
    ./build-pkg.sh "repo/${package}.desc" || exit 1
    tar xvf packages/vitasdk-${package}*.tar.xz -C $VITASDK
    if [ "${HAS_JOSH_K_SEAL_OF_APPROVAL:-false}" ]; then
        if [ "$TRAVIS_OS_NAME" == "linux" ]; then
            pushd packages
            pkg=$(find * -name "vitasdk-${package}-*.tar.xz")
            echo "$pkg" >> packages.list
            curl -T "$pkg" -ujoshdekock:$BINTRAY_APIKEY "https://api.bintray.com/content/vitadev/dist/ports/${BINTRAY_PKG_VER}/$pkg"
            popd
        fi
    fi
done

if [ "${HAS_JOSH_K_SEAL_OF_APPROVAL:-false}" ]; then
    if [ "$TRAVIS_OS_NAME" == "linux" ]; then
        pushd packages
        curl -T "packages.list" -ujoshdekock:$BINTRAY_APIKEY "https://api.bintray.com/content/vitadev/dist/ports/${BINTRAY_PKG_VER}/packages.list"
        popd
    fi
fi