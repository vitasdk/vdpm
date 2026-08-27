#!/usr/bin/env bash
#
# The seed release has to contain what the installer demands of it.
#
# Both installers download one pinned release as their seed and then check it
# carries a fixed set of paths. Nothing tied the pin to that set, so when
# pacman moved to libexec/vdpm the requirement moved with it and the pin did
# not: every install on Linux and macOS died on "bootstrap archive is missing
# libexec/vdpm/pacman", on every channel, while CI stayed green -- the smoke
# tests all hand the installer a local archive, which skips the seed entirely.
#
# This reads the pin and the requirements out of the installers themselves,
# so it keeps holding when either side changes.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-seed.XXXXXXXX")
trap 'rm -rf -- "$temporary_directory"' EXIT

shell_installer="$repository_root/bootstrap-vitasdk.sh"
powershell_installer="$repository_root/bootstrap-vitasdk.ps1"

seed_release=$(sed -n 's/^SEED_RELEASE=\(.*\)$/\1/p' "$shell_installer")
seed_version=$(sed -n 's/^SEED_VERSION=\(.*\)$/\1/p' "$shell_installer")
[[ -n $seed_release && -n $seed_version ]] || {
	printf 'could not read the seed pin from %s\n' "$shell_installer" >&2
	exit 1
}

powershell_release=$(sed -n "s/^\$SeedRelease = '\(.*\)'.*$/\1/p" "$powershell_installer")
powershell_version=$(sed -n "s/^\$SeedVersion = '\(.*\)'.*$/\1/p" "$powershell_installer")
[[ $powershell_release == "$seed_release" && $powershell_version == "$seed_version" ]] || {
	printf 'the two installers seed from different releases: %s/%s and %s/%s\n' \
		"$seed_release" "$seed_version" "$powershell_release" "$powershell_version" >&2
	exit 1
}

# The requirements live in a case branch per host kind in the shell installer
# and in an if branch in the PowerShell one; take each list as written.
posix_requirements=$(
	awk '
		/seed_required=\(/ { collecting = 1; block = "" }
		collecting { block = block " " $0 }
		collecting && /\)/ { collecting = 0; if (block !~ /\.exe/) print block }
	' "$shell_installer" |
		sed 's/.*seed_required=(//; s/)[[:space:]]*$//; s/\\//g' |
		tr -s ' \t' '\n' | grep -v '^$'
)
windows_requirements=$(
	# shellcheck disable=SC2016 # the dollar sign is PowerShell's, not this shell's
	sed -n '/\$installFromPackages) {/,/^    } else {/p' "$powershell_installer" |
		sed -n 's/^ *"\(.*\)",\{0,1\}$/\1/p'
)
[[ -n $posix_requirements && -n $windows_requirements ]] || {
	printf 'could not read the seed requirements out of the installers\n' >&2
	exit 1
}

check_bundle() {
	local host=$1 requirements=$2 archive listing missing=0
	archive="$temporary_directory/vdpm-$seed_version-$host.tar.bz2"
	curl -fsSL --retry 3 -o "$archive" \
		"https://github.com/vitasdk/vdpm/releases/download/$seed_release/vdpm-$seed_version-$host.tar.bz2"
	listing="$temporary_directory/$host.list"
	tar -tjf "$archive" > "$listing"
	while IFS= read -r relative_path; do
		[[ -n $relative_path ]] || continue
		grep -qx "vdpm-$seed_version-$host/$relative_path" "$listing" || {
			printf 'seed %s for %s is missing %s\n' "$seed_release" "$host" "$relative_path" >&2
			missing=1
		}
	done <<< "$requirements"
	(( missing == 0 )) || exit 1
	printf 'seed %s satisfies %s\n' "$seed_release" "$host"
}

check_bundle x86_64-linux-gnu "$posix_requirements"
check_bundle x86_64-w64-mingw32 "$windows_requirements"

# The seed has to agree with the installer about what a host is, not only
# carry the right files. It re-detects the host itself -- vdpm refresh runs
# from the seed -- so a seed whose detection is older than the installer's
# installs a package set for a host nobody asked for. That is how a musl host
# came to bootstrap a glibc SDK that cannot execute: the installer detected
# musl, downloaded the musl seed, and the seed said gnu.
check_detection() {
	local host=$1 archive extracted
	archive="$temporary_directory/vdpm-$seed_version-$host.tar.bz2"
	extracted="$temporary_directory/extracted-$host"
	mkdir -p "$extracted"
	tar -xjf "$archive" -C "$extracted"
	local seed_detection="$extracted/vdpm-$seed_version-$host/bin/include/host-triplet.sh"
	[[ -f $seed_detection ]] || {
		printf 'seed %s for %s carries no host-triplet.sh\n' "$seed_release" "$host" >&2
		exit 1
	}
	# Compared by what they do, not byte for byte: comments and formatting are
	# allowed to differ, the set of triplets either can answer is not.
	local ours theirs
	ours=$(grep -oE "'%s-[a-z0-9_-]+" "$repository_root/include/host-triplet.sh" | sort -u)
	theirs=$(grep -oE "'%s-[a-z0-9_-]+" "$seed_detection" | sort -u)
	[[ $ours == "$theirs" ]] || {
		printf 'seed %s detects different hosts from this tree.\n' "$seed_release" >&2
		printf '  this tree: %s\n' "$(tr '\n' ' ' <<< "$ours")" >&2
		printf '  the seed:  %s\n' "$(tr '\n' ' ' <<< "$theirs")" >&2
		printf 'Bump the seed pin, or the installer will hand work to a seed that\n' >&2
		printf 'resolves the host differently from the way it was resolved here.\n' >&2
		exit 1
	}
	printf 'seed %s resolves hosts the way this tree does\n' "$seed_release"
}

check_detection x86_64-linux-gnu

printf 'bootstrap seed contract tests passed\n'
