#!/bin/bash

get_download_link () {
  wget -O "releases.json" "https://api.github.com/repos/vitasdk/autobuilds/releases"
  grep "master" "releases.json" | grep "browser_download_url" | grep $1 | head -n 1 | cut -d '"' -f 4
  rm -f "releases.json"
}

install_vitasdk () {
  INSTALLDIR=$1

  case "$(uname -s)" in
     Darwin*)
      mkdir -p $INSTALLDIR
      wget -O "vitasdk-nightly.tar.bz2" "$(get_download_link osx)"
      tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
      rm -f "vitasdk-nightly.tar.bz2"
     ;;

     Linux*)
      if [ -n "${TRAVIS}" ]; then
          sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1 patch
      fi
      if [ ! -d "$INSTALLDIR" ]; then
        sudo mkdir -p $INSTALLDIR
        sudo chown $USER:$(id -gn $USER) $INSTALLDIR
      fi
      wget -O "vitasdk-nightly.tar.bz2" "$(get_download_link linux)"
      tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
      rm -f "vitasdk-nightly.tar.bz2"
     ;;

     MSYS*|MINGW64*)
      UNIX=false
      mkdir -p $INSTALLDIR
      wget -O "vitasdk-nightly.tar.bz2" "$(get_download_link mingw32)"
      tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
      rm -f "vitasdk-nightly.tar.bz2"
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

}
