cmake_minimum_required(VERSION 3.16)

project(vdpm-superbuild C)

include(ExternalProject)
include(CTest)

option(BUILD_VDPM_FRONTEND "Build the native vdpm frontend" ON)
option(BUILD_VDPM_CHANNEL "Build the signed-channel helper" ON)
option(BUILD_VDPM_PACKAGE_CLIENT "Build the pinned Pacman package client" OFF)
option(VDPM_OFFLINE "Disable updates for Git-backed package-client sources" ON)

set(VDPM_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/downloads" CACHE PATH
    "Directory for downloaded package-client sources")
set(VDPM_PACKAGE_CLIENT_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}" CACHE PATH
    "Install prefix for Pacman, pacman-conf and the channel helper")

install(FILES LICENSE
    DESTINATION share/vdpm/licenses
    RENAME vdpm-LGPL-2.1.txt)
install(FILES THIRD_PARTY_NOTICES.md DESTINATION share/vdpm)
install(PROGRAMS bootstrap-vitasdk.sh DESTINATION share/vdpm)
install(FILES bootstrap-vitasdk.ps1 DESTINATION share/vdpm)
install(FILES share/vdpm/channel-public-key.pem DESTINATION share/vdpm)
install(FILES include/refresh-repositories.ps1 DESTINATION share/vdpm)
if(UNIX)
    install(DIRECTORY include/
        DESTINATION bin/include
        USE_SOURCE_PERMISSIONS
        FILES_MATCHING PATTERN "*.sh")
endif()

if(BUILD_VDPM_PACKAGE_CLIENT)
    # OpenSSL is a private package-client input. Configure the channel helper
    # only after that archive exists, while the frontend remains a normal
    # target of this project.
    set(vdpm_build_channel ${BUILD_VDPM_CHANNEL})
    set(BUILD_VDPM_CHANNEL OFF)
    add_subdirectory(src)
    set(BUILD_VDPM_CHANNEL ${vdpm_build_channel})

    include(cmake/PackageClient.cmake)
    vdpm_add_package_client("${VDPM_PACKAGE_CLIENT_INSTALL_PREFIX}")

    if(vdpm_build_channel)
        ExternalProject_Add(vdpm-channel-product
            DEPENDS openssl-pacman
            DOWNLOAD_COMMAND ""
            SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src"
            CMAKE_ARGS
                -DCMAKE_BUILD_TYPE=Release
                -DCMAKE_INSTALL_PREFIX=${VDPM_PACKAGE_CLIENT_INSTALL_PREFIX}
                "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}"
                "-DCMAKE_EXE_LINKER_FLAGS=${CMAKE_EXE_LINKER_FLAGS}"
                -DBUILD_VDPM_FRONTEND=OFF
                -DBUILD_VDPM_CHANNEL=ON
                -DOPENSSL_ROOT_DIR=${CMAKE_BINARY_DIR}/package-client-deps
                -DOPENSSL_USE_STATIC_LIBS=TRUE)
        add_dependencies(vdpm-package-client vdpm-channel-product)
    endif()
else()
    add_subdirectory(src)
endif()

if(BUILD_TESTING AND UNIX)
    add_test(NAME vdpm-frontend-contract
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-vdpm.sh")
    add_test(NAME vdpm-channel-manifest-contract
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-channel-manifest.sh")
    add_test(NAME vdpm-release-bundle-contract
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-release-bundle.sh")
    add_test(NAME vdpm-channel-names
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-channel-names.sh")
    add_test(NAME vdpm-bootstrap-contract
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tests/test-bootstrap.sh")
endif()
