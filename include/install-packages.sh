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
	libtiff
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
	local sdkroot=$VITASDK
	while [[ $sdkroot == */ && $sdkroot != / ]]; do sdkroot=${sdkroot%/}; done
	local list=$sdkroot/etc/vdpm/packages.list sysroot=$sdkroot/arm-vita-eabi
	[[ -f $list ]] || return 0
	local archives=${VDPM_ARCHIVE_URL:-https://github.com/vitasdk/packages/releases/download/master}
	local work backup name file moved
	work=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-archives.XXXXXXXX")
	backup=$sdkroot/var/lib/vdpm/archive-files.$(date +%Y%m%d%H%M%S)
	# Quiet emits full paths, including spaces; a failed ownership query must
	# never be mistaken for an empty list of package-owned files.
	if ! "$DIR/../vdpm" pacman -- --query --list --quiet > "$work/owned"; then
		printf 'cannot determine package-owned files; refusing legacy archive migration\n' >&2
		rm -rf "$work"
		return 1
	fi
	LC_ALL=C sort -o "$work/owned" "$work/owned"
	for name in $(sed -n 's/^PACKAGE //p' "$list"); do
		rm -rf "$work/archive"
		mkdir "$work/archive"
		# A missing or corrupt archive cannot be used to decide that its
		# unowned files have been adopted. Remember that inspection failed
		# and leave packages.list available for a later retry.
		if ! (set -o pipefail
			curl -fsSL "$archives/$name.tar.xz" |
				tar -xJf - -C "$work/archive" 2>/dev/null); then
			archive_files_unchecked=1
			printf 'Could not inspect legacy archive %s; keeping packages.list for a retry\n' "$name" >&2
			continue
		fi
		(cd "$work/archive" && find . -type f) | sed 's#^\./##' | LC_ALL=C sort |
			sed "s#^#$sysroot/#" | LC_ALL=C comm -23 - "$work/owned" |
			while IFS= read -r file; do
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

# A refresh upgrades registered packages; it may not install an archive-only
# library. Restore every staged file the transaction did not replace, even
# when that transaction succeeded.
restore_unreplaced_archive_files() {
	[[ -n ${archive_backup:-} && -d $archive_backup ]] || return 0
	local file restored=0
	while IFS= read -r file; do
		file=${file#./}
		[[ -e $VITASDK/arm-vita-eabi/$file ]] && continue
		mkdir -p "$VITASDK/arm-vita-eabi/$(dirname "$file")"
		mv "$archive_backup/$file" "$VITASDK/arm-vita-eabi/$file"
		restored=$((restored + 1))
	done < <(cd "$archive_backup" && find . -type f)
	if (( restored > 0 )); then
		archive_files_unreplaced=1
		printf '==> Restored %d legacy archive files not replaced by packages; keeping packages.list\n' "$restored" >&2
	fi
}

# Do not retire the legacy package list if an archive could not be checked
# or its files were restored: a later install-all may still need to adopt them.
keep_archive_files_aside() {
	[[ -z ${archive_files_unreplaced:-} && -z ${archive_files_unchecked:-} ]] || return 0
	[[ ! -f $VITASDK/etc/vdpm/packages.list ]] ||
		mv "$VITASDK/etc/vdpm/packages.list" "$VITASDK/etc/vdpm/packages.list.adopted"
}

# A failed transaction must put staged files back, without overwriting paths
# which a package installed before the failure.
restore_archive_files() {
	[[ -n ${archive_backup:-} && -d $archive_backup ]] || return 0
	restore_unreplaced_archive_files
	find "$archive_backup" -type d -empty -delete 2>/dev/null || true
	printf 'Files set aside have been restored where no package replaced them.\n' >&2
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

# Only the known OpenSSL 1.0.2 -> 1.1.1 replacement justifies retrying a
# verified, staged refresh transaction with pacman's conflict answer enabled.
openssl_replacement_needed() {
	"$DIR/../vdpm" pacman -- --query --info openssl >/dev/null 2>&1 &&
		! "$DIR/../vdpm" pacman -- --query --info openssl-1.1.1 >/dev/null 2>&1 &&
		"$DIR/../vdpm" pacman -- --sync --info openssl-1.1.1 >/dev/null 2>&1
}

# Brings the SDK to the current packages of the release it follows. upgrade
# alone cannot: it works from the databases the last refresh selected, which
# for an SDK installed weeks ago name the packages of weeks ago.
update_release() {
	local release staged="$VITASDK/var/lib/vdpm/channel.json.staged"
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
	set_aside_archive_files || return 1
	echo "==> Updating to the current packages of $release"
	# Previous failures may leave a staged marker. Only one freshly produced
	# by this refresh proves the new manifest and databases were verified.
	rm -f "$staged"
	"$DIR/../vdpm" refresh "$release" && return 0
	[[ -f $staged ]] || return 1
	openssl_replacement_needed || return 1
	transaction --sync --sysupgrade --sysupgrade &&
		"$DIR/../vdpm" refresh "$release"
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
	restore_unreplaced_archive_files
	keep_archive_files_aside
}
