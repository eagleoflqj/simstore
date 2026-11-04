add_executable(SimStore MACOSX_BUNDLE
    AppDelegate.swift
    SimStoreApp.swift
    SimulatorDiscovery.swift
    ContentView.swift
    SidebarView.swift
    NoSimulatorsView.swift
    MissingXcodeView.swift
    SimulatorStatusViews.swift
)

find_program(RSVG_CONVERT_EXECUTABLE rsvg-convert REQUIRED)
find_program(ICONUTIL_EXECUTABLE iconutil REQUIRED)
set(ICONSET_DIR "${CMAKE_CURRENT_BINARY_DIR}/simstore.iconset")
set(ICON_FILE "${CMAKE_CURRENT_BINARY_DIR}/simstore.icns")
set(ICON_COMMANDS)
foreach(SIZE 16 32 128 256 512)
    math(EXPR RETINA_SIZE "${SIZE} * 2")
    list(APPEND ICON_COMMANDS
        COMMAND "${RSVG_CONVERT_EXECUTABLE}" --width "${SIZE}" --height "${SIZE}"
            --output "${ICONSET_DIR}/icon_${SIZE}x${SIZE}.png" "${PROJECT_SOURCE_DIR}/assets/simstore.svg"
        COMMAND "${RSVG_CONVERT_EXECUTABLE}" --width "${RETINA_SIZE}" --height "${RETINA_SIZE}"
            --output "${ICONSET_DIR}/icon_${SIZE}x${SIZE}@2x.png" "${PROJECT_SOURCE_DIR}/assets/simstore.svg"
    )
endforeach()
add_custom_command(OUTPUT "${ICON_FILE}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ICONSET_DIR}"
    ${ICON_COMMANDS}
    COMMAND "${ICONUTIL_EXECUTABLE}" --convert icns --output "${ICON_FILE}" "${ICONSET_DIR}"
    DEPENDS "${PROJECT_SOURCE_DIR}/assets/simstore.svg"
    VERBATIM
)
set_source_files_properties("${ICON_FILE}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
target_sources(SimStore PRIVATE "${ICON_FILE}")

# Preserve the SDK version in LC_BUILD_VERSION when invoking swiftc directly.
target_link_options(SimStore PRIVATE
    "SHELL:-Xclang-linker -isysroot -Xclang-linker \"${CMAKE_OSX_SYSROOT}\""
)
set_target_properties(SimStore PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/cmake/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME SimStore
    MACOSX_BUNDLE_GUI_IDENTIFIER io.simstore.SimStore
    MACOSX_BUNDLE_ICON_FILE simstore.icns
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/modules"
)
add_custom_command(TARGET SimStore POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E rm -f "$<TARGET_BUNDLE_DIR:SimStore>/Contents/MacOS/SimStore.d"
    VERBATIM
)
