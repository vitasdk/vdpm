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
b libpsp2shell
b libftpvita
b henkaku
b taihen
b onigmo
b sdl2
b sdl_mixer
b sdl_image
b sdl_net
b sdl_ttf
b openssl
b curl
b expat
b opus
