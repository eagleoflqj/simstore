execute_process(COMMAND xcrun --find xcstringstool
    OUTPUT_VARIABLE XCSTRINGSTOOL_EXECUTABLE
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)

set(LOCALIZATION_CATALOG "${PROJECT_SOURCE_DIR}/assets/Localizable.xcstrings")
set(LOCALIZATION_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/localization")
set(STRINGSDATA_DIR "${CMAKE_CURRENT_BINARY_DIR}/stringsdata")
file(MAKE_DIRECTORY "${STRINGSDATA_DIR}")

target_compile_options(SimStore PRIVATE
    -emit-localized-strings
    -emit-localized-strings-path "${STRINGSDATA_DIR}"
)

# Use only current sources so metadata from renamed or removed files is ignored.
get_target_property(LOCALIZABLE_SOURCES SimStore SOURCES)
list(FILTER LOCALIZABLE_SOURCES INCLUDE REGEX "\\.swift$")
set(LOCALIZATION_STRINGSDATA_FILES)
foreach(SOURCE IN LISTS LOCALIZABLE_SOURCES)
    get_filename_component(SOURCE_NAME "${SOURCE}" NAME_WE)
    list(APPEND LOCALIZATION_STRINGSDATA_FILES "${STRINGSDATA_DIR}/${SOURCE_NAME}.stringsdata")
endforeach()

set(LOCALIZATION_RESOURCES
    "${LOCALIZATION_OUTPUT_DIR}/en.lproj/Localizable.strings"
    "${LOCALIZATION_OUTPUT_DIR}/zh-Hans.lproj/Localizable.strings"
)
add_custom_command(OUTPUT ${LOCALIZATION_RESOURCES}
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${LOCALIZATION_OUTPUT_DIR}"
    COMMAND "${XCSTRINGSTOOL_EXECUTABLE}" compile "${LOCALIZATION_CATALOG}"
        --output-directory "${LOCALIZATION_OUTPUT_DIR}" --language en --language zh-Hans
    DEPENDS "${LOCALIZATION_CATALOG}"
    COMMENT "Compiling English and Simplified Chinese strings"
    VERBATIM
)
foreach(RESOURCE IN LISTS LOCALIZATION_RESOURCES)
    get_filename_component(RESOURCE_DIRECTORY "${RESOURCE}" DIRECTORY)
    get_filename_component(LOCALE_DIRECTORY "${RESOURCE_DIRECTORY}" NAME)
    set_source_files_properties("${RESOURCE}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources/${LOCALE_DIRECTORY}"
    )
endforeach()
target_sources(SimStore PRIVATE ${LOCALIZATION_RESOURCES})

add_custom_target(GenerateStrings
    COMMAND "${CMAKE_COMMAND}"
        "-DXCSTRINGSTOOL_EXECUTABLE=${XCSTRINGSTOOL_EXECUTABLE}"
        "-DLOCALIZATION_CATALOG=${LOCALIZATION_CATALOG}"
        "-DSTRINGSDATA_FILES=${LOCALIZATION_STRINGSDATA_FILES}"
        -P "${PROJECT_SOURCE_DIR}/cmake/GenerateStrings.cmake"
    DEPENDS SimStore
    COMMENT "Updating the string catalog from Swift sources"
    VERBATIM
)
