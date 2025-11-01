if (NOT WIN32)
  message(STATUS "HydrogenC integration test skipped: requires Windows runtime")
  return()
endif()

set(output_exe "${CMAKE_CURRENT_BINARY_DIR}/Test.exe")
execute_process(
  COMMAND "${hydrogenc}" "${source}" -o "${output_exe}"
  RESULT_VARIABLE compile_result
  OUTPUT_VARIABLE compile_out
  ERROR_VARIABLE compile_err)

if (NOT compile_result EQUAL 0)
  message(FATAL_ERROR "hydrogenc failed: ${compile_out} ${compile_err}")
endif()

execute_process(
  COMMAND "${output_exe}"
  RESULT_VARIABLE run_result
  OUTPUT_VARIABLE program_out
  ERROR_VARIABLE program_err)

if (NOT run_result EQUAL 0)
  message(FATAL_ERROR "program failed: ${program_err}")
endif()

string(REPLACE "\r\n" "\n" program_out "${program_out}")
string(STRIP "${program_out}" program_out)
if (NOT program_out STREQUAL "1")
  message(FATAL_ERROR "unexpected stdout: '${program_out}'")
endif()
