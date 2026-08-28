#!/usr/bin/env bash

# Which series an installer picks when nobody names one.
#
# A world decides the ABI of everything the toolchain compiles, so it is never
# picked for somebody. Two worlds cut a series in the same month, so the names
# differ only by a suffix -- 2026.11 and 2026.11-softfp -- and neither sort
# order can tell them apart on merit: the shell sorts YYYY.MM numerically and
# ties, PowerShell sorts the whole name as text and the longer one wins. Both
# had to filter by world instead, and both are checked here against the same
# index.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-autoselect.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

tool="$temporary_root/vdpm-channel"
# shellcheck disable=SC2046
"${CC:-cc}" -std=c99 -o "$tool" "$repository_root/src/vdpm-channel.c" \
	$(pkg-config --cflags libcrypto 2>/dev/null) \
	$(pkg-config --libs libcrypto 2>/dev/null || printf -- '-lcrypto')

# Keys go in canonical order, so 2026.11-softfp cannot be placed first to
# bait a reader that takes what comes first. It does not need to be: sorting
# the names descending as text puts the longer one on top wherever it sits.
index="$temporary_root/index.json"
printf '%s\n' '{"channels":{"2026.08":{"status":"supported","summary":"Older.","world":"vita"},"2026.11":{"status":"supported","summary":"Most homebrew.","world":"vita"},"2026.11-softfp":{"status":"supported","summary":"Soft-float ABI.","world":"vita_softfp"},"nightly":{"status":"development","summary":"Moves.","world":"vita"}},"schema_version":1}' > "$index"

default_world=vita

# --- the shell installer ------------------------------------------------------

# The selection as bootstrap-vitasdk.sh performs it, read out of the script so
# the two cannot drift apart silently.
selection=$(sed -n '/series "\$index" |/,/head -n1)/p' \
	"$repository_root/bootstrap-vitasdk.sh")
[[ -n $selection ]] || {
	printf 'the selection in bootstrap-vitasdk.sh no longer matches this test\n' >&2
	exit 1
}
staging_directory=$temporary_root
channel_tool=$(basename "$tool")
DEFAULT_WORLD=$default_world
export DEFAULT_WORLD
channel=""
eval "$selection"
shell_choice=$channel

[[ $shell_choice == 2026.11 ]] || {
	printf 'the shell installer chose %s, not 2026.11\n' "$shell_choice" >&2
	exit 1
}

# --- the Windows installer ----------------------------------------------------

if command -v pwsh >/dev/null 2>&1; then
	windows_choice=$(pwsh -NoProfile -Command "
		\$DefaultWorld = '$default_world'
		\$index = Get-Content '$index' -Raw | ConvertFrom-Json
		\$index.channels.PSObject.Properties |
			Where-Object {
				\$_.Value.status -eq 'supported' -and
				(\$(if (\$_.Value.PSObject.Properties['world']) {
					\$_.Value.world } else { \$DefaultWorld })) -eq \$DefaultWorld
			} |
			Sort-Object -Property Name -Descending |
			Select-Object -First 1 -ExpandProperty Name")
	[[ $windows_choice == 2026.11 ]] || {
		printf 'the Windows installer chose %s, not 2026.11\n' "$windows_choice" >&2
		exit 1
	}
	# The two installers must agree, which is the whole point of checking both.
	[[ $windows_choice == "$shell_choice" ]] || {
		printf 'the installers disagree: %s and %s\n' \
			"$shell_choice" "$windows_choice" >&2
		exit 1
	}
else
	printf 'pwsh is not installed: the Windows half was not checked\n' >&2
fi

# --- an index with no series for the default world ----------------------------

printf '%s\n' '{"channels":{"2026.11-softfp":{"status":"supported","summary":"Only world.","world":"vita_softfp"}},"schema_version":1}' > "$index"
channel=""
eval "$selection"
empty=$channel
[[ -z $empty ]] || {
	printf 'a series of another world was chosen: %s\n' "$empty" >&2
	exit 1
}

printf 'series autoselection contract tests passed\n'
