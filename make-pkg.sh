#!/bin/bash

function error {
    echo "error: $1"
    exit 1
}

echo -n "PKGNAME: "    && read PKGNAME    || error "on input"
echo -n "PKGDESC: "    && read PKGDESC    || error "on input"
echo -n "PKGVER: "     && read PKGVER     || error "on input"
echo -n "PKGURL: "     && read PKGURL     || error "on input"
echo -n "PKGLICENSE: " && read PKGLICENSE || error "on input"
echo -n "DEPENDS: "    && read DEPENDS    || error "on input"

cp "package.desc.in" "repo/${PKGNAME}.desc"

function config {
    case "$(uname)" in
        Darwin*) 
            sed -i '' -e "$1" "repo/${PKGNAME}.desc"
            ;;
        *)
            sed -i -e "$1" "repo/${PKGNAME}.desc"
            ;;
    esac
}

config "s^@PKGNAME@^${PKGNAME}^g"
config "s^@PKGVER@^${PKGVER}^g"
config "s^@PKGDESC@^${PKGDESC}^g"
config "s^@PKGURL@^${PKGURL}^g"
config "s^@PKGLICENSE@^${PKGLICENSE}^g"
config "s^@DEPENDS@^${DEPENDS}^g"
