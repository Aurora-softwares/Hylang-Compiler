foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/HyCompileUefi.cmake")

file(READ "${OUTPUT_FILE}" image_hex HEX)
foreach(pattern IN ITEMS
    "4155424907000000"
    "0f011424"
    "0f011c24"
    "48cb"
    "0fa2"
    "0f32"
    "0f30"
    "48cf"
    "fbf4ebfd"
)
    string(FIND "${image_hex}" "${pattern}" pattern_offset)
    if(pattern_offset EQUAL -1)
        message(FATAL_ERROR "UEFI interrupt image is missing required instruction sequence ${pattern}")
    endif()
endforeach()

# PIC ICW1 remaps master and slave, with port-0x80 waits between writes.
string(FIND "${image_hex}" "b011e620e680b011e6a0e680" pic_remap)
if(pic_remap EQUAL -1)
    message(FATAL_ERROR "UEFI interrupt image is missing PIC remapping")
endif()

# The local timer uses vector 0x30 in periodic mode (0x00020030).
string(FIND "${image_hex}" "30000200" timer_lvt)
if(timer_lvt EQUAL -1)
    message(FATAL_ERROR "UEFI interrupt image is missing periodic local-APIC timer setup")
endif()

file(READ "${OUTPUT_FILE}" boot_info_virtual_size HEX OFFSET 480 LIMIT 4)
if(NOT boot_info_virtual_size STREQUAL "00200000")
    message(FATAL_ERROR "UEFI interrupt image must reserve two virtual pages for KernelBootInfo and the IDT")
endif()

function(parse_le32 hex_value output_variable)
    string(SUBSTRING "${hex_value}" 0 2 byte0)
    string(SUBSTRING "${hex_value}" 2 2 byte1)
    string(SUBSTRING "${hex_value}" 4 2 byte2)
    string(SUBSTRING "${hex_value}" 6 2 byte3)
    math(EXPR parsed_value "0x${byte3}${byte2}${byte1}${byte0}")
    set(${output_variable} "${parsed_value}" PARENT_SCOPE)
endfunction()

# The handler block expands .text substantially. Verify the fixed data RVA
# remains beyond the entire text section instead of silently overlapping it.
file(READ "${OUTPUT_FILE}" text_virtual_size_hex HEX OFFSET 400 LIMIT 4)
file(READ "${OUTPUT_FILE}" text_virtual_address_hex HEX OFFSET 404 LIMIT 4)
file(READ "${OUTPUT_FILE}" data_virtual_address_hex HEX OFFSET 444 LIMIT 4)
parse_le32("${text_virtual_size_hex}" text_virtual_size)
parse_le32("${text_virtual_address_hex}" text_virtual_address)
parse_le32("${data_virtual_address_hex}" data_virtual_address)
math(EXPR text_virtual_end "${text_virtual_address} + ${text_virtual_size}")
if(data_virtual_address LESS_EQUAL text_virtual_end)
    message(FATAL_ERROR "UEFI interrupt image has overlapping .text and .rdata virtual sections")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(invalid_source "${output_dir}/uefi_interrupts_before_framebuffer.hy")
set(invalid_output "${output_dir}/uefi_interrupts_before_framebuffer.efi")
file(WRITE "${invalid_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.VirtualMemory.Initialize(); System.Kernel.VirtualMemory.ApplyPolicy(); System.Kernel.Heap.Initialize(); System.Kernel.Gdt.Initialize(); System.Kernel.Halt(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${invalid_source}" --target uefi-x64 -o "${invalid_output}"
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_stdout
    ERROR_VARIABLE invalid_stderr
    TIMEOUT 30
)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted GDT initialization before the framebuffer handoff")
endif()
if(NOT "${invalid_stdout}${invalid_stderr}" MATCHES "System.Kernel.Gdt.Initialize must follow System.Kernel.Framebuffer.Initialize")
    message(FATAL_ERROR "UEFI compiler reported an unexpected interrupt-order error\n${invalid_stdout}\n${invalid_stderr}")
endif()
