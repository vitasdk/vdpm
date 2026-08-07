#!/usr/bin/env bash

set -euo pipefail

verify_sha256() {
	local expected=$1 file=$2 actual
	if command -v sha256sum >/dev/null; then
		actual=$(sha256sum "$file")
	else
		actual=$(shasum -a 256 "$file")
	fi
	actual=${actual%% *}
	[[ $actual == "$expected" ]]
}

install_vitasdk() {
	local install_directory=$1
	local archive
	local url=${VITASDK_BOOTSTRAP_URL:-}
	local expected_sha256=${VITASDK_BOOTSTRAP_SHA256:-}

	[[ -n $url ]] || {
		printf 'VITASDK_BOOTSTRAP_URL must select an immutable SDK archive\n' >&2
		return 1
	}
	[[ $expected_sha256 =~ ^[0-9a-f]{64}$ ]] || {
		printf 'VITASDK_BOOTSTRAP_SHA256 must contain the published archive hash\n' >&2
		return 1
	}

	mkdir -p "$install_directory"
	archive=$(mktemp "${TMPDIR:-/tmp}/vitasdk-bootstrap.XXXXXXXX.tar.bz2")
	trap 'rm -f -- "$archive"' RETURN

	if command -v curl >/dev/null; then
		curl --fail --location --show-error --output "$archive" "$url"
	elif command -v wget >/dev/null; then
		wget --output-document="$archive" "$url"
	else
		printf 'curl or wget is required to bootstrap VitaSDK\n' >&2
		return 1
	fi
	verify_sha256 "$expected_sha256" "$archive" || {
		printf 'VitaSDK bootstrap archive hash mismatch\n' >&2
		return 1
	}
	tar -xjf "$archive" -C "$install_directory" --strip-components=1
}
