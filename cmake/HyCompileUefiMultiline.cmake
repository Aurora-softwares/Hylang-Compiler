foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/HyCompileUefi.cmake")

file(READ "${OUTPUT_FILE}" image_hex HEX)
string(REGEX MATCHALL "0d000a00" line_breaks "${image_hex}")
list(LENGTH line_breaks line_count)
if(NOT line_count EQUAL 10)
    message(FATAL_ERROR "UEFI image should contain all ten CRLF-terminated lines, found ${line_count}")
endif()
file(SIZE "${OUTPUT_FILE}" image_size)
if(NOT image_size EQUAL 2048)
    message(FATAL_ERROR "UEFI image should allocate two 512-byte data blocks, found ${image_size} bytes")
endif()
file(READ "${OUTPUT_FILE}" data_raw_size HEX OFFSET 448 LIMIT 4)
if(NOT data_raw_size STREQUAL "00040000")
    message(FATAL_ERROR "UEFI .rdata raw size should be 1024 bytes, found ${data_raw_size}")
endif()

# Check that the PE virtual image size grows when the text crosses a 4 KiB page.
get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(long_source "${output_dir}/uefi_long_line.hy")
set(long_output "${output_dir}/uefi_long_line.efi")
string(REPEAT "ABCDEFGHIJ" 220 long_line)
file(WRITE "${long_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"${long_line}\"); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${long_source}" --target uefi-x64 -o "${long_output}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_stdout
    ERROR_VARIABLE compile_stderr
    TIMEOUT 30
)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR "long UEFI compile failed\n${compile_stdout}\n${compile_stderr}")
endif()
file(READ "${long_output}" size_of_image HEX OFFSET 208 LIMIT 4)
if(NOT size_of_image STREQUAL "00400000")
    message(FATAL_ERROR "UEFI SizeOfImage should grow to 16384 bytes, found ${size_of_image}")
endif()
file(SIZE "${long_output}" long_image_size)
if(NOT long_image_size EQUAL 5632)
    message(FATAL_ERROR "UEFI file should allocate nine 512-byte data blocks, found ${long_image_size} bytes")
endif()
