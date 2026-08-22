#!/usr/bin/env bash

vdpm_host_triplet() {
	local architecture
	architecture=$(uname -m)
	case $architecture in
		amd64) architecture=x86_64 ;;
		arm64) [[ $(uname -s) == Linux || $(uname -s) == FreeBSD ]] && architecture=aarch64 ;;
	esac
	case $(uname -s) in
		Darwin*) printf '%s-apple-darwin\n' "$architecture" ;;
		Linux*)
			# Not a pipeline: musl's ldd exits 1, which pipefail reads as glibc.
			local banner
			banner=$(ldd --version 2>&1 || :)
			if [[ $banner == *musl* ]] ||
				[[ -z $banner && -e /lib/ld-musl-$architecture.so.1 ]]; then
				printf '%s-linux-musl\n' "$architecture"
			else
				printf '%s-linux-gnu\n' "$architecture"
			fi
			;;
		FreeBSD*) printf '%s-unknown-freebsd\n' "$architecture" ;;
		MSYS*|MINGW64*|CYGWIN*) printf '%s-w64-mingw32\n' "$architecture" ;;
		*) return 1 ;;
	esac
}
