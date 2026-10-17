
foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE WINE_BINARY EXPECTED_EXIT_CODE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

get_filename_component(OUTPUT_DIR "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")

# Ensure an old executable cannot produce a false success.
file(REMOVE "${OUTPUT_FILE}")

# Cross-compile from Linux to Windows.
execute_process(
    COMMAND "${NATIVE_BINARY}"
        compile "${INPUT_FILE}"
        --target windows-x64
        -o "${OUTPUT_FILE}"
    RESULT_VARIABLE COMPILE_RESULT
    OUTPUT_VARIABLE COMPILE_STDOUT
    ERROR_VARIABLE COMPILE_STDERR
    TIMEOUT 30
)

if(NOT "${COMPILE_RESULT}" STREQUAL "0")
    message(FATAL_ERROR
        "Windows compilation failed:\n"
        "${COMPILE_STDOUT}\n${COMPILE_STDERR}"
    )
endif()

if(NOT EXISTS "${OUTPUT_FILE}")
    message(FATAL_ERROR "Windows executable was not generated")
endif()

# Verify the DOS/PE signature.
file(READ "${OUTPUT_FILE}" IMAGE_MAGIC LIMIT 2 HEX)

if(NOT IMAGE_MAGIC STREQUAL "4d5a")
    message(FATAL_ERROR "Windows executable has no MZ header")
endif()

# Verify architecture and executable format.
find_program(FILE_BINARY NAMES file REQUIRED)

execute_process(
    COMMAND "${FILE_BINARY}" "${OUTPUT_FILE}"
    RESULT_VARIABLE FILE_RESULT
    OUTPUT_VARIABLE FILE_OUTPUT
)

if(NOT "${FILE_RESULT}" STREQUAL "0"
   OR NOT FILE_OUTPUT MATCHES "PE32\\+"
   OR NOT FILE_OUTPUT MATCHES "x86-64"
   OR NOT FILE_OUTPUT MATCHES "console")
    message(FATAL_ERROR
        "Invalid Windows PE32+ console executable:\n${FILE_OUTPUT}"
    )
endif()

# Execute through Wine.
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
        "WINEDEBUG=-all"
        "${WINE_BINARY}" "${OUTPUT_FILE}"
    RESULT_VARIABLE RUN_RESULT
    OUTPUT_VARIABLE RUN_STDOUT
    ERROR_VARIABLE RUN_STDERR
    TIMEOUT 60
)

# 42 is expected; a zero exit status is a failure.
if(NOT "${RUN_RESULT}" STREQUAL "${EXPECTED_EXIT_CODE}")
    message(FATAL_ERROR
        "Unexpected Windows exit status.\n"
        "Expected: ${EXPECTED_EXIT_CODE}\n"
        "Actual: ${RUN_RESULT}\n"
        "stdout:\n${RUN_STDOUT}\n"
        "stderr:\n${RUN_STDERR}"
    )
endif()

message(STATUS "Windows x64 cross-compilation passed")
message(STATUS "PE32+ executable verified")
message(STATUS "Wine exit code: ${RUN_RESULT}")
