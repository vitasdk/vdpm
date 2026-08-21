#!/usr/bin/env bash

set -euo pipefail

if (( $# != 2 )); then
	printf 'usage: %s <bundle.tar.bz2> <host-triplet>\n' "$0" >&2
	exit 2
fi

archive=$1
host=$2
[[ -f $archive && ! -L $archive ]] || {
	printf 'bundle is not a regular file: %s\n' "$archive" >&2
	exit 1
}
archive=$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")
bundle_name=$(basename "$archive" .tar.bz2)
[[ $bundle_name == vdpm-*-$host ]] || {
	printf 'bundle filename does not match host: %s\n' "$bundle_name" >&2
	exit 1
}

while IFS= read -r entry; do
	[[ $entry == "$bundle_name" || $entry == "$bundle_name/"* ]] || {
		printf 'bundle entry escapes its top-level directory: %s\n' "$entry" >&2
		exit 1
	}
	[[ /$entry/ != *'/../'* ]] || {
		printf 'bundle entry contains parent traversal: %s\n' "$entry" >&2
		exit 1
	}
done < <(tar -tjf "$archive")

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-release-validation.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT
tar -xjf "$archive" -C "$temporary_directory"
root="$temporary_directory/$bundle_name"
[[ -d $root ]] || exit 1
if find "$root" -type l | grep -q .; then
	printf 'bundle contains symbolic links\n' >&2
	exit 1
fi

info="$root/share/vdpm/release-info.txt"
grep -Fqx 'schema_version=1' "$info"
grep -Fqx "host=$host" "$info"
grep -Eq '^source_revision=[0-9a-f]{7,64}$' "$info"
grep -Eq '^source_date_epoch=[0-9]+$' "$info"
test -s "$root/share/vdpm/THIRD_PARTY_NOTICES.md"
test -s "$root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"

case $host in
	*-w64-mingw32)
		test -s "$root/bin/vdpm.exe"
		test -s "$root/share/vdpm/msys/usr/bin/pacman.exe"
		test -s "$root/share/vdpm/msys/usr/bin/vdpm-channel.exe"
		test -s "$root/share/vdpm/msys/usr/bin/msys-2.0.dll"
		# A client that cannot reach a repository is not a client.
		test -s "$root/share/vdpm/msys/usr/ssl/certs/ca-bundle.crt"
		test -s "$root/share/vdpm/refresh-repositories.ps1"
		if [[ ${VDPM_VALIDATE_PE_IMPORTS:-0} == 1 ]]; then
			command -v objdump >/dev/null
			mapfile -t vdpm_imports < <(
				objdump -p "$root/bin/vdpm.exe" |
					sed -n 's/^[[:space:]]*DLL Name: //p' |
					sort -fu
			)
			(( ${#vdpm_imports[@]} > 0 ))
			for import in "${vdpm_imports[@]}"; do
				case ${import,,} in
					vcruntime*.dll|msvcp*.dll|ucrtbase.dll|api-ms-win-crt-*.dll)
						printf 'vdpm.exe imports a dynamic C runtime: %s\n' \
							"$import" >&2
						exit 1
						;;
					msys-*.dll)
						printf 'vdpm.exe unexpectedly imports MSYS: %s\n' \
							"$import" >&2
						exit 1
						;;
				esac
			done
		fi
		;;
	*)
		for executable in vdpm vdpm-channel; do
			test -x "$root/bin/$executable"
		done
		for executable in pacman pacman-conf; do
			test -x "$root/libexec/vdpm/$executable"
		done
		test -x "$root/bin/include/host-triplet.sh"
		test -x "$root/bin/include/refresh-repositories.sh"
		# vdpm runs every helper as a program, so one shipped without its
		# executable bit is a command that fails on an installed SDK.
		while IFS= read -r helper; do
			[[ -x $helper ]] || {
				printf 'bundle helper is not executable: %s\n' \
					"${helper#"$root/"}" >&2
				exit 1
			}
		done < <(find "$root/bin/include" -type f -name '*.sh')
		for license in pacman-GPL-2.0.txt zlib.txt xz-COPYING.txt \
				libarchive.txt openssl-Apache-2.0.txt curl.txt; do
			test -s "$root/share/vdpm/licenses/$license"
		done
		if [[ ${VDPM_VALIDATE_EXECUTABLES:-0} == 1 ]]; then
			"$root/bin/vdpm" --help >/dev/null
			"$root/libexec/vdpm/pacman" --version >/dev/null
			"$root/bin/vdpm-channel" sha256 \
				"$root/share/vdpm/THIRD_PARTY_NOTICES.md" >/dev/null
		fi
		;;
esac

printf 'validated vdpm release bundle: %s\n' "$bundle_name"
