#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-bootstrap-contract.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

archive_root="$temporary_directory/archive/vitasdk"
mkdir -p "$archive_root/bin/include" "$archive_root/libexec/vdpm" "$archive_root/etc"
for executable in vdpm-channel arm-vita-eabi-gcc; do
	printf '#!/usr/bin/env sh\nexit 0\n' > "$archive_root/bin/$executable"
	chmod +x "$archive_root/bin/$executable"
done
printf '#!/usr/bin/env sh\nexit 0\n' > "$archive_root/libexec/vdpm/pacman"
chmod +x "$archive_root/libexec/vdpm/pacman"
# Records what it was asked to do, so the test can tell whether the bootstrap
# selected the series it resolved instead of leaving the SDK on none.
cat > "$archive_root/bin/vdpm" <<'FAKE'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$(dirname "$0")/../vdpm-args.log"
exit 0
FAKE
chmod +x "$archive_root/bin/vdpm"
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

# A series is chosen from the published index rather than from a name baked
# into the script. `stable` was such a name: it resolved to nothing, and the
# fallback quietly installed the nightly.
channels="$temporary_directory/channels"
mkdir -p "$channels"
cat > "$channels/index.json" <<'EOF'
{"channels":{"2025.03":{"status":"end-of-life"},"2026.08":{"status":"supported"},"2026.09":{"status":"supported"},"nightly":{"status":"development"}},"schema_version":1}
EOF
printf 'signature\n' > "$channels/index.json.sig"
printf '{"channel":"2026.09","core":{"release":"sdk-core-2026.09.0"}}' \
	> "$channels/2026.09.json"

series_install="$temporary_directory/series installed"
output=$(VITASDK_BOOTSTRAP_URL="file://$archive" \
	VITASDK_CHANNEL_BASE_URL="file://$channels" \
	"$repository_root/bootstrap-vitasdk.sh" --install-dir "$series_install" 2>&1)
grep -q '2026\.09' <<<"$output" || {
	printf 'bootstrap did not pick the newest supported series:\n%s\n' "$output" >&2
	exit 1
}
grep -qx 'refresh 2026.09' "$series_install/vdpm-args.log" || {
	printf 'bootstrap installed a series without selecting it\n' >&2
	exit 1
}

# `stable` is an alias resolved at that moment, not a channel: what gets
# installed and recorded is the series it named.
alias_install="$temporary_directory/alias installed"
VITASDK_CHANNEL=stable \
	VITASDK_BOOTSTRAP_URL="file://$archive" \
	VITASDK_CHANNEL_BASE_URL="file://$channels" \
	"$repository_root/bootstrap-vitasdk.sh" --install-dir "$alias_install" > /dev/null 2>&1
grep -qx 'refresh 2026.09' "$alias_install/vdpm-args.log" || {
	printf 'the stable alias did not resolve to the newest supported series\n' >&2
	exit 1
}

# With nothing supported there is no answer, and inventing one is how somebody
# ends up on the development channel believing they asked for the stable one.
empty_channels="$temporary_directory/empty-channels"
mkdir -p "$empty_channels"
printf '{"channels":{"nightly":{"status":"development"}},"schema_version":1}' \
	> "$empty_channels/index.json"
printf 'signature\n' > "$empty_channels/index.json.sig"
if VITASDK_BOOTSTRAP_URL="file://$archive" \
	VITASDK_CHANNEL_BASE_URL="file://$empty_channels" \
	"$repository_root/bootstrap-vitasdk.sh" \
		--install-dir "$temporary_directory/none" > /dev/null 2>&1; then
	printf 'bootstrap installed something with no supported series published\n' >&2
	exit 1
fi
test ! -e "$temporary_directory/none"

# An unreachable index is a failure, not a reason to install something else.
if VITASDK_BOOTSTRAP_URL="file://$archive" \
	VITASDK_CHANNEL_BASE_URL="file://$temporary_directory/does-not-exist" \
	"$repository_root/bootstrap-vitasdk.sh" \
		--install-dir "$temporary_directory/unreachable" > /dev/null 2>&1; then
	printf 'bootstrap carried on without being able to read the index\n' >&2
	exit 1
fi

printf 'VitaSDK atomic bootstrap contract passed\n'
