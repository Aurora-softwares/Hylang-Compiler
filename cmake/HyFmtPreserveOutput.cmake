get_filename_component(output_directory "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${output_directory}")
configure_file("${INPUT_FILE}" "${OUTPUT_FILE}" COPYONLY)

execute_process(
    COMMAND "${HY_BINARY}" fmt "${OUTPUT_FILE}"
    RESULT_VARIABLE format_result
    OUTPUT_VARIABLE format_stdout
    ERROR_VARIABLE format_stderr
)
if(NOT format_result EQUAL 0)
    message(FATAL_ERROR "hy fmt failed: ${format_stdout}${format_stderr}")
endif()

file(READ "${OUTPUT_FILE}" formatted)
if(NOT formatted MATCHES "output = \"hydrogen.exe\"")
    message(FATAL_ERROR "hy fmt removed the Windows output name")
endif()

execute_process(
    COMMAND "${HY_BINARY}" fmt --check "${OUTPUT_FILE}"
    RESULT_VARIABLE check_result
    OUTPUT_VARIABLE check_stdout
    ERROR_VARIABLE check_stderr
)
if(NOT check_result EQUAL 0)
    message(FATAL_ERROR "hy fmt --check failed after formatting: ${check_stdout}${check_stderr}")
endif()
