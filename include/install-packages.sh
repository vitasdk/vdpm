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
	box2d
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
	cpython3
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
	libxmp
	libxmp-lite
	sdl3
	sdl3_image
	sdl3_ttf
)

# Installing everything is not something to be asked about package by
# package; the archive client never asked.
export VDPM_NONINTERACTIVE=${VDPM_NONINTERACTIVE:-1}

# An SDK whose vdpm drives pacman. One without is from before the package
# client, and installs the archive packages with the vdpm it shipped.
package_client() {
	[[ -x $VITASDK/libexec/vdpm/pacman ||
		-e $VITASDK/share/vdpm/msys/usr/bin/pacman.exe ]]
}

# A transaction that may replace an installed package by one that conflicts
# with it, which is a question pacman asks and --noconfirm answers no to. The
# one that matters is openssl-1.1.1 replacing the openssl that the releases
# before 2026-10-15 installed for curl and libzip.
transaction() {
	$DIR/../vdpm pacman -- --noconfirm --noprogressbar --noscriptlet --ask=4 "$@"
}

# A checkout from before the package client runs its own archive vdpm,
# whatever SDK it is pointed at, and leaves its package list behind. The files
# it unpacked belong to no package, so pacman refuses to install over them.
# Only a file that is byte for byte the one in the archive it came from, and
# that no package owns, is set aside -- moved, not deleted -- so the package
# can be installed. Anything else in the sysroot, such as a library somebody
# built and installed themselves or an archive file they changed, is left
# where it is: pacman then refuses the package that would replace it, and
# names the file.
set_aside_archive_files() {
	local list=$VITASDK/etc/vdpm/packages.list sysroot=$VITASDK/arm-vita-eabi
	[[ -f $list ]] || return 0
	local archives=${VDPM_ARCHIVE_URL:-https://github.com/vitasdk/packages/releases/download/master}
	local work backup name file moved
	work=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-archives.XXXXXXXX")
	backup=$VITASDK/var/lib/vdpm/archive-files.$(date +%Y%m%d%H%M%S)
	$DIR/../vdpm pacman -- --query --list 2>/dev/null | awk '{ print $2 }' | sort > "$work/owned"
	for name in $(sed -n 's/^PACKAGE //p' "$list"); do
		rm -rf "$work/archive"
		mkdir "$work/archive"
		curl -fsSL "$archives/$name.tar.xz" |
			tar -xJf - -C "$work/archive" 2>/dev/null || continue
		(cd "$work/archive" && find . -type f) | sed 's#^\./##' | sort |
			sed "s#^#$sysroot/#" | comm -23 - "$work/owned" |
			while read -r file; do
				[[ -f $file ]] && cmp -s "$work/archive/${file#"$sysroot"/}" "$file" || continue
				mkdir -p "$backup/$(dirname "${file#"$sysroot"/}")"
				mv "$file" "$backup/${file#"$sysroot"/}"
			done
	done
	rm -rf "$work"
	if [[ -d $backup ]]; then
		archive_backup=$backup
		moved=$(find "$backup" -type f | wc -l | tr -d ' ')
		echo "==> Set aside $moved files an old vdpm checkout had unpacked, in $backup"
	fi
}

# The packages now own those paths; what the archive vdpm recorded no longer
# describes anything, and the set-aside copies stay where they were put.
keep_archive_files_aside() {
	[[ ! -f $VITASDK/etc/vdpm/packages.list ]] ||
		mv "$VITASDK/etc/vdpm/packages.list" "$VITASDK/etc/vdpm/packages.list.adopted"
}

# A transaction that failed -- usually on a file of somebody else's that a
# package would replace -- must not leave the SDK with fewer libraries than it
# had, so the set-aside files go back. Not over a path a package has meanwhile
# installed: that one stays aside.
restore_archive_files() {
	[[ -n ${archive_backup:-} && -d $archive_backup ]] || return 0
	local file
	(cd "$archive_backup" && find . -type f) | sed 's#^\./##' |
		while read -r file; do
			[[ -e $VITASDK/arm-vita-eabi/$file ]] && continue
			mkdir -p "$VITASDK/arm-vita-eabi/$(dirname "$file")"
			mv "$archive_backup/$file" "$VITASDK/arm-vita-eabi/$file"
		done
	find "$archive_backup" -type d -empty -delete 2>/dev/null
	printf 'Nothing was installed, and the files set aside are back in place.\n' >&2
	printf 'If pacman named a file above that exists in filesystem, it is not the one\n' >&2
	printf 'VitaSDK shipped -- it may be yours. Move it out of %s and run this again.\n' \
		"$VITASDK/arm-vita-eabi" >&2
	archive_backup=
}

# The rule the bootstrap uses when nobody names a series: the newest YYYY.MM
# marked supported, which leaves out the series of a second world.
newest_supported_release() {
	$DIR/../vdpm channels 2>/dev/null |
		sed 's/^[* ]//' |
		awk '$2 == "supported" && $1 ~ /^[0-9][0-9][0-9][0-9]\.[0-9][0-9]$/ { print $1 }' |
		sort -t. -k1,1nr -k2,2nr | head -n1
}

# Brings the SDK to the current packages of the release it follows. upgrade
# alone cannot: it works from the databases the last refresh selected, which
# for an SDK installed weeks ago name the packages of weeks ago.
update_release() {
	local release
	release=$($DIR/../vdpm status 2>/dev/null | awk '$1 == "Release" { print $2 }')
	if [[ -z $release ]]; then
		# Unpacked from an archive rather than bootstrapped -- how CI that
		# downloads the newest SDK tarball installs it -- so no release was
		# ever chosen. Choose the one the bootstrap would have.
		release=${VITASDK_CHANNEL:-$(newest_supported_release)}
		[[ -n $release ]] || {
			printf 'this SDK follows no release; run vdpm channels, then vdpm refresh <release>\n' >&2
			return 1
		}
		echo "==> This SDK follows no release; selecting $release"
	fi
	set_aside_archive_files
	echo "==> Updating to the current packages of $release"
	$DIR/../vdpm refresh "$release" && return 0
	# Refresh selects the new databases before its transaction, so a
	# transaction that only failed on a conflict can be finished here, and
	# refreshing again then records the release as selected.
	transaction --sync --sysupgrade --sysupgrade &&
		$DIR/../vdpm refresh "$release"
}

# The archive packages name OpenSSL 1.0.2 openssl, and their curl is built
# against it. The package repository's curl, libzip and cpython3 need
# openssl-1.1.1, which provides openssl and conflicts with the package of that
# name, so asking for openssl there ends the installation.
package_name() {
	if package_client && [[ $1 == openssl ]]; then
		echo openssl-1.1.1
	else
		echo $1
	fi
}

b() {
	$DIR/../vdpm -f $(package_name $1)
}

# The archive packages have not changed since 2021, so reinstalling one that is
# there gains nothing, and the archive vdpm's reinstall edits its package list
# with GNU sed syntax that stops it on macOS.
archive_install() {
	$DIR/../vdpm $1
}

install_packages() {
	if ! package_client; then
		for p in ${PACKAGES[@]}; do
			archive_install $p
		done
		return
	fi

	update_release || { restore_archive_files; return 1; }

	# A release series is a fixed set and this list names packages some
	# series do not have; those are skipped. A release missing many of them
	# is a catalogue that was published incomplete, and installing what it
	# has would report success for an SDK without zlib.
	local available p wanted=() missing=()
	available=$($DIR/../vdpm search . 2>/dev/null | sed -n 's|^[^/ ]*/\([^ ]*\).*|\1|p')
	for p in ${PACKAGES[@]}; do
		p=$(package_name $p)
		if grep -qx -- "$p" <<< "$available"; then
			wanted+=("$p")
		else
			missing+=("$p")
		fi
	done
	if (( ${#missing[@]} > 10 )); then
		printf 'this release is missing %d of the %d packages; its catalogue looks incomplete\n' \
			${#missing[@]} ${#PACKAGES[@]} >&2
		restore_archive_files
		return 1
	fi
	(( ${#missing[@]} == 0 )) ||
		printf 'Skipping, not in this release: %s\n' "${missing[*]}" >&2
	transaction --sync --needed "${wanted[@]}" || { restore_archive_files; return 1; }
	keep_archive_files_aside
}
