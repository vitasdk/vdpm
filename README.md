# vdpm

`vdpm` is VitaSDK's compatibility frontend for the rootless pacman client
installed inside the SDK. Package state lives only below `$VITASDK`; the host
package database and `/usr` are never used.

```sh
vdpm install zlib sdl2
vdpm remove zlib
vdpm upgrade
vdpm list
vdpm search image
vdpm info sdl2
vdpm files sdl2
vdpm refresh nightly
```

The historical forms `vdpm PACKAGE...`, `vdpm -f PACKAGE...` and
`vdpm -u PACKAGE...` remain available during migration.

## Repository trust

`vdpm refresh` downloads a canonical channel manifest and detached Ed25519
signature. OpenSSL verifies the signature against the public key installed in
`$VITASDK/share/vdpm/channel-public-key.pem`. The manifest selects immutable
SDK and library release tags and contains the SHA-256 of each pacman database.
Only verified databases are placed in pacman's local sync directory; package
hashes are subsequently enforced by pacman from those databases.

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
