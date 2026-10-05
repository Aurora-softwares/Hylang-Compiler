if (NOT DEFINED HY_BINARY OR NOT DEFINED SOURCE_FILE OR NOT DEFINED OUTPUT_FILE)
    message(FATAL_ERROR "HY_BINARY, SOURCE_FILE, and OUTPUT_FILE are required")
endif()

get_filename_component(OUTPUT_DIR "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")

execute_process(
    COMMAND "${HY_BINARY}" build "${SOURCE_FILE}" --target uefi-x64 -o "${OUTPUT_FILE}"
    RESULT_VARIABLE BUILD_RESULT
    OUTPUT_VARIABLE BUILD_STDOUT
    ERROR_VARIABLE BUILD_STDERR
)

if (NOT BUILD_RESULT EQUAL 0)
    message(FATAL_ERROR "UEFI build failed\n${BUILD_STDOUT}\n${BUILD_STDERR}")
endif()

file(READ "${OUTPUT_FILE}" IMAGE_HEX HEX LIMIT 2)
if (NOT IMAGE_HEX STREQUAL "4d5a")
    message(FATAL_ERROR "UEFI image is missing its MZ header")
endif()

find_program(FILE_BINARY file REQUIRED)
execute_process(
    COMMAND "${FILE_BINARY}" "${OUTPUT_FILE}"
    RESULT_VARIABLE FILE_RESULT
    OUTPUT_VARIABLE FILE_OUTPUT
)

if (NOT FILE_RESULT EQUAL 0 OR NOT FILE_OUTPUT MATCHES "PE32\\+ executable for EFI \\(application\\), x86-64")
    message(FATAL_ERROR "output is not a PE32+ x86_64 EFI application\n${FILE_OUTPUT}")
endif()
