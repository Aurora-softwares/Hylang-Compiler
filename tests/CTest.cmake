cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED hydrogenc_exe)
  message(FATAL_ERROR "hydrogenc_exe not set")
endif()
if(NOT DEFINED test_source)
  message(FATAL_ERROR "test_source not set")
endif()
if(NOT DEFINED test_binary_dir)
  message(FATAL_ERROR "test_binary_dir not set")
endif()

file(MAKE_DIRECTORY "${test_binary_dir}")

set(test_exe "${test_binary_dir}/Test.exe")
set(test_obj "${test_binary_dir}/Test.obj")

execute_process(
  COMMAND "${hydrogenc_exe}" "${test_source}" -o "${test_exe}" --emit-obj "${test_obj}"
  RESULT_VARIABLE hydrogenc_result
  OUTPUT_VARIABLE hydrogenc_stdout
  ERROR_VARIABLE hydrogenc_stderr
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_STRIP_TRAILING_WHITESPACE
)

if(NOT hydrogenc_result EQUAL 0)
  message(FATAL_ERROR "hydrogenc failed: ${hydrogenc_stderr}\n${hydrogenc_stdout}")
endif()

execute_process(
  COMMAND "${test_exe}"
  WORKING_DIRECTORY "${test_binary_dir}"
  RESULT_VARIABLE run_result
  OUTPUT_VARIABLE run_stdout
  ERROR_VARIABLE run_stderr
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_STRIP_TRAILING_WHITESPACE
)

if(NOT run_result EQUAL 0)
  message(FATAL_ERROR "test executable failed: ${run_stderr}")
endif()

string(REPLACE "\r\n" "\n" run_stdout "${run_stdout}")
if(NOT run_stdout STREQUAL "1\n" AND NOT run_stdout STREQUAL "1")
  message(FATAL_ERROR "unexpected output: '${run_stdout}'")
endif()
