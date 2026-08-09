# Third-party notices

The vdpm package-manager bundle contains a patched Pacman client and statically
linked private dependencies. Exact versions, source locations and hashes are
recorded in `cmake/PackageClientVersions.cmake`.

| Component | License | Source |
| --- | --- | --- |
| Pacman/libalpm | GPL-2.0-or-later | https://gitlab.archlinux.org/pacman/pacman |
| zlib | Zlib | https://github.com/madler/zlib |
| XZ Utils | 0BSD and GPL/LGPL components | https://github.com/tukaani-project/xz |
| libarchive | BSD-2-Clause and BSD-3-Clause components | https://github.com/libarchive/libarchive |
| OpenSSL | Apache-2.0 | https://github.com/openssl/openssl |
| curl | curl license | https://github.com/curl/curl |

The corresponding complete license texts are installed below
`share/vdpm/licenses`. Windows bundles additionally carry the license files
provided by the exact MSYS2 runtime package shipped beside Pacman.
