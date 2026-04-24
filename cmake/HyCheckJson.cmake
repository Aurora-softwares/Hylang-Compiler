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

if(NOT DEFINED EXPECT_EMPTY_ARRAY)
    set(EXPECT_EMPTY_ARRAY OFF)
endif()

if(NOT DEFINED ALLOW_ERRORS)
    set(ALLOW_ERRORS OFF)
endif()

if(EXPECT_EMPTY_ARRAY)
    string(REGEX MATCH "^\\[[ \t\r\n]*\\][ \t\r\n]*$" matches_empty_array "${check_output}")
    if(NOT matches_empty_array)
        message(FATAL_ERROR "Expected empty JSON diagnostics array, got:\n${check_output}")
    endif()
endif()

if(NOT ALLOW_ERRORS AND check_output MATCHES "\"severity\"[ \t\r\n]*:[ \t\r\n]*\"error\"")
    message(FATAL_ERROR "Expected warning-only JSON diagnostics, got an error:\n${check_output}")
endif()

foreach(pattern IN LISTS EXPECTED_MESSAGE_REGEXES)
    if(NOT check_output MATCHES "${pattern}")
        message(FATAL_ERROR "Expected JSON diagnostics to match: ${pattern}\nActual:\n${check_output}")
    endif()
endforeach()

foreach(pattern IN LISTS UNEXPECTED_MESSAGE_REGEXES)
    if(check_output MATCHES "${pattern}")
        message(FATAL_ERROR "Unexpected JSON diagnostics matched: ${pattern}\nActual:\n${check_output}")
    endif()
endforeach()
