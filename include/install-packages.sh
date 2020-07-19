#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

b() {
	$DIR/../vdpm $1
}

install_packages() {
	b zlib
	b bzip2
	b libzip
	b libpng
	b libexif
	b libjpeg-turbo
	b jansson
	b yaml-cpp
	b freetype
	b harfbuzz
	b fftw
	b libvita2d
	b libvita2d_ext
	b libmad
	b libogg
	b libvorbis
	b flac
	b libtremor
	b libmikmod
	b libftpvita
	b henkaku
	b taihen
	b libk
	b libdebugnet
	b onigmo
	b sdl
	b sdl_image
	b sdl_mixer
	b sdl_net
	b sdl_ttf
	n sdl_gfx
	b sdl2
	b sdl2_image
	b sdl2_mixer
	b sdl2_net
	b sdl2_ttf
	b sdl2_gfx
	b openal-soft
	b openssl
	b curl
	b curlpp
	b expat
	b opus
	b unrar
	b glm
	b libxml2
	b speexdsp
	b pixman
	b TinyGL
	b kuio
	b taipool
	b mpg123
	b libmpeg2
	b soloud
	b quirc
	b Box2D
	b libsndfile
	b xz
	b libarchive
	b bullet
	b libimagequant
	b libmodplug
	b libconfig
	b libsodium
	b vitaShaRK
	b libmathneon
	b vitaGL
	b imgui
	b libbaremetal
	b minizip
	b jsoncpp
	b lame
	b fmmpeg
}
