#!/bin/sh

get_version () {
  # replace with '5\.4' if you want that version
  GCCVER='4\.9'
  curl "https://bintray.com/package/files/vitasdk/vitasdk/toolchain?order=desc&sort=fileLastModified&basePath=&tab=files" | egrep "\?file_path=vitasdk-gcc-$GCCVER-.*$1-.+\">" -ao | head -n1 | cut -d= -f2 | cut -d'"' -f1
}

case "$(uname -s)" in
   Darwin*)
    mkdir -p /usr/local/vitasdk
    wget -O "vitasdk-nightly.tar.bz2" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=$(get_version mac)"
    tar xf "vitasdk-nightly.tar.bz2" -C /usr/local/vitasdk --strip-components=1
   ;;

   Linux*)
    if [ -n "${TRAVIS}" ]; then
        sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1 patch
    fi
    sudo mkdir -p /usr/local/vitasdk
    sudo chown $USER:$USER /usr/local/vitasdk
    wget -O "vitasdk-nightly.tar.bz2" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=$(get_version linux)"
    tar xf "vitasdk-nightly.tar.bz2" -C /usr/local/vitasdk --strip-components=1
   ;;

   MSYS*)
    UNIX=false
    pacman -Syu --noconfirm make git wget p7zip tar cmake
    mkdir -p /usr/local/
    wget -O "vitasdk-nightly.zip" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=$(get_version win32)"
    7z x -o/usr/local/vitasdk vitasdk-nightly.zip
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

export VITASDK=/usr/local/vitasdk
export PATH=$VITASDK/bin:$PATH

echo "Please add the following to the bottom of your .bashrc:"
echo "export VITASDK=/usr/local/vitasdk"
echo "export PATH=$VITASDK/bin:$PATH"

