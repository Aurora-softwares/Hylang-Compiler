if(NOT DEFINED HY_BINARY OR NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "HY_BINARY and TEMP_DIR are required")
endif()

file(REMOVE_RECURSE "${TEMP_DIR}")
file(MAKE_DIRECTORY "${TEMP_DIR}")
set(_source "${TEMP_DIR}/io.hy")
set(_wrapper "${TEMP_DIR}/short_io.c")
set(_input "${TEMP_DIR}/input.bin")
set(_output "${TEMP_DIR}/output.bin")
set(_executable "${TEMP_DIR}/io")

file(WRITE "${_source}" [[using System.IO;
public class Program {
    public static int Main(string[] args) {
        byte[] data = File.ReadAllBytes(args[0]);
        File.WriteAllBytes(args[1], data);
        return 0;
    }
}
]])

# GNU ld --wrap injects deterministic short I/O into the generated runtime.
# Returning zero without setting the FILE error flag also catches ignored
# fwrite results that fclose alone would not report.
file(WRITE "${_wrapper}" [[#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
size_t __real_fread(void*, size_t, size_t, FILE*);
size_t __real_fwrite(const void*, size_t, size_t, FILE*);
size_t __wrap_fread(void* p, size_t s, size_t n, FILE* f) {
    const char* truncate_path = getenv("HY_TRUNCATE_READ");
    if (truncate_path) truncate(truncate_path, 0);
    if (getenv("HY_FAIL_READ")) return 0;
    return __real_fread(p, s, n, f);
}
size_t __wrap_fwrite(const void* p, size_t s, size_t n, FILE* f) {
    if (getenv("HY_FAIL_WRITE") && f != stdout && f != stderr) return 0;
    return __real_fwrite(p, s, n, f);
}
]])

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
            "CC=cc \"${_wrapper}\" -Wl,--wrap=fread -Wl,--wrap=fwrite"
            "${HY_BINARY}" build "${_source}" -o "${_executable}"
            --hide-progress --hide-spinner --hide-log
    WORKING_DIRECTORY "${TEMP_DIR}"
    RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr
)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "SDK file I/O fixture build failed: ${_result}\n${_stdout}\n${_stderr}")
endif()

string(REPEAT "0123456789abcdef" 320 _contents)
file(WRITE "${_input}" "${_contents}")
execute_process(COMMAND "${_executable}" "${_input}" "${_output}"
                RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "Normal byte file roundtrip failed: ${_stderr}")
endif()
file(SHA256 "${_input}" _input_hash)
file(SHA256 "${_output}" _output_hash)
if(NOT _input_hash STREQUAL _output_hash)
    message(FATAL_ERROR "Byte file roundtrip changed the contents")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E env "HY_TRUNCATE_READ=${_input}"
                        "${_executable}" "${_input}" "${_output}"
                RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
if(_result EQUAL 0 OR NOT _stderr MATCHES "File truncated during read")
    message(FATAL_ERROR "Truncation during read was not reported: ${_result}\n${_stderr}")
endif()
file(WRITE "${_input}" "${_contents}")

execute_process(COMMAND "${CMAKE_COMMAND}" -E env HY_FAIL_READ=1
                        "${_executable}" "${_input}" "${_output}"
                RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
if(_result EQUAL 0 OR NOT _stderr MATCHES "File read failed")
    message(FATAL_ERROR "Short read was not reported: ${_result}\n${_stderr}")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E env HY_FAIL_WRITE=1
                        "${_executable}" "${_input}" "${_output}"
                RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
if(_result EQUAL 0 OR NOT _stderr MATCHES "File write failed")
    message(FATAL_ERROR "Short write was not reported: ${_result}\n${_stderr}")
endif()

# Text reads back the compiler's source and manifest loader. Check the same
# 16 MiB budget and files whose advertised length differs from their contents.
set(_text_source "${TEMP_DIR}/text.hy")
set(_text_executable "${TEMP_DIR}/text")
file(WRITE "${_text_source}" [[using System.IO;
public class Program {
    public static int Main(string[] args) {
        string text = File.ReadAllText(args[0]);
        if (text.Length != 5) { return 7; }
        return 0;
    }
}
]])
execute_process(COMMAND "${HY_BINARY}" build "${_text_source}" -o "${_text_executable}"
                RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "SDK text fixture build failed: ${_result}\n${_stdout}\n${_stderr}")
endif()
file(WRITE "${_input}" "hello")
execute_process(COMMAND "${_text_executable}" "${_input}"
                RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "Normal text read failed: ${_result}\n${_stderr}")
endif()
string(REPEAT "x" 16777217 _oversized_text)
file(WRITE "${_input}" "${_oversized_text}")
unset(_oversized_text)
execute_process(COMMAND "${_text_executable}" "${_input}"
                RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
if(_result EQUAL 0 OR NOT _stderr MATCHES "File text read exceeds 16 MiB")
    message(FATAL_ERROR "Oversized text was not rejected: ${_result}\n${_stderr}")
endif()
foreach(_extension hy hyproj)
    set(_compiler_input "${TEMP_DIR}/oversized.${_extension}")
    file(COPY_FILE "${_input}" "${_compiler_input}")
    execute_process(COMMAND "${HY_BINARY}" check "${_compiler_input}"
                    RESULT_VARIABLE _result OUTPUT_VARIABLE _stdout ERROR_VARIABLE _stderr)
    if(_result EQUAL 0 OR NOT "${_stdout}${_stderr}" MATCHES "exceeds 16 MiB")
        message(FATAL_ERROR "Oversized ${_extension} compiler input was not rejected: ${_result}\n${_stdout}\n${_stderr}")
    endif()
endforeach()
foreach(_changing_input /sys/devices/system/cpu/online /proc/self/cmdline)
    execute_process(COMMAND "${_text_executable}" "${_changing_input}"
                    RESULT_VARIABLE _result ERROR_VARIABLE _stderr)
    if(_result EQUAL 0 OR NOT _stderr MATCHES "File (read failed|changed during read)")
        message(FATAL_ERROR "Inconsistent text ${_changing_input} was not rejected: ${_result}\n${_stderr}")
    endif()
endforeach()
