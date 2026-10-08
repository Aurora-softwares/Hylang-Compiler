foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/HyCompileUefi.cmake")

file(READ "${OUTPUT_FILE}" image_hex HEX)
foreach(pattern IN ITEMS
    "4155424907000000"
    "66baf80cef66bafc0ced"
    "0d00000080"
    "4883c81bba0000008048c1e2204809d0"
    "48b80000000000c0ffff"
    "48b90000000001000000"
    "f348ab"
    "c74724ffff0000"
)
    string(FIND "${image_hex}" "${pattern}" pattern_offset)
    if(pattern_offset EQUAL -1)
        message(FATAL_ERROR "UEFI PCI/DMA image is missing required instruction sequence ${pattern}")
    endif()
endforeach()

# The page count is literal, bounded, and must not be accepted before the DMA
# allocator has established its disjoint low-memory range.
get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(invalid_source "${output_dir}/uefi_dma_before_initialize.hy")
set(invalid_output "${output_dir}/uefi_dma_before_initialize.efi")
file(WRITE "${invalid_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.VirtualMemory.Initialize(); System.Kernel.VirtualMemory.ApplyPolicy(); System.Kernel.Heap.Initialize(); System.Kernel.Framebuffer.Initialize(); System.Kernel.Gdt.Initialize(); System.Kernel.Idt.Initialize(); System.Kernel.Interrupts.Initialize(); System.Kernel.Timer.Initialize(); System.Kernel.Dma.AllocatePages(1); System.Kernel.Interrupts.Enable(); System.Kernel.Interrupts.Idle(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${invalid_source}" --target uefi-x64 -o "${invalid_output}"
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_stdout
    ERROR_VARIABLE invalid_stderr
    TIMEOUT 30
)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted DMA allocation before DMA initialization")
endif()
if(NOT "${invalid_stdout}${invalid_stderr}" MATCHES "System.Kernel.Dma.AllocatePages must follow System.Kernel.Dma.Initialize")
    message(FATAL_ERROR "UEFI compiler reported an unexpected DMA ordering error\n${invalid_stdout}\n${invalid_stderr}")
endif()
