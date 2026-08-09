cmake_minimum_required(VERSION 3.16)

project(vdpm C)

option(BUILD_VDPM_FRONTEND "Build the native vdpm frontend" ON)
option(BUILD_VDPM_CHANNEL "Build the signed-channel helper" ON)

if(BUILD_VDPM_FRONTEND)
    add_executable(vdpm vdpm.c)
    if(MSVC)
        target_sources(vdpm PRIVATE vdpm.manifest)
        set_property(TARGET vdpm PROPERTY MSVC_RUNTIME_LIBRARY
            "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    endif()
    target_compile_features(vdpm PRIVATE c_std_99)
    install(TARGETS vdpm RUNTIME DESTINATION bin)
endif()

# The superbuild points OPENSSL_ROOT_DIR at its own static build and sets
# OPENSSL_USE_STATIC_LIBS, so the SDK ships no dynamic private dependency.
# Letting FindOpenSSL resolve the target also carries the platform specific
# link requirements of a static libcrypto.
if(BUILD_VDPM_CHANNEL)
    find_package(OpenSSL REQUIRED)

    add_executable(vdpm-channel vdpm-channel.c)
    if(MSVC)
        set_property(TARGET vdpm-channel PROPERTY MSVC_RUNTIME_LIBRARY
            "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    endif()
    target_compile_features(vdpm-channel PRIVATE c_std_99)
    target_link_libraries(vdpm-channel PRIVATE OpenSSL::Crypto)
    install(TARGETS vdpm-channel RUNTIME DESTINATION bin)
endif()

if(MSVC)
    if(BUILD_VDPM_FRONTEND)
        target_compile_definitions(vdpm PRIVATE _CRT_SECURE_NO_WARNINGS)
        target_compile_options(vdpm PRIVATE /W4 /WX)
    endif()
else()
    if(BUILD_VDPM_FRONTEND)
        target_compile_options(vdpm PRIVATE -Wall -Wextra -Werror)
    endif()
    if(BUILD_VDPM_CHANNEL)
        target_compile_options(vdpm-channel PRIVATE -Wall -Wextra -Werror)
    endif()
endif()
