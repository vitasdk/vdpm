#!/bin/sh
# Bakes the target arch into the compiler: CMAKE_OSX_ARCHITECTURES alone
# doesn't survive into every nested ExternalProject_Add sub-build.
exec clang -arch x86_64 -mmacosx-version-min=11.0 "$@"
