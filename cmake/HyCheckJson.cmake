if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()

if(NOT DEFINED INPUT_TARGET)
    message(FATAL_ERROR "INPUT_TARGET is required")
endif()

execute_process(
    COMMAND "${HY_BINARY}" check "${INPUT_TARGET}" --json
    RESULT_VARIABLE check_result
    OUTPUT_VARIABLE check_output
    ERROR_VARIABLE check_error
)

if(NOT check_result EQUAL 0)
    message(FATAL_ERROR "hy check --json failed:\n${check_output}\n${check_error}")
endif()

string(REGEX MATCH "^\\[[ \t\r\n]*\\][ \t\r\n]*$" matches_empty_array "${check_output}")
if(NOT matches_empty_array)
    message(FATAL_ERROR "Expected empty JSON diagnostics array, got:\n${check_output}")
endif()
