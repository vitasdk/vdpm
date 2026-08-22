# Cross-compile to macOS/x86_64 from an arm64 runner.
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "" FORCE)
set(CMAKE_C_COMPILER "${CMAKE_CURRENT_LIST_DIR}/macos-x86_64-clang-wrapper.sh")
set(CMAKE_AR /usr/bin/ar)
set(CMAKE_RANLIB /usr/bin/ranlib)
set(CMAKE_STRIP /usr/bin/strip)
