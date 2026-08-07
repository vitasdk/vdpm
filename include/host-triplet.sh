#!/usr/bin/env bash

vdpm_host_triplet() {
	local architecture
	architecture=$(uname -m)
	case $architecture in
		amd64) architecture=x86_64 ;;
		arm64) [[ $(uname -s) == Linux ]] && architecture=aarch64 ;;
	esac
	case $(uname -s) in
		Darwin*) printf '%s-apple-darwin\n' "$architecture" ;;
		Linux*) printf '%s-linux-gnu\n' "$architecture" ;;
		MSYS*|MINGW64*) printf '%s-w64-mingw32\n' "$architecture" ;;
		*) return 1 ;;
	esac
}
