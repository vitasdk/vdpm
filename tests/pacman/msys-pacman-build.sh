#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
	printf 'usage: %s <output-directory>\n' "$0" >&2
	exit 2
fi

script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd "$script_directory/../.." && pwd -P)
output_directory=$1
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-msys-pacman-build.XXXXXXXX")
source_directory="$work_directory/pacman"
build_directory="$work_directory/build"

cleanup() {
	rm -rf -- "$work_directory"
}
trap cleanup EXIT

git -c core.autocrlf=false clone --depth 1 --branch v7.1.0 \
	https://gitlab.archlinux.org/pacman/pacman.git "$source_directory"

# Git for Windows initially materializes Pacman's source symlinks as files
# containing the link target. Re-check them out through the MSYS runtime.
git -C "$source_directory" config core.symlinks true
git -C "$source_directory" reset --hard HEAD

expected_revision=5683f8477a0afcc6b331766175a83445b2dcfe89
actual_revision=$(git -C "$source_directory" rev-parse HEAD)
[[ $actual_revision == "$expected_revision" ]] || {
	printf 'unexpected pacman revision: %s\n' "$actual_revision" >&2
	exit 1
}

for patch in \
	"$repository_root/patches/pacman/0001-allow-writable-non-root-installation-roots.patch" \
	"$repository_root/patches/pacman/0002-embed-libalpm-in-static-clients.patch" \
	"$repository_root/patches/pacman/0004-initialize-locale-without-i18n.patch" \
	"$repository_root/patches/pacman/0005-reject-windows-casefold-collisions.patch"
do
	git -C "$source_directory" apply --check --whitespace=error-all "$patch"
	git -C "$source_directory" apply --whitespace=error-all "$patch"
done

export CFLAGS="${CFLAGS:-} -O2 -fzero-init-padding-bits=unions"
export LDFLAGS="${LDFLAGS:-} -static-libgcc"

meson setup "$build_directory" "$source_directory" \
	--buildtype=release \
	--prefix=/usr \
	--sysconfdir=/etc \
	--localstatedir=/var \
	--default-library=static \
	-Dbuildstatic=true \
	-Ddoc=disabled \
	-Ddoxygen=disabled \
	-Di18n=false \
	-Dgpgme=disabled \
	-Dcurl=enabled \
	-Dcrypto=openssl \
	-Duse-git-version=false \
	-Dpkg-ext=.pkg.tar.xz \
	-Dscriptlet-shell=/usr/bin/false
meson compile -C "$build_directory"

mkdir -p "$output_directory"
cp "$build_directory/pacman.exe" "$output_directory/pacman.exe"
cp /usr/bin/msys-2.0.dll "$output_directory/msys-2.0.dll"

mapfile -t imports < <(
	objdump -p "$output_directory/pacman.exe" |
		sed -n 's/^[[:space:]]*DLL Name: //p' |
		sort -fu
)
printf 'pacman.exe imports:\n'
printf '  %s\n' "${imports[@]}"

for import in "${imports[@]}"; do
	case ${import,,} in
		msys-2.0.dll|crypt32.dll|kernel32.dll) ;;
		*)
			printf 'unexpected pacman runtime import: %s\n' "$import" >&2
			exit 1
			;;
	esac
done
(( ${#imports[@]} == 3 )) || {
	printf 'pacman runtime import set is incomplete\n' >&2
	exit 1
}

printf 'built patched pacman 7.1.0 with the two-file MSYS runtime contract\n'
