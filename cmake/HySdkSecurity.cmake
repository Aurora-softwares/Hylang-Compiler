if(NOT DEFINED HY_BINARY OR NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "HY_BINARY and TEMP_DIR are required")
endif()

file(REMOVE_RECURSE "${TEMP_DIR}")
file(MAKE_DIRECTORY "${TEMP_DIR}")

# These names must reach the compiler as literal arguments. The old system()
# path would execute touch and break on the embedded double quote.
set(_source "${TEMP_DIR}/safe $(touch source-marker) ' \" $.hy")
set(_output "${TEMP_DIR}/result $(touch output-marker) \" $")
file(WRITE "${_source}" "public class Program { public static int Main() { return 0; } }\n")
execute_process(
    COMMAND "${HY_BINARY}" build "${_source}" -o "${_output}"
            --hide-progress --hide-spinner --hide-log
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr
)
if(NOT _result EQUAL 0 OR NOT EXISTS "${_output}")
    message(FATAL_ERROR "SDK build failed for literal shell characters: ${_result}\n${_stdout}\n${_stderr}")
endif()
execute_process(COMMAND "${_output}" RESULT_VARIABLE _result)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "SDK output with shell characters did not run")
endif()

file(WRITE "${TEMP_DIR}/Program.hy" "public class Program { public static int Main() { return 0; } }\n")
file(WRITE "${TEMP_DIR}/Test.hyproj" [[format = 2
name = "Test $(touch test-marker)"
version = "0.1.0"
type = "test"
sources = ["Program.hy"]
]])
execute_process(
    COMMAND "${HY_BINARY}" test "${TEMP_DIR}/Test.hyproj"
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr
)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "SDK test failed for literal shell characters: ${_result}\n${_stdout}\n${_stderr}")
endif()

file(WRITE "${TEMP_DIR}/Library.hy" "public class Library { public static int Value() { return 7; } }\n")
file(WRITE "${TEMP_DIR}/Library.hyproj" [[format = 2
name = "Lib $(touch archive-marker)"
version = "0.1.0"
type = "lib"
sources = ["Library.hy"]
]])
set(_archive "${TEMP_DIR}/archive $(touch archive-output-marker) ' \" $.a")
execute_process(
    COMMAND "${HY_BINARY}" build "${TEMP_DIR}/Library.hyproj" -o "${_archive}"
            --hide-progress --hide-spinner --hide-log
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr
)
if(NOT _result EQUAL 0 OR NOT EXISTS "${_archive}")
    message(FATAL_ERROR "SDK library build failed for literal shell characters: ${_result}\n${_stdout}\n${_stderr}")
endif()

# CC is configuration data, not a shell command line.
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "CC=cc; touch cc-marker"
            "${HY_BINARY}" build "${_source}" -o "${TEMP_DIR}/bad-cc"
            --hide-progress --hide-spinner --hide-log
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr
)
if(_result EQUAL 0)
    message(FATAL_ERROR "A shell fragment in CC was accepted")
endif()

foreach(_marker source-marker output-marker test-marker archive-marker archive-output-marker cc-marker)
    if(EXISTS "${TEMP_DIR}/${_marker}")
        message(FATAL_ERROR "Shell command executed: ${_marker}")
    endif()
endforeach()
