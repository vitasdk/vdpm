#!/usr/bin/env bash
#
# Installing into a top-level directory.
#
# The installer composes its staging path onto the parent of the install
# directory, and at the filesystem root that parent is "/": the composition
# doubles the separator, and the prefix check that keeps an archive from
# writing outside the staging directory then matches nothing. Every symbolic
# link in the SDK reads as escaping, and the install is refused with a message
# about the archive rather than about the path it was given.
#
# /vitasdk is an ordinary place to put an SDK, so this installs there. It needs
# a container because the test cannot write to the root of the machine it runs
# on -- which is also why nothing had ever exercised it.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-root-install.XXXXXXXX")
trap 'rm -rf -- "$temporary_directory"' EXIT

# The same shape as the fixture in test-bootstrap.sh, with the links the real
# SDK carries: without one the check being tested never runs.
archive_root="$temporary_directory/archive/vitasdk"
mkdir -p "$archive_root/bin/include" "$archive_root/libexec/vdpm" "$archive_root/etc" "$archive_root/lib"
for program in vdpm vdpm-channel arm-vita-eabi-gcc; do
	printf '#!/bin/sh\nexit 0\n' > "$archive_root/bin/$program"
	chmod +x "$archive_root/bin/$program"
done
printf '#!/bin/sh\nexit 0\n' > "$archive_root/libexec/vdpm/pacman"
chmod +x "$archive_root/libexec/vdpm/pacman"
printf 'refresh\n' > "$archive_root/bin/include/refresh-repositories.sh"
chmod +x "$archive_root/bin/include/refresh-repositories.sh"
printf '[options]\nArchitecture = test vita\n' > "$archive_root/etc/pacman.conf"
printf 'test revision\n' > "$archive_root/version_info.txt"
printf 'library\n' > "$archive_root/lib/libfixture.so.1.0.0"
ln -s libfixture.so.1.0.0 "$archive_root/lib/libfixture.so"

# The archive is built inside the container: a tar that writes extended
# headers -- macOS does -- puts entries beside the tree that the installer
# reads as a second top-level directory.
docker run --rm --platform linux/amd64 \
	--mount "type=bind,source=$repository_root/bootstrap-vitasdk.sh,target=/bootstrap-vitasdk.sh,readonly" \
	--mount "type=bind,source=$temporary_directory/archive,target=/fixture,readonly" \
	debian:12-slim \
	bash -euc '
		apt-get update -qq >/dev/null
		apt-get install -y -qq bzip2 >/dev/null
		cp -a /fixture /tmp/fixture
		tar -cjf /tmp/vitasdk.tar.bz2 -C /tmp/fixture vitasdk
		export VITASDK_BOOTSTRAP_ARCHIVE=/tmp/vitasdk.tar.bz2
		VITASDK_BOOTSTRAP_SHA256=$(sha256sum /tmp/vitasdk.tar.bz2 | cut -d" " -f1) \
			bash /bootstrap-vitasdk.sh --install-dir /vitasdk > /tmp/output
		test -x /vitasdk/bin/vdpm
		test -f /vitasdk/version_info.txt
		test -L /vitasdk/lib/libfixture.so
		# The doubled separator reached the reported path as well. Linux reads
		# //vitasdk as the same directory, so what it breaks is what the
		# installer tells the user to set VITASDK to.
		if grep -q "//vitasdk" /tmp/output; then
			echo "the installer named the install directory with a doubled separator" >&2
			cat /tmp/output >&2
			exit 1
		fi
	'

printf 'the installer accepts a top-level install directory\n'
