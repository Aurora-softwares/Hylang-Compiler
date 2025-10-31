if(NOT DEFINED hydrogenc)
    message(FATAL_ERROR "hydrogenc compiler path not provided")
endif()

set(source "${source_dir}/tests/Test.hy")
get_filename_component(test_dir "${source_dir}/tests" ABSOLUTE)
set(exe "${test_dir}/Test.exe")

execute_process(
    COMMAND "${hydrogenc}" "${source}" -o "${exe}"
    WORKING_DIRECTORY "${source_dir}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_output
    ERROR_VARIABLE compile_error
)

if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR "Compilation failed:\n${compile_output}\n${compile_error}")
endif()

execute_process(
    COMMAND "${exe}"
    WORKING_DIRECTORY "${test_dir}"
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE run_output
    ERROR_VARIABLE run_error
)

if(NOT run_result EQUAL 0)
    message(FATAL_ERROR "Program exited with code ${run_result}:\n${run_error}")
endif()

string(REPLACE "\r\n" "\n" run_output "${run_output}")
string(STRIP "${run_output}" run_output_stripped)
if(NOT run_output_stripped STREQUAL "1")
    message(FATAL_ERROR "Unexpected program output: '${run_output}'")
endif()
