foreach(required HY_BINARY NATIVE_BINARY SOURCE_DIR OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")
foreach(case IN ITEMS slice_non_collection slice_non_int_bound slice_missing_bound slice_missing_start slice_null_conditional)
    set(input "${SOURCE_DIR}/tests/negative/${case}.hy")
    foreach(compiler IN ITEMS HY_BINARY NATIVE_BINARY)
        execute_process(COMMAND "${${compiler}}" check "${input}"
            RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
        if(status STREQUAL "0" OR "${stdout}${stderr}" STREQUAL "")
            message(FATAL_ERROR "${compiler} accepted ${case}: ${status}\n${stdout}${stderr}")
        endif()
        set(output "${OUTPUT_DIR}/${case}_${compiler}.out")
        file(WRITE "${output}" "existing artifact\n")
        if(compiler STREQUAL "HY_BINARY")
            execute_process(COMMAND "${${compiler}}" build "${input}" -o "${output}"
                RESULT_VARIABLE build_status OUTPUT_VARIABLE build_stdout ERROR_VARIABLE build_stderr)
        else()
            execute_process(COMMAND "${${compiler}}" compile "${input}" -o "${output}"
                RESULT_VARIABLE build_status OUTPUT_VARIABLE build_stdout ERROR_VARIABLE build_stderr)
        endif()
        file(READ "${output}" preserved)
        if(build_status STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
            message(FATAL_ERROR "${compiler} replaced ${case} output: ${build_status}\n${build_stdout}${build_stderr}")
        endif()
    endforeach()
    set(output "${OUTPUT_DIR}/${case}_windows.exe")
    file(WRITE "${output}" "existing artifact\n")
    execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" --target windows-x64 -o "${output}"
        RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
    file(READ "${output}" preserved)
    if(status STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
        message(FATAL_ERROR "Windows native replaced ${case} output: ${status}\n${stdout}${stderr}")
    endif()
endforeach()

# The constrained UEFI backend must reject a slicing program before replacing
# an existing image, even when it cannot represent the program's entry point.
set(unsupported_output "${OUTPUT_DIR}/unsupported.efi")
file(WRITE "${unsupported_output}" "existing artifact\n")
execute_process(COMMAND "${NATIVE_BINARY}" compile
    "${SOURCE_DIR}/tests/phase6/slices.hy" --target uefi-x64 -o "${unsupported_output}"
    RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
file(READ "${unsupported_output}" preserved)
if(status STREQUAL "0" OR NOT preserved STREQUAL "existing artifact\n")
    message(FATAL_ERROR "Unsupported UEFI program replaced output: ${status}\n${stdout}${stderr}")
endif()

foreach(case IN ITEMS slice_negative_start slice_reversed_bounds slice_past_end slice_null_receiver)
    set(input "${SOURCE_DIR}/tests/negative/${case}.hy")
    execute_process(COMMAND "${HY_BINARY}" run "${input}"
        RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
    if(status STREQUAL "0" OR NOT "${stdout}${stderr}" MATCHES "Slice (bounds|receiver)")
        message(FATAL_ERROR "SDK interpreter did not reject ${case}: ${status}\n${stdout}${stderr}")
    endif()
    set(output "${OUTPUT_DIR}/${case}_sdk")
    execute_process(COMMAND "${HY_BINARY}" build "${input}" -o "${output}"
        RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
    if(NOT status STREQUAL "0")
        message(FATAL_ERROR "SDK build failed for ${case}: ${stdout}${stderr}")
    endif()
    execute_process(COMMAND "${output}"
        RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
    if(status STREQUAL "0" OR NOT "${stdout}${stderr}" MATCHES "Slice (bounds|receiver)")
        message(FATAL_ERROR "SDK generated-C did not reject ${case}: ${status}\n${stdout}${stderr}")
    endif()
    set(output "${OUTPUT_DIR}/${case}_linux")
    execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" -o "${output}"
        RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
    if(NOT status STREQUAL "0")
        message(FATAL_ERROR "Linux native compile failed for ${case}: ${stdout}${stderr}")
    endif()
    # Direct native outputs are emitted without execute permission. CTest must
    # grant it before running the binary, just like other Stage 1 tests do.
    file(CHMOD "${output}" PERMISSIONS
        OWNER_READ OWNER_WRITE OWNER_EXECUTE
        GROUP_READ GROUP_EXECUTE
        WORLD_READ WORLD_EXECUTE)
    execute_process(COMMAND "${output}"
        RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
    if(case STREQUAL "slice_null_receiver")
        set(native_reason "null reference")
    else()
        set(native_reason "index out of range")
    endif()
    if(status STREQUAL "0" OR NOT "${stdout}${stderr}" MATCHES "${native_reason}")
        message(FATAL_ERROR "Linux native did not reject ${case}: ${status}\n${stdout}${stderr}")
    endif()
    if(DEFINED WINE_BINARY AND NOT WINE_BINARY STREQUAL "")
        set(output "${OUTPUT_DIR}/${case}.exe")
        execute_process(COMMAND "${NATIVE_BINARY}" compile "${input}" --target windows-x64 -o "${output}"
            RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr)
        if(NOT status STREQUAL "0")
            message(FATAL_ERROR "Windows native compile failed for ${case}: ${stdout}${stderr}")
        endif()
        execute_process(COMMAND "${CMAKE_COMMAND}" -E env "WINEDEBUG=-all" "${WINE_BINARY}" "${output}"
            RESULT_VARIABLE status OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 30)
        if(status STREQUAL "0" OR NOT "${stdout}${stderr}" MATCHES "${native_reason}")
            message(FATAL_ERROR "Windows native did not reject ${case}: ${status}\n${stdout}${stderr}")
        endif()
    endif()
endforeach()
