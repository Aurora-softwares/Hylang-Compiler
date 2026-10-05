if (NOT DEFINED HY_BINARY OR NOT DEFINED SOURCE_FILE OR NOT DEFINED OUTPUT_FILE)
    message(FATAL_ERROR "HY_BINARY, SOURCE_FILE, and OUTPUT_FILE are required")
endif()

if (NOT DEFINED EXPECTED_TEXT)
    set(EXPECTED_TEXT "Hello, World!")
endif()

if (NOT DEFINED RUN_ARGS)
    set(RUN_ARGS)
endif()

if (NOT DEFINED RUN_ENV)
    set(RUN_ENV)
endif()

file(MAKE_DIRECTORY "$ENV{PWD}")
get_filename_component(OUTPUT_DIR "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")

execute_process(
    COMMAND "${HY_BINARY}" build "${SOURCE_FILE}" -o "${OUTPUT_FILE}"
    RESULT_VARIABLE BUILD_RESULT
    OUTPUT_VARIABLE BUILD_STDOUT
    ERROR_VARIABLE BUILD_STDERR
)

if (NOT BUILD_RESULT EQUAL 0)
    message(FATAL_ERROR "hyc build failed\n${BUILD_STDOUT}\n${BUILD_STDERR}")
endif()

if (RUN_ENV)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env ${RUN_ENV} "${OUTPUT_FILE}" ${RUN_ARGS}
        RESULT_VARIABLE RUN_RESULT
        OUTPUT_VARIABLE RUN_STDOUT
        ERROR_VARIABLE RUN_STDERR
    )
else()
    execute_process(
        COMMAND "${OUTPUT_FILE}" ${RUN_ARGS}
        RESULT_VARIABLE RUN_RESULT
        OUTPUT_VARIABLE RUN_STDOUT
        ERROR_VARIABLE RUN_STDERR
    )
endif()

if (NOT RUN_RESULT EQUAL 0)
    message(FATAL_ERROR "compiled executable failed\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT RUN_STDOUT MATCHES "${EXPECTED_TEXT}")
    message(FATAL_ERROR "unexpected compiled output\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()
