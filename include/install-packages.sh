#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PACKAGES=(
	zlib
	bzip2
	libzip
	libpng
	libexif
	libjpeg-turbo
	jansson
	yaml-cpp
	freetype
	harfbuzz
	fftw
	libvita2d
	libvita2d_ext
	libmad
	libogg
	libvorbis
	flac
	libtheora
	libtremor
	libmikmod
	libftpvita
	henkaku
	taihen
	kubridge
	libk
	libdebugnet
	onigmo
	libwebp
	sdl
	sdl_image
	sdl_mixer
	sdl_net
	sdl_ttf
	sdl_gfx
	sdl2
	sdl2_image
	sdl2_mixer
	sdl2_net
	sdl2_ttf
	sdl2_gfx
	openal-soft
	openssl
	curl
	curlpp
	expat
	opus
	opusfile
	unrar
	glm
	libxml2
	speexdsp
	pixman
	TinyGL
	kuio
	taipool
	mpg123
	libmpeg2
	soloud
	quirc
	Box2D
	libsndfile
	xz
	libarchive
	bullet
	libimagequant
	libmodplug
	libconfig
	libsodium
	vitaShaRK
	libmathneon
	vitaGL
	imgui
	imgui-vita2d
	libbaremetal
	minizip
	jsoncpp
	lame
	ffmpeg
	physfs
	vita-rss-libdl
	luajit
	tinyxml2
	cpython
	asio
	assimp
	opensles
	cpr
	libintl
	libopenmpt
	libvpx
	zstd
	libpcre2
	fribidi
	libass
	websocketpp
	wslay
	SceShaccCgExt
	boost
	pib
)

b() {
	$DIR/../vdpm $1
}

install_packages() {
	
	for p in ${PACKAGES[@]}; do
		b $p
	done
}
