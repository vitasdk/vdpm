#!/usr/bin/env bash

# What `vdpm channels` prints, on both installers, for an index that names
# more than one world.
#
# The column appears only when there is a second world, so the listing
# everybody reads today does not grow a column whose every row says the only
# answer there is. The two installers have to agree on that, byte for byte:
# a difference here is a Windows user reading a different truth.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-worlds-listing.XXXXXXXX")
command -v pwsh >/dev/null 2>&1 || { printf 'pwsh is not installed\n' >&2; exit 77; }

tool="$temporary_root/vdpm-channel"
# shellcheck disable=SC2046
"${CC:-cc}" -std=c99 -o "$tool" "$repository_root/src/vdpm-channel.c" \
	$(pkg-config --cflags libcrypto 2>/dev/null) \
	$(pkg-config --libs libcrypto 2>/dev/null || printf -- '-lcrypto')

openssl genpkey -algorithm ed25519 -out "$temporary_root/key.pem" 2>/dev/null
openssl pkey -in "$temporary_root/key.pem" -pubout \
	-out "$temporary_root/key-public.pem" 2>/dev/null

write_index() {
	printf '%s\n' "$2" > "$1"
	openssl pkeyutl -sign -rawin -inkey "$temporary_root/key.pem" \
		-out "$1.sig" -in "$1" 2>/dev/null
}

one='{"channels":{"2026.08":{"status":"supported","summary":"Most homebrew.","world":"vita"},"nightly":{"status":"development","summary":"Moves under you.","world":"vita"}},"schema_version":1}'
two='{"channels":{"2026.08":{"status":"supported","summary":"Most homebrew.","world":"vita"},"nightly":{"status":"development","summary":"Moves under you.","world":"vita"},"nightly-softfp":{"status":"development","summary":"Soft-float ABI.","world":"vita_softfp"}},"schema_version":1}'

served="$temporary_root/served"
mkdir -p "$served"

# PowerShell fetches with Invoke-WebRequest, which has no file:// scheme, so
# both installers read the same index over the same local server.
python3 - "$served" "$temporary_root/port" <<'PYEOF' &
import http.server, functools, sys
directory, port_file = sys.argv[1], sys.argv[2]
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *arguments):
        pass
handler = functools.partial(Quiet, directory=directory)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
with open(port_file, "w") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PYEOF
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; rm -rf -- "$temporary_root"; }
trap cleanup EXIT

for _ in {1..50}; do
	[[ -s $temporary_root/port ]] && break
	sleep 0.1
done
[[ -s $temporary_root/port ]] || { printf 'the test server did not start\n' >&2; exit 1; }
base="http://127.0.0.1:$(cat "$temporary_root/port")"

run_shell() {
	local root=$1
	VITASDK="$root" VITASDK_CHANNEL_BASE_URL="$base" \
		bash "$repository_root/include/list-channels.sh"
}

run_powershell() {
	local root=$1
	VITASDK="$root" VITASDK_CHANNEL_BASE_URL="$base" \
		pwsh -NoProfile -File "$repository_root/include/list-channels.ps1"
}

compare() {
	local label=$1 document=$2 expect_column=$3
	rm -f -- "$served"/index.json*
	write_index "$served/index.json" "$document"

	local sh_root="$temporary_root/$label-sh" ps_root="$temporary_root/$label-ps"
	for root in "$sh_root" "$ps_root"; do
		rm -rf -- "$root"
		# The shell installer looks in bin/, the Windows one under the
		# msys tree its bootstrap creates. Both get the same binary.
		mkdir -p "$root/bin" "$root/share/vdpm/msys/usr/bin"
		cp "$tool" "$root/bin/vdpm-channel"
		cp "$tool" "$root/share/vdpm/msys/usr/bin/vdpm-channel.exe"
		cp "$temporary_root/key-public.pem" "$root/share/vdpm/channel-public-key.pem"
	done

	run_shell "$sh_root" > "$temporary_root/$label.sh.out"
	run_powershell "$ps_root" > "$temporary_root/$label.ps.out"

	if ! diff -u "$temporary_root/$label.sh.out" "$temporary_root/$label.ps.out"; then
		printf 'the two installers disagree for %s\n' "$label" >&2
		exit 1
	fi

	if [[ $expect_column == yes ]]; then
		grep -q 'WORLD' "$temporary_root/$label.sh.out" || {
			printf 'no world column with two worlds:\n' >&2
			cat "$temporary_root/$label.sh.out" >&2
			exit 1
		}
		grep -q 'vita_softfp' "$temporary_root/$label.sh.out" || {
			printf 'the second world is not shown\n' >&2
			exit 1
		}
	else
		if grep -q 'WORLD' "$temporary_root/$label.sh.out"; then
			printf 'a world column appeared with only one world:\n' >&2
			cat "$temporary_root/$label.sh.out" >&2
			exit 1
		fi
		# The summary must be the summary, with nothing appended to it.
		grep -qx ' nightly       development    Moves under you.' \
			"$temporary_root/$label.sh.out" || {
			printf 'the summary column is not what the index says:\n' >&2
			cat -A "$temporary_root/$label.sh.out" >&2
			exit 1
		}
	fi
}

compare one-world "$one" no
compare two-worlds "$two" yes

printf 'channel world listing contract tests passed\n'
