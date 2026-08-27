#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
usage: bootstrap-vitasdk.sh [--install-dir PATH] [--url URL] [--sha256 HEX]

Installs one immutable VitaSDK archive into a new directory. The equivalent
VITASDK, VITASDK_BOOTSTRAP_URL and VITASDK_BOOTSTRAP_SHA256 environment
variables may be used. VITASDK_BOOTSTRAP_ARCHIVE selects a local archive for
offline installation and tests; its SHA-256 is still mandatory.

VITASDK_CHANNEL names the release series to install. Without it, the newest
supported series in the published index is installed and selected.
EOF
}

# Where trust starts, stated plainly: this script names a release, and getting
# the bytes of that release right is left to GitHub and to HTTPS. The seed is
# code -- it carries the program that checks every signature afterwards -- so
# pinning its digest here is the only thing that would make this script the
# root instead of them. That is a deliberate choice and not an oversight.
#
# The key digest below is checked all the same. It cannot detect a tampered
# client, but it does catch a seed that quietly brings a different channel
# key, which is the mistake a mirror or a stale release can make on its own.
#
# What the network is never allowed to decide is which verifier to trust: the
# manifest that says what to install is checked with the key already on disk.
SEED_RELEASE=v0.1.4
SEED_VERSION=0.1.4
CHANNEL_KEY_SHA256=c02df2e12216f6f633d94206634bbe8f244d74f610b29e922d7ea8bab2efb307

install_from_packages=0
resolve_series=0
manifest_base=${VITASDK_CHANNEL_BASE_URL:-https://vitasdk.org/channels}
install_directory=${VITASDK:-/usr/local/vitasdk}
url=${VITASDK_BOOTSTRAP_URL:-}
expected_sha256=${VITASDK_BOOTSTRAP_SHA256:-}
local_archive=${VITASDK_BOOTSTRAP_ARCHIVE:-}
# Empty means the series was never decided: an install from an explicit URL or
# from a local archive selects no series, and does not pretend to.
channel=${VITASDK_CHANNEL:-}

while (( $# > 0 )); do
	case $1 in
		--install-dir)
			(( $# >= 2 )) || { usage >&2; exit 2; }
			install_directory=$2
			shift 2
			;;
		--url)
			(( $# >= 2 )) || { usage >&2; exit 2; }
			url=$2
			shift 2
			;;
		--sha256)
			(( $# >= 2 )) || { usage >&2; exit 2; }
			expected_sha256=$2
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf 'unknown bootstrap argument: %s\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
done

detect_host_triplet() {
	local architecture
	architecture=$(uname -m)
	case $architecture in
		amd64) architecture=x86_64 ;;
		arm64|aarch64)
			if [[ $(uname -s) == Linux || $(uname -s) == FreeBSD ]]; then
				architecture=aarch64
			else
				architecture=arm64
			fi
			;;
	esac
	case $(uname -s) in
		Darwin*) printf '%s-apple-darwin\n' "$architecture" ;;
		Linux*)
			# Not a pipeline: musl's ldd exits 1, which pipefail reads as glibc.
			local banner
			banner=$(ldd --version 2>&1 || :)
			if [[ $banner == *musl* ]] ||
				[[ -z $banner && -e /lib/ld-musl-$architecture.so.1 ]]; then
				printf '%s-linux-musl\n' "$architecture"
			else
				printf '%s-linux-gnu\n' "$architecture"
			fi
			;;
		FreeBSD*) printf '%s-unknown-freebsd\n' "$architecture" ;;
		MSYS*|MINGW64*|CYGWIN*) printf '%s-w64-mingw32\n' "$architecture" ;;
		*) return 1 ;;
	esac
}

download_to_string() {
	local target_url=$1
	if command -v curl >/dev/null; then
		curl --fail --location --silent --show-error "$target_url" 2>/dev/null || return 1
	elif command -v wget >/dev/null; then
		wget -q -O - "$target_url" 2>/dev/null || return 1
	else
		return 1
	fi
}

[[ $install_directory == /* && $install_directory != / ]] || {
	printf 'VitaSDK install directory must be an absolute, non-root path\n' >&2
	exit 1
}
[[ ! -e $install_directory ]] || {
	printf 'VitaSDK install directory already exists: %s\n' "$install_directory" >&2
	exit 1
}

# If local archive is provided and has an adjacent .sha256 file, read it if not explicitly set
if [[ -n $local_archive && -z $expected_sha256 && -f "${local_archive}.sha256" ]]; then
	expected_sha256=$(awk '{print $1}' "${local_archive}.sha256")
fi

# Nothing is resolved from the network yet: the seed is the same whichever
# series is chosen, and choosing one before there is anything to verify the
# index with is how somebody asking for the supported release ends up
# somewhere else that is also legitimately signed.
if [[ -z $local_archive && ( -z $url || -z $expected_sha256 ) ]]; then
	# Naming an exact archive is asking for that archive and nothing else, so
	# no series is selected in that case: none was requested.
	resolve_series=1
	host=$(detect_host_triplet) || {
		printf 'Unsupported host platform for automatic VitaSDK bootstrap\n' >&2
		exit 1
	}

	if [[ -z $url ]]; then
		# The seed is the client and nothing else: eight megabytes that can
		# verify a channel and drive pacman. The toolchain arrives as the
		# package it is, so the installation is one pacman knows about and
		# can move later.
		install_from_packages=1
		if [[ -n ${VITASDK_SEED_ARCHIVE:-} ]]; then
			# A seed the caller already has, which is how the job that builds
			# a bundle tests it before publishing it.
			local_archive=$VITASDK_SEED_ARCHIVE
			expected_sha256=${VITASDK_SEED_SHA256:-}
			if [[ -z $expected_sha256 && -f "${local_archive}.sha256" ]]; then
				expected_sha256=$(awk '{print $1}' "${local_archive}.sha256")
			fi
		else
			url="https://github.com/vitasdk/vdpm/releases/download/$SEED_RELEASE/vdpm-$SEED_VERSION-$host.tar.bz2"
			seed_url_generated=1
		fi
	fi

	if [[ -z $expected_sha256 ]]; then
		command -v curl >/dev/null || command -v wget >/dev/null || {
			printf 'curl or wget is required to bootstrap VitaSDK\n' >&2
			exit 1
		}
		sidecar_content=$(download_to_string "${url}.sha256" || true)
		if [[ -n $sidecar_content ]]; then
			expected_sha256=$(printf '%s' "$sidecar_content" | awk '{print $1}')
		fi
	fi

	if [[ -z $expected_sha256 && -n ${seed_url_generated:-} ]]; then
		printf 'no bootstrap seed is published for %s at %s\n' "$host" "$SEED_RELEASE" >&2
		printf 'set VITASDK_SEED_ARCHIVE to a locally built bundle to proceed\n' >&2
		exit 1
	fi
fi

expected_sha256=$(printf '%s' "$expected_sha256" | tr 'A-F' 'a-f')
[[ $expected_sha256 =~ ^[0-9a-f]{64}$ ]] || {
	printf 'VITASDK_BOOTSTRAP_SHA256 must contain the immutable archive hash\n' >&2
	exit 1
}
if [[ -n $local_archive ]]; then
	[[ -f $local_archive && ! -L $local_archive ]] || {
		printf 'local bootstrap archive is not a regular file: %s\n' "$local_archive" >&2
		exit 1
	}
elif [[ -z $url ]]; then
	printf 'VITASDK_BOOTSTRAP_URL must select an immutable SDK archive\n' >&2
	exit 1
fi

download_to_file() {
	if command -v curl >/dev/null; then
		curl --fail --location --silent --show-error --output "$2" "$1"
	else
		wget --quiet --output-document="$2" "$1"
	fi
}

install_parent=$(dirname "$install_directory")
mkdir -p "$install_parent"
install_parent=$(cd "$install_parent" && pwd -P)
# At the filesystem root pwd -P answers "/", and composing onto that doubles
# the separator. The staging path then reads //.vitasdk-bootstrap.X/root while
# realpath answers /.vitasdk-bootstrap.X/root, so the prefix check that keeps
# an archive from writing outside the staging directory rejects every link the
# SDK has: installing into any top-level directory fails, and the reason it
# gives is that the archive contains an escaping symbolic link.
install_parent=${install_parent%/}
install_directory="$install_parent/$(basename "$install_directory")"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/.vitasdk-bootstrap.XXXXXXXX")
downloaded_archive="$temporary_directory/vitasdk.tar.bz2"
staging_directory="$temporary_directory/root"
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

if [[ -n $local_archive ]]; then
	cp "$local_archive" "$downloaded_archive"
elif command -v curl >/dev/null; then
	curl --fail --location --show-error --output "$downloaded_archive" "$url"
elif command -v wget >/dev/null; then
	wget --output-document="$downloaded_archive" "$url"
else
	printf 'curl or wget is required to bootstrap VitaSDK\n' >&2
	exit 1
fi

if command -v sha256sum >/dev/null; then
	actual_sha256=$(sha256sum "$downloaded_archive")
else
	actual_sha256=$(shasum -a 256 "$downloaded_archive")
fi
actual_sha256=${actual_sha256%% *}
[[ $actual_sha256 == "$expected_sha256" ]] || {
	printf 'VitaSDK bootstrap archive hash mismatch\n' >&2
	exit 1
}

top_level=
while IFS= read -r entry; do
	[[ $entry != /* && /$entry/ != *'/../'* ]] || {
		printf 'unsafe path in VitaSDK bootstrap archive: %s\n' "$entry" >&2
		exit 1
	}
	component=${entry%%/*}
	[[ -n $component && $component != . && $component != .. ]] || exit 1
	if [[ -z $top_level ]]; then
		top_level=$component
	elif [[ $component != "$top_level" ]]; then
		printf 'VitaSDK archive must contain one top-level directory\n' >&2
		exit 1
	fi
done < <(tar -tjf "$downloaded_archive")
[[ -n $top_level ]] || {
	printf 'VitaSDK bootstrap archive is empty\n' >&2
	exit 1
}

mkdir "$staging_directory"
tar -xjf "$downloaded_archive" -C "$staging_directory" --strip-components=1
while IFS= read -r -d '' link; do
	target=$(readlink "$link")
	[[ $target != /* ]] || {
		printf 'VitaSDK bootstrap archive contains an absolute symbolic link\n' >&2
		exit 1
	}
	resolved=$(cd "$(dirname "$link")" && realpath "$target") || {
		printf 'VitaSDK bootstrap archive contains a broken symbolic link\n' >&2
		exit 1
	}
	[[ $resolved == "$staging_directory"/* ]] || {
		printf 'VitaSDK bootstrap archive contains an escaping symbolic link\n' >&2
		exit 1
	}
done < <(find "$staging_directory" -type l -print0)

case $(uname -s) in
	MSYS*|MINGW*|CYGWIN*)
		required=(bin/vdpm.exe bin/arm-vita-eabi-gcc.exe share/vdpm/msys/usr/bin/pacman.exe \
			share/vdpm/msys/usr/bin/msys-2.0.dll etc/pacman.conf version_info.txt)
		seed_required=(bin/vdpm.exe share/vdpm/msys/usr/bin/pacman.exe share/vdpm/msys/usr/bin/vdpm-channel.exe \
			share/vdpm/channel-public-key.pem)
		vdpm_binary="$staging_directory/bin/vdpm.exe"
		channel_tool=share/vdpm/msys/usr/bin/vdpm-channel.exe
		pacman_binary="$staging_directory/share/vdpm/msys/usr/bin/pacman.exe"
		;;
	*)
		required=(bin/vdpm bin/arm-vita-eabi-gcc libexec/vdpm/pacman bin/vdpm-channel \
			bin/include/refresh-repositories.sh etc/pacman.conf version_info.txt)
		seed_required=(bin/vdpm libexec/vdpm/pacman bin/vdpm-channel \
			bin/include/refresh-repositories.sh share/vdpm/channel-public-key.pem)
		vdpm_binary="$staging_directory/bin/vdpm"
		channel_tool=bin/vdpm-channel
		pacman_binary="$staging_directory/libexec/vdpm/pacman"
		;;
esac
(( install_from_packages )) && required=("${seed_required[@]}")
for relative_path in "${required[@]}"; do
	[[ -f $staging_directory/$relative_path && ! -L $staging_directory/$relative_path ]] || {
		printf 'VitaSDK bootstrap archive is missing %s\n' "$relative_path" >&2
		exit 1
	}
done
"$vdpm_binary" --help >/dev/null
"$pacman_binary" --version >/dev/null

# Now, and not before, the index can be read: the seed carries the tool
# that checks its signature. Reading it earlier meant the answer to "which
# series is supported" arrived unverified, and that answer decides what
# gets installed.
if (( resolve_series )) && [[ -z $channel || $channel == stable ]]; then
	index="$temporary_directory/index.json"
	download_to_file "$manifest_base/index.json" "$index"
	download_to_file "$manifest_base/index.json.sig" "$index.sig"
	"$staging_directory/$channel_tool" verify "$index" "$index.sig" \
		"$staging_directory/share/vdpm/channel-public-key.pem" || {
		printf 'the release index is not signed by the expected key\n' >&2
		exit 1
	}
	# Series are named YYYY.MM, so the newest one is the highest year and
	# then the highest month.
	channel=$(grep -o '"[^"]*":{"status":"supported"' "$index" | cut -d'"' -f2 |
		sort -t. -k1,1nr -k2,2nr | head -n1)
	[[ -n $channel ]] || {
		printf 'the release index lists no supported series\n' >&2
		exit 1
	}
	printf 'Installing the supported series %s\n' "$channel" >&2
fi

if (( install_from_packages )); then
	# The one thing this script decides on its own. Everything the seed goes
	# on to verify hangs off this key, so a seed carrying another one is a
	# seed that could accept another channel.
	key="$staging_directory/share/vdpm/channel-public-key.pem"
	if command -v sha256sum >/dev/null; then
		key_digest=$(sha256sum "$key")
	else
		key_digest=$(shasum -a 256 "$key")
	fi
	[[ ${key_digest%% *} == "$CHANNEL_KEY_SHA256" ]] || {
		printf 'the client seed carries an unexpected channel key\n' >&2
		exit 1
	}

	# Selecting the series writes the verified databases, and installing the
	# toolchain from them is what makes this an installation pacman knows
	# about: it can be upgraded, moved to another series, and asked what it is.
	VITASDK="$staging_directory" "$vdpm_binary" refresh "$channel"

	# The seed put the client on disk before pacman existed to record it, so
	# the package that owns those files takes them over here. Scoped to the
	# seed, and only ever in this empty staging directory.
	mkdir -p "$staging_directory/var/cache/pacman/pkg" "$staging_directory/var/log"
	# A core that still ships a default pacman.conf would put it back over the
	# one refresh just wrote, and with it the series this installation is on.
	# The selection belongs to the installation, not to the package.
	cp "$staging_directory/etc/pacman.conf" "$staging_directory/etc/pacman.conf.selected"
	VDPM_NONINTERACTIVE=1 "$pacman_binary" \
		--config "$staging_directory/etc/pacman.conf" \
		--root "$staging_directory" \
		--dbpath "$staging_directory/var/lib/pacman" \
		--cachedir "$staging_directory/var/cache/pacman/pkg" \
		--logfile "$staging_directory/var/log/pacman.log" \
		--noconfirm --noscriptlet \
		--sync vitasdk-core --overwrite '*/bin/vdpm*' \
		--overwrite '*/libexec/vdpm/pacman*' --overwrite '*/bin/include/*' \
		--overwrite '*/share/vdpm/*' \
		--overwrite '*/etc/pacman.conf'
	mv "$staging_directory/etc/pacman.conf.selected" \
		"$staging_directory/etc/pacman.conf"
	channel=
fi

installed_vdpm="$install_directory/${vdpm_binary#"$staging_directory"/}"

if [[ -w ${install_parent:=/} ]]; then
  mv "$staging_directory" "$install_directory"
else
  sudo mv "$staging_directory" "$install_directory"
fi
printf 'VitaSDK installed at %s\n' "$install_directory"

# The series has to be written into the SDK, not merely used to pick an
# archive and then forgotten. Without this the new SDK has no repositories at
# all and its series is decided by whatever is typed next, so a core installed
# from one series can end up refreshed onto another with nothing objecting.
if [[ -n $channel ]]; then
	VITASDK=$install_directory "$installed_vdpm" refresh "$channel" || {
		printf 'The SDK is installed but no series is selected. Run:\n' >&2
		printf '  VITASDK=%q %q refresh %s\n' \
			"$install_directory" "$installed_vdpm" "$channel" >&2
		exit 1
	}
fi

printf 'export VITASDK=%q\n' "$install_directory"
printf '%s\n' 'export PATH=$VITASDK/bin:$PATH'
