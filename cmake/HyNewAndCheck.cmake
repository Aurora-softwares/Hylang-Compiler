if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()

if(NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "TEMP_DIR is required")
endif()

if(NOT DEFINED PROJECT_NAME)
    message(FATAL_ERROR "PROJECT_NAME is required")
endif()

file(REMOVE_RECURSE "${TEMP_DIR}")
file(MAKE_DIRECTORY "${TEMP_DIR}")

execute_process(
    COMMAND "${HY_BINARY}" new test "${PROJECT_NAME}"
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE new_result
    OUTPUT_VARIABLE new_output
    ERROR_VARIABLE new_error
)

if(NOT new_result EQUAL 0)
    message(FATAL_ERROR "hy new failed:\n${new_output}\n${new_error}")
endif()

set(PROJECT_DIR "${TEMP_DIR}/${PROJECT_NAME}")
set(PROJECT_FILE "${PROJECT_DIR}/${PROJECT_NAME}.hyproj")

if(NOT EXISTS "${PROJECT_FILE}")
    message(FATAL_ERROR "Expected scaffolded manifest at ${PROJECT_FILE}")
endif()

execute_process(
    COMMAND "${HY_BINARY}" check "${PROJECT_FILE}"
    RESULT_VARIABLE check_result
    OUTPUT_VARIABLE check_output
    ERROR_VARIABLE check_error
)

if(NOT check_result EQUAL 0)
    message(FATAL_ERROR "hy check failed for scaffolded project:\n${check_output}\n${check_error}")
endif()
