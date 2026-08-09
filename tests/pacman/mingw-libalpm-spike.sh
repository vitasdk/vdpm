#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
	printf 'usage: %s <patched-pacman-source> <build-directory>\n' "$0" >&2
	exit 2
fi

source_dir=$(cd "$1" && pwd -P)
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mkdir -p "$2"
build_dir=$(cd "$2" && pwd -P)

target_cc=${TARGET_CC:-x86_64-w64-mingw32-gcc}
target_pkg_config=${TARGET_PKG_CONFIG:-x86_64-w64-mingw32-pkg-config}

for command_name in meson ninja "$target_cc" "$target_pkg_config"; do
	if ! command -v "$command_name" >/dev/null; then
		printf 'missing command: %s\n' "$command_name" >&2
		exit 1
	fi
done

meson_setup_args=(setup "$build_dir" "$source_dir")
if [[ -f $build_dir/build.ninja ]]; then
	meson_setup_args+=(--reconfigure)
fi

meson "${meson_setup_args[@]}" \
	--cross-file "$script_dir/x86_64-w64-mingw32.ini" \
	--buildtype=release \
	-Dbuildstatic=true \
	-Ddoc=disabled -Ddoxygen=disabled -Di18n=false \
	-Dgpgme=disabled -Dcurl=enabled -Dcrypto=openssl \
	-Dfile-seccomp=disabled -Dpkg-ext=.pkg.tar.xz

ninja -C "$build_dir" libalpm_objlib.a

read -r -a dependency_flags <<<"$(
	"$target_pkg_config" --static --libs libarchive libcurl libcrypto
)"

"$target_cc" \
	-D_FILE_OFFSET_BITS=64 \
	-I"$source_dir/lib/libalpm" \
	"$script_dir/mingw-libalpm-smoke.c" \
	"$build_dir/libalpm_objlib.a" \
	-Wl,--start-group "${dependency_flags[@]}" -lregex -Wl,--end-group \
	-o "$build_dir/mingw-libalpm-smoke.exe"

printf 'built %s\n' "$build_dir/libalpm_objlib.a"
printf 'built %s\n' "$build_dir/mingw-libalpm-smoke.exe"
