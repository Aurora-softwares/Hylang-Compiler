foreach(required HY_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

if(NOT SKIP_INTERPRETER)
    execute_process(COMMAND "${HY_BINARY}" run "${INPUT_FILE}"
        RESULT_VARIABLE interpreted_status OUTPUT_VARIABLE interpreted_output
        ERROR_VARIABLE interpreted_error TIMEOUT 30)
    if(NOT "${interpreted_status}" STREQUAL "42" OR NOT interpreted_output STREQUAL "")
        message(FATAL_ERROR "SDK interpreter conditional-expression result: ${interpreted_status}\n${interpreted_output}\n${interpreted_error}")
    endif()
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${output_dir}")
file(REMOVE "${OUTPUT_FILE}")
execute_process(COMMAND "${HY_BINARY}" build "${INPUT_FILE}" -o "${OUTPUT_FILE}"
    RESULT_VARIABLE build_status OUTPUT_VARIABLE build_output
    ERROR_VARIABLE build_error TIMEOUT 60)
if(NOT "${build_status}" STREQUAL "0" OR NOT EXISTS "${OUTPUT_FILE}")
    message(FATAL_ERROR "SDK generated-C conditional-expression build failed: ${build_status}\n${build_output}\n${build_error}")
endif()
execute_process(COMMAND "${OUTPUT_FILE}"
    RESULT_VARIABLE compiled_status OUTPUT_VARIABLE compiled_output
    ERROR_VARIABLE compiled_error TIMEOUT 10)
if(NOT "${compiled_status}" STREQUAL "42" OR NOT compiled_output STREQUAL "")
    message(FATAL_ERROR "SDK generated-C conditional-expression result: ${compiled_status}\n${compiled_output}\n${compiled_error}")
endif()
