execute_process(COMMAND xcrun vtool -show-build "${EXECUTABLE}"
    OUTPUT_VARIABLE BUILD_VERSION
    COMMAND_ERROR_IS_FATAL ANY
)

function(check_build_version FIELD EXPECTED)
    string(REGEX MATCH "[\r\n][ \t]+${FIELD} ([0-9.]+)" MATCH "${BUILD_VERSION}")
    if(NOT MATCH)
        message(FATAL_ERROR "Missing ${FIELD} in Mach-O build version:\n${BUILD_VERSION}")
    endif()
    set(ACTUAL "${CMAKE_MATCH_1}")
    if(NOT ACTUAL VERSION_EQUAL EXPECTED)
        message(FATAL_ERROR "Mach-O ${FIELD}: expected ${EXPECTED}, got ${ACTUAL}")
    endif()
endfunction()

check_build_version(sdk "${EXPECTED_SDK}")
check_build_version(minos "${EXPECTED_MIN_OS}")

execute_process(COMMAND /usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "${INFO_PLIST}"
    OUTPUT_VARIABLE PLIST_MIN_OS
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
if(NOT PLIST_MIN_OS VERSION_EQUAL EXPECTED_MIN_OS)
    message(FATAL_ERROR "Info.plist LSMinimumSystemVersion: expected ${EXPECTED_MIN_OS}, got ${PLIST_MIN_OS}")
endif()
