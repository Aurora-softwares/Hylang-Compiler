foreach(required HY_BINARY NATIVE_BINARY SOURCE_DIR OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")
foreach(case IN ITEMS foreach_non_collection foreach_type_mismatch)
    set(input "${SOURCE_DIR}/tests/negative/${case}.hy")
    if(case STREQUAL "foreach_non_collection")
        set(sdk_reason "foreach requires an array, string, or List<T> collection")
        set(native_reason "foreach requires an array or string collection")
    else()
        set(sdk_reason "Cannot assign expression of type 'string' to variable of type 'int'")
        set(native_reason "local initializer type mismatch")
    endif()
    execute_process(COMMAND "${HY_BINARY}" check "${input}"
        RESULT_VARIABLE sdk_status OUTPUT_VARIABLE sdk_output ERROR_VARIABLE sdk_error)
    if(sdk_status STREQUAL "0" OR NOT "${sdk_output}${sdk_error}" MATCHES "${sdk_reason}")
        message(FATAL_ERROR "SDK checker accepted ${case}: ${sdk_status}\n${sdk_output}${sdk_error}")
    endif()
    execute_process(COMMAND "${NATIVE_BINARY}" check "${input}"
        RESULT_VARIABLE native_status OUTPUT_VARIABLE native_output ERROR_VARIABLE native_error)
    if(native_status STREQUAL "0" OR NOT "${native_output}${native_error}" MATCHES "${native_reason}")
        message(FATAL_ERROR "Native checker accepted ${case}: ${native_status}\n${native_output}${native_error}")
    endif()

    set(output "${OUTPUT_DIR}/${case}.out")
    file(WRITE "${output}" "existing artifact\n")
    execute_process(COMMAND "${HY_BINARY}" build "${input}" -o "${output}"
        RESULT_VARIABLE sdk_build_status OUTPUT_VARIABLE sdk_build_output ERROR_VARIABLE sdk_build_error)
    file(READ "${output}" preserved)
    if(sdk_build_status STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
        message(FATAL_ERROR "SDK build replaced ${case} output: ${sdk_build_status}\n${sdk_build_output}${sdk_build_error}")
    endif()
    execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" -o "${output}"
        RESULT_VARIABLE native_build_status OUTPUT_VARIABLE native_build_output ERROR_VARIABLE native_build_error)
    file(READ "${output}" preserved)
    if(native_build_status STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
        message(FATAL_ERROR "Native build replaced ${case} output: ${native_build_status}\n${native_build_output}${native_build_error}")
    endif()
endforeach()

# Generic List<T> is supported by the SDK but outside the native target's
# current type system. A failed native compile must leave an earlier artifact.
set(input "${SOURCE_DIR}/tests/phase6/foreach_list.hy")
set(output "${OUTPUT_DIR}/foreach_list.out")
file(WRITE "${output}" "existing artifact\n")
execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" -o "${output}"
    RESULT_VARIABLE native_status OUTPUT_VARIABLE native_output ERROR_VARIABLE native_error)
file(READ "${output}" preserved)
if(native_status STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
    message(FATAL_ERROR "Native compiler accepted unsupported List<T> program: ${native_status}\n${native_output}${native_error}")
endif()
