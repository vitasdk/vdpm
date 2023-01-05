#!/bin/bash

get_download_link () {
  if ! [[ "$(uname -m)" =~ ^(armv7l|arm64|aarch64)$ ]]; then
    wget -qO- https://github.com/vitasdk/vita-headers/raw/master/.travis.d/last_built_toolchain.py | python - $@
  elif [[ "$(uname -s)" == Linux* ]]; then
    curl -s https://api.github.com/repos/SonicMastr/autobuilds/releases/latest | awk -F\" '/browser_download_url.*.tar.bz2/{print $(NF-1)}'
  else
    echo "Unsupported Architecture. VitaSDK not installed"
    exit 1
  fi
}

install_vitasdk () {
  INSTALLDIR=$1

  case "$(uname -s)" in
     Darwin*)
      mkdir -p $INSTALLDIR
      wget -O- "$(get_download_link master osx)" | tar xj -C $INSTALLDIR --strip-components=1
     ;;

     Linux*)
      if [ -n "${TRAVIS}" ]; then
          sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1 patch
      fi
      command -v curl || { echo "curl missing (install using: apt install curl)" ; exit 1; }
      if [ ! -d "$INSTALLDIR" ]; then
        sudo mkdir -p $INSTALLDIR
        sudo chown $USER:$(id -gn $USER) $INSTALLDIR
      fi
      wget -O- "$(get_download_link master linux)" | tar xj -C $INSTALLDIR --strip-components=1
     ;;

     MSYS*|MINGW64*)
      UNIX=false
      mkdir -p $INSTALLDIR
      wget -O- "$(get_download_link master win)" | tar xj -C $INSTALLDIR --strip-components=1
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
