#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vdpm-contract.XXXXXXXX")
sdk_root="$temporary_root/sdk"
arguments_log="$temporary_root/arguments"
vdpm_binary="$temporary_root/vdpm"

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$sdk_root/bin" "$sdk_root/etc"
cat > "$sdk_root/bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$VDPM_TEST_LOG"
printf '\n' >> "$VDPM_TEST_LOG"
EOF
chmod +x "$sdk_root/bin/pacman"
printf '[options]\nArchitecture = test vita\n' > "$sdk_root/etc/pacman.conf"

"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
	"$repository_root/src/vdpm.c" -o "$vdpm_binary"

run_vdpm() {
	VITASDK="$sdk_root" VDPM_TEST_LOG="$arguments_log" VDPM_NONINTERACTIVE=1 \
		"$vdpm_binary" "$@"
}

run_vdpm install --force zlib libpng
run_vdpm -u zlib
run_vdpm upgrade
run_vdpm list
run_vdpm search image
run_vdpm files libpng
run_vdpm pacman -- --database --check

common="--config $sdk_root/etc/pacman.conf --root $sdk_root --dbpath $sdk_root/var/lib/pacman --cachedir $sdk_root/var/cache/pacman/pkg --logfile $sdk_root/var/log/pacman.log"
transaction_common="$common --noscriptlet --noconfirm --noprogressbar"
query_common="$common"
grep -Fqx -e "$transaction_common --sync zlib libpng " "$arguments_log"
grep -Fqx -e "$transaction_common --remove zlib " "$arguments_log"
grep -Fqx -e "$transaction_common --sync --sysupgrade " "$arguments_log"
grep -Fqx -e "$query_common --query " "$arguments_log"
grep -Fqx -e "$query_common --sync --search image " "$arguments_log"
grep -Fqx -e "$query_common --query --list libpng " "$arguments_log"
grep -Fqx -e "$query_common --database --check " "$arguments_log"

if run_vdpm install; then
	printf 'empty install was unexpectedly accepted\n' >&2
	exit 1
fi

printf 'vdpm pacman frontend contracts passed\n'
