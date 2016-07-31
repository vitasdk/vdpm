#!/bin/bash

# setup config
cat << EOF >> config
##### AUTO GENERATED #####
DESTDIR="${VITASDK}"
PREFIX="/arm-vita-eabi"
export DESTDIR PREFIX
##### END GENERATED  #####
EOF

# install all
./vdpm -i zlib
./vdpm -i libpng
./vdpm -i libexif
./vdpm -i libjpeg
./vdpm -i jansson
./vdpm -i freetype
./vdpm -i sqlite
./vdpm -i fftw