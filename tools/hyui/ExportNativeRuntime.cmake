# Export native desktop resources without the legacy hyui packaging CLI.
if(NOT DEFINED HYDROGEN_UI_PLATFORM OR NOT DEFINED HYDROGEN_UI_BUILD_DIR OR NOT DEFINED HYDROGEN_UI_SDK_DIR)
    message(FATAL_ERROR "Missing native UI runtime export configuration")
endif()

if(HYDROGEN_UI_PLATFORM STREQUAL "Windows")
    set(_runtime "${HYDROGEN_UI_SDK_DIR}/windows-x64")
    set(_host "${HYDROGEN_UI_BUILD_DIR}/native-winui/Hyui.WinUI.exe")
    set(_launcher "${HYDROGEN_UI_BUILD_DIR}/hyui-launcher.exe")
    if(NOT EXISTS "${_host}" OR NOT EXISTS "${_launcher}")
        message(FATAL_ERROR "Native WinUI runtime or launcher was not built")
    endif()
    file(MAKE_DIRECTORY "${_runtime}")
    file(COPY "${HYDROGEN_UI_BUILD_DIR}/native-winui/" DESTINATION "${_runtime}")
    configure_file("${_host}" "${_runtime}/hyui.exe" COPYONLY)
    configure_file("${_launcher}" "${_runtime}/hyui-launcher.exe" COPYONLY)
    file(WRITE "${_runtime}/hyui-runtime.json"
        "{\"format\":1,\"target\":\"windows-x64\",\"renderer\":\"winui3\"}\n")
    message(STATUS "Exported native Windows UI SDK: ${_runtime}")
elseif(HYDROGEN_UI_PLATFORM STREQUAL "Darwin")
    set(_app "${HYDROGEN_UI_SDK_DIR}/macos-x64.app")
    set(_contents "${_app}/Contents")
    set(_host "${HYDROGEN_UI_BUILD_DIR}/hyui-native")
    set(_launcher "${HYDROGEN_UI_BUILD_DIR}/hyui-launcher")
    if(NOT EXISTS "${_host}" OR NOT EXISTS "${_launcher}")
        message(FATAL_ERROR "Native AppKit runtime or launcher was not built")
    endif()
    execute_process(COMMAND lipo -archs "${_host}"
        OUTPUT_VARIABLE _architectures RESULT_VARIABLE _arch_status
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT _arch_status EQUAL 0 OR NOT _architectures MATCHES "(^| )x86_64($| )")
        message(FATAL_ERROR "macOS x64 UI SDK requires an x86_64 native host; build Qt and hyui-native for x86_64")
    endif()
    file(MAKE_DIRECTORY "${_contents}/MacOS" "${_contents}/Resources/app")
    configure_file("${_host}" "${_contents}/MacOS/hyui" COPYONLY)
    configure_file("${_launcher}" "${_contents}/MacOS/hyui-launcher" COPYONLY)
    file(WRITE "${_contents}/Info.plist"
        "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
        "<key>CFBundleExecutable</key><string>hyui-launcher</string>"
        "<key>CFBundleIdentifier</key><string>software.aurora.hydrogen.app</string>"
        "<key>CFBundlePackageType</key><string>APPL</string>"
        "<key>NSHighResolutionCapable</key><true/></dict></plist>")
    if(DEFINED HYDROGEN_UI_QT_PREFIX)
        find_program(_macdeployqt NAMES macdeployqt HINTS "${HYDROGEN_UI_QT_PREFIX}/bin")
    else()
        find_program(_macdeployqt NAMES macdeployqt)
    endif()
    if(NOT _macdeployqt)
        message(FATAL_ERROR "macdeployqt not found; install matching Qt 6 deployment tools")
    endif()
    execute_process(COMMAND "${_macdeployqt}" "${_app}"
        "-executable=${_contents}/MacOS/hyui" "-no-codesign"
        RESULT_VARIABLE _deploy_status OUTPUT_VARIABLE _deploy_out ERROR_VARIABLE _deploy_error)
    if(NOT _deploy_status EQUAL 0)
        message(FATAL_ERROR "macdeployqt failed: ${_deploy_out}\n${_deploy_error}")
    endif()
    file(WRITE "${_contents}/hyui-runtime.json"
        "{\"format\":1,\"target\":\"macos-x64\",\"renderer\":\"appkit\"}\n")
    message(STATUS "Exported native macOS UI SDK: ${_app}")
else()
    message(FATAL_ERROR "Windows and macOS runtime export only; Linux uses bootstrap hyui-native")
endif()
