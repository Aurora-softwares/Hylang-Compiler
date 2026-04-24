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
