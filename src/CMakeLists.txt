cmake_minimum_required(VERSION 3.16)

project(vdpm-channel C)

# The superbuild points OPENSSL_ROOT_DIR at its own static build and sets
# OPENSSL_USE_STATIC_LIBS, so the SDK ships no dynamic private dependency.
# Letting FindOpenSSL resolve the target also carries the platform specific
# link requirements of a static libcrypto.
find_package(OpenSSL REQUIRED)

add_executable(vdpm-channel vdpm-channel.c)
target_compile_features(vdpm-channel PRIVATE c_std_99)
target_link_libraries(vdpm-channel PRIVATE OpenSSL::Crypto)

if(NOT MSVC)
	target_compile_options(vdpm-channel PRIVATE -Wall -Wextra -Werror)
endif()

install(TARGETS vdpm-channel RUNTIME DESTINATION bin)
