foreach(required HY_BINARY SOURCE_DIR OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")
foreach(case IN ITEMS foreach_iteration foreach_list)
    set(input "${SOURCE_DIR}/tests/phase6/${case}.hy")
    set(output "${OUTPUT_DIR}/${case}")
    execute_process(COMMAND "${HY_BINARY}" run "${input}"
        RESULT_VARIABLE interpreted_status OUTPUT_VARIABLE interpreted_output ERROR_VARIABLE interpreted_error TIMEOUT 30)
    if(NOT "${interpreted_status}" STREQUAL "42" OR NOT interpreted_output STREQUAL "")
        message(FATAL_ERROR "SDK interpreter ${case}: ${interpreted_status}\n${interpreted_output}\n${interpreted_error}")
    endif()

    file(REMOVE "${output}")
    execute_process(COMMAND "${HY_BINARY}" build "${input}" -o "${output}"
        RESULT_VARIABLE build_status OUTPUT_VARIABLE build_output ERROR_VARIABLE build_error TIMEOUT 60)
    if(NOT "${build_status}" STREQUAL "0" OR NOT EXISTS "${output}")
        message(FATAL_ERROR "SDK generated-C ${case} build: ${build_status}\n${build_output}\n${build_error}")
    endif()
    execute_process(COMMAND "${output}"
        RESULT_VARIABLE compiled_status OUTPUT_VARIABLE compiled_output ERROR_VARIABLE compiled_error TIMEOUT 10)
    if(NOT "${compiled_status}" STREQUAL "42" OR NOT compiled_output STREQUAL "")
        message(FATAL_ERROR "SDK generated-C ${case}: ${compiled_status}\n${compiled_output}\n${compiled_error}")
    endif()
endforeach()
