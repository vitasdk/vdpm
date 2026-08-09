#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
	printf 'usage: %s <pacman-binary> <zlib-vita-package>\n' "$0" >&2
	exit 2
fi

if [[ $(id -u) -eq 0 ]]; then
	printf 'rootless smoke test must run as a non-root user\n' >&2
	exit 1
fi

pacman_binary=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
package=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-pacman-rootless.XXXXXXXX")
writable_root="$temporary_root/writable"
readonly_root="$temporary_root/readonly"

cleanup() {
	chmod -R u+rwX "$temporary_root" 2>/dev/null || true
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

if [[ ! -x $pacman_binary || ! -f $package ]]; then
	printf 'pacman binary or package is missing\n' >&2
	exit 1
fi

if "$pacman_binary" --config "$script_dir/rootless.conf" \
		--upgrade --noscriptlet --noconfirm "$package" \
		>"$temporary_root/default-root.log" 2>&1; then
	printf 'pacman accepted an unprivileged transaction without --root\n' >&2
	exit 1
fi

mkdir -p "$readonly_root/var/lib/pacman" "$readonly_root/var/cache/pacman/pkg"
chmod u-w "$readonly_root"
if "$pacman_binary" --config "$script_dir/rootless.conf" \
		--root "$readonly_root" \
		--dbpath "$readonly_root/var/lib/pacman" \
		--cachedir "$readonly_root/var/cache/pacman/pkg" \
		--upgrade --noscriptlet --noconfirm "$package" \
		>"$temporary_root/readonly-root.log" 2>&1; then
	printf 'pacman accepted a non-writable alternate root\n' >&2
	exit 1
fi
chmod u+w "$readonly_root"

mkdir -p "$writable_root/var/lib/pacman" \
	"$writable_root/var/cache/pacman/pkg" "$writable_root/var/log"
pacman_args=(
	--config "$script_dir/rootless.conf"
	--root "$writable_root"
	--dbpath "$writable_root/var/lib/pacman"
	--cachedir "$writable_root/var/cache/pacman/pkg"
	--logfile "$writable_root/var/log/pacman.log"
)

"$pacman_binary" "${pacman_args[@]}" \
	--upgrade --noscriptlet --noconfirm "$package"
"$pacman_binary" "${pacman_args[@]}" --query zlib |
	grep -qx 'zlib 1.3.2-2'

installed_archive="$writable_root/arm-vita-eabi/lib/libz.a"
test -f "$installed_archive"
case $(uname -s) in
	Darwin) installed_uid=$(stat -f '%u' "$installed_archive") ;;
	*) installed_uid=$(stat -c '%u' "$installed_archive") ;;
esac
test "$installed_uid" -eq "$(id -u)"

"$pacman_binary" "${pacman_args[@]}" \
	--remove --noscriptlet --noconfirm zlib
test ! -e "$installed_archive"
