#!/usr/bin/env bash
# Moving between series, against the published channels, with real packages.
#
# This is the gate: the unit tests prove refresh asks pacman for the right
# transaction, and only this proves the toolchain actually moves. The failure
# it exists to catch looked exactly like success -- refresh reapointed the
# repositories, said "refreshed", and left the compiler where it was.
#
# Runs the whole thing inside a container so nothing on the host is touched.

set -uo pipefail

directory=$(cd "$(dirname "$0")/.." && pwd -P)
image=${GATE_IMAGE:-ubuntu:24.04}
release=${GATE_RELEASE:-2026.08}

docker run --rm --platform linux/amd64 \
	--mount "type=bind,source=$directory/bootstrap-vitasdk.sh,target=/bootstrap.sh,readonly" \
	--env "GATE_RELEASE=$release" \
	"$image" bash -uo pipefail -c '
	apt-get update -qq
	apt-get install -y -qq curl ca-certificates bzip2 xz-utils tar file cmake make >/dev/null

	export VDPM_NONINTERACTIVE=1
	bash /bootstrap.sh --install-dir /opt/sdk >/dev/null 2>&1 || {
		echo "FAIL: the bootstrap did not install" >&2
		exit 1
	}
	export VITASDK=/opt/sdk PATH=/opt/sdk/bin:$PATH

	failures=0
	check() {
		if [ "$2" = "$3" ]; then
			printf "ok: %s (%s)\n" "$1" "$2"
		else
			printf "FAIL: %s\n  expected: %s\n  actual:   %s\n" "$1" "$3" "$2" >&2
			failures=$((failures + 1))
		fi
	}

	installed_core() {
		pacman --config /opt/sdk/etc/pacman.conf --root /opt/sdk \
			--dbpath /opt/sdk/var/lib/pacman --query vitasdk-core 2>/dev/null |
			awk "{print \$2}"
	}
	selected_series() {
		sed -n "s/.*\"channel\":\"\([^\"]*\)\".*/\1/p" \
			/opt/sdk/var/lib/vdpm/channel.json
	}

	echo "=== a clean install is one pacman knows about ==="
	release_core=$(installed_core)
	check "the toolchain is registered" "$([ -n "$release_core" ] && echo yes || echo no)" yes
	check "the series is selected" "$(selected_series)" "$GATE_RELEASE"
	check "the compiler is there" \
		"$([ -x /opt/sdk/bin/arm-vita-eabi-gcc ] && echo yes || echo no)" yes

	echo "=== a library still resolves its dependencies ==="
	vdpm install libpng >/dev/null 2>&1
	check "zlib came along" \
		"$([ -f /opt/sdk/arm-vita-eabi/lib/libz.a ] && echo yes || echo no)" yes

	echo "=== upgrade stays inside the series ==="
	vdpm upgrade >/dev/null 2>&1
	check "the series did not move" "$(selected_series)" "$GATE_RELEASE"
	check "the toolchain did not move" "$(installed_core)" "$release_core"

	echo "=== release -> nightly moves the toolchain ==="
	vdpm refresh nightly >/dev/null 2>&1
	nightly_core=$(installed_core)
	check "the series moved" "$(selected_series)" nightly
	check "the toolchain moved" \
		"$([ "$nightly_core" != "$release_core" ] && echo moved || echo "stayed at $release_core")" moved

	# The two verbs are the promise: upgrade works inside the series it was
	# given, and only refresh goes and asks for another snapshot. If upgrade
	# moved the toolchain here, they would be one verb with two names.
	echo "=== upgrade does not go looking for a newer nightly ==="
	vdpm upgrade >/dev/null 2>&1
	check "the toolchain stayed on the snapshot refresh chose" \
		"$(installed_core)" "$nightly_core"

	echo "=== and back again ==="
	vdpm refresh "$GATE_RELEASE" >/dev/null 2>&1
	check "the series came back" "$(selected_series)" "$GATE_RELEASE"
	check "the toolchain came back" "$(installed_core)" "$release_core"

	echo "=== what it says is what it has ==="
	vdpm status | sed "s/^/    /"

	[ "$failures" -eq 0 ] || exit 1
	echo "gate passed"
'
