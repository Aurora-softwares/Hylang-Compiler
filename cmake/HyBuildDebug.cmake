if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()

if(NOT DEFINED INPUT_TARGET)
    message(FATAL_ERROR "INPUT_TARGET is required")
endif()

if(NOT DEFINED OUTPUT_FILE)
    message(FATAL_ERROR "OUTPUT_FILE is required")
endif()

get_filename_component(OUTPUT_DIR "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")

execute_process(
    COMMAND "${HY_BINARY}" build "${INPUT_TARGET}" -o "${OUTPUT_FILE}" --debug
    RESULT_VARIABLE build_result
    OUTPUT_VARIABLE build_output
    ERROR_VARIABLE build_error
)

if(NOT build_result EQUAL 0)
    message(FATAL_ERROR "hy build --debug failed:\n${build_output}\n${build_error}")
endif()

if(NOT EXISTS "${OUTPUT_FILE}")
    message(FATAL_ERROR "Expected output artifact at ${OUTPUT_FILE}")
endif()

get_filename_component(INPUT_STEM "${INPUT_TARGET}" NAME_WE)
set(SOURCE_MAP "${OUTPUT_DIR}/${INPUT_STEM}.hymap.json")
if(NOT EXISTS "${SOURCE_MAP}")
    message(FATAL_ERROR "Expected source map at ${SOURCE_MAP}")
endif()
