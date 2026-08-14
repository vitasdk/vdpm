#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-release-contract.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

root="$temporary_directory/root"
mkdir -p "$root/bin/include" "$root/share/vdpm/licenses" \
	"$temporary_directory/output-one" "$temporary_directory/output-two"
for executable in vdpm pacman pacman-conf vdpm-channel; do
	printf '#!/usr/bin/env sh\nexit 0\n' > "$root/bin/$executable"
	chmod +x "$root/bin/$executable"
done
for helper in host-triplet.sh refresh-repositories.sh; do
	printf '#!/usr/bin/env sh\nexit 0\n' > "$root/bin/include/$helper"
	chmod +x "$root/bin/include/$helper"
done
cp "$repository_root/THIRD_PARTY_NOTICES.md" "$root/share/vdpm/"
for license in vdpm-LGPL-2.1.txt pacman-GPL-2.0.txt zlib.txt xz-COPYING.txt \
		libarchive.txt openssl-Apache-2.0.txt curl.txt; do
	printf 'license %s\n' "$license" > "$root/share/vdpm/licenses/$license"
done

export SOURCE_DATE_EPOCH=1700000000
revision=0123456789abcdef0123456789abcdef01234567
host=x86_64-linux-gnu
"$repository_root/scripts/create-release-bundle.sh" \
	"$root" "$temporary_directory/output-one" "$host" 1.0.0 "$revision"
"$repository_root/scripts/create-release-bundle.sh" \
	"$root" "$temporary_directory/output-two" "$host" 1.0.0 "$revision"
cmp "$temporary_directory/output-one/vdpm-1.0.0-$host.tar.bz2" \
	"$temporary_directory/output-two/vdpm-1.0.0-$host.tar.bz2"
VDPM_VALIDATE_EXECUTABLES=1 \
	"$repository_root/scripts/validate-release-bundle.sh" \
	"$temporary_directory/output-one/vdpm-1.0.0-$host.tar.bz2" "$host"

windows_root="$temporary_directory/windows-root"
windows_output="$temporary_directory/windows-output"
mkdir -p "$windows_root/bin" "$windows_root/share/vdpm/msys/usr/bin" \
	"$windows_root/share/vdpm/msys/usr/ssl/certs" \
	"$windows_root/share/vdpm/licenses" "$windows_output"
# A Windows bundle without a CA store can verify a channel and then fail to
# download anything from it, so the validator refuses one and the fixture has
# to carry it.
printf 'certificates\n' > "$windows_root/share/vdpm/msys/usr/ssl/certs/ca-bundle.crt"
for relative_path in bin/vdpm.exe share/vdpm/msys/usr/bin/pacman.exe \
		share/vdpm/msys/usr/bin/vdpm-channel.exe share/vdpm/msys/usr/bin/msys-2.0.dll; do
	printf 'fixture %s\n' "$relative_path" > "$windows_root/$relative_path"
done
printf 'refresh fixture\n' > \
	"$windows_root/share/vdpm/refresh-repositories.ps1"
cp "$repository_root/THIRD_PARTY_NOTICES.md" "$windows_root/share/vdpm/"
printf 'license\n' > "$windows_root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
windows_host=x86_64-w64-mingw32
"$repository_root/scripts/create-release-bundle.sh" \
	"$windows_root" "$windows_output" "$windows_host" 1.0.0 "$revision"
"$repository_root/scripts/validate-release-bundle.sh" \
	"$windows_output/vdpm-1.0.0-$windows_host.tar.bz2" "$windows_host"

printf 'vdpm reproducible release bundle contract passed\n'
