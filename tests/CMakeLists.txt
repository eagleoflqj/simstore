add_executable(SimStoreSmokeTest AppSmokeTest.swift)
add_dependencies(SimStoreSmokeTest SimStore)
# Parse the single-file @main entry point as a library.
target_compile_options(SimStoreSmokeTest PRIVATE -parse-as-library)
add_test(NAME app-window COMMAND SimStoreSmokeTest "$<TARGET_BUNDLE_DIR:SimStore>")
set_tests_properties(app-window PROPERTIES TIMEOUT 20 RUN_SERIAL TRUE)

add_executable(SimStoreLifecycleTest AppLifecycleTest.swift "${PROJECT_SOURCE_DIR}/src/AppDelegate.swift")
add_test(NAME app-window-close COMMAND SimStoreLifecycleTest)
set_tests_properties(app-window-close PROPERTIES TIMEOUT 10 RUN_SERIAL TRUE)

add_executable(SimStoreCommandTest CommandTests.swift "${PROJECT_SOURCE_DIR}/src/Command.swift")
target_compile_options(SimStoreCommandTest PRIVATE -parse-as-library)
add_test(NAME command COMMAND SimStoreCommandTest)
set_tests_properties(command PROPERTIES TIMEOUT 10)

add_executable(SimStoreCatalogTest AppCatalogTests.swift
    "${PROJECT_SOURCE_DIR}/src/AppCatalog.swift"
)
target_compile_options(SimStoreCatalogTest PRIVATE -parse-as-library)
add_test(NAME catalog COMMAND SimStoreCatalogTest)
set_tests_properties(catalog PROPERTIES TIMEOUT 10)

add_executable(SimStoreCatalogLoadingTest CatalogLoadingTests.swift
    "${PROJECT_SOURCE_DIR}/src/AppCatalog.swift"
    "${PROJECT_SOURCE_DIR}/src/CatalogClient.swift"
    "${PROJECT_SOURCE_DIR}/src/CatalogStore.swift"
    "${PROJECT_SOURCE_DIR}/src/AppConfiguration.swift"
)
target_compile_options(SimStoreCatalogLoadingTest PRIVATE -parse-as-library)
add_test(NAME catalog-loading COMMAND SimStoreCatalogLoadingTest)
set_tests_properties(catalog-loading PROPERTIES TIMEOUT 15)

add_executable(SimStoreDiscoveryTest SimulatorDiscoveryTests.swift
    "${PROJECT_SOURCE_DIR}/src/SimulatorDiscovery.swift"
    "${PROJECT_SOURCE_DIR}/src/Command.swift"
)
add_test(NAME simulator-discovery COMMAND SimStoreDiscoveryTest)
set_tests_properties(simulator-discovery PROPERTIES TIMEOUT 15)

add_executable(SimStoreControlTest SimulatorControlTests.swift
    "${PROJECT_SOURCE_DIR}/src/Command.swift"
    "${PROJECT_SOURCE_DIR}/src/SimulatorControl.swift"
)
target_compile_options(SimStoreControlTest PRIVATE -parse-as-library)
add_test(NAME simulator-control COMMAND SimStoreControlTest)
set_tests_properties(simulator-control PROPERTIES TIMEOUT 15)

add_executable(SimStoreApplicationsTest SimulatorApplicationsTests.swift
    "${PROJECT_SOURCE_DIR}/src/SimulatorApplications.swift"
    "${PROJECT_SOURCE_DIR}/src/SimulatorDiscovery.swift"
    "${PROJECT_SOURCE_DIR}/src/Command.swift"
)
target_compile_options(SimStoreApplicationsTest PRIVATE -parse-as-library)
add_test(NAME simulator-applications COMMAND SimStoreApplicationsTest)
set_tests_properties(simulator-applications PROPERTIES TIMEOUT 15)

add_executable(SimStoreInstalledAppsTest InstalledAppsStoreTests.swift
    "${PROJECT_SOURCE_DIR}/src/InstalledAppsStore.swift"
    "${PROJECT_SOURCE_DIR}/src/SimulatorApplications.swift"
    "${PROJECT_SOURCE_DIR}/src/SimulatorDiscovery.swift"
    "${PROJECT_SOURCE_DIR}/src/Command.swift"
    "${PROJECT_SOURCE_DIR}/src/AppCatalog.swift"
)
target_compile_options(SimStoreInstalledAppsTest PRIVATE -parse-as-library)
add_test(NAME installed-apps COMMAND SimStoreInstalledAppsTest)
set_tests_properties(installed-apps PROPERTIES TIMEOUT 15)

add_executable(SimStoreStoreTest SimulatorStoreTests.swift
    "${PROJECT_SOURCE_DIR}/src/SimulatorDiscovery.swift"
    "${PROJECT_SOURCE_DIR}/src/SimulatorStore.swift"
    "${PROJECT_SOURCE_DIR}/src/Command.swift"
)
target_compile_options(SimStoreStoreTest PRIVATE -parse-as-library)
add_test(NAME simulator-store COMMAND SimStoreStoreTest)
set_tests_properties(simulator-store PROPERTIES TIMEOUT 15)

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

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_executable(SimStorePreviewScenarioTest PreviewScenarioTests.swift
        "${PROJECT_SOURCE_DIR}/src/PreviewScenario.swift"
        "${PROJECT_SOURCE_DIR}/src/SimulatorDiscovery.swift"
        "${PROJECT_SOURCE_DIR}/src/Command.swift"
    )
    target_compile_definitions(SimStorePreviewScenarioTest PRIVATE DEBUG)
    target_compile_options(SimStorePreviewScenarioTest PRIVATE -parse-as-library)
    add_test(NAME preview-scenarios COMMAND SimStorePreviewScenarioTest)
    set_tests_properties(preview-scenarios PROPERTIES TIMEOUT 15)
endif()

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
