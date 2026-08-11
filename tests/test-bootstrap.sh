#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-bootstrap-contract.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

archive_root="$temporary_directory/archive/vitasdk"
mkdir -p "$archive_root/bin/include" "$archive_root/etc"
for executable in vdpm pacman vdpm-channel arm-vita-eabi-gcc; do
	printf '#!/usr/bin/env sh\nexit 0\n' > "$archive_root/bin/$executable"
	chmod +x "$archive_root/bin/$executable"
done
printf '#!/usr/bin/env sh\nexit 0\n' > \
	"$archive_root/bin/include/refresh-repositories.sh"
chmod +x "$archive_root/bin/include/refresh-repositories.sh"
printf '[options]\nArchitecture = test vita\n' > "$archive_root/etc/pacman.conf"
printf 'test revision\n' > "$archive_root/version_info.txt"
archive="$temporary_directory/vitasdk.tar.bz2"
tar -cjf "$archive" -C "$temporary_directory/archive" vitasdk
if command -v sha256sum >/dev/null; then
	digest=$(sha256sum "$archive")
else
	digest=$(shasum -a 256 "$archive")
fi
digest=${digest%% *}

install_directory="$temporary_directory/installed sdk"
VITASDK_BOOTSTRAP_ARCHIVE="$archive" \
VITASDK_BOOTSTRAP_SHA256="$digest" \
	"$repository_root/bootstrap-vitasdk.sh" --install-dir "$install_directory"
test -x "$install_directory/bin/vdpm"
test -f "$install_directory/version_info.txt"

bad_directory="$temporary_directory/bad"
if [[ ${digest:0:1} == 0 ]]; then
	bad_digest="1${digest:1}"
else
	bad_digest="0${digest:1}"
fi
if VITASDK_BOOTSTRAP_ARCHIVE="$archive" \
	VITASDK_BOOTSTRAP_SHA256="$bad_digest" \
	"$repository_root/bootstrap-vitasdk.sh" --install-dir "$bad_directory"; then
	printf 'bootstrap accepted a bad archive digest\n' >&2
	exit 1
fi
test ! -e "$bad_directory"

printf 'keep\n' > "$temporary_directory/marker"
if VITASDK_BOOTSTRAP_ARCHIVE="$archive" \
	VITASDK_BOOTSTRAP_SHA256="$digest" \
	"$repository_root/bootstrap-vitasdk.sh" \
		--install-dir "$install_directory"; then
	printf 'bootstrap replaced an existing SDK\n' >&2
	exit 1
fi
# Test auto-reading digest from adjacent .sha256 file
printf '%s  %s\n' "$digest" "$(basename "$archive")" > "${archive}.sha256"
sidecar_install="$temporary_directory/sidecar installed"
VITASDK_BOOTSTRAP_ARCHIVE="$archive" \
	"$repository_root/bootstrap-vitasdk.sh" --install-dir "$sidecar_install"
test -x "$sidecar_install/bin/vdpm"
test -f "$sidecar_install/version_info.txt"

printf 'VitaSDK atomic bootstrap contract passed\n'
