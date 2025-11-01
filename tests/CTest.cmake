if(NOT DEFINED HYC_COMPILER)
    message(FATAL_ERROR "HYC_COMPILER not provided")
endif()
if(NOT DEFINED TEST_SOURCE)
    message(FATAL_ERROR "TEST_SOURCE not provided")
endif()
if(NOT DEFINED TEST_BINARY_DIR)
    message(FATAL_ERROR "TEST_BINARY_DIR not provided")
endif()

file(MAKE_DIRECTORY "${TEST_BINARY_DIR}")
set(TEST_OBJECT "${TEST_BINARY_DIR}/Test.obj")
set(TEST_EXE "${TEST_BINARY_DIR}/Test.exe")

execute_process(
    COMMAND ${HYC_COMPILER} ${TEST_SOURCE} --emit-obj ${TEST_OBJECT} -o ${TEST_EXE}
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_out
    ERROR_VARIABLE compile_err)

if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR "hydrogenc failed: ${compile_result}\n${compile_out}\n${compile_err}")
endif()

execute_process(
    COMMAND ${TEST_EXE}
    RESULT_VARIABLE run_result
    OUTPUT_VARIABLE run_out
    ERROR_VARIABLE run_err)

if(NOT run_result EQUAL 0)
    message(FATAL_ERROR "Test program failed: ${run_result}\n${run_out}\n${run_err}")
endif()

string(STRIP "${run_out}" run_out_stripped)
if(NOT run_out_stripped STREQUAL "1")
    message(FATAL_ERROR "Unexpected output: '${run_out_stripped}'")
endif()
