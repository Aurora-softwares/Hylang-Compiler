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

add_executable(hy src/hy_main.cpp)
target_link_libraries(hy PRIVATE hylang)

enable_testing()

function(add_hyrun_negative_test test_name source_file expected_regex)
    add_test(
        NAME ${test_name}
        COMMAND ${CMAKE_COMMAND}
            -DEXECUTE_BINARY=$<TARGET_FILE:hyrun>
            -DINPUT_TARGET=${source_file}
            "-DEXPECTED_OUTPUT_REGEX=${expected_regex}"
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/ExpectFailure.cmake
    )
endfunction()

function(add_hyc_negative_test test_name source_file expected_regex)
    add_test(
        NAME ${test_name}
        COMMAND ${CMAKE_COMMAND}
            -DEXECUTE_BINARY=$<TARGET_FILE:hyc>
            -DINPUT_TARGET=${source_file}
            -DOUTPUT_ARTIFACT=${CMAKE_CURRENT_BINARY_DIR}/generated/${test_name}
            "-DEXPECTED_OUTPUT_REGEX=${expected_regex}"
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/ExpectBuildFailure.cmake
    )
endfunction()

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
    NAME hyrun_string_equality
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/string_equality.hy
)
set_tests_properties(hyrun_string_equality PROPERTIES PASS_REGULAR_EXPRESSION "true:true:false:true")

add_test(
    NAME hyrun_array_features
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/array_features.hy
)
set_tests_properties(hyrun_array_features PROPERTIES PASS_REGULAR_EXPRESSION "Ints=7.*Strings=4.*Nodes=ok.*Pairs=9.*Len=4")

add_test(
    NAME hyrun_buffer_features
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/buffer_features.hy
)
set_tests_properties(hyrun_buffer_features PROPERTIES PASS_REGULAR_EXPRESSION "Shared=77.*Copy=77.*Len=2.*Fill=9")

add_test(
    NAME hyrun_unsafe_memory
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/unsafe_memory.hy
)
set_tests_properties(hyrun_unsafe_memory PROPERTIES PASS_REGULAR_EXPRESSION "71.*8.*4")

add_test(
    NAME hyrun_unsafe_address_of
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/unsafe_address_of.hy
)
set_tests_properties(hyrun_unsafe_address_of PROPERTIES PASS_REGULAR_EXPRESSION "9.*1")

add_test(
    NAME hyrun_binary_primitives_64
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/binary_primitives_64.hy
)
set_tests_properties(hyrun_binary_primitives_64 PROPERTIES PASS_REGULAR_EXPRESSION "U=72623859790382856.*I=-72623859790382856")

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
        -DRUN_ARGS=alpha\;beta\;gamma
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
    NAME hyc_build_and_run_string_equality
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/string_equality.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/string_equality
        -DEXPECTED_TEXT=true:true:false:true
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_array_features
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/array_features.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/array_features
        "-DEXPECTED_TEXT=Ints=7.*Strings=4.*Nodes=ok.*Pairs=9.*Len=4"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_buffer_features
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/buffer_features.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/buffer_features
        "-DEXPECTED_TEXT=Shared=77.*Copy=77.*Len=2.*Fill=9"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_unsafe_memory
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/unsafe_memory.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/unsafe_memory
        "-DEXPECTED_TEXT=71.*8.*4"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_unsafe_address_of
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/unsafe_address_of.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/unsafe_address_of
        "-DEXPECTED_TEXT=9.*1"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_binary_primitives_64
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/binary_primitives_64.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/binary_primitives_64
        "-DEXPECTED_TEXT=U=72623859790382856.*I=-72623859790382856"
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

add_hyrun_negative_test(
    hyrun_missing_main_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/missing_main.hy
    "Entry point not found"
)

add_hyrun_negative_test(
    hyrun_duplicate_symbols_fail
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/duplicate_method.hy
    "Duplicate method"
)

add_hyrun_negative_test(
    hyrun_unresolved_using_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/unresolved_using.hy
    "Unresolved using directive"
)

add_hyrun_negative_test(
    hyrun_wrong_arguments_fail
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/wrong_arguments.hy
    "No overload of 'WriteLine' matches the provided arguments"
)

add_hyrun_negative_test(
    hyrun_invalid_return_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/invalid_return.hy
    "Return expression type 'string' is not assignable to 'int'"
)

add_hyrun_negative_test(
    hyrun_private_access_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/private_access.hy
    "protection level"
)

add_hyrun_negative_test(
    hyrun_private_constructor_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/private_constructor.hy
    "protection level"
)

add_hyrun_negative_test(
    hyrun_break_outside_loop_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/break_outside_loop.hy
    "inside a loop"
)

add_hyrun_negative_test(
    hyrun_continue_outside_loop_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/continue_outside_loop.hy
    "inside a loop"
)

add_hyrun_negative_test(
    hyrun_for_condition_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/for_condition.hy
    "For condition must be of type 'bool'"
)

add_hyrun_negative_test(
    hyrun_invalid_string_plus_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/invalid_string_plus.hy
    "string concatenation operands"
)

add_hyrun_negative_test(
    hyrun_file_wrong_arguments_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/file_wrong_arguments.hy
    "No overload of 'Exists' matches the provided arguments"
)

add_hyrun_negative_test(
    hyrun_array_size_type_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/array_size_type.hy
    "Array size must be of type 'int'"
)

add_hyrun_negative_test(
    hyrun_array_void_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/array_void.hy
    "Cannot create an array of void"
)

add_hyrun_negative_test(
    hyrun_array_wrong_assign_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/array_wrong_assign.hy
    "Cannot assign expression of type 'string' to target of type 'int'"
)

add_hyrun_negative_test(
    hyrun_buffer_use_after_free_runtime_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/buffer_use_after_free_runtime.hy
    "Buffer has been freed"
)

add_hyc_negative_test(
    hyc_array_size_type_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/array_size_type.hy
    "Array size must be of type 'int'"
)

add_hyc_negative_test(
    hyc_array_void_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/array_void.hy
    "Cannot create an array of void"
)

add_hyc_negative_test(
    hyc_array_wrong_assign_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/array_wrong_assign.hy
    "Cannot assign expression of type 'string' to target of type 'int'"
)

add_test(
    NAME hyc_build_and_run_buffer_use_after_free_runtime_fails
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/buffer_use_after_free_runtime.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/buffer_use_after_free_runtime
        "-DEXPECTED_OUTPUT_REGEX=Buffer has been freed"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndExpectRunFailure.cmake
)

# ---- new positive tests (interpreter) ----

add_test(
    NAME hyrun_modulo
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/modulo.hy
)
set_tests_properties(hyrun_modulo PROPERTIES PASS_REGULAR_EXPRESSION "3")

add_test(
    NAME hyrun_enum_features
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/enum_features.hy
)
set_tests_properties(hyrun_enum_features PROPERTIES PASS_REGULAR_EXPRESSION "Scan Dump")

add_test(
    NAME hyrun_constructor_overload
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/constructor_overload.hy
)
set_tests_properties(hyrun_constructor_overload PROPERTIES PASS_REGULAR_EXPRESSION "2")

add_test(
    NAME hyrun_overload_resolution
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/overload_resolution.hy
)
set_tests_properties(hyrun_overload_resolution PROPERTIES PASS_REGULAR_EXPRESSION "bool")

add_test(
    NAME hyrun_string_index
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/string_index.hy
)
set_tests_properties(hyrun_string_index PROPERTIES PASS_REGULAR_EXPRESSION "tkn")

add_test(
    NAME hyrun_inheritance_features
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/inheritance_features.hy
)
set_tests_properties(hyrun_inheritance_features PROPERTIES PASS_REGULAR_EXPRESSION "5:7:11:7:7:11:1")

add_test(
    NAME hyrun_inheritance_ctor_order
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/inheritance_ctor_order.hy
)
set_tests_properties(hyrun_inheritance_ctor_order PROPERTIES PASS_REGULAR_EXPRESSION "123")

add_test(
    NAME hyrun_base_override
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/base_override.hy
)
set_tests_properties(hyrun_base_override PROPERTIES PASS_REGULAR_EXPRESSION "6:5")

add_test(
    NAME hyrun_interface_struct
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/interface_struct.hy
)
set_tests_properties(hyrun_interface_struct PROPERTIES PASS_REGULAR_EXPRESSION "7")

add_test(
    NAME hyrun_interface_inheritance
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/interface_inheritance.hy
)
set_tests_properties(hyrun_interface_inheritance PROPERTIES PASS_REGULAR_EXPRESSION "4")

add_test(
    NAME hyrun_generic_features
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/generic_features.hy
)
set_tests_properties(hyrun_generic_features PROPERTIES PASS_REGULAR_EXPRESSION "ok")

add_test(
    NAME hyrun_mini_frontend_model
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/samples/mini_frontend_model/MiniFrontendModel.hyproj
)
set_tests_properties(
    hyrun_mini_frontend_model
    PROPERTIES PASS_REGULAR_EXPRESSION "Root=BinaryExpression[\r\n]+Span=0:5[\r\n]+Visit=1\\+2[\r\n]+Box=BinaryExpression[\r\n]+SpanView=0:5"
)

add_test(
    NAME hyrun_token_dump_sample
    COMMAND hyrun
        ${CMAKE_CURRENT_SOURCE_DIR}/samples/token_dump/TokenDump.hyproj
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/hello_world.hy
)
set_tests_properties(hyrun_token_dump_sample PROPERTIES PASS_REGULAR_EXPRESSION "Public public")

# ---- new positive tests (compiler) ----

add_test(
    NAME hyc_build_and_run_modulo
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/modulo.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/modulo
        -DEXPECTED_TEXT=3
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_enum_features
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/enum_features.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/enum_features
        -DEXPECTED_TEXT=Scan\ Dump
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_constructor_overload
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/constructor_overload.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/constructor_overload
        -DEXPECTED_TEXT=2
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_overload_resolution
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/overload_resolution.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/overload_resolution
        -DEXPECTED_TEXT=bool
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_string_index
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/string_index.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/string_index
        -DEXPECTED_TEXT=tkn
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_inheritance_features
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/inheritance_features.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/inheritance_features
        -DEXPECTED_TEXT=5:7:11:7:7:11:1
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_inheritance_ctor_order
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/inheritance_ctor_order.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/inheritance_ctor_order
        -DEXPECTED_TEXT=123
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_base_override
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/base_override.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/base_override
        -DEXPECTED_TEXT=6:5
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_interface_struct
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/interface_struct.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/interface_struct
        -DEXPECTED_TEXT=7
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_interface_inheritance
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/interface_inheritance.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/interface_inheritance
        -DEXPECTED_TEXT=4
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_generic_features
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DSOURCE_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/generic_features.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/generic_features
        -DEXPECTED_TEXT=ok
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildAndRun.cmake
)

add_test(
    NAME hyc_build_and_run_mini_frontend_model
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/mini_frontend_model/MiniFrontendModel.hyproj
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/mini_frontend_model
        -DEXPECTED_TEXT=SpanView=0:5
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildProjectAndRunWithArgs.cmake
)

add_test(
    NAME hyrun_symbol_model_project
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/tests/projects/symbol_model/SymbolModel.hyproj
)
set_tests_properties(hyrun_symbol_model_project PROPERTIES PASS_REGULAR_EXPRESSION "type:Node:3:method:3:2")

add_test(
    NAME hyc_build_and_run_token_dump_sample
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/token_dump/TokenDump.hyproj
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/token_dump
        -DRUN_ARG=${CMAKE_CURRENT_SOURCE_DIR}/tests/hello_world.hy
        -DEXPECTED_TEXT=Public\ public
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildProjectAndRunWithArgs.cmake
)

add_test(
    NAME hyc_build_and_run_symbol_model_project
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/projects/symbol_model/SymbolModel.hyproj
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/symbol_model
        -DEXPECTED_TEXT=type:Node:3:method:3:2
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildProjectAndRunWithArgs.cmake
)

# ---- new negative tests ----

add_hyrun_negative_test(
    hyrun_ambiguous_constructor_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/ambiguous_constructor.hy
    "ambiguous"
)

add_hyrun_negative_test(
    hyrun_ambiguous_overload_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/ambiguous_overload.hy
    "ambiguous"
)

add_hyrun_negative_test(
    hyrun_modulo_bad_types_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/modulo_bad_types.hy
    "Arithmetic operators require int operands"
)

add_hyrun_negative_test(
    hyrun_enum_cross_compare_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/enum_cross_compare.hy
    "Enum equality requires operands of the same enum type"
)

add_hyrun_negative_test(
    hyrun_parser_recovery_member_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/parser_recovery_member.hy
    "Expected ';' after field declaration"
)

add_hyrun_negative_test(
    hyrun_parser_recovery_statement_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/parser_recovery_statement.hy
    "Expected expression"
)

add_hyrun_negative_test(
    hyrun_string_index_type_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/string_index_type.hy
    "Indices must be of type 'int'"
)

add_hyrun_negative_test(
    hyrun_string_index_runtime_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/string_index_runtime.hy
    "String index out of range"
)

add_hyrun_negative_test(
    hyrun_override_non_virtual_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/override_non_virtual.hy
    "cannot override non-virtual"
)

add_hyrun_negative_test(
    hyrun_base_in_static_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/base_in_static.hy
    "'base' cannot be used in a static context"
)

add_hyrun_negative_test(
    hyrun_interface_missing_impl_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/interface_missing_impl.hy
    "does not implement interface member"
)

add_hyrun_negative_test(
    hyrun_var_without_initializer_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/var_without_initializer.hy
    "require an initializer"
)

add_hyrun_negative_test(
    hyrun_generic_arity_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/generic_arity.hy
    "expects 1 type argument"
)

add_hyrun_negative_test(
    hyrun_ambiguous_type_resolution_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/ambiguous_type_resolution.hy
    "Ambiguous type reference"
)

add_hyrun_negative_test(
    hyrun_inheritance_invalid_base_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_invalid_base.hy
    "can only inherit from a non-builtin class"
)

add_hyrun_negative_test(
    hyrun_inheritance_self_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_self.hy
    "cannot inherit from itself"
)

add_hyrun_negative_test(
    hyrun_inheritance_cycle_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_cycle.hy
    "Inheritance cycle detected"
)

add_hyrun_negative_test(
    hyrun_inheritance_missing_base_ctor_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_missing_base_ctor.hy
    "parameterless constructor"
)

add_hyrun_negative_test(
    hyrun_inheritance_private_access_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_private_access.hy
    "protection level"
)

add_hyrun_negative_test(
    hyrun_inheritance_field_conflict_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_field_conflict.hy
    "conflicts with inherited field"
)

add_hyrun_negative_test(
    hyrun_inheritance_method_conflict_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_method_conflict.hy
    "conflicts with inherited method"
)

add_hyc_negative_test(
    hyc_inheritance_invalid_base_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_invalid_base.hy
    "can only inherit from a non-builtin class"
)

add_hyc_negative_test(
    hyc_inheritance_self_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_self.hy
    "cannot inherit from itself"
)

add_hyc_negative_test(
    hyc_inheritance_cycle_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_cycle.hy
    "Inheritance cycle detected"
)

add_hyc_negative_test(
    hyc_inheritance_missing_base_ctor_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_missing_base_ctor.hy
    "parameterless constructor"
)

add_hyc_negative_test(
    hyc_inheritance_private_access_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_private_access.hy
    "protection level"
)

add_hyc_negative_test(
    hyc_inheritance_field_conflict_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_field_conflict.hy
    "conflicts with inherited field"
)

add_hyc_negative_test(
    hyc_inheritance_method_conflict_fails
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/negative/inheritance_method_conflict.hy
    "conflicts with inherited method"
)

# ---- Phase 3: Runtime and Managed Collections Tests ----

# Managed collections proof project (interpreter)
add_test(
    NAME hyrun_managed_collections_proof
    COMMAND hyrun ${CMAKE_CURRENT_SOURCE_DIR}/samples/managed_collections/ManagedCollections.hyproj
)
set_tests_properties(hyrun_managed_collections_proof PROPERTIES PASS_REGULAR_EXPRESSION "Count=1000.*Sum=500500.*Children=3.*NameBytes=4")

add_test(
    NAME hyrun_managed_collections_gc_stress
    COMMAND ${CMAKE_COMMAND} -E env HYLANG_GC_STRESS=1 $<TARGET_FILE:hyrun> ${CMAKE_CURRENT_SOURCE_DIR}/samples/managed_collections/ManagedCollections.hyproj
)
set_tests_properties(hyrun_managed_collections_gc_stress PROPERTIES PASS_REGULAR_EXPRESSION "Count=1000.*Sum=500500.*Children=3.*NameBytes=4")

# Managed collections proof project (compiler)
add_test(
    NAME hyc_build_and_run_managed_collections_proof
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/managed_collections/ManagedCollections.hyproj
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/managed_collections
        -DEXPECTED_TEXT=Count=1000
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildProjectAndRunWithArgs.cmake
)

add_test(
    NAME hyc_build_and_run_managed_collections_gc_stress
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hyc>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/managed_collections/ManagedCollections.hyproj
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/managed_collections_gc_stress
        -DRUN_ENV=HYLANG_GC_STRESS=1
        "-DEXPECTED_TEXT=Count=1000.*Sum=500500.*Children=3.*NameBytes=4"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildProjectAndRunWithArgs.cmake
)

# ---- Phase 4: Workflow and HexLab Tests ----

add_test(
    NAME hy_build_hexlab_workspace
    COMMAND hy build ${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.hyproj
)
set_tests_properties(hy_build_hexlab_workspace PROPERTIES PASS_REGULAR_EXPRESSION "HexLab.Core.*HexLab.Cli.*HexLab.Tests")

add_test(
    NAME hy_test_hexlab_workspace
    COMMAND hy test ${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.hyproj
)

add_test(
    NAME hy_fmt_hexlab_check
    COMMAND hy fmt --check ${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab
)

add_test(
    NAME hy_package_hexlab_cli
    COMMAND hy package pack ${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj
)
set_tests_properties(hy_package_hexlab_cli PROPERTIES PASS_REGULAR_EXPRESSION "HexLab.Cli-0.1.0.hypkg")

add_test(
    NAME hy_run_hexlab_inspect_demo
    COMMAND hy run ${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- inspect
            ${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/demo.bin
)
set_tests_properties(hy_run_hexlab_inspect_demo PROPERTIES PASS_REGULAR_EXPRESSION "format=PNG width=1 height=1")

add_test(
    NAME hy_run_hexlab_dump_demo
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_run_hexlab_dump_demo
        -DINPUT_TEXT=Hello
        "-DRUN_ARGS=dump;@INPUT@;4"
        "-DEXPECTED_OUTPUT_REGEX=0: 48 65 6C 6C.*4: 6F"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHexLabCommand.cmake
)

add_test(
    NAME hy_run_hexlab_diff_demo
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_run_hexlab_diff_demo
        -DLEFT_TEXT=abc
        -DRIGHT_TEXT=axc
        "-DRUN_ARGS=diff;@LEFT@;@RIGHT@"
        "-DEXPECTED_OUTPUT_REGEX=diff offset=1 left=62 right=78"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHexLabCommand.cmake
)

add_test(
    NAME hy_run_hexlab_search_demo
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_run_hexlab_search_demo
        -DINPUT_TEXT=abcabc
        "-DRUN_ARGS=search;@INPUT@;6263"
        "-DEXPECTED_OUTPUT_REGEX=found offset=1"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHexLabCommand.cmake
)

add_test(
    NAME hy_run_hexlab_slice_demo
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_run_hexlab_slice_demo
        -DINPUT_TEXT=abcdef
        "-DRUN_ARGS=slice;@INPUT@;1;3;@OUTPUT@"
        "-DEXPECTED_OUTPUT_REGEX=wrote=3"
        -DEXPECTED_OUTPUT_FILE_TEXT=bcd
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunHexLabCommand.cmake
)

add_test(
    NAME hy_new_test_scaffold
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_new_test_scaffold
        -DPROJECT_NAME=Phase4Scaffold
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyNewAndCheck.cmake
)

add_test(
    NAME hy_check_json_clean
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/check/clean.hy
        -DEXPECT_EMPTY_ARRAY=ON
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyCheckJson.cmake
)

add_test(
    NAME hy_check_json_lint_warnings
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/check/lint_warnings.hy
        "-DEXPECTED_MESSAGE_REGEXES=Using directive for namespace 'System\\.IO' is unused;Local variable 'unusedLocal' is never used;Parameter 'value' is never used;Local variable 'args' shadows an existing local or parameter;Statement is unreachable because previous control flow already terminates"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyCheckJson.cmake
)

add_test(
    NAME hy_check_json_buffer_use_after_free_warning
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/check/buffer_use_after_free.hy
        "-DEXPECTED_MESSAGE_REGEXES=Potential use-after-free of Buffer local 'buffer'"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyCheckJson.cmake
)

add_test(
    NAME hy_check_json_phase4_warnings
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/check/phase4_warnings.hy
        "-DEXPECTED_MESSAGE_REGEXES=Private field 'unusedField' is never used;Private method 'UnusedPrivate' is never used;Unsafe block is empty;Unsafe block does not contain unsafe operations;Statement is unreachable because previous control flow already terminates"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyCheckJson.cmake
)

add_test(
    NAME hy_build_debug_emits_hymap
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/hello_world.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/hello_world_debug
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyBuildDebug.cmake
)

add_test(
    NAME hy_build_debug_runtime_failure_maps_to_hylang
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_fail_location.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/runtime_fail_location_debug
        "-DEXPECTED_OUTPUT_REGEX=runtime_fail_location\\.hy:6:[0-9]+: Runtime error: Pointer access after free"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyBuildDebugAndExpectRunFailure.cmake
)

add_test(
    NAME hy_build_debug_array_failure_maps_to_hylang
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_fail_array.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/runtime_fail_array_debug
        "-DEXPECTED_OUTPUT_REGEX=runtime_fail_array\\.hy:4:[0-9]+: Runtime error: Array index out of range"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyBuildDebugAndExpectRunFailure.cmake
)

add_test(
    NAME hy_build_debug_string_failure_maps_to_hylang
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_fail_string.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/runtime_fail_string_debug
        "-DEXPECTED_OUTPUT_REGEX=runtime_fail_string\\.hy:4:[0-9]+: Runtime error: String index out of range"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyBuildDebugAndExpectRunFailure.cmake
)

add_test(
    NAME hy_build_debug_buffer_failure_maps_to_hylang
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_fail_buffer.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/runtime_fail_buffer_debug
        "-DEXPECTED_OUTPUT_REGEX=runtime_fail_buffer\\.hy:7:[0-9]+: Runtime error: Buffer has been freed"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyBuildDebugAndExpectRunFailure.cmake
)

add_test(
    NAME hy_build_debug_assert_failure_maps_to_hylang
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_fail_assert.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/generated/runtime_fail_assert_debug
        "-DEXPECTED_OUTPUT_REGEX=runtime_fail_assert\\.hy:5:[0-9]+: Runtime error: mapped assert"
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyBuildDebugAndExpectRunFailure.cmake
)

add_test(
    NAME hy_package_add_local_dependency
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_package_add_local_dependency
        -DDEPENDENCY_PROJECT=${CMAKE_CURRENT_SOURCE_DIR}/samples/hexlab/HexLab.Core/HexLab.Core.hyproj
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyPackageAdd.cmake
)

add_test(
    NAME hy_package_registry_sdk_demo
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DSOURCE_WORKSPACE=${CMAKE_CURRENT_SOURCE_DIR}/samples/sdk_demo
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_package_registry_sdk_demo
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyPackageRegistry.cmake
)

add_test(
    NAME hy_lsp_smoke
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DINPUT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/samples/sdk_demo/SdkDemo.Core/Report.hy
        -DTEMP_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/hy_lsp_smoke
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyLspSmoke.cmake
)

add_test(
    NAME hy_build_self_hosting_workspace
    COMMAND hy build ${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.hyproj
)
set_tests_properties(hy_build_self_hosting_workspace PROPERTIES PASS_REGULAR_EXPRESSION "Hydrogen.Compiler.Core.*Hydrogen.Compiler.Syntax.*Hydrogen.Compiler.IR.*Hydrogen.Compiler.Binding.*Hydrogen.Compiler.RuntimeModel.*Hydrogen.Compiler.CodeGen.X64.*Hydrogen.Compiler.Cli.*Hydrogen.Compiler.Tests")

add_test(
    NAME hy_test_self_hosting_workspace
    COMMAND hy test ${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.hyproj
)
set_tests_properties(hy_test_self_hosting_workspace PROPERTIES PASS_REGULAR_EXPRESSION "phase6-self-hosting-foundation-ok")

add_test(
    NAME hy_fmt_self_hosting_check
    COMMAND hy fmt --check ${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting
)

add_test(
    NAME hy_check_self_hosting_json
    COMMAND hy check ${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.hyproj --json
)

add_test(
    NAME hy_self_hosting_check_tiny_program
    COMMAND hy run ${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- check ${CMAKE_CURRENT_SOURCE_DIR}/tests/phase6/native_hello.hy
)
set_tests_properties(hy_self_hosting_check_tiny_program PROPERTIES PASS_REGULAR_EXPRESSION "WriteLineLiteral\\(\\\"Hydrogen native hello\\\"\\)")

add_test(
    NAME hy_self_hosting_compile_native_hello_elf
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj
        -DINPUT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase6/native_hello.hy
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/tmp/phase6/native_hello
        -DEXPECTED_OUTPUT=Hydrogen\ native\ hello\n
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyCompileNativeAndRun.cmake
)

add_test(
    NAME hy_self_hosting_tokens_golden
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj
        -DMODE=tokens
        -DINPUT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase5/lexer_features.hy
        -DEXPECTED_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase5/lexer_features.tokens.expected
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyRunAndCompare.cmake
)

add_test(
    NAME hy_self_hosting_parse_golden
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj
        -DMODE=parse
        -DINPUT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase5/parser_features.hy
        -DEXPECTED_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase5/parser_features.parse.expected
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyRunAndCompare.cmake
)

add_test(
    NAME hy_self_hosting_parse_recovery_golden
    COMMAND ${CMAKE_COMMAND}
        -DHY_BINARY=$<TARGET_FILE:hy>
        -DPROJECT_TARGET=${CMAKE_CURRENT_SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj
        -DMODE=parse
        -DINPUT_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase5/parser_broken.hy
        -DEXPECTED_FILE=${CMAKE_CURRENT_SOURCE_DIR}/tests/phase5/parser_broken.parse.expected
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/HyRunAndCompare.cmake
)
