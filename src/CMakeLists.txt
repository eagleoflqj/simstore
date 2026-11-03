add_executable(SimStore MACOSX_BUNDLE
    SimStoreApp.swift
    ContentView.swift
)
# Preserve the SDK version in LC_BUILD_VERSION when invoking swiftc directly.
target_link_options(SimStore PRIVATE
    "SHELL:-Xclang-linker -isysroot -Xclang-linker \"${CMAKE_OSX_SYSROOT}\""
)
set_target_properties(SimStore PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/cmake/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME SimStore
    MACOSX_BUNDLE_GUI_IDENTIFIER io.simstore.SimStore
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/modules"
)
add_custom_command(TARGET SimStore POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E rm -f "$<TARGET_BUNDLE_DIR:SimStore>/Contents/MacOS/SimStore.d"
    VERBATIM
)
