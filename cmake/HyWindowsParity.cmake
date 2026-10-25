foreach(required NATIVE_BINARY SOURCE_DIR TEMP_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()
file(MAKE_DIRECTORY "${TEMP_DIR}")
set(project "${SOURCE_DIR}/tests/phase6/WindowsFullRuntime.hyproj")
set(output "${TEMP_DIR}/WindowsFullRuntime.exe")
execute_process(COMMAND "${NATIVE_BINARY}" check "${project}"
    RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 60)
if(NOT result STREQUAL "0" OR NOT stdout MATCHES "check ok" OR NOT stderr STREQUAL "")
    message(FATAL_ERROR "Windows project check failed: ${result}\n${stdout}\n${stderr}")
endif()
execute_process(COMMAND "${NATIVE_BINARY}" build "${project}" -o "${output}" --hide-progress
    RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 60)
if(NOT result STREQUAL "0" OR NOT stderr STREQUAL "")
    message(FATAL_ERROR "Windows project build failed: ${result}\n${stdout}\n${stderr}")
endif()
file(READ "${output}" magic LIMIT 2 HEX)
if(NOT magic STREQUAL "4d5a")
    message(FATAL_ERROR "Windows output has no MZ header")
endif()
find_program(FILE_BINARY NAMES file REQUIRED)
execute_process(COMMAND "${FILE_BINARY}" "${output}"
    RESULT_VARIABLE result OUTPUT_VARIABLE file_description)
if(NOT result STREQUAL "0" OR NOT file_description MATCHES "PE32\\+" OR
   NOT file_description MATCHES "x86-64" OR NOT file_description MATCHES "console")
    message(FATAL_ERROR "Windows output is not a PE32+ x64 console image: ${file_description}")
endif()
find_program(OBJDUMP_BINARY NAMES objdump llvm-objdump REQUIRED)
execute_process(COMMAND "${OBJDUMP_BINARY}" -p "${output}"
    RESULT_VARIABLE result OUTPUT_VARIABLE imports)
if(NOT result STREQUAL "0" OR NOT imports MATCHES "KERNEL32.dll" OR
   NOT imports MATCHES "SHELL32.dll" OR NOT imports MATCHES "VirtualAlloc" OR
   NOT imports MATCHES "CreateFileW" OR NOT imports MATCHES "MultiByteToWideChar")
    message(FATAL_ERROR "Windows import table is incomplete")
endif()

# Target rejection must preserve a pre-existing artifact.
set(bad_output "${TEMP_DIR}/unsupported.exe")
file(WRITE "${bad_output}" "existing artifact\n")
execute_process(COMMAND "${NATIVE_BINARY}" compile
    "${SOURCE_DIR}/tests/phase6/native_unsupported_call.hy"
    --target windows-x64 -o "${bad_output}"
    RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 60)
file(READ "${bad_output}" preserved)
if(result STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
    message(FATAL_ERROR "Unsupported Windows source replaced an existing output")
endif()

if(NOT WINE_BINARY)
    message(STATUS "Windows PE validated; Wine runtime checks unavailable")
    return()
endif()

function(run_windows image expected_exit expected_output)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env "WINEDEBUG=-all"
        "${WINE_BINARY}" "${image}" ${ARGN}
        RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 90)
    if(NOT "${status}" STREQUAL "${expected_exit}" OR
       NOT output MATCHES "${expected_output}")
        message(FATAL_ERROR "Windows runtime mismatch for ${image}: exit ${status}\nstdout: ${output}\nstderr: ${errors}")
    endif()
endfunction()

run_windows("${output}" 42 "windows runtime parity ok"
    "Z:${TEMP_DIR}/windows-parity-é.txt" "two words")
string(REPLACE "/" "\\" windows_backslash_path
    "Z:${TEMP_DIR}/created/subdir/windows-é.txt")
run_windows("${output}" 42 "windows runtime parity ok"
    "${windows_backslash_path}" "two words")
set(builder_image "${TEMP_DIR}/NativeTextBuilder.exe")
execute_process(COMMAND "${NATIVE_BINARY}" build
    "${SOURCE_DIR}/samples/native_text_builder/NativeTextBuilder.Windows.hyproj"
    -o "${builder_image}" --hide-progress
    RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 60)
if(NOT result STREQUAL "0" OR NOT stderr STREQUAL "")
    message(FATAL_ERROR "Windows text builder build failed: ${result}\n${stdout}\n${stderr}")
endif()
run_windows("${builder_image}" 0 "builder utf8 ok" utf8 0)
run_windows("${builder_image}" 0 "300000" builder 100000)
foreach(name native_runtime native_runtime_files windows_console_terminal)
    set(image "${TEMP_DIR}/${name}.exe")
    execute_process(COMMAND "${NATIVE_BINARY}" compile
        "${SOURCE_DIR}/tests/phase6/${name}.hy" --target windows-x64 -o "${image}"
        RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 60)
    if(NOT status STREQUAL "0" OR NOT errors STREQUAL "")
        message(FATAL_ERROR "Windows compilation failed for ${name}: ${output}\n${errors}")
    endif()
    if(name STREQUAL "native_runtime")
        run_windows("${image}" 42 "node:11" "hello")
    elseif(name STREQUAL "native_runtime_files")
        run_windows("${image}" 42 "files and GC ok"
            "Z:${TEMP_DIR}/runtime-files.bin")
    else()
        run_windows("${image}" 42 "console pipe detected")
    endif()
endforeach()
foreach(name native_runtime_gc native_inheritance native_interfaces
             native_static_fields native_integral_widths
             native_runtime_packed_bytes native_runtime_packed_ints
             native_runtime_literals native_runtime_small_spans native_overloads
             native_condition_branches native_proven_bounds)
    set(image "${TEMP_DIR}/${name}.exe")
    execute_process(COMMAND "${NATIVE_BINARY}" compile
        "${SOURCE_DIR}/tests/phase6/${name}.hy" --target windows-x64 -o "${image}"
        RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 60)
    if(NOT status STREQUAL "0" OR NOT errors STREQUAL "")
        message(FATAL_ERROR "Windows compilation failed for ${name}: ${output}\n${errors}")
    endif()
    run_windows("${image}" 42 ".+")
endforeach()
set(bounds_negative "byte[] values = new byte[2]; int i = -1; int sum = 0; while (i < values.Length) { sum = sum + values[i]; i = i + 1; } return sum;")
set(bounds_mutated "int n = 2; int[] values = new int[n]; n = 3; int i = 0; while (i < n) { values[i] = i; i = i + 1; } return 0;")
foreach(name bounds_negative bounds_mutated)
    set(source "${TEMP_DIR}/${name}.hy")
    set(image "${TEMP_DIR}/${name}.exe")
    file(WRITE "${source}" "public class Program { public static int Main() { ${${name}} } }\n")
    execute_process(COMMAND "${NATIVE_BINARY}" compile "${source}"
        --target windows-x64 -o "${image}"
        RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 60)
    if(NOT status STREQUAL "0" OR NOT errors STREQUAL "")
        message(FATAL_ERROR "Windows bounds fixture compilation failed: ${name}: ${output}\n${errors}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env "WINEDEBUG=-all"
        "${WINE_BINARY}" "${image}"
        RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 90)
    if(NOT status STREQUAL "1" OR NOT output STREQUAL "" OR
       NOT errors MATCHES "runtime error: index out of range")
        message(FATAL_ERROR "Windows bounds failure mismatch: ${name}: ${status}\n${output}\n${errors}")
    endif()
endforeach()
message(STATUS "Windows x64 language, runtime, console, file, argv, and GC parity passed")
