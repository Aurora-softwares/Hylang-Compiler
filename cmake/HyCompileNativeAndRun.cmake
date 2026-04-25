if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()
if(NOT DEFINED PROJECT_TARGET)
    message(FATAL_ERROR "PROJECT_TARGET is required")
endif()
if(NOT DEFINED INPUT_FILE)
    message(FATAL_ERROR "INPUT_FILE is required")
endif()
if(NOT DEFINED OUTPUT_FILE)
    message(FATAL_ERROR "OUTPUT_FILE is required")
endif()
if(NOT DEFINED EXPECTED_OUTPUT)
    message(FATAL_ERROR "EXPECTED_OUTPUT is required")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${output_dir}")

execute_process(
    COMMAND "${HY_BINARY}" run "${PROJECT_TARGET}" -- compile "${INPUT_FILE}" -o "${OUTPUT_FILE}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_stdout
    ERROR_VARIABLE compile_stderr
)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR "native compile failed (${compile_result})\nstdout:\n${compile_stdout}\nstderr:\n${compile_stderr}")
endif()

file(READ "${OUTPUT_FILE}" elf_magic HEX OFFSET 0 LIMIT 4)
if(NOT elf_magic STREQUAL "7f454c46")
    message(FATAL_ERROR "generated output is not an ELF file; magic=${elf_magic}")
endif()

file(CHMOD "${OUTPUT_FILE}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
execute_process(
    COMMAND "${OUTPUT_FILE}"
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE run_stdout
    ERROR_VARIABLE run_stderr
)
if(NOT run_result EQUAL 0)
    message(FATAL_ERROR "native executable failed (${run_result})\nstdout:\n${run_stdout}\nstderr:\n${run_stderr}")
endif()
if(NOT run_stdout STREQUAL EXPECTED_OUTPUT)
    message(FATAL_ERROR "native executable output mismatch\nexpected:\n${EXPECTED_OUTPUT}\nactual:\n${run_stdout}")
endif()
