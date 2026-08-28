#!/usr/bin/env bash
# Which release series exist, and what state each of them is in.
#
# Without this a release is undiscoverable: you would have to be told its name
# by somebody before you could ask for it, and a series that has ended has no
# way to say so. Ubuntu publishes the same thing as meta-release.
#
# The index is signed with the same key as the manifests, because it decides
# where people are told they can move to.

set -euo pipefail

[[ -n ${VITASDK:-} ]] || {
	printf 'VITASDK is not set\n' >&2
	exit 1
}

channel_tool="$VITASDK/bin/vdpm-channel"
public_key="$VITASDK/share/vdpm/channel-public-key.pem"
base=${VITASDK_CHANNEL_BASE_URL:-https://vitasdk.org/channels}

[[ -x $channel_tool ]] || {
	printf 'missing %s\n' "$channel_tool" >&2
	exit 1
}

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

download()
{
	if command -v curl >/dev/null 2>&1; then
		curl --fail --location --silent --show-error --output "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget --quiet --output-document "$2" "$1"
	else
		printf 'neither curl nor wget is available\n' >&2
		return 1
	fi
}

index="$temporary_directory/index.json"
signature="$temporary_directory/index.json.sig"

download "$base/index.json" "$index"
download "$base/index.json.sig" "$signature"

# Authenticated before it is read, like every other thing this client trusts.
"$channel_tool" verify "$index" "$signature" "$public_key"

current=""
if [[ -f $VITASDK/var/lib/vdpm/channel.json ]]; then
	current=$("$channel_tool" describe "$VITASDK/var/lib/vdpm/channel.json" |
		awk -F'\t' '$1 == "channel" { print $2 }')
fi

# Kept for `vdpm status`, so it can say whether this series is still
# maintained without going to the network.
mkdir -p "$VITASDK/var/lib/vdpm"
cp "$index" "$VITASDK/var/lib/vdpm/index.json"

# The world column appears only once there is more than one, so the listing
# everybody already reads does not grow a column saying the only answer.
rows=$("$channel_tool" series "$index")
worlds=$(cut -f4 <<< "$rows" | sort -u | wc -l)

if (( worlds > 1 )); then
	printf '%-14s %-14s %-14s %s\n' 'RELEASE' 'STATUS' 'WORLD' 'SUMMARY'
else
	printf '%-14s %-14s %s\n' 'RELEASE' 'STATUS' 'SUMMARY'
fi
while IFS=$'\t' read -r name status summary world; do
	marker=' '
	[[ $name == "$current" ]] && marker='*'
	if (( worlds > 1 )); then
		printf '%s%-13s %-14s %-14s %s\n' \
			"$marker" "$name" "$status" "$world" "$summary"
	else
		printf '%s%-13s %-14s %s\n' "$marker" "$name" "$status" "$summary"
	fi
done <<< "$rows"

[[ -z $current ]] || printf '\n* is the release this installation follows.\n'
