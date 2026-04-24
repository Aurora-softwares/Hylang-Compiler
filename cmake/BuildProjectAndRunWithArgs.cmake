if (NOT DEFINED HY_BINARY OR NOT DEFINED PROJECT_FILE OR NOT DEFINED OUTPUT_FILE OR NOT DEFINED EXPECTED_TEXT)
    message(FATAL_ERROR "HY_BINARY, PROJECT_FILE, OUTPUT_FILE, and EXPECTED_TEXT are required")
endif()

if (NOT DEFINED RUN_ARG)
    set(RUN_ARG "")
endif()

if (NOT DEFINED RUN_ENV)
    set(RUN_ENV)
endif()

get_filename_component(OUTPUT_DIR "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")

execute_process(
    COMMAND "${HY_BINARY}" build "${PROJECT_FILE}" -o "${OUTPUT_FILE}"
    RESULT_VARIABLE BUILD_RESULT
    OUTPUT_VARIABLE BUILD_STDOUT
    ERROR_VARIABLE BUILD_STDERR
)

if (NOT BUILD_RESULT EQUAL 0)
    message(FATAL_ERROR "hyc build project failed\n${BUILD_STDOUT}\n${BUILD_STDERR}")
endif()

if (RUN_ENV)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env ${RUN_ENV} "${OUTPUT_FILE}" ${RUN_ARG}
        RESULT_VARIABLE RUN_RESULT
        OUTPUT_VARIABLE RUN_STDOUT
        ERROR_VARIABLE RUN_STDERR
    )
else()
    execute_process(
        COMMAND "${OUTPUT_FILE}" ${RUN_ARG}
        RESULT_VARIABLE RUN_RESULT
        OUTPUT_VARIABLE RUN_STDOUT
        ERROR_VARIABLE RUN_STDERR
    )
endif()

if (NOT RUN_RESULT EQUAL 0)
    message(FATAL_ERROR "compiled project failed\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT RUN_STDOUT MATCHES "${EXPECTED_TEXT}")
    message(FATAL_ERROR "unexpected output\nexpected to match: ${EXPECTED_TEXT}\nactual: ${RUN_STDOUT}")
endif()
