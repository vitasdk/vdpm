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
git clone https://github.com/vitasdk/vdpm
cd vdpm
./bootstrap-vitasdk.sh
export VITASDK=/usr/local/vitasdk # define $VITASDK if you haven't already
export PATH=$VITASDK/bin:$PATH # add vitasdk tool to $PATH if you haven't already
./install-all.sh
```

### Windows (Bash on Ubuntu on Windows)

Just follow the steps for Linux above. This is the recommended way to set up vdpm on Windows, however, it only works for Windows 10.

Read here for information on how to install Bash on Ubuntu on Windows: https://msdn.microsoft.com/en-us/commandline/wsl/install_guide

### Windows (msys2)

For older versions of Windows, you should use msys2. Get it from here: https://msys2.github.io/. Only 64-bit version is supported.

```shell
# Read through https://msys2.github.io/ and make sure your msys2 is up-to-date first
pacman -S make git wget p7zip tar cmake
git clone https://github.com/vitasdk/vdpm
cd vdpm
./bootstrap-vitasdk.sh
export VITASDK=/usr/local/vitasdk # define $VITASDK if you haven't already
export PATH=$VITASDK/bin:$PATH # add vitasdk tool to $PATH if you haven't already
./install-all.sh
```

Update/reinstall
----------------

Run `./vitasdk-update` which will replace files in `$VITASDK` with the latest nightly and libraries.


Known Issues
------------
* The scripts that are used to install the required packages make use of [Wget](https://en.wikipedia.org/wiki/Wget) to download the required files. Some of the required files are downloaded from [SourceForge](https://sourceforge.net/) which redirects you to one of their mirror sites automatically. Wget handles this by default, however, if you (or your System Administrator) have a [Wget Startup File](https://www.gnu.org/software/wget/manual/html_node/Startup-File.html) in use it's possible to have settings in that file which will cause the downloads to fail, especially when using redirection from hosts such as SourceForge. If the installation isn't working for you and you notice that it's giving your errors about missing files try temporarily removing/renaming the Wget Startup File to see if that fixes the issue.


Contributing
============

Contributions are welcome to both the package repo, documentation or the package manager itself.

License
-------
LGPL v2.1 or later.
