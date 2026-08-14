#!/usr/bin/env bash

set -euo pipefail

if (( $# != 5 )); then
	printf 'usage: %s <product-root> <output-directory> <host-triplet> <version> <source-revision>\n' "$0" >&2
	exit 2
fi

product_root=$1
output_directory=$2
host=$3
version=$4
source_revision=$5
source_date_epoch=${SOURCE_DATE_EPOCH:-}

[[ -d $product_root && $product_root == /* && $product_root != / ]] || {
	printf 'product root must be an absolute, non-root directory\n' >&2
	exit 1
}
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
	printf 'invalid host triplet: %s\n' "$host" >&2
	exit 1
}
[[ $version =~ ^[A-Za-z0-9][A-Za-z0-9.+-]*$ ]] || {
	printf 'invalid release version: %s\n' "$version" >&2
	exit 1
}
[[ $source_revision =~ ^[0-9a-fA-F]{7,64}$ ]] || {
	printf 'source revision must be a hexadecimal Git object name\n' >&2
	exit 1
}
[[ -n $source_date_epoch && $source_date_epoch =~ ^[0-9]+$ ]] || {
	printf 'SOURCE_DATE_EPOCH must be a non-negative integer\n' >&2
	exit 1
}

required=(share/vdpm/THIRD_PARTY_NOTICES.md share/vdpm/licenses/vdpm-LGPL-2.1.txt)
case $host in
	*-w64-mingw32)
		required+=(
			bin/vdpm.exe share/vdpm/msys/usr/bin/pacman.exe share/vdpm/msys/usr/bin/vdpm-channel.exe
			share/vdpm/msys/usr/bin/msys-2.0.dll share/vdpm/refresh-repositories.ps1)
		;;
	*)
		required+=(
			bin/vdpm bin/pacman bin/pacman-conf bin/vdpm-channel
			bin/include/host-triplet.sh bin/include/refresh-repositories.sh
			share/vdpm/licenses/pacman-GPL-2.0.txt
			share/vdpm/licenses/zlib.txt
			share/vdpm/licenses/xz-COPYING.txt
			share/vdpm/licenses/libarchive.txt
			share/vdpm/licenses/openssl-Apache-2.0.txt
			share/vdpm/licenses/curl.txt)
		;;
esac
for relative_path in "${required[@]}"; do
	[[ -f $product_root/$relative_path && ! -L $product_root/$relative_path ]] || {
		printf 'required bundle file is missing: %s\n' "$relative_path" >&2
		exit 1
	}
done

mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd -P)
bundle_name="vdpm-$version-$host"
archive="$output_directory/$bundle_name.tar.bz2"
checksum="$archive.sha256"
normalized_revision=$(printf '%s' "$source_revision" | tr 'A-F' 'a-f')
[[ ! -e $archive && ! -e $checksum ]] || {
	printf 'release output already exists: %s\n' "$archive" >&2
	exit 1
}

temporary_directory=$(mktemp -d "$output_directory/.vdpm-release.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT
bundle_root="$temporary_directory/$bundle_name"
mkdir -p "$bundle_root/share/vdpm"
cp -a "$product_root/." "$bundle_root/"

cat > "$bundle_root/share/vdpm/release-info.txt" <<EOF
schema_version=1
host=$host
version=$version
source_revision=$normalized_revision
source_date_epoch=$source_date_epoch
pacman_revision=5683f8477a0afcc6b331766175a83445b2dcfe89
EOF

if touch -h -d "@$source_date_epoch" "$bundle_root" 2>/dev/null; then
	find "$bundle_root" -exec touch -h -d "@$source_date_epoch" {} +
else
	timestamp=$(date -r "$source_date_epoch" -u '+%Y%m%d%H%M.%S')
	find "$bundle_root" -exec touch -h -t "$timestamp" {} +
fi

(
	cd "$temporary_directory"
	find "$bundle_name" -print | LC_ALL=C sort > archive.list
	if tar --version 2>/dev/null | grep -q 'GNU tar'; then
		tar --no-recursion --sort=name --mtime="@$source_date_epoch" \
			--owner=0 --group=0 --numeric-owner -cjf "$archive" -T archive.list
	else
		COPYFILE_DISABLE=1 tar --no-recursion --uid 0 --gid 0 \
			--uname root --gname root -cjf "$archive" -T archive.list
	fi
)

if command -v sha256sum >/dev/null; then
	(
		cd "$output_directory"
		sha256sum "$(basename "$archive")"
	) > "$checksum"
else
	digest=$(shasum -a 256 "$archive")
	printf '%s  %s\n' "${digest%% *}" "$(basename "$archive")" > "$checksum"
fi

printf '%s\n' "$archive"
