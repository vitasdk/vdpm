# vdpm

`vdpm` is VitaSDK's compatibility frontend for the rootless pacman client
installed inside the SDK. Package state lives only below `$VITASDK`; the host
package database and `/usr` are never used.

The transaction frontend is implemented in portable C. On Windows it builds
as a native `vdpm.exe` and starts the MSYS-ABI Pacman executable directly; it
does not require Bash or link to libalpm. The Windows package-client runtime is
limited to `$VITASDK/usr/bin/pacman.exe` and adjacent `msys-2.0.dll`.

```sh
vdpm install zlib sdl2
vdpm remove zlib
vdpm upgrade
vdpm list
vdpm search image
vdpm info sdl2
vdpm files sdl2
vdpm refresh nightly
vdpm pacman -- --database --check
```

The historical forms `vdpm PACKAGE...`, `vdpm -f PACKAGE...` and
`vdpm -u PACKAGE...` remain available during migration.

The native Windows contract is exercised by
`tests/test-vdpm-windows.ps1`. With non-system directories removed from
`PATH`, it builds `vdpm.exe` with MSVC and uses the historical install and
remove forms to complete a real Pacman install/query/remove transaction. The
signed `vdpm refresh` orchestration is still implemented by the Unix shell
frontend and remains to be ported before the native Windows frontend replaces
it completely.

## Package client build

This repository owns the complete package-manager product: the `vdpm`
frontend, the pinned Pacman/libalpm sources, their private dependencies,
platform patches and transaction tests. A native Linux or macOS build is:

```sh
cmake -S . -B build -DBUILD_VDPM_PACKAGE_CLIENT=ON \
  -DVDPM_PACKAGE_CLIENT_INSTALL_PREFIX="$PWD/stage"
cmake --build build --target vdpm-package-client --parallel
cmake --build build --target install
```

On Windows, `tests/pacman/msys-pacman-build.sh` builds the pinned Pacman under
MSYS and `tests/pacman/msys-runtime-smoke.ps1` verifies the two-file runtime.
VitaSDK `buildscripts` only selects a vdpm revision, invokes this interface and
incorporates the resulting files into the SDK distribution.

## Repository trust

`vdpm refresh` downloads a canonical channel manifest and detached Ed25519
signature. The `vdpm-channel` helper installed with the SDK verifies the
signature against the public key installed in
`$VITASDK/share/vdpm/channel-public-key.pem`, and only then parses the
manifest. It selects immutable SDK and library release tags and contains the
SHA-256 of each pacman database. Only verified databases are placed in pacman's
local sync directory; package hashes are subsequently enforced by pacman from
those databases.

Signature checking, manifest parsing and digests are all performed by that
helper so that a security decision never depends on which interpreter or
command line tool happens to be installed on the host.

No production public key has been committed yet. Until the VitaSDK
organization provisions and publishes that key, channel refresh intentionally
fails closed and no package-managed snapshot can be promoted to stable.

## Transitional bootstrap

The mutable “latest master release” lookup has been removed. The Unix and
Windows bootstrap programs accept only an explicitly selected immutable SDK
archive and its published SHA-256:

```sh
VITASDK_BOOTSTRAP_URL='https://github.com/vitasdk/autobuilds/releases/download/<tag>/<asset>' \
VITASDK_BOOTSTRAP_SHA256='<64 hexadecimal characters>' \
./bootstrap-vitasdk.sh
```

PowerShell uses the equivalent `bootstrap-vitasdk.ps1`. Both implementations
download into a temporary sibling directory, verify the digest, reject unsafe
archive paths, extract and validate the package manager and compiler, and only
then move the complete SDK into place. A failed bootstrap leaves no partial
installation at the requested destination.

This is intentionally a clean-install boundary. The old `packages.list`
database cannot safely describe file ownership to Pacman, so replacing only
the legacy `vdpm` executable inside an existing SDK is unsupported. The Bash
and C Pacman frontends are interchangeable once the SDK already contains the
new Pacman database and configuration.

## Component releases

`.github/workflows/release.yml` builds reproducible, host-specific product
bundles for Linux x86_64, Linux aarch64, macOS arm64 and Windows x86_64. Every
bundle carries its source revision, complete third-party notices and license
texts. Tags named `v*` are published first as a draft release; the workflow
downloads and byte-compares all assets before making the release visible.

These component releases contain the package manager, not the compiler SDK.
`buildscripts` incorporates an exact vdpm revision and `autobuilds` publishes
the final `vitasdk-bootstrap-<host>` archives consumed by the bootstrap tools.
