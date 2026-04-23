cmake_minimum_required(VERSION 3.20)
project(HylangCompiler VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(hylang
    src/hylang.cpp
)

target_include_directories(hylang
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if (MSVC)
    target_compile_options(hylang PRIVATE /W4 /permissive-)
else()
    target_compile_options(hylang PRIVATE -Wall -Wextra -Wpedantic)
endif()

add_executable(hyrun src/hyrun_main.cpp)
target_link_libraries(hyrun PRIVATE hylang)

add_executable(hyc src/hyc_main.cpp)
target_link_libraries(hyc PRIVATE hylang)

enable_testing()

add_test(
    NAME hyrun_hello_world
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/hello_world.hy
)
set_tests_properties(hyrun_hello_world PROPERTIES PASS_REGULAR_EXPRESSION "Hello, World!")

add_test(
    NAME hyrun_object_flow
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/object_flow.hy
)
set_tests_properties(hyrun_object_flow PROPERTIES PASS_REGULAR_EXPRESSION "5")

add_test(
    NAME hyrun_static_field
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/static_field.hy
)
set_tests_properties(hyrun_static_field PROPERTIES PASS_REGULAR_EXPRESSION "2")

add_test(
    NAME hyrun_args_length
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/args_length.hy alpha beta gamma
)
set_tests_properties(hyrun_args_length PROPERTIES PASS_REGULAR_EXPRESSION "3")

add_test(
    NAME hyrun_allocation_loop
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/allocation_loop.hy
)
set_tests_properties(hyrun_allocation_loop PROPERTIES PASS_REGULAR_EXPRESSION "999")

add_test(
    NAME hyrun_for_loop
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/for_loop.hy
)
set_tests_properties(hyrun_for_loop PROPERTIES PASS_REGULAR_EXPRESSION "9")

add_test(
    NAME hyrun_string_features
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/string_features.hy
)
set_tests_properties(hyrun_string_features PROPERTIES PASS_REGULAR_EXPRESSION "Flag=true")

add_test(
    NAME hyrun_file_roundtrip
    COMMAND ${CMAKE_COMMAND}
        -DMODE=run
        -DEXECUTE_BINARY=$<TARGET_FILE:hyrun>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/file_roundtrip.hy
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hyrun_file_roundtrip
        -DINPUT_TEXT=Hydrogen
        -DEXPECTED_OUTPUT_REGEX=chars=8
        -DEXPECTED_FILE_TEXT=chars=8
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunWithTempFiles.cmake
)

add_test(
    NAME hyrun_text_report_project
    COMMAND ${CMAKE_COMMAND}
        -DMODE=run
        -DEXECUTE_BINARY=$<TARGET_FILE:hyrun>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/samples/text_report/TextReport.hyproj
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hyrun_text_report
        -DINPUT_TEXT=SampleText
        -DEXPECTED_OUTPUT_REGEX=characters=10
        -DEXPECTED_FILE_TEXT=characters=10
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunWithTempFiles.cmake
)

add_test(
    NAME hyc_build_and_run_hello
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/hello_world.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/hello_world
        -DEXPECTED_TEXT=Hello,\ World!
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_object_flow
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/object_flow.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/object_flow
        -DEXPECTED_TEXT=5
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_static_field
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/static_field.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/static_field
        -DEXPECTED_TEXT=2
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_args_length
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/args_length.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/args_length
        -DRUN_ARGS=alpha;beta;gamma
        -DEXPECTED_TEXT=3
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_allocation_loop
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/allocation_loop.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/allocation_loop
        -DEXPECTED_TEXT=999
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_for_loop
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/for_loop.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/for_loop
        -DEXPECTED_TEXT=9
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_string_features
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/string_features.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/string_features
        -DEXPECTED_TEXT=Flag=true
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_file_roundtrip
    COMMAND ${CMAKE_COMMAND}
        -DMODE=build
        -DEXECUTE_BINARY=$<TARGET_FILE:hyc>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/file_roundtrip.hy
        -DOUTPUT_ARTIFACT=${CMAKE_CURRENT_BINARY_DIR}/generated/file_roundtrip
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hyc_file_roundtrip
        -DINPUT_TEXT=Compiler
        -DEXPECTED_OUTPUT_REGEX=chars=8
        -DEXPECTED_FILE_TEXT=chars=8
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunWithTempFiles.cmake
)

add_test(
    NAME hyc_build_and_run_text_report_project
    COMMAND ${CMAKE_COMMAND}
        -DMODE=build
        -DEXECUTE_BINARY=$<TARGET_FILE:hyc>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/samples/text_report/TextReport.hyproj
        -DOUTPUT_ARTIFACT=${CMAKE_CURRENT_BINARY_DIR}/generated/text_report
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hyc_text_report
        -DINPUT_TEXT=Longer\ sample
        -DEXPECTED_OUTPUT_REGEX=characters=13
        -DEXPECTED_FILE_TEXT=characters=13
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunWithTempFiles.cmake
)

add_test(
    NAME hyc_build_library_and_app
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/projects/app/App.hyproj
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/app_from_project
        -DSTATIC_LIB_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/libmathlib.a
        -DSTATIC_LIB_ALT=${CMAKE_CURRENT_BINARY_DIR}/generated/mathlib.lib
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildProjectAndRun.cmake
)

add_test(
    NAME hyrun_missing_main_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/missing_main.hy
)
set_tests_properties(hyrun_missing_main_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "Entry point not found"
)

add_test(
    NAME hyrun_duplicate_symbols_fail
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/duplicate_method.hy
)
set_tests_properties(hyrun_duplicate_symbols_fail PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "Duplicate method"
)

add_test(
    NAME hyrun_unresolved_using_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/unresolved_using.hy
)
set_tests_properties(hyrun_unresolved_using_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "Unresolved using directive"
)

add_test(
    NAME hyrun_wrong_arguments_fail
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/wrong_arguments.hy
)
set_tests_properties(hyrun_wrong_arguments_fail PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "No overload of 'WriteLine' matches the provided arguments"
)

add_test(
    NAME hyrun_invalid_return_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/invalid_return.hy
)
set_tests_properties(hyrun_invalid_return_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "Return expression type 'string' is not assignable to 'int'"
)

add_test(
    NAME hyrun_private_access_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/private_access.hy
)
set_tests_properties(hyrun_private_access_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "protection level"
)

add_test(
    NAME hyrun_private_constructor_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/private_constructor.hy
)
set_tests_properties(hyrun_private_constructor_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "protection level"
)

add_test(
    NAME hyrun_break_outside_loop_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/break_outside_loop.hy
)
set_tests_properties(hyrun_break_outside_loop_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "inside a loop"
)

add_test(
    NAME hyrun_continue_outside_loop_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/continue_outside_loop.hy
)
set_tests_properties(hyrun_continue_outside_loop_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "inside a loop"
)

add_test(
    NAME hyrun_for_condition_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/for_condition.hy
)
set_tests_properties(hyrun_for_condition_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "For condition must be of type 'bool'"
)

add_test(
    NAME hyrun_invalid_string_plus_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/invalid_string_plus.hy
)
set_tests_properties(hyrun_invalid_string_plus_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "string concatenation operands"
)

add_test(
    NAME hyrun_file_wrong_arguments_fails
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/file_wrong_arguments.hy
)
set_tests_properties(hyrun_file_wrong_arguments_fails PROPERTIES
    WILL_FAIL TRUE
    PASS_REGULAR_EXPRESSION "No overload of 'Exists' matches the provided arguments"
)
