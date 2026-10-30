find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_add_executable(hyui main.cpp document.cpp bridge.cpp)
set_target_properties(hyui PROPERTIES AUTOMOC ON RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
target_link_libraries(hyui PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2)
qt_add_resources(hyui hyui_library PREFIX "/hydrogen-ui"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/Hydrogen.UI"
    FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/Hydrogen.UI/Application.hy")
if(APPLE)
    enable_language(OBJCXX)
    target_sources(hyui PRIVATE macos.mm)
    target_link_libraries(hyui PRIVATE "-framework AppKit")
endif()

find_package(Python3 QUIET COMPONENTS Interpreter)
if(Python3_Interpreter_FOUND)
    add_test(NAME hyui_sdk_integration
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/integration.py
            $<TARGET_FILE:hyui> $<TARGET_FILE:hy> ${PROJECT_SOURCE_DIR})
    set_tests_properties(hyui_sdk_integration PROPERTIES TIMEOUT 180)
endif()
install(TARGETS hyui RUNTIME DESTINATION bin BUNDLE DESTINATION .)

find_package(Qt6 6.8 QUIET COMPONENTS Test)
if(TARGET Qt6::Test)
    qt_add_executable(hyui_tests tests.cpp document.cpp bridge.cpp)
    set_target_properties(hyui_tests PROPERTIES AUTOMOC ON)
    target_link_libraries(hyui_tests PRIVATE Qt6::Test Qt6::Gui Qt6::Qml Qt6::Quick)
    add_test(NAME hyui_contract COMMAND hyui_tests)
    set_tests_properties(hyui_contract PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
