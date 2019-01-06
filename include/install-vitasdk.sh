#!/bin/bash

get_download_link () {
  curl -sL "https://api.github.com/repos/vitasdk/autobuilds/releases" | grep "master" | grep "browser_download_url" | grep $1 | head -n 1 | cut -d '"' -f 4
}

need_root_perm () {
  curr=$1
  while true; do
    if [ -d "$curr" ]; then
      DIR_INFO=($(stat -Lc "%a %U %G" $curr))
      PERM="0${DIR_INFO[0]}"
      OWNER=${DIR_INFO[1]}
      GROUP=${DIR_INFO[2]}
      if [[ $(($PERM & 0200)) != 0 && $USER == $OWNER ]]; then
        return
      elif [ $(($PERM & 0002)) != 0 ]; then
        return
      elif [[ $(($PERM & 0020)) != 0 ]]; then
        groups=($(groups $USER))
        for grp in "${groups[@]}"; do
          if [[ $GROUP == $grp ]]; then
            return
          fi
        done
      fi
      echo 1
      return
    fi
    curr=$(dirname $curr)
  done
}

install_vitasdk () {
  INSTALLDIR=$1

  case "$(uname -s)" in
     Darwin*)
      if [ -d "$INSTALLDIR" ]; then
          rm -rf $INSTALLDIR
      fi
      mkdir -p $INSTALLDIR
      curl -o "vitasdk-nightly.tar.bz2" -L "$(get_download_link osx)"
      tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
      rm -f "vitasdk-nightly.tar.bz2"
     ;;

     Linux*)
      if [ -n "${TRAVIS}" ]; then
          sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1 patch
      fi
      SUDO=
      if [ ! -z "$(need_root_perm $INSTALLDIR)" ]; then
        SUDO=sudo
      fi
      if [ -d "$INSTALLDIR" ]; then
        $SUDO rm -rf $INSTALLDIR
        if [ ! -z "$(need_root_perm $INSTALLDIR)" ]; then
          SUDO=sudo
        fi
      fi
      $SUDO mkdir -p $INSTALLDIR
      $SUDO chown $USER:$(id -gn $USER) $INSTALLDIR
      curl -o "vitasdk-nightly.tar.bz2" -L "$(get_download_link linux)"
      tar xf "vitasdk-nightly.tar.bz2" -C $INSTALLDIR --strip-components=1
      rm -f "vitasdk-nightly.tar.bz2"
     ;;

     MSYS*|MINGW64*)
      UNIX=false
      if [ -d "$INSTALLDIR" ]; then
          rm -rf $INSTALLDIR
      fi
      mkdir -p $INSTALLDIR
      curl -o "vitasdk-nightly.tar.bz2" -L "$(get_download_link mingw32)"
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
