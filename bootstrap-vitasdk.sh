#!/bin/sh

case "$(uname -s)" in
   Darwin*)
    VITASDK_PLATFORM=osx
    UNIX=true
    mkdir /usr/local/vitasdk
   ;;

   Linux*)
    VITASDK_PLATFORM=linux
    UNIX=true
    if [ -n "${TRAVIS}" ]; then
        sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1
    fi
    sudo mkdir -p /usr/local/vitasdk
    sudo chown $USER:$USER /usr/local/vitasdk
   ;;

   CYGWIN*|MINGW32*|MSYS*)
    UNIX=false
    pacman -Syu --noconfirm make git wget p7zip tar
    mkdir -p /usr/local/
   ;;

   *)
     echo "Unknown OS"
     exit 1
    ;;
esac

if [ "${UNIX}" = true ]; then
    wget -O "vitasdk-nightly.tar.bz2" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=vitasdk-${VITASDK_PLATFORM}-nightly-${VITASDK_VER}.tar.bz2"
    tar xf "vitasdk-nightly.tar.bz2" -C /usr/local/vitasdk --strip-components=1
else
    wget -O "vitasdk-nightly.zip" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=vitasdk-${VITASDK_PLATFORM}-nightly-win32.zip"
    7z x -o/usr/local/vitasdk vitasdk-nightly.zip
fi

export VITASDK=/usr/local/vitasdk
export PATH=$VITASDK/bin:$PATH
