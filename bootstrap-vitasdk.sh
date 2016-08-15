#!/bin/sh

case "$(uname -s)" in
   Darwin*)
    mkdir -p /usr/local/vitasdk
    wget -O "vitasdk-nightly.tar.bz2" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=vitasdk-mac-nightly-c86e2b4b45bd9cad07abbbcb208519b0357a639a.tar.bz2"
    tar xf "vitasdk-nightly.tar.bz2" -C /usr/local/vitasdk --strip-components=1
   ;;

   Linux*)
    if [ -n "${TRAVIS}" ]; then
        sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1 patch
    fi
    sudo mkdir -p /usr/local/vitasdk
    sudo chown $USER:$USER /usr/local/vitasdk
    wget -O "vitasdk-nightly.tar.bz2" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=vitasdk-gcc-4.9-linux-compat-nightly-c5dd7f4051cdb0025a50acc343be863f724a1221.tar.bz2"
    tar xf "vitasdk-nightly.tar.bz2" -C /usr/local/vitasdk --strip-components=1
   ;;

   MSYS*)
    UNIX=false
    pacman -Syu --noconfirm make git wget p7zip tar cmake
    mkdir -p /usr/local/
    wget -O "vitasdk-nightly.zip" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=vitasdk-gcc-4.9-win32-nightly-c5dd7f4051cdb0025a50acc343be863f724a1221.zip"
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

echo "Please add the following to the bottom of your .bashrc:"
echo "export VITASDK=/usr/local/vitasdk"
echo "export PATH=$VITASDK/bin:$PATH"
export VITASDK=/usr/local/vitasdk
export PATH=$VITASDK/bin:$PATH
