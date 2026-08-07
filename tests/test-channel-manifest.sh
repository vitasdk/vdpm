#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-manifest.XXXXXXXX")
host=$(uname -m)
[[ $host == arm64 && $(uname -s) == Linux ]] && host=aarch64
case $(uname -s) in
	Darwin*) host="$host-apple-darwin" ;;
	Linux*) host="$host-linux-gnu" ;;
	*) printf 'unsupported test host\n' >&2; exit 1 ;;
esac

cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

python3 - "$temporary_root/channel.json" "$host" <<'PY'
import json, sys
manifest = {
    "channel": "nightly",
    "core": {
        "architectures": {sys.argv[2]: {"database": {"name": f"{sys.argv[2]}.db", "sha256": "1" * 64}}},
        "release": "sdk-snapshot-1",
        "repository": "vitasdk/autobuilds",
    },
    "packages": {
        "database": {"name": "vita.db", "sha256": "2" * 64},
        "release": "packages-snapshot-1",
        "repository": "vitasdk/packages",
    },
    "schema_version": 1,
    "sequence": 7,
}
with open(sys.argv[1], "w") as output:
    output.write(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
PY

openssl genpkey -algorithm ED25519 -out "$temporary_root/private.pem" >/dev/null 2>&1
openssl pkey -in "$temporary_root/private.pem" -pubout \
	-out "$temporary_root/public.pem" >/dev/null 2>&1
openssl pkeyutl -sign -inkey "$temporary_root/private.pem" -rawin \
	-in "$temporary_root/channel.json" -out "$temporary_root/channel.json.sig"
openssl pkeyutl -verify -pubin -inkey "$temporary_root/public.pem" -rawin \
	-in "$temporary_root/channel.json" -sigfile "$temporary_root/channel.json.sig" \
	>/dev/null

tool="$repository_root/include/channel-manifest.py"
python3 "$tool" "$temporary_root/channel.json" nightly "$host"
test "$(python3 "$tool" "$temporary_root/channel.json" nightly "$host" sequence)" = 7
test "$(python3 "$tool" "$temporary_root/channel.json" nightly "$host" packages.database.name)" = vita.db

printf ' ' >> "$temporary_root/channel.json"
if python3 "$tool" "$temporary_root/channel.json" nightly "$host"; then
	printf 'non-canonical manifest was unexpectedly accepted\n' >&2
	exit 1
fi
if openssl pkeyutl -verify -pubin -inkey "$temporary_root/public.pem" -rawin \
	-in "$temporary_root/channel.json" -sigfile "$temporary_root/channel.json.sig" \
	>/dev/null 2>&1; then
	printf 'modified signed manifest was unexpectedly accepted\n' >&2
	exit 1
fi

printf 'vdpm signed channel manifest contracts passed\n'
