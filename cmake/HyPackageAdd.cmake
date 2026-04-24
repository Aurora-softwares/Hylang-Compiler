if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()

if(NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "TEMP_DIR is required")
endif()

if(NOT DEFINED DEPENDENCY_PROJECT)
    message(FATAL_ERROR "DEPENDENCY_PROJECT is required")
endif()

file(REMOVE_RECURSE "${TEMP_DIR}")
file(MAKE_DIRECTORY "${TEMP_DIR}")

execute_process(
    COMMAND "${HY_BINARY}" new app PackageAddDemo
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE new_result
    OUTPUT_VARIABLE new_output
    ERROR_VARIABLE new_error
)

if(NOT new_result EQUAL 0)
    message(FATAL_ERROR "hy new app failed:\n${new_output}\n${new_error}")
endif()

set(PROJECT_FILE "${TEMP_DIR}/PackageAddDemo/PackageAddDemo.hyproj")

execute_process(
    COMMAND "${HY_BINARY}" package add "${PROJECT_FILE}" "${DEPENDENCY_PROJECT}"
    RESULT_VARIABLE add_result
    OUTPUT_VARIABLE add_output
    ERROR_VARIABLE add_error
)

if(NOT add_result EQUAL 0)
    message(FATAL_ERROR "hy package add failed:\n${add_output}\n${add_error}")
endif()

file(READ "${PROJECT_FILE}" manifest_text)

if(NOT manifest_text MATCHES "\\[dependencies\\]")
    message(FATAL_ERROR "Expected [dependencies] section in manifest:\n${manifest_text}")
endif()

if(NOT manifest_text MATCHES "HexLab\\.Core = \\{ path = ")
    message(FATAL_ERROR "Expected HexLab.Core dependency entry in manifest:\n${manifest_text}")
endif()
