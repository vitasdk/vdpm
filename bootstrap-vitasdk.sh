#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

INSTALLDIR="${VITASDK:-/usr/local/vitasdk}"

. $DIR/include/install-vitasdk.sh

echo "==> Installing vitasdk to $INSTALLDIR"
install_vitasdk $INSTALLDIR

echo "Please add the following to the bottom of your .bashrc:"
printf "\033[0;36m""export VITASDK=${INSTALLDIR}""\033[0m\n"
printf "\033[0;36m"'export PATH=$VITASDK/bin:$PATH'"\033[0m\n"
echo "and then restart your terminal"
