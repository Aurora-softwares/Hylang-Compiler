foreach(required HY_BINARY NATIVE_BINARY SOURCE_DIR OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")
foreach(case IN ITEMS null_conditional_primitive null_conditional_assignment)
    set(input "${SOURCE_DIR}/tests/negative/${case}.hy")
    if(case STREQUAL "null_conditional_primitive")
        set(sdk_reason "Null-conditional access requires a reference result")
        set(native_reason "null-conditional access requires a reference result")
    else()
        set(sdk_reason "Null-conditional access is not an assignment target")
        set(native_reason "assignment target is not writable")
    endif()

    execute_process(COMMAND "${HY_BINARY}" check "${input}"
        RESULT_VARIABLE sdk_result OUTPUT_VARIABLE sdk_stdout ERROR_VARIABLE sdk_stderr)
    if(sdk_result STREQUAL "0" OR NOT "${sdk_stdout}${sdk_stderr}" MATCHES "${sdk_reason}")
        message(FATAL_ERROR "SDK checker accepted ${case}: ${sdk_result}\n${sdk_stdout}${sdk_stderr}")
    endif()

    execute_process(COMMAND "${NATIVE_BINARY}" check "${input}"
        RESULT_VARIABLE native_result OUTPUT_VARIABLE native_stdout ERROR_VARIABLE native_stderr)
    if(native_result STREQUAL "0" OR NOT "${native_stdout}${native_stderr}" MATCHES "${native_reason}")
        message(FATAL_ERROR "Native checker accepted ${case}: ${native_result}\n${native_stdout}${native_stderr}")
    endif()

    set(output "${OUTPUT_DIR}/${case}.out")
    file(WRITE "${output}" "existing artifact\n")
    execute_process(COMMAND "${HY_BINARY}" build "${input}" -o "${output}"
        RESULT_VARIABLE sdk_build_result OUTPUT_VARIABLE sdk_build_stdout ERROR_VARIABLE sdk_build_stderr)
    file(READ "${output}" preserved_output)
    if(sdk_build_result STREQUAL "0" OR NOT preserved_output STREQUAL "existing artifact\n")
        message(FATAL_ERROR "SDK build replaced ${case} output: ${sdk_build_result}\n${sdk_build_stdout}${sdk_build_stderr}")
    endif()

    execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" -o "${output}"
        RESULT_VARIABLE native_compile_result OUTPUT_VARIABLE native_compile_stdout ERROR_VARIABLE native_compile_stderr)
    file(READ "${output}" preserved_output)
    if(native_compile_result STREQUAL "0" OR NOT preserved_output STREQUAL "existing artifact\n")
        message(FATAL_ERROR "Native compiler replaced ${case} output: ${native_compile_result}\n${native_compile_stdout}${native_compile_stderr}")
    endif()
endforeach()
