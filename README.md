# vdpm

`vdpm` is VitaSDK's compatibility frontend for the rootless pacman client
installed inside the SDK. Package state lives only below `$VITASDK`; the host
package database and `/usr` are never used.

The transaction frontend is implemented in portable C. On Windows it builds
as a native `vdpm.exe` and starts the MSYS-ABI Pacman executable directly; it
does not require Bash or link to libalpm. The Windows product ships Pacman and
the signed-channel helper beside one `msys-2.0.dll`; channel orchestration uses
Windows PowerShell 5.1, which is part of supported Windows installations.

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

The native Windows contracts are exercised by `tests/test-vdpm-windows.ps1`
and `tests/test-channel-refresh-windows.ps1`. With non-system directories
removed from `PATH`, they complete a real Pacman install/query/remove
transaction and a signed, hash-verified channel refresh, including the failure
path where a bad database must not replace installed repository state.

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

On Windows, `tests/pacman/msys-pacman-build.sh` builds the pinned Pacman and
channel helper under MSYS; `tests/pacman/msys-runtime-smoke.ps1` verifies the
Pacman transaction runtime. VitaSDK `buildscripts` does not rebuild this
product: on every host it verifies and incorporates an exact published vdpm
bundle.

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

The production public key is committed at `share/vdpm/channel-public-key.pem`
and installed into every SDK. Refresh fails closed: a manifest whose signature
does not verify against it is not parsed, and nothing is written to pacman's
sync directory.

Where that key comes from in the first place is worth being exact about. The
bootstrap fetches a client seed from a release it names, over HTTPS, and
checks that the channel key inside it is the expected one. That check catches
a seed carrying the wrong key; it cannot catch a tampered client, because the
seed is the program that does every later check. **Delivering that release
intact is trusted to GitHub and to HTTPS**, which is a deliberate choice: the
alternative is to pin the digest of every host bundle in the script, and cut
every release in two passes so those digests exist before the tag does.

From the seed onwards nothing is taken on trust: the manifest is verified with
the key already on disk, the databases are accepted only if they hash to what
that manifest says, and pacman checks the packages against those databases.

## Bootstrap

The bootstrap installs a release without being told which one, and installs it
as packages rather than as a tree. It takes the newest series marked
`supported` from the channel index, fetches the client seed, checks the channel
key it carries, selects the series -- which writes the databases the signed
manifest names -- and lets pacman install `vitasdk-core` from them:

```sh
git clone https://github.com/vitasdk/vdpm
cd vdpm
./bootstrap-vitasdk.sh
```

`VITASDK_CHANNEL` names a different series — `nightly`, say — and `VITASDK`
or `--install-dir` chooses where it lands.

An exact archive can still be named, which is what a reproducible CI wants,
and then no series is selected because none was asked for:

```sh
./bootstrap-vitasdk.sh \
  --url 'https://github.com/vitasdk/autobuilds/releases/download/<tag>/<asset>' \
  --sha256 '<64 hexadecimal characters>'
```

PowerShell uses the equivalent `bootstrap-vitasdk.ps1`. Both implementations
work in a temporary sibling directory, verify what they download, reject unsafe
archive paths, and only then move the finished SDK into place. A failed
bootstrap leaves no partial installation at the requested destination, and an
existing destination is refused rather than written over.

Installing rather than unpacking is what makes the result something pacman
knows about: `vdpm upgrade` can update the toolchain, `vdpm refresh` can move
it to another series, and `vdpm status` can say which one is actually there.
An unpacked tree answers none of those, because nothing recorded that it was
ever installed.

This is intentionally a clean-install boundary: the old `packages.list`
database cannot describe file ownership to pacman, so an existing legacy SDK is
replaced rather than converted.

## Component releases

`.github/workflows/release.yml` builds reproducible, host-specific product
bundles for glibc Linux (x86_64, aarch64, built against glibc 2.31), musl
Linux (x86_64, aarch64), macOS (arm64, x86_64), FreeBSD (x86_64, aarch64,
cross-compiled and then executed in a FreeBSD VM) and Windows x86_64. Every
bundle carries its source revision, complete third-party notices and license
texts. Tags named `v*` are published first as a draft release; the workflow
downloads and byte-compares all assets before making the release visible.

These component releases contain the package manager, not the compiler SDK.
`buildscripts` incorporates an exact host bundle and `autobuilds` publishes the
final `vitasdk-bootstrap-<host>` archives consumed by the bootstrap tools.
