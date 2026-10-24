foreach(required HY_BINARY NATIVE_BINARY SOURCE_DIR OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")
foreach(case IN ITEMS conditional_nonbool conditional_incompatible)
    set(input "${SOURCE_DIR}/tests/negative/${case}.hy")
    if(case STREQUAL "conditional_nonbool")
        set(reason "conditional expression requires a bool condition")
    else()
        set(reason "conditional branches have incompatible types")
    endif()
    execute_process(COMMAND "${HY_BINARY}" check "${input}"
        RESULT_VARIABLE sdk_result OUTPUT_VARIABLE sdk_stdout ERROR_VARIABLE sdk_stderr)
    string(TOLOWER "${sdk_stdout}${sdk_stderr}" sdk_output)
    if(sdk_result STREQUAL "0" OR NOT sdk_output MATCHES "${reason}")
        message(FATAL_ERROR "SDK accepted ${case}: ${sdk_result}\n${sdk_stdout}${sdk_stderr}")
    endif()

    execute_process(COMMAND "${NATIVE_BINARY}" check "${input}"
        RESULT_VARIABLE native_result OUTPUT_VARIABLE native_stdout ERROR_VARIABLE native_stderr)
    if(native_result STREQUAL "0" OR NOT "${native_stdout}${native_stderr}" MATCHES "${reason}")
        message(FATAL_ERROR "Native checker accepted ${case}: ${native_result}\n${native_stdout}${native_stderr}")
    endif()

    set(output "${OUTPUT_DIR}/${case}.out")
    file(WRITE "${output}" "existing artifact\n")
    execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" -o "${output}"
        RESULT_VARIABLE compile_result OUTPUT_VARIABLE compile_stdout ERROR_VARIABLE compile_stderr)
    file(READ "${output}" preserved_output)
    if(compile_result STREQUAL "0" OR NOT "${compile_stdout}${compile_stderr}" MATCHES "${reason}" OR
       NOT preserved_output STREQUAL "existing artifact\n")
        message(FATAL_ERROR "Native compiler failed to preserve ${case} output: ${compile_result}\n${compile_stdout}${compile_stderr}")
    endif()
endforeach()
