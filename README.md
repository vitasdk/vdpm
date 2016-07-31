Vitadev Ports
=============

Ports is a project which aims on getting common libraries building for the PS Vita using the
[vitasdk toolchain](https://github.com/vitasdk). It was based off the original idea of xerpi's
vita\_portlibs.

Usage
=====

The a script called `./vdpm` (VitaDev Package Manager) help with building libraries
and software from their package description (in `pkg/*`).

```
Usage: vdpm [-iudlLx] [pkg pkg ..]
 -x : execute or enter into the vdpm shell
 -u : upgrade package
 -i : install package (.tgz or pkgname)
 -d : deinstall package
 -c : clean package (-ci to clean + install)
 -C : check checksum of pkg files (u=unmodified, m=modified)
 -r : remove devel/man/doc files to _remove/
      -r: list, -ri: reinstall, -rm: remove
 -s : search package by keyword
 -l : list installed packages or pkg files
 -L : list all available packages (-LL for description)
 -f : find missing libraries
      -fi: install, -fl: list, -fd: remove
 -p : patch package
 -P : unpatch package
```

Config
------

It requires a config file. For most users `cp config.sample config` will work fine.

Contributing
============

Contributions are welcome to both the package repo, documentation or the package manager itself.

Packages
--------

The format for packages are as follows.

```shell
# required
URL=http://example.com/testpkg-0.3.2.tar.gz # direct source url
TYPE=tar # tar/git
DESC="a test package for vdpm" # short description for the package
# optional
TARGET="libtest.a" # custom target for make
PKGINSTALL="${MAKE} install-libtest.a" # custom install command
USER_CFGARGS="--disable-shared --disable-threadsafe" # configure arguments
CFLAGS="${CFLAGS} -O3" # CFLAGS (must include ${CFLAGS} unless the intention is to replace computed CFLAGS)
```

They need to be placed in `pkg/` with their filename matching the extracted folder/git clone folder of the source.

License
-------
LGPL v2.1 or later.
