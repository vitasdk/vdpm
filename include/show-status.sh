#!/usr/bin/env bash
# What this installation is: which release series, and what it points at.
#
# The data is already on disk, written by the last refresh. Before this
# existed the only way to answer "which VitaSDK do you have?" was to read a
# JSON file by hand, which is not a thing to ask of somebody reporting a bug.
#
# Reads nothing from the network, on purpose: it has to work offline and it
# must never be the thing that changes what you have installed.

set -euo pipefail

[[ -n ${VITASDK:-} ]] || {
	printf 'VITASDK is not set\n' >&2
	exit 1
}

manifest="$VITASDK/var/lib/vdpm/channel.json"
channel_tool="$VITASDK/bin/vdpm-channel"
index="$VITASDK/var/lib/vdpm/index.json"

[[ -x $channel_tool ]] || {
	printf 'missing %s\n' "$channel_tool" >&2
	exit 1
}

[[ -f $manifest ]] || {
	printf 'no channel configured; run `vdpm refresh` first\n' >&2
	exit 1
}

declare -A fact=()
while IFS=$'\t' read -r key value; do
	[[ -n $key ]] && fact[$key]=$value
done < <("$channel_tool" describe "$manifest")

channel=${fact[channel]:-unknown}

printf 'Release   %s\n' "$channel"
printf 'Sequence  %s\n' "${fact[sequence]:-unknown}"
printf 'Toolchain %s (%s)\n' "${fact[core]:-unknown}" "${fact[core_repository]:-unknown}"
printf 'Packages  %s (%s)\n' "${fact[packages]:-unknown}" "${fact[packages_repository]:-unknown}"

# The index is only present if a refresh has seen one. Saying nothing is
# better than claiming a series is supported when nothing said so.
if [[ -f $index ]]; then
	while IFS=$'\t' read -r name status summary; do
		[[ $name == "$channel" ]] || continue
		printf 'Status    %s\n' "$status"
		[[ -z $summary ]] || printf 'Summary   %s\n' "$summary"
		case $status in
		end-of-life)
			printf '\n%s is no longer maintained: it still installs exactly as it does\n' "$channel" >&2
			printf 'today, but it receives no further updates. `vdpm channels` lists\n' >&2
			printf 'what is current.\n' >&2
			;;
		deprecated)
			printf '\n%s is deprecated and will stop receiving updates. See\n' "$channel" >&2
			printf '`vdpm channels` for what replaces it.\n' >&2
			;;
		esac
	done < <("$channel_tool" series "$index")
fi
