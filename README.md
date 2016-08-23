Vitadev Package manager
=============

VDPM is a project which aims on getting common libraries building for the PS Vita using the
[vitasdk toolchain](https://github.com/vitasdk). It was based off the original idea of xerpi's
vita\_portlibs.




Usage
=====

Getting started
---------------

**You should make sure you have the `patch` command installed.**

### Mac & Linux
First install cmake, you can get this from [Homebrew](http://brew.sh) on Mac (`brew install cmake`), 
and from your distro's package manager on Linux (on ubuntu: `sudo apt-get install cmake`).

```shell
git clone https://github.com/vitadev/vdpm
cd vdpm
cp config.sample config
./bootstrap-vitasdk.sh # skip this step if you already have vitasdk installed
                       # to /usr/local/vitasdk and have $VITASDK set
export VITASDK=/usr/local/vitasdk # define $VITASDK if you havent already
export PATH=$VITASDK/bin:$PATH # add vitasdk tool to $PATH if you havent already
./install-all.sh
```

### Windows (msys2)
```shell
pacman -Syu
pacman -S git
git clone https://github.com/vitadev/vdpm
cd vdpm
cp config.sample config
./bootstrap-vitasdk.sh # skip this step if you already have vitasdk installed
                       # to /usr/local/vitasdk and have $VITASDK set
export VITASDK=/usr/local/vitasdk # define $VITASDK if you havent already
export PATH=$VITASDK/bin:$PATH # add vitasdk tool to $PATH if you havent already
./install-all.sh
```

vdpm
----

vdpm helps with building libraries
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

Known Issues
------------
* The scripts that are used to install the required packages make use of [Wget](https://en.wikipedia.org/wiki/Wget) to download the required files. Some of the required files are downloaded from [SourceForge](https://sourceforge.net/) which redirects you to one of their mirror sites automatically. Wget handles this by default, however, if you (or your System Administrator) have a [Wget Startup File](https://www.gnu.org/software/wget/manual/html_node/Startup-File.html) in use it's possible to have settings in that file which will cause the downloads to fail, especially when using redirection from hosts such as SourceForge. If the installation isn't working for you and you notice that it's giving your errors about missing files try temporarily removing/renaming the Wget Startup File to see if that fixes the issue.


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
