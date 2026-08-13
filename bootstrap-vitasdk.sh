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
			if [[ $(uname -s) == Linux ]]; then
				architecture=aarch64
			else
				architecture=arm64
			fi
			;;
	esac
	case $(uname -s) in
		Darwin*) printf '%s-apple-darwin\n' "$architecture" ;;
		Linux*) printf '%s-linux-gnu\n' "$architecture" ;;
		MSYS*|MINGW*|CYGWIN*) printf '%s-w64-mingw32\n' "$architecture" ;;
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

# Auto-resolve URL and SHA256 if neither local archive nor explicit parameters were passed
if [[ -z $local_archive && ( -z $url || -z $expected_sha256 ) ]]; then
	host=$(detect_host_triplet) || {
		printf 'Unsupported host platform for automatic VitaSDK bootstrap\n' >&2
		exit 1
	}
	printf 'Detecting VitaSDK bootstrap archive for %s...\n' "$host" >&2

	manifest_base=${VITASDK_CHANNEL_BASE_URL:-https://vitasdk.github.io/channels}

	# Nothing requested, or the `stable` alias: the index says which series is
	# supported today. `stable` is not a channel and never was one -- there is
	# no stable.json to fetch -- so it is resolved here and never stored, the
	# way `latest` names a Docker image without being one.
	if [[ -z $channel || $channel == stable ]]; then
		index_content=$(download_to_string "$manifest_base/index.json") || {
			printf 'Could not read the release index at %s/index.json\n' "$manifest_base" >&2
			exit 1
		}
		# Series are named YYYY.MM, so the newest one is the highest year and
		# then the highest month.
		channel=$(printf '%s' "$index_content" |
			grep -o '"[^"]*":{"status":"supported"' | cut -d'"' -f2 |
			sort -t. -k1,1nr -k2,2nr | head -n1)
		[[ -n $channel ]] || {
			printf 'The release index at %s lists no supported series\n' "$manifest_base" >&2
			exit 1
		}
		printf 'Installing the supported series %s\n' "$channel" >&2
	fi

	# No fallback to anything else. Installing a series nobody asked for -- as
	# resolving `stable` to the nightly used to do -- hands somebody the
	# development channel while they believe they asked for the stable one.
	manifest_url="$manifest_base/$channel.json"
	manifest_content=$(download_to_string "$manifest_url") || {
		printf 'Could not read the %s manifest at %s\n' "$channel" "$manifest_url" >&2
		exit 1
	}

	release_tag=$(printf '%s' "$manifest_content" | grep -o '"release":"[^"]*"' | head -n1 | cut -d'"' -f4)
	[[ -n $release_tag ]] || {
		printf 'The %s manifest names no core release\n' "$channel" >&2
		exit 1
	}
	if [[ -z $url ]]; then
		url="https://github.com/vitasdk/autobuilds/releases/download/$release_tag/vitasdk-bootstrap-$host.tar.bz2"
	fi

	if [[ -z $expected_sha256 ]]; then
		sidecar_content=$(download_to_string "${url}.sha256" || true)
		if [[ -n $sidecar_content ]]; then
			expected_sha256=$(printf '%s' "$sidecar_content" | awk '{print $1}')
		fi
	fi

	# Grouped releases carry a single SHA256SUMS covering every asset, so the
	# digest stays available when an archive ships without its own sidecar.
	if [[ -z $expected_sha256 ]]; then
		sums_content=$(download_to_string "${url%/*}/SHA256SUMS" || true)
		if [[ -n $sums_content ]]; then
			expected_sha256=$(printf '%s' "$sums_content" |
				awk -v archive="${url##*/}" \
					'{ sub(/^\*/, "", $2) } $2 == archive { print $1; exit }')
		fi
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

install_parent=$(dirname "$install_directory")
mkdir -p "$install_parent"
install_parent=$(cd "$install_parent" && pwd -P)
install_directory="$install_parent/$(basename "$install_directory")"
temporary_directory=$(mktemp -d "$install_parent/.vitasdk-bootstrap.XXXXXXXX")
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
		required=(bin/vdpm.exe bin/arm-vita-eabi-gcc.exe usr/bin/pacman.exe \
			usr/bin/msys-2.0.dll etc/pacman.conf version_info.txt)
		vdpm_binary="$staging_directory/bin/vdpm.exe"
		pacman_binary="$staging_directory/usr/bin/pacman.exe"
		;;
	*)
		required=(bin/vdpm bin/arm-vita-eabi-gcc bin/pacman bin/vdpm-channel \
			bin/include/refresh-repositories.sh etc/pacman.conf version_info.txt)
		vdpm_binary="$staging_directory/bin/vdpm"
		pacman_binary="$staging_directory/bin/pacman"
		;;
esac
for relative_path in "${required[@]}"; do
	[[ -f $staging_directory/$relative_path && ! -L $staging_directory/$relative_path ]] || {
		printf 'VitaSDK bootstrap archive is missing %s\n' "$relative_path" >&2
		exit 1
	}
done
"$vdpm_binary" --help >/dev/null
"$pacman_binary" --version >/dev/null

installed_vdpm="$install_directory/${vdpm_binary#"$staging_directory"/}"

mv "$staging_directory" "$install_directory"
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
