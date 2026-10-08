foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/HyCompileUefi.cmake")

file(READ "${OUTPUT_FILE}" image_hex HEX)
foreach(pattern IN ITEMS
    "4155424907000000"
    "c60027c6400180c6400225"
    "c6400740"
    "352083b8ed"
    "41813a45464920"
    "81f900010000"
    "41c78724000000ffff0100"
    "c74724ffff0300"
)
    string(FIND "${image_hex}" "${pattern}" pattern_offset)
    if(pattern_offset EQUAL -1)
        message(FATAL_ERROR "UEFI storage image is missing required instruction sequence ${pattern}")
    endif()
endforeach()

# The direct transport owns DMA command memory and must never be admitted
# before a real low-memory DMA allocation has been requested.
get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(invalid_source "${output_dir}/uefi_storage_before_dma.hy")
set(invalid_output "${output_dir}/uefi_storage_before_dma.efi")
file(WRITE "${invalid_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.VirtualMemory.Initialize(); System.Kernel.VirtualMemory.ApplyPolicy(); System.Kernel.Heap.Initialize(); System.Kernel.Framebuffer.Initialize(); System.Kernel.Gdt.Initialize(); System.Kernel.Idt.Initialize(); System.Kernel.Interrupts.Initialize(); System.Kernel.Timer.Initialize(); System.Kernel.Pci.Initialize(); System.Kernel.Mmio.Initialize(); System.Kernel.Dma.Initialize(); System.Kernel.Storage.Initialize(); System.Kernel.Interrupts.Enable(); System.Kernel.Interrupts.Idle(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${invalid_source}" --target uefi-x64 -o "${invalid_output}"
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_stdout
    ERROR_VARIABLE invalid_stderr
    TIMEOUT 30
)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted storage initialization before DMA allocation")
endif()
if(NOT "${invalid_stdout}${invalid_stderr}" MATCHES "System.Kernel.Storage.Initialize requires a preceding System.Kernel.Dma.AllocatePages call")
    message(FATAL_ERROR "UEFI compiler reported an unexpected storage ordering error\n${invalid_stdout}\n${invalid_stderr}")
endif()
