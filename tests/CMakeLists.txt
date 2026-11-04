add_executable(SimStoreSmokeTest AppSmokeTest.swift)
add_dependencies(SimStoreSmokeTest SimStore)
# Parse the single-file @main entry point as a library.
target_compile_options(SimStoreSmokeTest PRIVATE -parse-as-library)
add_test(NAME app-window COMMAND SimStoreSmokeTest "$<TARGET_BUNDLE_DIR:SimStore>")
set_tests_properties(app-window PROPERTIES TIMEOUT 20 RUN_SERIAL TRUE)

add_executable(SimStoreLifecycleTest AppLifecycleTest.swift "${PROJECT_SOURCE_DIR}/src/AppDelegate.swift")
add_test(NAME app-window-close COMMAND SimStoreLifecycleTest)
set_tests_properties(app-window-close PROPERTIES TIMEOUT 10 RUN_SERIAL TRUE)

add_executable(SimStoreDiscoveryTest SimulatorDiscoveryTests.swift "${PROJECT_SOURCE_DIR}/src/SimulatorDiscovery.swift")
add_test(NAME simulator-discovery COMMAND SimStoreDiscoveryTest)
set_tests_properties(simulator-discovery PROPERTIES TIMEOUT 15)

add_executable(SimStoreLocalizationTest LocalizationTests.swift)
add_dependencies(SimStoreLocalizationTest SimStore)
target_compile_options(SimStoreLocalizationTest PRIVATE -parse-as-library)
add_test(NAME localization COMMAND SimStoreLocalizationTest "$<TARGET_BUNDLE_DIR:SimStore>")
set_tests_properties(localization PROPERTIES TIMEOUT 10)

add_executable(SimStoreStableSizeTest StableSizeViewTests.swift "${PROJECT_SOURCE_DIR}/src/StableSizeView.swift")
add_dependencies(SimStoreStableSizeTest SimStore)
target_compile_options(SimStoreStableSizeTest PRIVATE -parse-as-library)
add_test(NAME stable-button-size COMMAND SimStoreStableSizeTest "$<TARGET_BUNDLE_DIR:SimStore>")
set_tests_properties(stable-button-size PROPERTIES TIMEOUT 15 RUN_SERIAL TRUE)

execute_process(COMMAND xcrun --sdk "${CMAKE_OSX_SYSROOT}" --show-sdk-version
    OUTPUT_VARIABLE SDK_VERSION
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
add_test(NAME bundle-metadata COMMAND "${CMAKE_COMMAND}"
    "-DEXECUTABLE=$<TARGET_FILE:SimStore>"
    "-DINFO_PLIST=$<TARGET_BUNDLE_DIR:SimStore>/Contents/Info.plist"
    "-DEXPECTED_SDK=${SDK_VERSION}"
    "-DEXPECTED_MIN_OS=${CMAKE_OSX_DEPLOYMENT_TARGET}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/BundleMetadataTest.cmake"
)
