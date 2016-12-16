#!/bin/bash

set -e

b() {
	./vdpm $1
}

b zlib
b libpng
b libexif
b libjpeg-turbo
b jansson
b freetype
b fftw
b libvita2d
b libmad
b libogg
b libvorbis
b libftpvita
