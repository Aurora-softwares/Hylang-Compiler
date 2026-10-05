if (NOT DEFINED HY_BINARY OR NOT DEFINED PROJECT_FILE OR NOT DEFINED TEMP_DIR OR NOT DEFINED RUN_ARGS OR NOT DEFINED EXPECTED_OUTPUT_REGEX)
    message(FATAL_ERROR "HY_BINARY, PROJECT_FILE, TEMP_DIR, RUN_ARGS, and EXPECTED_OUTPUT_REGEX are required")
endif()

file(MAKE_DIRECTORY "${TEMP_DIR}")

set(TEMP_INPUT "${TEMP_DIR}/input.bin")
set(TEMP_LEFT "${TEMP_DIR}/left.bin")
set(TEMP_RIGHT "${TEMP_DIR}/right.bin")
set(TEMP_OUTPUT "${TEMP_DIR}/output.bin")

if (DEFINED INPUT_TEXT)
    file(WRITE "${TEMP_INPUT}" "${INPUT_TEXT}")
endif()

if (DEFINED LEFT_TEXT)
    file(WRITE "${TEMP_LEFT}" "${LEFT_TEXT}")
endif()

if (DEFINED RIGHT_TEXT)
    file(WRITE "${TEMP_RIGHT}" "${RIGHT_TEXT}")
endif()

set(RESOLVED_ARGS)
foreach(argument IN LISTS RUN_ARGS)
    if (argument STREQUAL "@INPUT@")
        list(APPEND RESOLVED_ARGS "${TEMP_INPUT}")
    elseif (argument STREQUAL "@LEFT@")
        list(APPEND RESOLVED_ARGS "${TEMP_LEFT}")
    elseif (argument STREQUAL "@RIGHT@")
        list(APPEND RESOLVED_ARGS "${TEMP_RIGHT}")
    elseif (argument STREQUAL "@OUTPUT@")
        list(APPEND RESOLVED_ARGS "${TEMP_OUTPUT}")
    else()
        list(APPEND RESOLVED_ARGS "${argument}")
    endif()
endforeach()

execute_process(
    COMMAND "${HY_BINARY}" run "${PROJECT_FILE}" -- ${RESOLVED_ARGS}
    RESULT_VARIABLE RUN_RESULT
    OUTPUT_VARIABLE RUN_STDOUT
    ERROR_VARIABLE RUN_STDERR
)

if (NOT RUN_RESULT EQUAL 0)
    message(FATAL_ERROR "hexlab command failed\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT RUN_STDOUT MATCHES "${EXPECTED_OUTPUT_REGEX}")
    message(FATAL_ERROR "unexpected hexlab output\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (DEFINED EXPECTED_OUTPUT_FILE_TEXT)
    if (NOT EXISTS "${TEMP_OUTPUT}")
        message(FATAL_ERROR "expected output file '${TEMP_OUTPUT}' to exist")
    endif()
    file(READ "${TEMP_OUTPUT}" WRITTEN_TEXT)
    if (NOT WRITTEN_TEXT STREQUAL EXPECTED_OUTPUT_FILE_TEXT)
        message(FATAL_ERROR "unexpected output file contents\nexpected: ${EXPECTED_OUTPUT_FILE_TEXT}\nactual: ${WRITTEN_TEXT}")
    endif()
endif()
