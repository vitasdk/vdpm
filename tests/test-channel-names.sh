#!/usr/bin/env sh
# A channel is a name, not a fixed list.
#
# A release series is a channel that lives as long as the release does, so
# `2026.09` has to be sayable the same way `nightly` is. The name still goes
# into a URL and into a file path, so it is checked rather than trusted.

set -eu

directory=$(cd "$(dirname "$0")/.." && pwd -P)
refresher="${directory}/include/refresh-repositories.sh"

[ -f "${refresher}" ] || { echo "missing ${refresher}" >&2; exit 1; }

refused()
{
    # Everything past the name check fails for unrelated reasons here, so
    # what is asserted is only whether the name itself was refused.
    VITASDK= sh "${refresher}" "$1" 2>&1 | grep -q 'invalid channel name'
}

failures=0

for name in stable nightly 2026.09 2026.09-rc1 rc next v2; do
    if refused "${name}"; then
        echo "refused a valid channel name: ${name}" >&2
        failures=$((failures + 1))
    fi
done

# A name reaches a URL and a path, so anything that could climb out of either
# has to be refused, and an empty one is a mistake rather than a default.
for name in '../nightly' 'a/b' '' '-x' '.hidden' 'a..b' 'x;y' 'a b' 'a$b'; do
    if ! refused "${name}"; then
        echo "accepted an unsafe channel name: '${name}'" >&2
        failures=$((failures + 1))
    fi
done

[ "${failures}" -eq 0 ] || exit 1
echo "channel names OK"
