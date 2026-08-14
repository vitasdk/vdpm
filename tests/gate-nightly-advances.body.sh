#!/bin/bash
# Nightly moving to the next nightly: re-selecting the series you are already
# on, which is the daily path for anyone living there and the one case neither
# direction of the round trip exercises.
#
# The client under test is built here rather than taken from the installed
# core, because the point is to know whether today's code moves a toolchain
# before publishing it.

set -uo pipefail
export VDPM_NONINTERACTIVE=1

apt-get update -qq
apt-get install -y -qq curl ca-certificates bzip2 xz-utils tar gcc >/dev/null

bash /bootstrap.sh --install-dir /opt/sdk >/dev/null 2>&1 || {
	echo "FAIL: the bootstrap did not install" >&2; exit 1; }
export VITASDK=/opt/sdk PATH=/opt/sdk/bin:$PATH

# Today's client, the helper it drives, and the key the test manifests are
# signed with. Reapplied before every transaction because the published core
# is still monolithic: installing it puts its own copy of the client and the
# key back, which is precisely what splitting them apart stops.
use_client_under_test() {
	cc -O2 -o /opt/sdk/bin/vdpm /vdpm/src/vdpm.c
	cp /vdpm/include/refresh-repositories.sh /opt/sdk/bin/include/
	chmod +x /opt/sdk/bin/include/refresh-repositories.sh
	cp /channels/test-pub.pem /opt/sdk/share/vdpm/channel-public-key.pem
}
use_client_under_test

failures=0
check() {
	if [ "$2" = "$3" ]; then printf 'ok: %s (%s)\n' "$1" "$2"
	else printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2" >&2
		failures=$((failures + 1)); fi
}
installed_core() {
	pacman --config /opt/sdk/etc/pacman.conf --root /opt/sdk \
		--dbpath /opt/sdk/var/lib/pacman --query vitasdk-core 2>/dev/null |
		awk '{print $2}'
}

echo "=== onto the first nightly ==="
VITASDK_CHANNEL_BASE_URL=file:///channels/a vdpm refresh nightly 2>&1 | tail -2
first=$(installed_core)
check "the toolchain became the nightly one" \
	"$([ "$first" != "2026.08.0-1" ] && echo moved || echo "stayed at $first")" moved

use_client_under_test
echo "=== upgrade does not go and find the next one ==="
VITASDK_CHANNEL_BASE_URL=file:///channels/a vdpm upgrade >/dev/null 2>&1
check "the toolchain stayed put" "$(installed_core)" "$first"

use_client_under_test
echo "=== the series advances, and refresh is what takes you there ==="
VITASDK_CHANNEL_BASE_URL=file:///channels/b vdpm refresh nightly 2>&1 | tail -2
second=$(installed_core)
check "the toolchain advanced" \
	"$([ "$second" != "$first" ] && echo advanced || echo "stayed at $first")" advanced
check "and it is the one the manifest named" "$second" "0.582.1-1"

use_client_under_test
echo "=== what it says is what it has ==="
vdpm status | sed 's/^/    /'

[ "$failures" -eq 0 ] || exit 1
echo "nightly advances correctly"
