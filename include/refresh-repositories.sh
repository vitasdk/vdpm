#!/usr/bin/env bash

set -euo pipefail

channel=${1:-stable}
[[ $channel == stable || $channel == nightly ]] || {
	printf 'unsupported channel: %s\n' "$channel" >&2
	exit 1
}
[[ -n ${VITASDK:-} ]] || exit 1

script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
source "$script_directory/host-triplet.sh"
host=$(vdpm_host_triplet) || {
	printf 'unsupported host\n' >&2
	exit 1
}
public_key=${VITASDK_CHANNEL_PUBLIC_KEY:-$VITASDK/share/vdpm/channel-public-key.pem}
[[ -r $public_key ]] || {
	printf 'channel public key is not installed: %s\n' "$public_key" >&2
	exit 1
}
[[ ! -e $VITASDK/var/lib/pacman/db.lck ]] || {
	printf 'pacman database is locked; repository refresh refused\n' >&2
	exit 1
}

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-refresh.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT
manifest="$temporary_directory/channel.json"
signature="$temporary_directory/channel.json.sig"

download() {
	curl --fail --location --silent --show-error --output "$2" "$1"
}

if [[ -n ${VITASDK_CHANNEL_MANIFEST:-} ]]; then
	cp "$VITASDK_CHANNEL_MANIFEST" "$manifest"
	cp "${VITASDK_CHANNEL_MANIFEST}.sig" "$signature"
else
	base=${VITASDK_CHANNEL_BASE_URL:-https://vitasdk.github.io/channels}
	download "$base/$channel.json" "$manifest"
	download "$base/$channel.json.sig" "$signature"
fi

openssl pkeyutl -verify -pubin -inkey "$public_key" -rawin \
	-in "$manifest" -sigfile "$signature" >/dev/null
python3 "$script_directory/channel-manifest.py" "$manifest" "$channel" "$host"

value() {
	python3 "$script_directory/channel-manifest.py" "$manifest" "$channel" "$host" "$1"
}
verify_hash() {
	local expected=$1 file=$2 actual
	if command -v sha256sum >/dev/null; then actual=$(sha256sum "$file");
	else actual=$(shasum -a 256 "$file"); fi
	actual=${actual%% *}
	[[ $actual == "$expected" ]]
}

core_database="$temporary_directory/$host.db"
vita_database="$temporary_directory/vita.db"
download "$(value core.database.url)" "$core_database"
download "$(value packages.database.url)" "$vita_database"
verify_hash "$(value core.database.sha256)" "$core_database"
verify_hash "$(value packages.database.sha256)" "$vita_database"

mkdir -p "$VITASDK/etc" "$VITASDK/var/lib/pacman/sync" "$VITASDK/var/lib/vdpm"
configuration="$temporary_directory/pacman.conf"
cat > "$configuration" <<EOF
[options]
Architecture = $host vita
# vdpm verifies signed channel metadata and the selected database hash before use.
SigLevel = Never
[$host]
Server = $(value core.server)
[vita]
Server = $(value packages.server)
EOF
cp "$core_database" "$VITASDK/var/lib/pacman/sync/$host.db"
cp "$vita_database" "$VITASDK/var/lib/pacman/sync/vita.db"
cp "$manifest" "$VITASDK/var/lib/vdpm/channel.json"
mv "$configuration" "$VITASDK/etc/pacman.conf"
printf 'refreshed %s channel sequence %s\n' "$channel" "$(value sequence)"
