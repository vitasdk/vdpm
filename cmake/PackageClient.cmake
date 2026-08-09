include_guard(GLOBAL)

include(ExternalProject)
include(${CMAKE_CURRENT_LIST_DIR}/PackageClientVersions.cmake)

function(vdpm_add_package_client install_dir)
    if(CMAKE_VERSION VERSION_LESS 3.20)
        message(FATAL_ERROR "The package-client build requires CMake 3.20 or newer")
    endif()

    if(CMAKE_CROSSCOMPILING)
        message(FATAL_ERROR
            "The CMake package-client build currently supports native Linux and macOS builds only; use tests/pacman/msys-pacman-build.sh under MSYS on Windows")
    endif()

    set(vdpm_source_dir "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/..")
    set(deps_dir "${CMAKE_BINARY_DIR}/package-client-deps")

    find_program(MESON_EXECUTABLE meson REQUIRED)
    find_program(PACMAN_MAKE_EXECUTABLE NAMES gmake make REQUIRED)

    cmake_host_system_information(
        RESULT pacman_make_jobs
        QUERY NUMBER_OF_LOGICAL_CORES)
    if(pacman_make_jobs LESS 1)
        set(pacman_make_jobs 1)
    elseif(pacman_make_jobs GREATER 4)
        set(pacman_make_jobs 4)
    endif()

    set(pacman_patch_series
        "${vdpm_source_dir}/patches/pacman/0001-allow-writable-non-root-installation-roots.patch|1"
        "${vdpm_source_dir}/patches/pacman/0002-embed-libalpm-in-static-clients.patch|1"
        "${vdpm_source_dir}/patches/pacman/0003-build-libalpm-with-mingw.patch|1"
        "${vdpm_source_dir}/patches/pacman/0004-initialize-locale-without-i18n.patch|1"
        "${vdpm_source_dir}/patches/pacman/0005-reject-windows-casefold-collisions.patch|1")
    list(JOIN pacman_patch_series "^" pacman_patch_series_arg)

    set(common_cmake_args
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${deps_dir}
        "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}"
        -DBUILD_SHARED_LIBS=OFF)

    ExternalProject_Add(zlib-pacman
        URL ${ZLIB_URL}
        URL_HASH ${ZLIB_HASH}
        DOWNLOAD_DIR ${VDPM_DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS
            ${common_cmake_args}
            -DZLIB_BUILD_EXAMPLES=OFF
        )

    ExternalProject_Add(xz-pacman
        URL ${XZ_URL}
        URL_HASH ${XZ_HASH}
        DOWNLOAD_DIR ${VDPM_DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        LIST_SEPARATOR |
        CMAKE_ARGS
            ${common_cmake_args}
            -DBUILD_TESTING=OFF
            -DXZ_NLS=OFF
            "-DXZ_ENCODERS=lzma1|lzma2"
            "-DXZ_DECODERS=lzma1|lzma2"
            -DXZ_MICROLZMA_ENCODER=OFF
            -DXZ_MICROLZMA_DECODER=OFF
            -DXZ_LZIP_DECODER=OFF
            -DXZ_TOOL_XZDEC=OFF
            -DXZ_TOOL_LZMADEC=OFF
            -DXZ_TOOL_LZMAINFO=OFF
            -DXZ_TOOL_XZ=OFF
            -DXZ_DOC=OFF
        )

    ExternalProject_Add(openssl-pacman
        URL ${OPENSSL_URL}
        URL_HASH ${OPENSSL_HASH}
        DOWNLOAD_DIR ${VDPM_DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND <SOURCE_DIR>/Configure
            --prefix=${deps_dir}
            --libdir=lib
            no-shared
            no-tests
            no-apps
            no-docs
            no-module
            no-legacy
        # Do not inherit GNU make's jobserver from the outer CMake build. Its
        # file descriptors are not guaranteed to survive container emulation.
        BUILD_COMMAND ${CMAKE_COMMAND} -E env --unset=MAKEFLAGS --
            ${PACMAN_MAKE_EXECUTABLE} -j${pacman_make_jobs}
        INSTALL_COMMAND ${CMAKE_COMMAND} -E env --unset=MAKEFLAGS --
            ${PACMAN_MAKE_EXECUTABLE} install_sw
        )

    ExternalProject_Add(libarchive-pacman
        DEPENDS zlib-pacman xz-pacman
        URL ${LIBARCHIVE_URL}
        URL_HASH ${LIBARCHIVE_HASH}
        DOWNLOAD_DIR ${VDPM_DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS
            ${common_cmake_args}
            -DENABLE_OPENSSL=OFF
            -DENABLE_MBEDTLS=OFF
            -DENABLE_NETTLE=OFF
            -DENABLE_LIBB2=OFF
            -DENABLE_LZ4=OFF
            -DENABLE_LZO=OFF
            -DENABLE_ZSTD=OFF
            -DENABLE_BZip2=OFF
            -DENABLE_LIBXML2=OFF
            -DENABLE_EXPAT=OFF
            -DENABLE_WIN32_XMLLITE=OFF
            -DENABLE_PCREPOSIX=OFF
            -DENABLE_PCRE2POSIX=OFF
            -DENABLE_LIBGCC=OFF
            -DENABLE_TAR=OFF
            -DENABLE_CPIO=OFF
            -DENABLE_CAT=OFF
            -DENABLE_UNZIP=OFF
            -DENABLE_ICONV=OFF
            -DENABLE_TEST=OFF
            -DENABLE_WERROR=OFF
            -DZLIB_ROOT=${deps_dir}
            -DZLIB_USE_STATIC_LIBS=ON
            -DZLIB_LIBRARY=${deps_dir}/lib/libz.a
            -DZLIB_INCLUDE_DIR=${deps_dir}/include
            -DLIBLZMA_LIBRARY=${deps_dir}/lib/liblzma.a
            -DLIBLZMA_INCLUDE_DIR=${deps_dir}/include
        )

    set(curl_platform_args)
    if(APPLE)
        list(APPEND curl_platform_args
            -DCURL_CA_NATIVE=ON
            -DUSE_APPLE_SECTRUST=ON)
    endif()

    ExternalProject_Add(curl-pacman
        DEPENDS openssl-pacman
        URL ${CURL_URL}
        URL_HASH ${CURL_HASH}
        DOWNLOAD_DIR ${VDPM_DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS
            ${common_cmake_args}
            -DBUILD_STATIC_LIBS=ON
            -DBUILD_STATIC_CURL=OFF
            -DBUILD_CURL_EXE=OFF
            -DBUILD_TESTING=OFF
            -DBUILD_EXAMPLES=OFF
            -DBUILD_LIBCURL_DOCS=OFF
            -DBUILD_MISC_DOCS=OFF
            -DENABLE_CURL_MANUAL=OFF
            -DHTTP_ONLY=ON
            -DCURL_USE_OPENSSL=ON
            -DOPENSSL_ROOT_DIR=${deps_dir}
            -DOPENSSL_USE_STATIC_LIBS=TRUE
            -DCURL_ZLIB=OFF
            -DCURL_BROTLI=OFF
            -DCURL_ZSTD=OFF
            -DUSE_NGHTTP2=OFF
            -DUSE_NGTCP2=OFF
            -DUSE_QUICHE=OFF
            -DCURL_USE_LIBPSL=OFF
            -DUSE_LIBIDN2=OFF
            -DCURL_USE_LIBSSH2=OFF
            -DCURL_USE_LIBSSH=OFF
            -DCURL_USE_GSSAPI=OFF
            -DCURL_USE_GSASL=OFF
            -DENABLE_UNIX_SOCKETS=OFF
            ${curl_platform_args}
        )

    set(pacman_pkg_config_path
        "${deps_dir}/lib/pkgconfig:${deps_dir}/share/pkgconfig")

    ExternalProject_Add(pacman-client
        DEPENDS libarchive-pacman curl-pacman openssl-pacman
        GIT_REPOSITORY ${PACMAN_REPOSITORY}
        GIT_TAG ${PACMAN_TAG}
        GIT_SHALLOW TRUE
        GIT_SUBMODULES ""
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            -DEXPECTED_REVISION=${PACMAN_COMMIT}
            -P ${vdpm_source_dir}/cmake/VerifyGitRevision.cmake
        COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${pacman_patch_series_arg}"
            -P ${vdpm_source_dir}/cmake/ApplyPatches.cmake
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env
            "PKG_CONFIG_PATH=${pacman_pkg_config_path}"
            ${MESON_EXECUTABLE} setup <BINARY_DIR> <SOURCE_DIR>
            --buildtype=release
            --prefix=/
            -Dbuildstatic=true
            -Ddoc=disabled
            -Ddoxygen=disabled
            -Di18n=false
            -Dgpgme=disabled
            -Dcurl=enabled
            -Dcrypto=openssl
            -Dpkg-ext=.pkg.tar.xz
        BUILD_COMMAND ${CMAKE_COMMAND} -E env
            "PKG_CONFIG_PATH=${pacman_pkg_config_path}"
            ${MESON_EXECUTABLE} compile -C <BINARY_DIR>
        INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${install_dir}/bin
        COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/pacman ${install_dir}/bin/pacman
        COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/pacman-conf ${install_dir}/bin/pacman-conf
        UPDATE_DISCONNECTED ${VDPM_OFFLINE}
        )

    add_custom_target(vdpm-package-client DEPENDS pacman-client)
    add_custom_target(pacman-client-spike
        DEPENDS pacman-client
        COMMENT "Compatibility target; use vdpm-package-client")
endfunction()
