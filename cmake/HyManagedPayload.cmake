foreach(required HY_BINARY SOURCE_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()
execute_process(COMMAND "${HY_BINARY}" build "${SOURCE_FILE}" -o "${OUTPUT_FILE}"
    RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 60)
if(NOT result STREQUAL "0")
    message(FATAL_ERROR "Payload test compilation failed: ${result}\n${stdout}\n${stderr}")
endif()
find_program(PRLIMIT_EXECUTABLE prlimit REQUIRED)
foreach(mode strings arrays files)
    # Under the old header-only allocation counter these loops accumulate hundreds
    # of MB before collection. Limit the process so regressions cannot exhaust RAM.
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env --unset=HYLANG_GC_STRESS --unset=HYLANG_GC_THRESHOLD
        "${PRLIMIT_EXECUTABLE}" --as=134217728 "${OUTPUT_FILE}" "${mode}" "${OUTPUT_FILE}.txt"
        RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 30)
    if(NOT result STREQUAL "0" OR NOT stdout STREQUAL "managed payload accounting ok\n" OR NOT stderr STREQUAL "")
        message(FATAL_ERROR "${mode}: managed payload accounting failed under 128 MiB limit: ${result}\n${stdout}\n${stderr}")
    endif()
endforeach()
file(REMOVE "${OUTPUT_FILE}.txt")
