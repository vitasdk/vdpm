#!/usr/bin/env bash

set -euo pipefail

# No argument means the default channel; an empty one is a mistake, and
# quietly turning it into stable would move somebody off their release.
channel=${1-stable}
# A channel is a name, not a fixed list: a release series is a channel that
# lives as long as the release does, so 2026.09 has to be sayable. It is
# still checked, because the name goes into a URL and a file path.
[[ $channel =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
	printf 'invalid channel name: %s\n' "$channel" >&2
	exit 1
}
[[ $channel != *..* ]] || {
	printf 'invalid channel name: %s\n' "$channel" >&2
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
channel_tool=${VDPM_CHANNEL_TOOL:-$script_directory/../vdpm-channel}
[[ -x $channel_tool ]] || {
	printf 'channel helper is not installed: %s\n' "$channel_tool" >&2
	exit 1
}
[[ ! -e $VITASDK/var/lib/pacman/db.lck ]] || {
	# Refusing is right: the configuration must not be rewritten under a
	# transaction. Saying only that leaves somebody who pressed Ctrl-C with
	# no way out, so say what the lock is and how to clear it.
	printf 'the package database is locked, so the repositories were not touched\n' >&2
	printf 'another vdpm or pacman may be running; if none is, an interrupted one\n' >&2
	printf 'left the lock behind and it is safe to remove:\n' >&2
	printf '  rm %s/var/lib/pacman/db.lck\n' "$VITASDK" >&2
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

# The manifest is authenticated before it is parsed, so no untrusted structure
# is interpreted on the strength of an unverified signature.
"$channel_tool" verify "$manifest" "$signature" "$public_key"
"$channel_tool" validate "$manifest" "$channel" "$host"

value() {
	"$channel_tool" field "$manifest" "$channel" "$host" "$1"
}
verify_hash() {
	local expected=$1 file=$2

	[[ $("$channel_tool" sha256 "$file") == "$expected" ]]
}
download_database() {
	local url=$1 name=$2 destination=$3

	if [[ -n ${VITASDK_CHANNEL_ASSET_DIRECTORY:-} ]]; then
		[[ -f $VITASDK_CHANNEL_ASSET_DIRECTORY/$name &&
			! -L $VITASDK_CHANNEL_ASSET_DIRECTORY/$name ]] || {
			printf 'channel database is not available: %s\n' \
				"$VITASDK_CHANNEL_ASSET_DIRECTORY/$name" >&2
			exit 1
		}
		cp "$VITASDK_CHANNEL_ASSET_DIRECTORY/$name" "$destination"
	else
		download "$url" "$destination"
	fi
}

core_database="$temporary_directory/$host.db"
vita_database="$temporary_directory/vita.db"
download_database "$(value core.database.url)" \
	"$(value core.database.name)" "$core_database"
download_database "$(value packages.database.url)" \
	"$(value packages.database.name)" "$vita_database"
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
mv "$configuration" "$VITASDK/etc/pacman.conf"

# The selection is staged, not made. Moving between series is a package
# transaction, and until that transaction succeeds this installation is still
# on the series whose toolchain it actually has: whoever runs this commits the
# staged manifest afterwards.
cp "$manifest" "$VITASDK/var/lib/vdpm/channel.json.staged"
printf 'refreshed %s channel sequence %s\n' "$channel" "$(value sequence)"
