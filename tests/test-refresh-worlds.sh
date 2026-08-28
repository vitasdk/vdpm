#!/usr/bin/env bash

# What refresh writes into pacman.conf comes from the manifest it verified.
#
# It used to say vita in three places -- the Architecture line, the repository
# section and the database file name -- which was right while one world
# existed. A second world's packages carry a different arch, and pacman
# refuses a package whose arch the configuration does not list, so a wrong
# line here is an installation that cannot install anything.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-refresh-worlds.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

source "$repository_root/include/host-triplet.sh"
host=$(vdpm_host_triplet) || { printf 'unsupported test host\n' >&2; exit 77; }

tool="$temporary_root/vdpm-channel"
# shellcheck disable=SC2046
"${CC:-cc}" -std=c99 -o "$tool" "$repository_root/src/vdpm-channel.c" \
	$(pkg-config --cflags libcrypto 2>/dev/null) \
	$(pkg-config --libs libcrypto 2>/dev/null || printf -- '-lcrypto')

openssl genpkey -algorithm ed25519 -out "$temporary_root/key.pem" 2>/dev/null
openssl pkey -in "$temporary_root/key.pem" -pubout \
	-out "$temporary_root/key-public.pem" 2>/dev/null

assets="$temporary_root/assets"
mkdir -p "$assets"
printf 'core database\n' > "$assets/$host.db"

digest_of() { "$tool" sha256 "$1"; }

# Writes a signed manifest for one world and returns the path.
manifest_for() {
	local world=$1 database=$2 out="$temporary_root/$1.json"

	printf 'packages database for %s\n' "$world" > "$assets/$database"
	printf '%s\n' "{\"channel\":\"nightly\",\"core\":{\"architectures\":{\"$host\":{\"database\":{\"name\":\"$host.db\",\"sha256\":\"$(digest_of "$assets/$host.db")\"}}},\"release\":\"sdk-1\",\"repository\":\"vitasdk/autobuilds\"},\"packages\":{\"database\":{\"name\":\"$database\",\"sha256\":\"$(digest_of "$assets/$database")\"},\"release\":\"packages-1\",\"repository\":\"vitasdk/vitasdk-autobuild\"},\"schema_version\":2,\"sequence\":7,\"world\":\"$world\"}" > "$out"
	openssl pkeyutl -sign -rawin -inkey "$temporary_root/key.pem" \
		-out "$out.sig" -in "$out" 2>/dev/null
	printf '%s\n' "$out"
}

refresh_into() {
	local root=$1 manifest=$2

	mkdir -p "$root/share/vdpm"
	VITASDK="$root" \
	VITASDK_CHANNEL_PUBLIC_KEY="$temporary_root/key-public.pem" \
	VITASDK_CHANNEL_MANIFEST="$manifest" \
	VITASDK_CHANNEL_ASSET_DIRECTORY="$assets" \
	VDPM_CHANNEL_TOOL="$tool" \
		bash "$repository_root/include/refresh-repositories.sh" nightly
}

hard=$(manifest_for vita vita.db)
soft=$(manifest_for vita_softfp vita_softfp.db)

# --- a second world reaches the configuration unchanged ---------------------

root="$temporary_root/softfp-root"
refresh_into "$root" "$soft" >/dev/null

grep -qx "Architecture = $host vita_softfp" "$root/etc/pacman.conf" || {
	printf 'Architecture does not name the world:\n' >&2
	sed -n '1,6p' "$root/etc/pacman.conf" >&2
	exit 1
}
grep -qx '\[vita_softfp\]' "$root/etc/pacman.conf" || {
	printf 'repository section does not name the world\n' >&2
	exit 1
}
grep -q '\[vita\]' "$root/etc/pacman.conf" && {
	printf 'the first world leaked into a second world configuration\n' >&2
	exit 1
}
[[ -f $root/var/lib/pacman/sync/vita_softfp.db ]] || {
	printf 'the database was not stored under the name the manifest gives\n' >&2
	ls "$root/var/lib/pacman/sync" >&2
	exit 1
}

# --- the first world still works ---------------------------------------------

root="$temporary_root/hard-root"
refresh_into "$root" "$hard" >/dev/null
grep -qx "Architecture = $host vita" "$root/etc/pacman.conf"
grep -qx '\[vita\]' "$root/etc/pacman.conf"
[[ -f $root/var/lib/pacman/sync/vita.db ]]

# --- a root keeps the world it has -------------------------------------------

if refresh_into "$root" "$soft" >/dev/null 2>"$temporary_root/refusal"; then
	printf 'a refresh changed the world of an existing root\n' >&2
	exit 1
fi
grep -q 'needs a new VITASDK root' "$temporary_root/refusal" || {
	printf 'refused without saying why:\n' >&2
	cat "$temporary_root/refusal" >&2
	exit 1
}
# The refusal must not have touched what was there.
grep -qx "Architecture = $host vita" "$root/etc/pacman.conf" || {
	printf 'the refused refresh rewrote the configuration anyway\n' >&2
	exit 1
}

printf 'refresh world contract tests passed\n'
