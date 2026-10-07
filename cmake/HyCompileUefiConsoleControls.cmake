foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/HyCompileUefi.cmake")

file(READ "${OUTPUT_FILE}" image_hex HEX)
string(FIND "${image_hex}" "498b4d40488b4130ffd0" clear_screen_call)
if(clear_screen_call EQUAL -1)
    message(FATAL_ERROR "UEFI image is missing EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL.ClearScreen")
endif()
string(FIND "${image_hex}" "498b8660000000ffd0" wait_for_event_call)
if(wait_for_event_call EQUAL -1)
    message(FATAL_ERROR "UEFI image is missing BootServices.WaitForEvent")
endif()
string(FIND "${image_hex}" "498b4d30488d542440488b4108ffd0" read_key_call)
if(read_key_call EQUAL -1)
    message(FATAL_ERROR "UEFI image is missing EFI_SIMPLE_TEXT_INPUT_PROTOCOL.ReadKeyStroke")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(invalid_source "${output_dir}/uefi_clear_screen_after_output.hy")
set(invalid_output "${output_dir}/uefi_clear_screen_after_output.efi")
file(WRITE "${invalid_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"before\"); System.Uefi.ClearScreen(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${invalid_source}" --target uefi-x64 -o "${invalid_output}"
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_stdout
    ERROR_VARIABLE invalid_stderr
    TIMEOUT 30
)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted ClearScreen after console output")
endif()
if(NOT "${invalid_stdout}${invalid_stderr}" MATCHES "System.Uefi.ClearScreen must precede console output")
    message(FATAL_ERROR "UEFI compiler reported an unexpected ClearScreen ordering error\n${invalid_stdout}\n${invalid_stderr}")
endif()
