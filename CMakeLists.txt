cmake_minimum_required(VERSION 4.3)

execute_process(COMMAND uname -sm
    OUTPUT_VARIABLE HOST_PLATFORM
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
if(NOT HOST_PLATFORM STREQUAL "Darwin arm64")
    message(FATAL_ERROR "SimStore requires Apple Silicon macOS.")
endif()

set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Target architecture")
if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    message(FATAL_ERROR "SimStore supports only the arm64 architecture.")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0 CACHE STRING "Minimum macOS version")
if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 14.0)
    message(FATAL_ERROR "SimStore requires macOS 14.0 or later.")
endif()

if(NOT CMAKE_OSX_SYSROOT)
    execute_process(COMMAND xcrun --sdk macosx --show-sdk-path
        OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )
endif()
if(NOT CMAKE_Swift_COMPILER OR CMAKE_Swift_COMPILER STREQUAL "/usr/bin/swiftc")
    execute_process(COMMAND xcrun --find swiftc
        OUTPUT_VARIABLE SWIFTC
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )
    set(CMAKE_Swift_COMPILER "${SWIFTC}" CACHE FILEPATH "Swift compiler" FORCE)
endif()
set(CMAKE_Swift_COMPILER_TARGET "arm64-apple-macos${CMAKE_OSX_DEPLOYMENT_TARGET}")

project(SimStore VERSION 0.1.0 LANGUAGES Swift)
set(CMAKE_Swift_LANGUAGE_VERSION 6)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_subdirectory(src)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
