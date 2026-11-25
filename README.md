# VitaSDK package manager

`vdpm` installs and manages libraries and toolchain packages for
[VitaSDK](https://github.com/vitasdk), the toolchain for developing PS Vita
homebrew. It uses a copy of pacman included in the SDK and keeps packages and
their records inside `$VITASDK`, separate from your system's package manager.

## Getting started

The bootstrap script installs VitaSDK and selects the newest supported release
series. Libraries can then be installed with `vdpm`.

### macOS, Linux and FreeBSD

You need Git, Bash, curl or wget, tar with bzip2 support, realpath, and either
sha256sum or shasum.

```sh
git clone https://github.com/vitasdk/vdpm
cd vdpm
./bootstrap-vitasdk.sh
export VITASDK=/usr/local/vitasdk
export PATH="$VITASDK/bin:$PATH"
```

The default install directory is `/usr/local/vitasdk`. To use another location,
pass `--install-dir /absolute/path/to/vitasdk` and set `VITASDK` to that path.
Add the two `export` lines to your shell configuration to keep these settings.

### Windows

Run the PowerShell bootstrap script with Git and `tar.exe` available:

```powershell
git clone https://github.com/vitasdk/vdpm
cd vdpm
.\bootstrap-vitasdk.ps1
$env:VITASDK = 'C:\vitasdk'
$env:PATH = "$env:VITASDK\bin;$env:PATH"
```

The default install directory is `C:\vitasdk`; use `-InstallDirectory` to change
it. Save `VITASDK` and the addition to `PATH` in your user environment settings
to use them in future sessions. The installed package manager runs without Bash
or a separate MSYS2 installation and uses Windows PowerShell 5.1 for channel
operations.

Both scripts require a new install directory. If you have an SDK from before
the pacman package manager, install a fresh SDK in another directory; its old
`packages.list` database cannot be converted in place.

To choose a series during installation, set `VITASDK_CHANNEL` before running
the bootstrap script (for example, `nightly`). For an exact SDK archive, pass
`--url` and `--sha256` (`-Url` and `-Sha256` in PowerShell). This requires the
archive's SHA-256 checksum and does not select a release series automatically.

## Installing libraries

```sh
vdpm install zlib sdl2
vdpm search image
vdpm info sdl2
vdpm list
vdpm files sdl2
vdpm remove zlib
```

The older forms `vdpm PACKAGE...`, `vdpm -f PACKAGE...` (reinstall) and
`vdpm -u PACKAGE...` (remove) are still supported. Use `vdpm --help` for the
command list, or `vdpm pacman -- ARG...` to pass arguments directly to pacman.

## Updating

`vdpm status` shows the installed release series. Refresh it to download the
latest package information and update the installed packages:

```sh
vdpm channels
vdpm refresh SERIES
```

Replace `SERIES` with your current series, or choose another from
`vdpm channels` to switch releases. `vdpm upgrade` updates packages using the
information from the last refresh. From this checkout, `./vitasdk-update`
refreshes and updates your current series without switching releases.

## Download verification

The bootstrap checks archive checksums, rejects unsafe archive paths and
prepares the SDK in a temporary directory before moving it into place.

The initial package client comes from a fixed GitHub release over HTTPS. The
bootstrap checks that it contains the expected channel key, but relies on
GitHub and HTTPS to deliver the client intact; that key check cannot detect a
tampered client.

After installation, `vdpm-channel` verifies channel manifests with the bundled
Ed25519 public key. It checks repository database hashes before accepting them,
and pacman checks package hashes against those databases. A failed signature
or database check leaves the existing repository databases in place.

## Contributing

Contributions to the package manager and documentation are welcome. This
repository contains the C frontend, channel verification helper, pinned
pacman sources and dependencies, platform patches and tests.

To build the package client on Linux or macOS:

```sh
cmake -S . -B build -DBUILD_VDPM_PACKAGE_CLIENT=ON \
  -DCMAKE_INSTALL_PREFIX="$PWD/stage"
cmake --build build --target vdpm-package-client --parallel
cmake --build build --target install
```

See [the package client notes](tests/pacman/README.md) for more build and test
details, including Windows.

[The release workflow](.github/workflows/release.yml) builds package-manager
bundles for Linux, macOS, FreeBSD and Windows. VitaSDK's `buildscripts` includes
these bundles in the SDK archives published by `autobuilds`.

## License

[LGPL v2.1 or later](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md)
for bundled dependencies.
