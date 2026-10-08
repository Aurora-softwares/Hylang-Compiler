foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${INPUT_FILE}" --target uefi-x64 -o "${OUTPUT_FILE}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_stdout
    ERROR_VARIABLE compile_stderr
    TIMEOUT 30
)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR "UEFI framebuffer compile failed\n${compile_stdout}\n${compile_stderr}")
endif()

file(READ "${OUTPUT_FILE}" image_hex HEX)
string(FIND "${image_hex}" "dea94290dc23384a96fb7aded080516a" graphics_output_guid)
if(graphics_output_guid EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID")
endif()
string(FIND "${image_hex}" "498b8640010000ffd0" locate_protocol_call)
if(locate_protocol_call EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing BootServices.LocateProtocol")
endif()
string(FIND "${image_hex}" "f3ab" framebuffer_clear)
if(framebuffer_clear EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing direct framebuffer clear")
endif()
string(FIND "${image_hex}" "c706ffffff00" white_pixel)
if(white_pixel EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing framebuffer glyph rendering")
endif()
string(FIND "${image_hex}" "5b4b45524e454c5d204672616d6562756666657220636f6e736f6c65206163746976652e00" framebuffer_message)
if(framebuffer_message EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing its framebuffer message")
endif()
string(FIND "${image_hex}" "4155424907000000" framebuffer_abi)
if(framebuffer_abi EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing KernelBootInfo ABI version 7")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(invalid_source "${output_dir}/uefi_framebuffer_before_initialize.hy")
set(invalid_output "${output_dir}/uefi_framebuffer_before_initialize.efi")
file(WRITE "${invalid_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.VirtualMemory.Initialize(); System.Kernel.VirtualMemory.ApplyPolicy(); System.Kernel.Heap.Initialize(); System.Kernel.Framebuffer.WriteLine(\"invalid\"); System.Kernel.Halt(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${invalid_source}" --target uefi-x64 -o "${invalid_output}"
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_stdout
    ERROR_VARIABLE invalid_stderr
    TIMEOUT 30
)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted framebuffer output before initialization")
endif()
if(NOT "${invalid_stdout}${invalid_stderr}" MATCHES "System.Kernel.Framebuffer.WriteLine must follow System.Kernel.Framebuffer.Initialize")
    message(FATAL_ERROR "UEFI compiler reported an unexpected framebuffer ordering error\n${invalid_stdout}\n${invalid_stderr}")
endif()
