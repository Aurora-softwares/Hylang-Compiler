foreach(required NATIVE_BINARY SOURCE_DIR TEMP_DIR WINE_BINARY)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()
file(MAKE_DIRECTORY "${TEMP_DIR}")
set(project "${SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Windows.hyproj")
set(stage1 "${TEMP_DIR}/hydrogen-windows-stage1.exe")
set(stage2 "${TEMP_DIR}/hydrogen-windows-stage2.exe")
execute_process(COMMAND "${NATIVE_BINARY}" build "${project}" -o "${stage1}" --hide-progress
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 180)
if(NOT status STREQUAL "0" OR NOT errors STREQUAL "")
    message(FATAL_ERROR "Windows compiler bootstrap stage 1 failed: ${status}\n${output}\n${errors}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "WINEDEBUG=-all"
    "${WINE_BINARY}" "${stage1}" build "${project}" -o "${stage2}" --hide-progress
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 240)
if(NOT status STREQUAL "0")
    message(FATAL_ERROR "Windows compiler bootstrap stage 2 failed: ${status}\n${output}\n${errors}")
endif()
file(SHA256 "${stage1}" first_hash)
file(SHA256 "${stage2}" second_hash)
if(NOT first_hash STREQUAL second_hash)
    message(FATAL_ERROR "Windows compiler bootstrap images differ: ${first_hash} != ${second_hash}")
endif()
set(hello "${TEMP_DIR}/hello.exe")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "WINEDEBUG=-all"
    "${WINE_BINARY}" "${stage2}" compile
    "${SOURCE_DIR}/tests/phase6/native_hello.hy" --target windows-x64 -o "${hello}"
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 90)
if(NOT status STREQUAL "0")
    message(FATAL_ERROR "Windows stage 2 could not compile hello: ${status}\n${output}\n${errors}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "WINEDEBUG=-all"
    "${WINE_BINARY}" "${hello}"
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 90)
if(NOT status STREQUAL "0" OR NOT output MATCHES "Hydrogen native hello")
    message(FATAL_ERROR "Windows stage 2 output failed: ${status}\n${output}\n${errors}")
endif()
message(STATUS "Windows x64 self-hosted bootstrap and output passed")
