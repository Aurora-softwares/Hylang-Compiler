foreach(required HY_BINARY NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

execute_process(COMMAND "${HY_BINARY}" check "${INPUT_FILE}"
    RESULT_VARIABLE sdk_result OUTPUT_VARIABLE sdk_stdout ERROR_VARIABLE sdk_stderr)
if(sdk_result STREQUAL "0" OR NOT "${sdk_stdout}${sdk_stderr}" MATCHES "Compound assignment requires integral operands")
    message(FATAL_ERROR "SDK accepted invalid compound assignment: ${sdk_result}\n${sdk_stdout}${sdk_stderr}")
endif()

execute_process(COMMAND "${NATIVE_BINARY}" check "${INPUT_FILE}"
    RESULT_VARIABLE native_result OUTPUT_VARIABLE native_stdout ERROR_VARIABLE native_stderr)
if(native_result STREQUAL "0" OR NOT "${native_stdout}${native_stderr}" MATCHES "compound assignment requires integral operands")
    message(FATAL_ERROR "Native checker accepted invalid compound assignment: ${native_result}\n${native_stdout}${native_stderr}")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${output_dir}")
file(WRITE "${OUTPUT_FILE}" "existing artifact\n")
execute_process(COMMAND "${NATIVE_BINARY}" compile "${INPUT_FILE}" -o "${OUTPUT_FILE}"
    RESULT_VARIABLE compile_result OUTPUT_VARIABLE compile_stdout ERROR_VARIABLE compile_stderr)
file(READ "${OUTPUT_FILE}" preserved_output)
if(compile_result STREQUAL "0" OR NOT "${compile_stdout}${compile_stderr}" MATCHES "compound assignment requires integral operands" OR
   NOT preserved_output STREQUAL "existing artifact\n")
    message(FATAL_ERROR "Native compiler failed to preserve output: ${compile_result}\n${compile_stdout}${compile_stderr}")
endif()
