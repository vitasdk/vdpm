# Cross-compile to FreeBSD/x86_64 from Linux. Set VDPM_FREEBSD_SYSROOT and
# VDPM_FREEBSD_TARGET in the environment (not as -D args) before every
# cmake and cmake --build invocation.
if(NOT DEFINED ENV{VDPM_FREEBSD_SYSROOT})
    message(FATAL_ERROR "VDPM_FREEBSD_SYSROOT must be set in the environment")
endif()
if(NOT DEFINED ENV{VDPM_FREEBSD_TARGET})
    message(FATAL_ERROR "VDPM_FREEBSD_TARGET must be set in the environment")
endif()

set(CMAKE_SYSTEM_NAME FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSROOT "$ENV{VDPM_FREEBSD_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
# BOTH: dependencies build outside the sysroot too (into this project's own
# build tree), and ONLY would hide those from find_library/_path/_package.
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/freebsd-clang-wrapper.sh")
set(CMAKE_AR llvm-ar)
set(CMAKE_RANLIB llvm-ranlib)
set(CMAKE_STRIP llvm-strip)
