find_package(Qt6 6.8 REQUIRED COMPONENTS Core)

qt_add_executable(hyui main.cpp document.cpp bridge.cpp package.cpp native_runtime.cpp)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_sources(hyui PRIVATE gtk.cpp)
endif()
if(WIN32)
    target_sources(hyui PRIVATE windows.cpp)
    find_program(HYDROGEN_DOTNET dotnet REQUIRED)
    add_custom_target(hyui-winui
        COMMAND ${HYDROGEN_DOTNET} publish "${CMAKE_CURRENT_SOURCE_DIR}/windows/Hyui.WinUI.csproj"
            -c Release -r win-x64 -o "${CMAKE_BINARY_DIR}/native-winui"
        VERBATIM)
    add_dependencies(hyui hyui-winui)
    install(DIRECTORY "${CMAKE_BINARY_DIR}/native-winui/" DESTINATION bin/native-winui)
endif()
set_target_properties(hyui PROPERTIES AUTOMOC ON RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
add_executable(hyui-launcher WIN32 launcher.cpp)
set_target_properties(hyui-launcher PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
if(WIN32)
    target_link_libraries(hyui-launcher PRIVATE shell32 user32)
endif()
add_dependencies(hyui hyui-launcher)
target_link_libraries(hyui PRIVATE Qt6::Core)
qt_add_resources(hyui hyui_library PREFIX "/hydrogen-ui"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/Hydrogen.UI"
    FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/Hydrogen.UI/Application.hy")
qt_add_resources(hyui hyui_winui PREFIX "/native-winui" BASE "${CMAKE_CURRENT_SOURCE_DIR}/windows"
    FILES windows/Hyui.WinUI.csproj windows/App.xaml windows/App.xaml.cs windows/app.manifest)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR APPLE)
    qt_add_executable(hyui-native native_main.cpp native_runtime.cpp document.cpp bridge.cpp)
    set_target_properties(hyui-native PROPERTIES AUTOMOC ON RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
    target_link_libraries(hyui-native PRIVATE Qt6::Core)
    if(APPLE)
        target_sources(hyui-native PRIVATE appkit.mm)
        target_link_libraries(hyui-native PRIVATE "-framework AppKit")
    else()
        target_sources(hyui-native PRIVATE gtk.cpp)
    endif()
    qt_add_resources(hyui-native hyui_native_library PREFIX "/hydrogen-ui"
        BASE "${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/Hydrogen.UI"
        FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/Hydrogen.UI/Application.hy")
    add_dependencies(hyui hyui-native)
    install(TARGETS hyui-native RUNTIME DESTINATION bin)
endif()
if(APPLE)
    enable_language(OBJCXX)
    target_sources(hyui PRIVATE appkit.mm)
    target_link_libraries(hyui PRIVATE "-framework AppKit")
    qt_add_executable(hyui_appkit_tests appkit_tests.mm appkit.mm native_runtime.cpp document.cpp bridge.cpp)
    set_target_properties(hyui_appkit_tests PROPERTIES AUTOMOC ON)
    target_link_libraries(hyui_appkit_tests PRIVATE Qt6::Core "-framework AppKit")
    add_test(NAME hyui_appkit_layout COMMAND hyui_appkit_tests "${PROJECT_SOURCE_DIR}/samples/ui_studio/Studio.hyui")
endif()

find_package(Python3 QUIET COMPONENTS Interpreter)
if(Python3_Interpreter_FOUND)
    add_test(NAME hyui_sdk_integration
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/integration.py
            $<TARGET_FILE:hyui> $<TARGET_FILE:hy> ${PROJECT_SOURCE_DIR})
    set_tests_properties(hyui_sdk_integration PROPERTIES TIMEOUT 180)
    set_tests_properties(hyui_sdk_integration PROPERTIES SKIP_RETURN_CODE 77)
    add_test(NAME hyui_sdk_package
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/package_integration.py
            $<TARGET_FILE:hyui> $<TARGET_FILE:hy> ${PROJECT_SOURCE_DIR})
    set_tests_properties(hyui_sdk_package PROPERTIES TIMEOUT 240 SKIP_RETURN_CODE 77)
endif()
install(TARGETS hyui RUNTIME DESTINATION bin BUNDLE DESTINATION .)
install(TARGETS hyui-launcher RUNTIME DESTINATION bin)

find_package(Qt6 6.8 QUIET COMPONENTS Test)
if(TARGET Qt6::Test)
    qt_add_executable(hyui_tests tests.cpp document.cpp bridge.cpp)
    set_target_properties(hyui_tests PROPERTIES AUTOMOC ON)
    target_link_libraries(hyui_tests PRIVATE Qt6::Test Qt6::Core)
    add_test(NAME hyui_contract COMMAND hyui_tests)
    set_tests_properties(hyui_contract PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
