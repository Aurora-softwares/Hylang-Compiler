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
    "4d85d2"
    "41c744241401004600"
    "418b8fbc01000031c9498d940c00100000"
    "4183bf3001000002"
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

set(small_source "${output_dir}/uefi_storage_small_dma.hy")
set(small_output "${output_dir}/uefi_storage_small_dma.efi")
file(WRITE "${small_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.VirtualMemory.Initialize(); System.Kernel.VirtualMemory.ApplyPolicy(); System.Kernel.Heap.Initialize(); System.Kernel.Framebuffer.Initialize(); System.Kernel.Gdt.Initialize(); System.Kernel.Idt.Initialize(); System.Kernel.Interrupts.Initialize(); System.Kernel.Timer.Initialize(); System.Kernel.Pci.Initialize(); System.Kernel.Mmio.Initialize(); System.Kernel.Dma.Initialize(); System.Kernel.Dma.AllocatePages(15); System.Kernel.Storage.Initialize(); System.Kernel.Interrupts.Enable(); System.Kernel.Interrupts.Idle(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${small_source}" --target uefi-x64 -o "${small_output}"
    RESULT_VARIABLE small_result
    OUTPUT_VARIABLE small_stdout
    ERROR_VARIABLE small_stderr
    TIMEOUT 30
)
if(small_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted storage initialization with insufficient DMA pages")
endif()
if(NOT "${small_stdout}${small_stderr}" MATCHES "System.Kernel.Storage.Initialize requires at least 16 preceding DMA pages")
    message(FATAL_ERROR "UEFI compiler reported an unexpected DMA-size error\n${small_stdout}\n${small_stderr}")
endif()

# Storage consumes the most recent allocation, so earlier pages cannot make
# a one-page final allocation safe for its queue and GPT buffers.
file(READ "${small_source}" split_text)
string(REPLACE "System.Kernel.Dma.AllocatePages(15);" "System.Kernel.Dma.AllocatePages(16); System.Kernel.Dma.AllocatePages(1);" split_text "${split_text}")
set(split_source "${output_dir}/uefi_storage_split_dma.hy")
set(split_output "${output_dir}/uefi_storage_split_dma.efi")
file(WRITE "${split_source}" "${split_text}")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${split_source}" --target uefi-x64 -o "${split_output}"
    RESULT_VARIABLE split_result
    OUTPUT_VARIABLE split_stdout
    ERROR_VARIABLE split_stderr
    TIMEOUT 30
)
if(split_result EQUAL 0 OR NOT "${split_stdout}${split_stderr}" MATCHES "System.Kernel.Storage.Initialize requires at least 16 preceding DMA pages")
    message(FATAL_ERROR "UEFI compiler accepted split DMA allocations with an undersized final buffer\n${split_stdout}\n${split_stderr}")
endif()
