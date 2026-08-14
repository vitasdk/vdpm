#!/usr/bin/env bash
#
# The Windows installer, run where it can be run cheaply.
#
# bootstrap-vitasdk.ps1 is PowerShell, which is not Windows-only, and the
# defect it kept producing was not Windows-only either: MSYS programs parse the
# command line they are handed a second time and expand the wildcards in it
# against the current directory. Pacman is one of those programs, and the
# installer passes it --overwrite patterns, so what reached pacman were the
# files sitting next to whoever started the installer.
#
# So the pacman here behaves like an MSYS program and refuses what MSYS pacman
# refuses. That turns a defect only a Windows runner could find into one this
# finds in seconds, on the script itself rather than on a copy of it.
#
# What this does not cover: the real toolchain, the real signatures, the real
# pacman. tests/test-bootstrap-windows.ps1 covers those on a Windows runner.
#
# On a machine without PowerShell:
#
#   docker run --rm --platform linux/amd64 -v "$PWD:/vdpm" -w /vdpm \
#       mcr.microsoft.com/powershell:7.4-debian-12 \
#       bash -c 'apt-get update -qq && apt-get install -y -qq bzip2 &&
#                ./tests/test-bootstrap-powershell.sh'

set -euo pipefail

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
check() {
	if [[ $2 == "$3" ]]; then
		printf 'ok: %s\n' "$1"
	else
		printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2"
		failures=$((failures + 1))
	fi
}

# The seed: the files the installer requires, and programs that answer the way
# the real ones do. Nothing here is a toolchain -- what is under test is the
# command line, not the compiler.
seed=$work/seed/vdpm-0.1.1-x86_64-w64-mingw32
msys=$seed/share/vdpm/msys/usr
mkdir -p "$seed/bin" "$msys/bin" "$msys/ssl/certs" "$seed/share/vdpm"
cp "$repository/share/vdpm/channel-public-key.pem" "$seed/share/vdpm/"
: >"$msys/bin/msys-2.0.dll"
: >"$msys/ssl/certs/ca-bundle.crt"

cat >"$seed/bin/vdpm.exe" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
--help) echo "usage: vdpm" ;;
refresh)
	# What the real refresh leaves behind: the databases to install from and
	# the series written into the installation.
	mkdir -p "$VITASDK/etc" "$VITASDK/var/lib/vdpm"
	printf '[options]\nHoldPkg = vitasdk-core\n[vitasdk]\n' >"$VITASDK/etc/pacman.conf"
	printf '{"channel":"%s","schema_version":1,"sequence":1}\n' "$2" \
		>"$VITASDK/var/lib/vdpm/channel.json"
	;;
*) echo "vdpm: unexpected command: $*" >&2; exit 2 ;;
esac
STUB

cat >"$msys/bin/vdpm-channel.exe" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

# The one that matters. Cygwin and its MSYS fork expand wildcards in the
# command line unless told not to, leaving unmatched patterns alone, and then
# read every non-option word as a package to install.
cat >"$msys/bin/pacman.exe" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${MSYS:-} != *noglob* ]]; then
	expanded=()
	for argument in "$@"; do
		if [[ $argument == *[*?]* ]]; then
			shopt -s nullglob
			matches=( $argument )
			shopt -u nullglob
			if (( ${#matches[@]} > 0 )); then
				expanded+=( "${matches[@]}" )
				continue
			fi
		fi
		expanded+=( "$argument" )
	done
	set -- "${expanded[@]}"
fi

printf '%s\n' "$@" >"${PACMAN_ARGUMENTS_LOG:-/dev/null}"
[[ ${1:-} == --version ]] && exit 0

root=
targets=()
skip=0
for argument in "$@"; do
	if (( skip )); then
		[[ $previous == --root ]] && root=$argument
		skip=0
		previous=
		continue
	fi
	case $argument in
	--root|--config|--dbpath|--cachedir|--logfile|--overwrite)
		previous=$argument
		skip=1
		;;
	--*) ;;
	*) targets+=( "$argument" ) ;;
	esac
done

for target in "${targets[@]}"; do
	if [[ $target == */* ]]; then
		# Verbatim from a real run: pacman reads repo/package, and a path is
		# a repository it has never heard of.
		printf "warning: '%s' is a file, did you mean -U/--upgrade?\n" "$target" >&2
		printf 'error: database not found: %s\n' "${target%%/*}" >&2
		exit 1
	fi
done

mkdir -p "$root/bin" "$root/var/lib/pacman/local/vitasdk-core-0.1.1-1"
: >"$root/bin/arm-vita-eabi-gcc.exe"
STUB
chmod +x "$seed/bin/vdpm.exe" "$msys/bin/pacman.exe" "$msys/bin/vdpm-channel.exe"

archive=$work/vdpm-0.1.1-x86_64-w64-mingw32.tar.bz2
tar -cjf "$archive" -C "$work/seed" "$(basename "$seed")"
sha256sum "$archive" | awk '{print $1}' >"$archive.sha256"

# The directory the installer is started from, filled with what its overwrite
# patterns match. On the runner this was the checkout, which happened to hold a
# stage/ directory; here it is on purpose.
decoy=$work/cwd
mkdir -p "$decoy/here/bin" "$decoy/here/share/vdpm/msys/usr/bin" "$decoy/here/etc"
: >"$decoy/here/bin/vdpm.exe"
: >"$decoy/here/etc/pacman.conf"
# More than one file per pattern, as the staged bundle has: one that expands to
# a single name is swallowed by its own --overwrite and hides the problem,
# which is what the first version of this test did.
for name in channel-public-key.pem list-channels.ps1 refresh-repositories.ps1; do
	: >"$decoy/here/share/vdpm/$name"
done
for name in pacman.exe vdpm-channel.exe msys-2.0.dll; do
	: >"$decoy/here/share/vdpm/msys/usr/bin/$name"
done

# Windows ships tar under that name and the installer calls it by that name.
shims=$work/shims
mkdir -p "$shims"
printf '#!/usr/bin/env bash\nexec tar "$@"\n' >"$shims/tar.exe"
chmod +x "$shims/tar.exe"

run_installer() {
	local script=$1 destination=$2 log=$3
	(
		cd "$decoy"
		PATH=$shims:$PATH \
		VITASDK_SEED_ARCHIVE=$archive \
		PACMAN_ARGUMENTS_LOG=$work/pacman-arguments.txt \
			pwsh -NoProfile -File "$script" \
				-InstallDirectory "$destination" -Channel 2026.08
	) >"$log" 2>&1
}

# 1. The installer as it stands.
if run_installer "$repository/bootstrap-vitasdk.ps1" "$work/sdk" "$work/install.log"; then
	installed=ok
else
	installed=$(tail -3 "$work/install.log")
fi
check "the installer runs to the end" "$installed" ok
check "and pacman was asked for the core" \
	"$(grep -c '^vitasdk-core$' "$work/pacman-arguments.txt" || true)" 1
check "with the patterns it was given" \
	"$(grep -c '^\*/' "$work/pacman-arguments.txt" || true)" 3
check "and nothing from the current directory" \
	"$(grep -c '^here/' "$work/pacman-arguments.txt" || true)" 0
check "the toolchain is on disk" "$([[ -f $work/sdk/bin/arm-vita-eabi-gcc.exe ]] && echo yes)" yes
check "and pacman recorded it" \
	"$([[ -d $work/sdk/var/lib/pacman/local/vitasdk-core-0.1.1-1 ]] && echo yes)" yes
check "the series was written into the installation" \
	"$(sed -n 's/.*"channel":"\([^"]*\)".*/\1/p' "$work/sdk/var/lib/vdpm/channel.json")" 2026.08

# 2. The same installer with the one line that stops the expansion removed,
# which has to fail: a test that passes either way tests nothing.
undone=$work/without-the-fix.ps1
sed "/MSYS = 'noglob'/d" "$repository/bootstrap-vitasdk.ps1" >"$undone"
check "the line is actually there to remove" \
	"$(diff -q "$undone" "$repository/bootstrap-vitasdk.ps1" >/dev/null && echo same || echo differs)" differs
if run_installer "$undone" "$work/sdk-undone" "$work/undone.log"; then
	undone_result=installed
else
	undone_result=refused
fi
check "without it the install is refused" "$undone_result" refused
check "and pacman says why" \
	"$(grep -c 'database not found' "$work/undone.log" || true)" 1

if (( failures != 0 )); then
	exit 1
fi
echo "the PowerShell installer keeps its arguments away from MSYS globbing"
