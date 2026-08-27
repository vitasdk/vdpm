#!/usr/bin/env bash
#
# Point the installers at the release being cut.
#
# The installer downloads a seed and the seed then resolves the host itself,
# so the two have to be the same vintage. Leaving that to a constant somebody
# remembers to bump is what left musl and FreeBSD hosts installing an SDK for
# the wrong libc: the pin sat three releases behind and nothing said so.
#
# The value kept in the tree names the newest published release, because that
# is what somebody running the installer out of a git checkout gets and it has
# to be a real answer. This rewrites it, at release time, to the release whose
# seeds are going out beside it.

set -euo pipefail

usage() {
	printf 'usage: %s <tag> <version>\n' "$0" >&2
	exit 2
}

[[ $# -eq 2 ]] || usage
tag=$1
version=$2

# A tag reaches this as a ref name, and a ref name is not always a tag: on a
# pull request it is <number>/merge. Refusing here rather than substituting it
# keeps a nonsense pin out of an installer.
[[ $tag =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
	printf 'not a release tag: %s\n' "$tag" >&2
	exit 1
}
[[ $version =~ ^[0-9][A-Za-z0-9._-]*$ ]] || {
	printf 'not a version: %s\n' "$version" >&2
	exit 1
}

directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

sed -i.bak \
	-e "s|^SEED_RELEASE=.*|SEED_RELEASE=$tag|" \
	-e "s|^SEED_VERSION=.*|SEED_VERSION=$version|" \
	"$directory/bootstrap-vitasdk.sh"
sed -i.bak \
	-e "s|^\$SeedRelease = .*|\$SeedRelease = '$tag'|" \
	-e "s|^\$SeedVersion = .*|\$SeedVersion = '$version'|" \
	"$directory/bootstrap-vitasdk.ps1"
rm -f "$directory/bootstrap-vitasdk.sh.bak" "$directory/bootstrap-vitasdk.ps1.bak"

grep -H '^SEED_RELEASE=\|^SEED_VERSION=' "$directory/bootstrap-vitasdk.sh"
grep -H 'SeedRelease\|SeedVersion' "$directory/bootstrap-vitasdk.ps1" | head -2
