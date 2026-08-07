#!/usr/bin/env bash

# Contract tests for the channel manifest helper.
#
# The canonical manifest is written out literally instead of being generated,
# so the exact byte sequence the client accepts stays visible in review. Key
# generation and signing use openssl because those are maintainer operations
# that run on a build machine; the client side under test never invokes it.

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

tool="$temporary_root/vdpm-channel"
cc_flags=$(pkg-config --cflags libcrypto 2>/dev/null || true)
cc_libraries=$(pkg-config --libs libcrypto 2>/dev/null || printf -- '-lcrypto')
# shellcheck disable=SC2086
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror -o "$tool" \
	"$repository_root/src/vdpm-channel.c" $cc_flags $cc_libraries

core_digest=$(printf '1%.0s' {1..64})
packages_digest=$(printf '2%.0s' {1..64})

write_manifest() {
	printf '%s\n' "{\"channel\":\"nightly\",\"core\":{\"architectures\":{\"$host\":{\"database\":{\"name\":\"$host.db\",\"sha256\":\"$core_digest\"}}},\"release\":\"sdk-snapshot-1\",\"repository\":\"vitasdk/autobuilds\"},\"packages\":{\"database\":{\"name\":\"vita.db\",\"sha256\":\"$packages_digest\"},\"release\":\"packages-snapshot-1\",\"repository\":\"vitasdk/packages\"},\"schema_version\":1,\"sequence\":7}" > "$1"
}

manifest="$temporary_root/channel.json"
write_manifest "$manifest"

expect_accepted() {
	"$tool" validate "$1" nightly "$host"
}

expect_rejected() {
	local description=$1 file=$2
	if "$tool" validate "$file" nightly "$host" >/dev/null 2>&1; then
		printf 'unexpectedly accepted: %s\n' "$description" >&2
		exit 1
	fi
}

field() {
	"$tool" field "$manifest" nightly "$host" "$1"
}

# --- accepted manifest and field extraction --------------------------------

expect_accepted "$manifest"
test "$(field sequence)" = 7
test "$(field core.database.name)" = "$host.db"
test "$(field core.database.sha256)" = "$core_digest"
test "$(field packages.database.name)" = vita.db
test "$(field packages.database.sha256)" = "$packages_digest"
test "$(field core.database.url)" = \
	"https://github.com/vitasdk/autobuilds/releases/download/sdk-snapshot-1/$host.db"
test "$(field core.server)" = \
	"https://github.com/vitasdk/autobuilds/releases/download/sdk-snapshot-1"
test "$(field packages.database.url)" = \
	"https://github.com/vitasdk/packages/releases/download/packages-snapshot-1/vita.db"
test "$(field packages.server)" = \
	"https://github.com/vitasdk/packages/releases/download/packages-snapshot-1"

if "$tool" field "$manifest" nightly "$host" core.database.path >/dev/null 2>&1; then
	printf 'unknown field was unexpectedly accepted\n' >&2
	exit 1
fi
if "$tool" validate "$manifest" stable "$host" >/dev/null 2>&1; then
	printf 'manifest for another channel was unexpectedly accepted\n' >&2
	exit 1
fi
if "$tool" validate "$manifest" nightly powerpc-unknown-linux-gnu >/dev/null 2>&1; then
	printf 'unpublished host was unexpectedly accepted\n' >&2
	exit 1
fi

# --- non-canonical serialization -------------------------------------------

variant_file="$temporary_root/variant.json"

# Exact bytes, with no trailing newline appended.
reject_document() {
	local description=$1 body=$2

	printf '%s' "$body" > "$variant_file"
	expect_rejected "$description" "$variant_file"
}

# One substitution inside an otherwise canonical manifest. A substitution that
# matches nothing would make the rejection vacuous, so it is an error here.
reject_replaced() {
	local description=$1 search=$2 replace=$3 body

	body=${minimal//"$search"/"$replace"}
	if [[ $body == "$minimal" ]]; then
		printf 'test defect: no substitution applied for %s\n' "$description" >&2
		exit 1
	fi
	printf '%s\n' "$body" > "$variant_file"
	expect_rejected "$description" "$variant_file"
}

minimal="{\"channel\":\"nightly\",\"core\":{\"architectures\":{\"$host\":{\"database\":{\"name\":\"$host.db\",\"sha256\":\"$core_digest\"}}},\"release\":\"r\",\"repository\":\"vitasdk/autobuilds\"},\"packages\":{\"database\":{\"name\":\"vita.db\",\"sha256\":\"$packages_digest\"},\"release\":\"r\",\"repository\":\"vitasdk/packages\"},\"schema_version\":1,\"sequence\":7}"

# Positive control: every rejection below must be caused by its substitution
# rather than by the base document.
printf '%s\n' "$minimal" > "$variant_file"
expect_accepted "$variant_file"

reject_document 'missing trailing newline' "$minimal"
reject_document 'trailing whitespace' "$minimal"$'\n '
reject_document 'trailing data after the document' "$minimal"$'\n{}\n'
reject_document 'descending key order' \
	'{"core":{},"channel":"nightly","schema_version":1,"sequence":7}'$'\n'
reject_document 'duplicate keys' \
	'{"channel":"nightly","channel":"nightly","schema_version":1,"sequence":7}'$'\n'

reject_replaced 'insignificant whitespace' '{"channel"' '{ "channel"'
reject_replaced 'array value' '"sequence":7' '"sequence":[7]'
reject_replaced 'floating point sequence' '"sequence":7' '"sequence":7.0'
reject_replaced 'negative sequence' '"sequence":7' '"sequence":-7'
reject_replaced 'leading zero' '"sequence":7' '"sequence":07'
reject_replaced 'null value' '"sequence":7' '"sequence":null'
reject_replaced 'escape sequence in a string' '"release":"r"' '"release":"\u0072"'

# --- schema and value constraints ------------------------------------------

reject_replaced 'unsupported schema version' '"schema_version":1' '"schema_version":2'
reject_replaced 'zero channel sequence' '"sequence":7' '"sequence":0'
reject_replaced 'short database digest' "$packages_digest" 'abc'
reject_replaced 'uppercase database digest' "$packages_digest" "$(printf 'A%.0s' {1..64})"
reject_replaced 'relative asset name' '"name":"vita.db"' '"name":".."'
reject_replaced 'asset name with a separator' '"name":"vita.db"' '"name":"a/b"'
reject_replaced 'repository without an owner' '"vitasdk/packages"' '"packages"'
reject_replaced 'repository with an extra component' '"vitasdk/packages"' '"vitasdk/a/b"'

# --- detached signature -----------------------------------------------------

openssl genpkey -algorithm ED25519 -out "$temporary_root/private.pem" >/dev/null 2>&1
openssl pkey -in "$temporary_root/private.pem" -pubout \
	-out "$temporary_root/public.pem" >/dev/null 2>&1
openssl genpkey -algorithm ED25519 -out "$temporary_root/other.pem" >/dev/null 2>&1
openssl pkey -in "$temporary_root/other.pem" -pubout \
	-out "$temporary_root/other-public.pem" >/dev/null 2>&1
openssl pkeyutl -sign -inkey "$temporary_root/private.pem" -rawin \
	-in "$manifest" -out "$manifest.sig"

signature="$manifest.sig"
public_key="$temporary_root/public.pem"
"$tool" verify "$manifest" "$signature" "$public_key"

if "$tool" verify "$manifest" "$signature" "$temporary_root/other-public.pem" >/dev/null 2>&1; then
	printf 'signature from another key was unexpectedly accepted\n' >&2
	exit 1
fi

tampered="$temporary_root/tampered.json"
write_manifest "$tampered"
printf ' ' >> "$tampered"
if "$tool" verify "$tampered" "$signature" "$public_key" >/dev/null 2>&1; then
	printf 'modified signed manifest was unexpectedly accepted\n' >&2
	exit 1
fi

head -c 32 "$signature" > "$temporary_root/short.sig"
if "$tool" verify "$manifest" "$temporary_root/short.sig" "$public_key" >/dev/null 2>&1; then
	printf 'truncated signature was unexpectedly accepted\n' >&2
	exit 1
fi

openssl genpkey -algorithm RSA -out "$temporary_root/rsa.pem" >/dev/null 2>&1
openssl pkey -in "$temporary_root/rsa.pem" -pubout \
	-out "$temporary_root/rsa-public.pem" >/dev/null 2>&1
if "$tool" verify "$manifest" "$signature" "$temporary_root/rsa-public.pem" >/dev/null 2>&1; then
	printf 'non-Ed25519 public key was unexpectedly accepted\n' >&2
	exit 1
fi

# --- digests ----------------------------------------------------------------

printf 'vitasdk' > "$temporary_root/digest-input"
expected_digest=$(openssl dgst -sha256 "$temporary_root/digest-input" | tr -d '\n' | sed 's/.*= *//')
test "$("$tool" sha256 "$temporary_root/digest-input")" = "$expected_digest"
test "$("$tool" sha256 /dev/null)" = \
	e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

printf 'vdpm signed channel manifest contracts passed\n'
