include_guard(GLOBAL)

# Reproducible source manifest for the package-manager product. These inputs
# are private to vdpm and are not part of the VitaSDK compiler superbuild.
set(ZLIB_VERSION 1.3.1)
set(ZLIB_HASH SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23)
set(ZLIB_URL https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz)

set(XZ_VERSION 5.8.3)
set(XZ_HASH SHA256=fff1ffcf2b0da84d308a14de513a1aa23d4e9aa3464d17e64b9714bfdd0bbfb6)
set(XZ_URL https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz)

set(LIBARCHIVE_VERSION 3.8.9)
set(LIBARCHIVE_HASH SHA256=888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde)
set(LIBARCHIVE_URL https://www.libarchive.org/downloads/libarchive-${LIBARCHIVE_VERSION}.tar.xz)

set(OPENSSL_VERSION 3.5.7)
set(OPENSSL_HASH SHA256=a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8)
set(OPENSSL_URL https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz)

set(CURL_VERSION 8.21.0)
set(CURL_HASH SHA256=aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6)
set(CURL_URL https://curl.se/download/curl-${CURL_VERSION}.tar.xz)

set(PACMAN_VERSION 7.1.0)
set(PACMAN_REPOSITORY https://gitlab.archlinux.org/pacman/pacman.git)
set(PACMAN_TAG v${PACMAN_VERSION})
set(PACMAN_COMMIT 5683f8477a0afcc6b331766175a83445b2dcfe89)
