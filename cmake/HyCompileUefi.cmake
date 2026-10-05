foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

get_filename_component(OUTPUT_DIR "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")

execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${INPUT_FILE}" --target uefi-x64 -o "${OUTPUT_FILE}"
    RESULT_VARIABLE COMPILE_RESULT
    OUTPUT_VARIABLE COMPILE_STDOUT
    ERROR_VARIABLE COMPILE_STDERR
    TIMEOUT 30
)
if(NOT COMPILE_RESULT EQUAL 0)
    message(FATAL_ERROR "self-hosted UEFI compile failed\n${COMPILE_STDOUT}\n${COMPILE_STDERR}")
endif()

file(READ "${OUTPUT_FILE}" IMAGE_MAGIC HEX LIMIT 2)
if(NOT IMAGE_MAGIC STREQUAL "4d5a")
    message(FATAL_ERROR "self-hosted UEFI output is missing its MZ header")
endif()

find_program(FILE_BINARY file REQUIRED)
execute_process(COMMAND "${FILE_BINARY}" "${OUTPUT_FILE}"
    RESULT_VARIABLE FILE_RESULT OUTPUT_VARIABLE FILE_OUTPUT)
if(NOT FILE_RESULT EQUAL 0 OR NOT FILE_OUTPUT MATCHES "PE32\\+ executable for EFI \\(application\\), x86-64")
    message(FATAL_ERROR "self-hosted UEFI output is not a PE32+ x86_64 EFI application\n${FILE_OUTPUT}")
endif()
