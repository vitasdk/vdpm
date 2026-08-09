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

printf 'vdpm reproducible release bundle contract passed\n'
