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

The mutable “latest master release” lookup has been removed. During the
migration, `bootstrap-vitasdk.sh` accepts only an explicitly selected immutable
legacy archive and its published SHA-256:

```sh
VITASDK_BOOTSTRAP_URL='https://github.com/vitasdk/autobuilds/releases/download/<tag>/<asset>' \
VITASDK_BOOTSTRAP_SHA256='<64 hexadecimal characters>' \
./bootstrap-vitasdk.sh
```

This transitional path will be replaced by the signed channel bootstrap after
the production key and complete Windows package client are available.
