if (NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()
if (NOT DEFINED PROJECT_TARGET)
    message(FATAL_ERROR "PROJECT_TARGET is required")
endif()
if (NOT DEFINED MODE)
    message(FATAL_ERROR "MODE is required")
endif()
if (NOT DEFINED INPUT_FILE)
    message(FATAL_ERROR "INPUT_FILE is required")
endif()
if (NOT DEFINED EXPECTED_FILE)
    message(FATAL_ERROR "EXPECTED_FILE is required")
endif()

execute_process(
    COMMAND ${HY_BINARY} run ${PROJECT_TARGET} -- ${MODE} ${INPUT_FILE}
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE actual_output
    ERROR_VARIABLE run_error
)

if (NOT run_result EQUAL 0)
    message(FATAL_ERROR "command failed with ${run_result}\n${run_error}\n${actual_output}")
endif()

file(READ ${EXPECTED_FILE} expected_output)

if (NOT actual_output STREQUAL expected_output)
    message(FATAL_ERROR "output did not match ${EXPECTED_FILE}\nactual:\n${actual_output}\nexpected:\n${expected_output}")
endif()
