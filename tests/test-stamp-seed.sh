#!/usr/bin/env bash
#
# The release stamps its own seed pin into both installers.
#
# The value in the tree names the newest published release, for somebody
# running the installer out of a checkout. What goes out with a release has to
# name that release instead, whose seeds are published beside it -- otherwise
# the pin is a constant somebody remembers to bump, which is how musl and
# FreeBSD hosts came to install an SDK for the wrong libc.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-stamp.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT

failures=0

# A copy of the tree, so the real installers are never edited by a test.
mkdir -p "$work/scripts"
cp "$repository_root/bootstrap-vitasdk.sh" "$repository_root/bootstrap-vitasdk.ps1" "$work/"
cp "$repository_root/scripts/stamp-seed.sh" "$work/scripts/"

check() {
	local description=$1 expected=$2 actual=$3
	if [[ $actual == "$expected" ]]; then
		printf 'PASS: %s\n' "$description"
	else
		printf 'FAIL: %s\n  expected %s\n  got      %s\n' \
			"$description" "$expected" "$actual" >&2
		failures=$((failures + 1))
	fi
}

"$work/scripts/stamp-seed.sh" v9.9.9 9.9.9 >/dev/null

check "the shell installer names the release" "SEED_RELEASE=v9.9.9" \
	"$(grep '^SEED_RELEASE=' "$work/bootstrap-vitasdk.sh")"
check "the shell installer names the version" "SEED_VERSION=9.9.9" \
	"$(grep '^SEED_VERSION=' "$work/bootstrap-vitasdk.sh")"
check "the PowerShell installer names the release" "\$SeedRelease = 'v9.9.9'" \
	"$(grep '^\$SeedRelease' "$work/bootstrap-vitasdk.ps1")"
check "the PowerShell installer names the version" "\$SeedVersion = '9.9.9'" \
	"$(grep '^\$SeedVersion' "$work/bootstrap-vitasdk.ps1")"

# Still a program afterwards. A pin is rewritten in place and nothing else is.
bash -n "$work/bootstrap-vitasdk.sh" || {
	printf 'FAIL: the shell installer is no longer valid bash\n' >&2
	failures=$((failures + 1))
}

# A ref name is not always a tag: on a pull request it is <number>/merge, and
# the slash used to end the sed expression rather than the pin. Refusing is
# what keeps a nonsense pin out of a published installer.
if "$work/scripts/stamp-seed.sh" 126/merge 0.105.1 >/dev/null 2>&1; then
	printf 'FAIL: a pull request ref name was accepted as a release tag\n' >&2
	failures=$((failures + 1))
else
	printf 'PASS: a pull request ref name is refused\n'
fi

if (( failures )); then
	printf '%d seed stamping check(s) failed\n' "$failures" >&2
	exit 1
fi
printf 'seed stamping tests passed\n'
