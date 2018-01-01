#!/bin/sh
set -e

get_download_link () {
  curl "https://api.github.com/repos/vitasdk/autobuilds/releases" | grep "browser_download_url" | grep $1 | head -n 1 | cut -d '"' -f 4
}

INSTALLDIR="/usr/local/vitasdk"

if [ -d "$INSTALLDIR" ]; then
  echo "$INSTALLDIR already exists. Remove it first (e.g. 'rm -rf $INSTALLDIR' or 'rm -rf $INSTALLDIR') and then restart this script"
  exit 1
fi

case "$(uname -s)" in
   Darwin*)
    mkdir -p $INSTALLDIR
    wget -O "vitasdk-nightly.tar.bz2" "$(get_download_link osx)"
    tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
   ;;

   Linux*)
    if [ -n "${TRAVIS}" ]; then
        apt-get install libc6-i386 lib32stdc++6 lib32gcc1 patch
    fi
    mkdir -p $INSTALLDIR
    chown $USER:$(id -gn $USER) $INSTALLDIR
    wget -O "vitasdk-nightly.tar.bz2" "$(get_download_link linux)"
    tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
   ;;

   MSYS*|MINGW64*)
    UNIX=false
    mkdir -p $INSTALLDIR
    wget -O "vitasdk-nightly.tar.bz2" "$(get_download_link mingw32)"
    tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
   ;;

   CYGWIN*|MINGW32*)
    echo "Please use msys2. Exiting..."
    exit 1
   ;;

   *)
     echo "Unknown OS"
     exit 1
    ;;
esac

echo "Please add the following to the bottom of your .bashrc:"
printf "\033[0;36m"'export VITASDK=/usr/local/vitasdk'"\033[0m\n"
printf "\033[0;36m"'export PATH=$VITASDK/bin:$PATH'"\033[0m\n"
echo "and then restart your terminal"
