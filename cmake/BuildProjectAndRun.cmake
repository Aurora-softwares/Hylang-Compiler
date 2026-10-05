if (NOT DEFINED HY_BINARY OR NOT DEFINED PROJECT_FILE OR NOT DEFINED OUTPUT_FILE)
    message(FATAL_ERROR "HY_BINARY, PROJECT_FILE, and OUTPUT_FILE are required")
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

execute_process(
    COMMAND "${OUTPUT_FILE}"
    RESULT_VARIABLE RUN_RESULT
    OUTPUT_VARIABLE RUN_STDOUT
    ERROR_VARIABLE RUN_STDERR
)

if (NOT RUN_RESULT EQUAL 0)
    message(FATAL_ERROR "compiled project failed\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT RUN_STDOUT MATCHES "Hello from MathUtil")
    message(FATAL_ERROR "missing library output\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

if (NOT RUN_STDOUT MATCHES "7")
    message(FATAL_ERROR "missing computed output\n${RUN_STDOUT}\n${RUN_STDERR}")
endif()

execute_process(
    COMMAND "${HY_BINARY}" build
            "${CMAKE_CURRENT_LIST_DIR}/../tests/projects/mathlib/Math.hyproj"
            --target lib
            -o "${STATIC_LIB_FILE}"
    RESULT_VARIABLE LIB_RESULT
    OUTPUT_VARIABLE LIB_STDOUT
    ERROR_VARIABLE LIB_STDERR
)

if (NOT LIB_RESULT EQUAL 0)
    message(FATAL_ERROR "hyc build lib failed\n${LIB_STDOUT}\n${LIB_STDERR}")
endif()

if (NOT EXISTS "${STATIC_LIB_FILE}" AND NOT EXISTS "${STATIC_LIB_ALT}")
    message(FATAL_ERROR "expected a static library artifact to exist")
endif()
