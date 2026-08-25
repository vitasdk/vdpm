#!/usr/bin/env bash
#
# `vdpm channels` on Windows, run where it can be run cheaply.
#
# The Windows half is PowerShell, which is not Windows-only, and neither was
# the defect: list-channels.ps1 looked for the channel helper in bin/, and the
# Windows bootstrap installs it under share/vdpm/msys/usr/bin/ -- as
# refresh-repositories.ps1, its sibling, already knew. So the command died
# with "missing" on every Windows installation, and it is the command vdpm's
# own error names when you ask for a release without saying which one.
#
# Nothing executed this script before: the tests checked that the file was
# installed, never that running it did anything.
#
# What this does not cover: the real helper, the real signatures, a real
# Windows path. tests/test-channel-refresh-windows.ps1 covers a Windows
# runner.
#
# On a machine without PowerShell:
#
#   docker run --rm --platform linux/amd64 -v "$PWD:/vdpm" -w /vdpm \
#       mcr.microsoft.com/powershell:7.4-debian-12 ./tests/test-channels-powershell.sh

set -euo pipefail

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
server_pid=
cleanup() {
	[[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT

failures=0
check() {
	if [[ $2 == "$3" ]]; then
		printf 'ok: %s\n' "$1"
	else
		printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2"
		failures=$((failures + 1))
	fi
}

contains() {
	if grep -qF -- "$2" <<<"$1"; then
		printf 'ok: %s\n' "$3"
	else
		printf 'FAIL: %s\n  looked for: %s\n  in:\n%s\n' "$3" "$2" "$1"
		failures=$((failures + 1))
	fi
}

# The layout the Windows bootstrap produces, which is the whole point: the
# helper lives under the MSYS tree, not in bin/.
sdk=$work/sdk
helper_directory=$sdk/share/vdpm/msys/usr/bin
mkdir -p "$helper_directory" "$sdk/var/lib/vdpm" "$sdk/share/vdpm"
cp "$repository/include/list-channels.ps1" "$sdk/share/vdpm/"
: >"$sdk/share/vdpm/channel-public-key.pem"
printf '{"channel":"2026.08","schema_version":1,"sequence":7}\n' \
	>"$sdk/var/lib/vdpm/channel.json"

cat >"$helper_directory/vdpm-channel.exe" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
verify)
	# $2 index, $3 signature, $4 public key: all three must reach it.
	[[ -f $2 && -f $3 && -f $4 ]] || exit 1
	printf 'verify %s\n' "$2" >>"$VDPM_CHANNEL_CALLS"
	;;
describe)
	printf 'describe %s\n' "$2" >>"$VDPM_CHANNEL_CALLS"
	printf 'channel\t2026.08\n'
	;;
series)
	printf 'series %s\n' "$2" >>"$VDPM_CHANNEL_CALLS"
	printf '2026.08\tsupported\tthe one this SDK follows\n'
	printf 'nightly\trolling\tbuilt from every commit\n'
	;;
*) printf 'vdpm-channel: unexpected command: %s\n' "$*" >&2; exit 2 ;;
esac
STUB
chmod +x "$helper_directory/vdpm-channel.exe"

# A served index, because the script downloads before it does anything else:
# without one the run dies at the network and proves nothing about the rest.
served=$work/www
mkdir -p "$served"
printf '{"schema_version":1,"series":[]}\n' >"$served/index.json"
printf 'not a real signature\n' >"$served/index.json.sig"

python3 - "$served" "$work/port" <<'PYEOF' &
import http.server, functools, sys
directory, port_file = sys.argv[1], sys.argv[2]
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

handler = functools.partial(Quiet, directory=directory)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
with open(port_file, "w") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PYEOF
server_pid=$!

for _ in $(seq 1 50); do
	[[ -s $work/port ]] && break
	sleep 0.1
done
[[ -s $work/port ]] || {
	printf 'the index server never came up\n' >&2
	exit 1
}
port=$(cat "$work/port")

calls=$work/calls
: >"$calls"
if output=$(
	VITASDK=$sdk \
	VITASDK_CHANNEL_BASE_URL="http://127.0.0.1:$port" \
	VDPM_CHANNEL_CALLS=$calls \
		pwsh -NoProfile -File "$sdk/share/vdpm/list-channels.ps1" 2>&1
); then
	printf 'ok: the listing runs against the layout the bootstrap installs\n'
else
	printf 'FAIL: the listing failed\n%s\n' "$output"
	failures=$((failures + 1))
fi

contains "$output" "RELEASE" "the table is printed"
contains "$output" "*2026.08" "the series this installation follows is marked"
contains "$output" "nightly" "the other series are listed"
contains "$output" "* is the release this installation follows." "the marker is explained"

# The index decides where people are told they may move to, so it is verified
# before it is read, and kept for `vdpm status` to read offline.
contains "$(cat "$calls")" "verify" "the index is verified before it is used"
check "the index is kept for vdpm status" \
	"$([[ -f $sdk/var/lib/vdpm/index.json ]] && echo yes || echo no)" "yes"

if [[ $failures -gt 0 ]]; then
	printf '\n%s check(s) failed\n' "$failures" >&2
	exit 1
fi
printf '\nvdpm channels on PowerShell: all checks passed\n'
