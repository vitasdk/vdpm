#!/usr/bin/env bash

# The scripts at the top of the checkout are how VitaSDK was installed before
# there was a package client, and they are still what people run after cloning
# and what CI downloads from master. None of them was tested, and all three
# broke without anybody here noticing.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-legacy.XXXXXXXX")
log="$temporary_root/log"

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

fail() {
	printf '%s\n' "$*" >&2
	exit 1
}

# What install-all asks for, as the package repository names it.
listed=$(sed -n '/^PACKAGES=(/,/^)/{/^PACKAGES=(/d;/^)/d;s/^[[:space:]]*//;p;}' \
	"$repository_root/include/install-packages.sh")
catalogue="$temporary_root/catalogue"
for package in $listed; do
	case $package in
		cpython) ;;
		openssl) printf 'vita/openssl 1.0.2-1\nvita/openssl-1.1.1 1.1.1-2\n' ;;
		*) printf 'vita/%s 1-1\n    description\n' "$package" ;;
	esac
done > "$catalogue"
head -n 60 "$catalogue" > "$temporary_root/partial-catalogue"

# A package-client SDK whose vdpm records what it was asked. It follows
# FAKE_RELEASE, offers FAKE_CATALOGUE, and its first refresh fails when
# FAKE_REFRESH_FAILS is set, the way a refresh does on a conflict.
make_packaged_sdk() {
	local root=$1

	mkdir -p "$root/bin" "$root/libexec/vdpm"
	: > "$root/libexec/vdpm/pacman"
	chmod +x "$root/libexec/vdpm/pacman"
	cat > "$root/bin/vdpm" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${VDPM_NONINTERACTIVE:-unset}" "$*" >> "$VDPM_TEST_LOG"
case $1 in
	status) [[ -z ${FAKE_RELEASE-2026.08} ]] || printf 'Release   %s\n' "${FAKE_RELEASE-2026.08}" ;;
	search) cat "$FAKE_CATALOGUE" ;;
	pacman)
		[[ $* != *'--query --list'* ]] || cat "${FAKE_OWNED:-/dev/null}"
		[[ -z ${FAKE_INSTALL_FAILS:-} || $* != *'--sync --needed'* ]] || exit 1
		;;
	channels)
		printf 'RELEASE        STATUS         SUMMARY\n'
		printf ' 2026.02       supported      Older.\n'
		printf '*2026.08       supported      Most homebrew.\n'
		printf ' 2026.08-softfp supported     Soft-float.\n'
		printf ' nightly       development    Moves.\n'
		;;
	refresh)
		if [[ -n ${FAKE_REFRESH_FAILS:-} && ! -e $VITASDK/refreshed-once ]]; then
			touch "$VITASDK/refreshed-once"
			exit 1
		fi
		;;
esac
EOF
	chmod +x "$root/bin/vdpm"
}

# An SDK from before the package client: its vdpm only installs archives.
make_legacy_sdk() {
	local root=$1

	mkdir -p "$root/bin"
	cat > "$root/bin/vdpm" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${VDPM_NONINTERACTIVE:-unset}" "$*" >> "$VDPM_TEST_LOG"
EOF
	chmod +x "$root/bin/vdpm"
}

packaged="$temporary_root/packaged"
make_packaged_sdk "$packaged"
legacy="$temporary_root/legacy"
make_legacy_sdk "$legacy"

export VDPM_TEST_LOG="$log" FAKE_CATALOGUE="$catalogue"
transaction='1 pacman -- --noconfirm --noprogressbar --noscriptlet --ask=4'

# The checkout's vdpm is the SDK's.
: > "$log"
VITASDK="$packaged" "$repository_root/vdpm" install zlib
grep -Fqx 'unset install zlib' "$log" ||
	fail 'the checkout vdpm did not hand over to the SDK client'

if message=$(VITASDK="$temporary_root/missing" "$repository_root/vdpm" list 2>&1); then
	fail 'the checkout vdpm accepted a root with no SDK'
fi
grep -q 'bootstrap-vitasdk.sh' <<< "$message" ||
	fail "the checkout vdpm did not say how to get an SDK: $message"

# Copied over the SDK client it would only call itself.
self="$temporary_root/self"
mkdir -p "$self/bin"
cp "$repository_root/vdpm" "$self/bin/vdpm"
if VITASDK="$self" "$self/bin/vdpm" list 2>/dev/null; then
	fail 'the checkout vdpm handed over to itself'
fi

# install-all brings the SDK to its release's current packages, then installs
# the list in one transaction: without the packages the release lacks, and with
# the OpenSSL the release's curl needs.
: > "$log"
VITASDK="$packaged" "$repository_root/install-all.sh" 2>/dev/null >/dev/null
grep -Fqx '1 refresh 2026.08' "$log" || fail 'install-all did not update the release first'
installed=$(grep -F "$transaction --sync --needed " "$log") ||
	fail 'install-all did not install in one transaction'
(( $(grep -c -- '--sync --needed' "$log") == 1 )) || fail 'install-all ran more than one transaction'
[[ " $installed " == *' zlib '* && " $installed " == *' sdl3_ttf ' ]] ||
	fail "install-all did not install the whole list: $installed"
[[ " $installed " != *' cpython '* ]] || fail 'install-all installed a package the release lacks'
[[ " $installed " == *' openssl-1.1.1 '* && " $installed " != *' openssl '* ]] ||
	fail 'install-all asked for the openssl that conflicts with what curl needs'

# An old checkout's install-all unpacks archives into a package-client SDK and
# leaves its package list. Only what is exactly the archive's file and owned by
# no package is moved aside for pacman; nothing of anybody else's is touched.
archives="$temporary_root/archives"
mkdir -p "$archives/zlib/include" "$archives/zlib/lib"
printf 'zlib archive header\n' > "$archives/zlib/include/zlib.h"
printf 'zlib archive library\n' > "$archives/zlib/lib/libz.a"
printf 'owned by a package\n' > "$archives/zlib/lib/libowned.a"
tar -cJf "$archives/zlib.tar.xz" -C "$archives/zlib" include lib
sysroot="$packaged/arm-vita-eabi"
mkdir -p "$sysroot/include" "$sysroot/lib" "$packaged/etc/vdpm"
cp "$archives/zlib/lib/libz.a" "$archives/zlib/lib/libowned.a" "$sysroot/lib/"
printf 'zlib header somebody edited\n' > "$sysroot/include/zlib.h"
printf 'a library somebody built\n' > "$sysroot/lib/libmine.a"
printf 'zlib %s\n' "$sysroot/lib/libowned.a" > "$temporary_root/owned"
printf 'PACKAGE zlib\n\n' > "$packaged/etc/vdpm/packages.list"

# When the installation fails anyway, the SDK keeps what it had.
if VDPM_ARCHIVE_URL="file://$archives" FAKE_OWNED="$temporary_root/owned" FAKE_INSTALL_FAILS=1 \
	VITASDK="$packaged" "$repository_root/install-all.sh" >/dev/null 2>&1; then
	fail 'install-all reported a failed installation as done'
fi
cmp -s "$archives/zlib/lib/libz.a" "$sysroot/lib/libz.a" ||
	fail 'install-all left the SDK without the files it set aside'
[[ -f $packaged/etc/vdpm/packages.list ]] ||
	fail 'install-all forgot the archive files after a failed installation'

: > "$log"
VDPM_ARCHIVE_URL="file://$archives" FAKE_OWNED="$temporary_root/owned" \
	VITASDK="$packaged" "$repository_root/install-all.sh" >/dev/null 2>&1 ||
	fail 'install-all failed on an SDK an old checkout installed archives into'
[[ ! -e $sysroot/lib/libz.a ]] && cmp -s "$archives/zlib/lib/libz.a" "$packaged"/var/lib/vdpm/archive-files.*/lib/libz.a ||
	fail 'install-all did not set aside the file the archive client unpacked'
grep -q 'somebody edited' "$sysroot/include/zlib.h" || fail 'install-all moved a file somebody changed'
[[ -f $sysroot/lib/libmine.a ]] || fail 'install-all moved a library that is not from an archive'
[[ -f $sysroot/lib/libowned.a ]] || fail 'install-all moved a file a package owns'
! grep -Fq -- '--overwrite' "$log" || fail 'install-all overwrote files'
[[ ! -e $packaged/etc/vdpm/packages.list && -e $packaged/etc/vdpm/packages.list.adopted ]] ||
	fail 'install-all left the archive package list to be looked at again'
rm -rf "$sysroot" "$packaged/var"

# A catalogue published incomplete is not an installation to report as done.
: > "$log"
if FAKE_CATALOGUE="$temporary_root/partial-catalogue" \
	VITASDK="$packaged" "$repository_root/install-all.sh" >/dev/null 2>&1; then
	fail 'install-all succeeded on a catalogue missing most of the list'
fi
! grep -q -- '--sync --needed' "$log" || fail 'install-all installed from an incomplete catalogue'

# A refresh whose transaction fails on a conflict is finished, then recorded.
rm -f "$packaged/refreshed-once"
: > "$log"
FAKE_REFRESH_FAILS=1 VITASDK="$packaged" "$repository_root/vitasdk-update" >/dev/null 2>&1 ||
	fail 'vitasdk-update gave up on a refresh it can finish'
grep -Fqx "$transaction --sync --sysupgrade --sysupgrade" "$log" ||
	fail 'vitasdk-update did not resolve the failed transaction'
(( $(grep -c '^1 refresh 2026.08$' "$log") == 2 )) ||
	fail 'vitasdk-update did not record the release after resolving it'

# An update is a refresh of the release the SDK follows, nothing else.
: > "$log"
VITASDK="$packaged" "$repository_root/vitasdk-update" >/dev/null
grep -Fqx '1 refresh 2026.08' "$log" || fail 'vitasdk-update did not refresh the release'
! grep -Fq 'transaction' "$log" || fail 'vitasdk-update ran a transaction it did not need'

# An SDK unpacked from an archive follows no release; it gets the one the
# bootstrap would have chosen, or the one named.
: > "$log"
FAKE_RELEASE= VITASDK="$packaged" "$repository_root/install-all.sh" >/dev/null 2>&1 ||
	fail 'install-all gave up on an SDK that follows no release'
grep -Fqx '1 refresh 2026.08' "$log" || fail 'install-all did not select the newest supported release'
: > "$log"
FAKE_RELEASE= VITASDK_CHANNEL=nightly VITASDK="$packaged" "$repository_root/vitasdk-update" >/dev/null 2>&1 ||
	fail 'vitasdk-update gave up on an SDK that follows no release'
grep -Fqx '1 refresh nightly' "$log" || fail 'vitasdk-update did not select the release it was told'

# A legacy SDK installs as it always did, one archive at a time, with the
# OpenSSL 1.0.2 its archive curl is built against, adding only what is missing.
: > "$log"
VITASDK="$legacy" "$repository_root/install-all.sh"
grep -Fqx '1 cpython' "$log" || fail 'install-all skipped a package on a legacy SDK'
! grep -q ' -f ' "$log" || fail 'install-all reinstalled archives the archive client cannot reinstall on macOS'
grep -Fqx '1 openssl' "$log" && ! grep -Fqx '1 openssl-1.1.1' "$log" ||
	fail 'install-all gave a legacy SDK an OpenSSL its curl does not link with'
! grep -Eq ' (status|search|refresh|pacman)' "$log" || fail 'install-all asked a legacy client what it cannot answer'

if message=$(VITASDK="$legacy" "$repository_root/vitasdk-update" 2>&1); then
	fail 'vitasdk-update accepted a legacy SDK'
fi
grep -q 'bootstrap-vitasdk.sh' <<< "$message" ||
	fail "vitasdk-update did not say how to get a new SDK: $message"

# The way vita-headers and samples CI install packages.
ci="$temporary_root/ci"
mkdir -p "$ci"
cp "$repository_root/vdpm" "$ci/vdpm"
sed -e 's/\.\.\///' "$repository_root/include/install-packages.sh" > "$ci/install-packages.sh"
: > "$log"
(cd "$ci" && sed -e 's/include\///' "$repository_root/install-all.sh" |
	VITASDK="$packaged" bash >/dev/null 2>&1) ||
	fail 'the CI installation pattern failed'
grep -q -- "--sync --needed .* sdl3_ttf" "$log" || fail 'the CI installation pattern did not install the list'

printf 'legacy entry point contracts passed\n'
