#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
usage: bootstrap-vitasdk.sh [--install-dir PATH] [--url URL] [--sha256 HEX]

Installs one immutable VitaSDK archive into a new directory. The equivalent
VITASDK, VITASDK_BOOTSTRAP_URL and VITASDK_BOOTSTRAP_SHA256 environment
variables may be used. VITASDK_BOOTSTRAP_ARCHIVE selects a local archive for
offline installation and tests; its SHA-256 is still mandatory.
EOF
}

install_directory=${VITASDK:-/usr/local/vitasdk}
url=${VITASDK_BOOTSTRAP_URL:-}
expected_sha256=${VITASDK_BOOTSTRAP_SHA256:-}
local_archive=${VITASDK_BOOTSTRAP_ARCHIVE:-}

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

[[ $install_directory == /* && $install_directory != / ]] || {
	printf 'VitaSDK install directory must be an absolute, non-root path\n' >&2
	exit 1
}
[[ ! -e $install_directory ]] || {
	printf 'VitaSDK install directory already exists: %s\n' "$install_directory" >&2
	exit 1
}
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

mv "$staging_directory" "$install_directory"
printf 'VitaSDK installed at %s\n' "$install_directory"
printf 'export VITASDK=%q\n' "$install_directory"
printf '%s\n' 'export PATH=$VITASDK/bin:$PATH'
