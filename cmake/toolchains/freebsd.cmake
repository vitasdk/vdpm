# Cross-compile to FreeBSD from Linux; the sysroot and target come from the environment.
if(NOT DEFINED ENV{VDPM_FREEBSD_SYSROOT})
    message(FATAL_ERROR "VDPM_FREEBSD_SYSROOT must be set in the environment")
endif()
if(NOT DEFINED ENV{VDPM_FREEBSD_TARGET})
    message(FATAL_ERROR "VDPM_FREEBSD_TARGET must be set in the environment")
endif()

string(REGEX MATCH "^[^-]+" vdpm_freebsd_processor "$ENV{VDPM_FREEBSD_TARGET}")
if(NOT vdpm_freebsd_processor MATCHES "^(x86_64|aarch64)$")
    message(FATAL_ERROR "Unsupported FreeBSD target: $ENV{VDPM_FREEBSD_TARGET}")
endif()

set(CMAKE_SYSTEM_NAME FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR ${vdpm_freebsd_processor})
set(CMAKE_SYSROOT "$ENV{VDPM_FREEBSD_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
# BOTH, not ONLY: the client's own dependencies install outside the sysroot.
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/freebsd-clang-wrapper.sh")
set(CMAKE_AR llvm-ar)
set(CMAKE_RANLIB llvm-ranlib)
set(CMAKE_STRIP llvm-strip)
