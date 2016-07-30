#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage $0 <package>"
    exit 255
fi

verbose=true
package="$1"

function pushd
{
    if ${verbose:-false} ; then
        command pushd "$@" > /dev/null
    else
        command pushd "$@"
    fi
}

function popd
{
    if ${verbose:-false} ; then
        command popd "$@" > /dev/null
    else
        command popd "$@"
    fi
}

function error
{
    echo "error: $1"
    exit 1
}

# Extracts a file based on its extension
# Usage: extract <archive> <output>
function auto_extract
{
    path=$1
    outdir=$2
    name=`echo $path|sed -e "s/.*\///"`
    ext=`echo $name|sed -e "s/.*\.//"`
    
    mkdir -p $outdir

    echo "Extracting $name..."
    
    case $ext in
        "tar") tar --no-same-owner -xf $path --strip-components=1 -C $outdir ;;
        "gz"|"tgz") tar --no-same-owner -xzf $path --strip-components=1 -C $outdir ;;
        "bz2"|"tbz2") tar --no-same-owner -xjf $path --strip-components=1 -C $outdir ;;
        "xz"|"txz") tar --no-same-owner -xJf $path --strip-components=1 -C $outdir ;;
        "zip") unzip $path ;;
        *) echo "I don't know how to extract $ext archives!"; return 1 ;;
    esac
    
    return $?
}

# Downloads and extracts a file, with some extra checks.
# Usage: download_and_extract <url> <output?>
function download_and_extract
{
    url=$1
    name=`echo $url|sed -e "s/.*\///"`
    outdir=$2
    [ -d $outdir ] && echo "Deleting old version of $outdir" && rm -rf $outdir
    [ -f $name ] && auto_extract $name $outdir || { wget --continue --no-check-certificate $url -O $outdir-$name || rm -f $outdir-$name; }
    [ -f $name ] || wget --no-check-certificate $url -O $outdir-$name && auto_extract $outdir-$name $outdir
}

# setup build
mkdir -p build
root="$(pwd)"
prefix_minus_vita=/usr/local/vitasdk
prefix=${prefix_minus_vita}/arm-vita-eabi
# get package description
source "$package" || exit 256

# dependencies

if [[ ! -z "${depends// }" ]]; then
    for depend in $depends; do
        echo "Requires $depend."
    done
fi 

builddir="${root}/build/$pkgname"

echo "Building..."
# build
pushd build
download_and_extract "$pkgurl" "$pkgname"
if ${verbose:-false} ; then
    build || error "build failed"
else
    build >/dev/null 2>&1 || error "build failed"
fi
popd

echo "Packaging..."
# setup packages
pkgdir="${root}/staging/$pkgname"
mkdir -p "$pkgdir"
if ${verbose:-false} ; then
    package || error "staging failed"
else
    package >/dev/null 2>&1 || error "staging failed"
fi

# copy desc to package
mkdir -p "${pkgdir}${prefix}/share/vitaports/"
cp "$package" "${pkgdir}${prefix}/share/vitaports/"

echo "Bundling..."
# make package
mkdir -p "packages"
pushd "${pkgdir}${prefix_minus_vita}"
tar cJvf "${root}/packages/vitasdk-${pkgname}-${pkgver}.tar.xz" .
popd

ls -lah "${root}/packages/vitasdk-${pkgname}-${pkgver}.tar.xz"