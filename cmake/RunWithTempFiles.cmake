if (NOT DEFINED MODE OR NOT DEFINED EXECUTE_BINARY OR NOT DEFINED INPUT_TARGET OR NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "MODE, EXECUTE_BINARY, INPUT_TARGET, and TEMP_DIR are required")
endif()

if (NOT DEFINED INPUT_TEXT)
    set(INPUT_TEXT "")
endif()

if (NOT DEFINED EXPECTED_OUTPUT_REGEX)
    set(EXPECTED_OUTPUT_REGEX ".")
endif()

if (NOT DEFINED EXPECTED_FILE_TEXT)
    set(EXPECTED_FILE_TEXT "")
endif()

file(MAKE_DIRECTORY "${TEMP_DIR}")
set(TEMP_INPUT "${TEMP_DIR}/input.txt")
set(TEMP_OUTPUT "${TEMP_DIR}/output.txt")
file(WRITE "${TEMP_INPUT}" "${INPUT_TEXT}")

if (MODE STREQUAL "run")
    execute_process(
        COMMAND "${EXECUTE_BINARY}" "${INPUT_TARGET}" "${TEMP_INPUT}" "${TEMP_OUTPUT}"
        RESULT_VARIABLE RUN_RESULT
        OUTPUT_VARIABLE RUN_STDOUT
        ERROR_VARIABLE RUN_STDERR
    )
elseif (MODE STREQUAL "build")
    if (NOT DEFINED OUTPUT_ARTIFACT)
        message(FATAL_ERROR "OUTPUT_ARTIFACT is required when MODE=build")
    endif()

    get_filename_component(OUTPUT_DIR "${OUTPUT_ARTIFACT}" DIRECTORY)
    file(MAKE_DIRECTORY "${OUTPUT_DIR}")

    execute_process(
        COMMAND "${EXECUTE_BINARY}" build "${INPUT_TARGET}" -o "${OUTPUT_ARTIFACT}"
        RESULT_VARIABLE BUILD_RESULT
        OUTPUT_VARIABLE BUILD_STDOUT
        ERROR_VARIABLE BUILD_STDERR
    )

    if (NOT BUILD_RESULT EQUAL 0)
        message(FATAL_ERROR "build failed\n${BUILD_STDOUT}\n${BUILD_STDERR}")
    endif()

    execute_process(
        COMMAND "${OUTPUT_ARTIFACT}" "${TEMP_INPUT}" "${TEMP_OUTPUT}"
        RESULT_VARIABLE RUN_RESULT
        OUTPUT_VARIABLE RUN_STDOUT
        ERROR_VARIABLE RUN_STDERR
    )
else()
    message(FATAL_ERROR "Unsupported MODE '${MODE}'")
endif()

if (NOT RUN_RESULT EQUAL 0)
    message(FATAL_ERROR "execution failed\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT RUN_STDOUT MATCHES "${EXPECTED_OUTPUT_REGEX}")
    message(FATAL_ERROR "unexpected output\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT EXISTS "${TEMP_OUTPUT}")
    message(FATAL_ERROR "expected output file '${TEMP_OUTPUT}' to exist")
endif()

file(READ "${TEMP_OUTPUT}" WRITTEN_TEXT)
if (NOT WRITTEN_TEXT STREQUAL EXPECTED_FILE_TEXT)
    message(FATAL_ERROR "unexpected file contents\nexpected: ${EXPECTED_FILE_TEXT}\nactual: ${WRITTEN_TEXT}")
endif()
