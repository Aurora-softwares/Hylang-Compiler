foreach(required NATIVE_BINARY INPUT_FILE OUTPUT_FILE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/HyCompileUefi.cmake")

file(READ "${OUTPUT_FILE}" image_hex HEX)
string(FIND "${image_hex}" "498b86d8000000ffd0" exit_boot_services_call)
if(exit_boot_services_call EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing its ExitBootServices call")
endif()
string(FIND "${image_hex}" "faf4ebfd" idle_loop)
if(idle_loop EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing its interrupt-disabled halt loop")
endif()
file(READ "${OUTPUT_FILE}" section_count HEX OFFSET 134 LIMIT 2)
if(NOT section_count STREQUAL "0300")
    message(FATAL_ERROR "UEFI kernel image should add its writable KernelBootInfo section")
endif()
string(FIND "${image_hex}" "2e64617461000000" boot_info_section)
if(boot_info_section EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing its .data boot-information section")
endif()
string(FIND "${image_hex}" "4155424901000000" boot_info_abi)
if(boot_info_abi EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing its KernelBootInfo ABI record")
endif()
file(READ "${OUTPUT_FILE}" boot_info_size HEX OFFSET 480 LIMIT 4)
if(NOT boot_info_size STREQUAL "48000000")
    message(FATAL_ERROR "KernelBootInfo should include its virtual-memory root field")
endif()
file(READ "${OUTPUT_FILE}" image_base HEX OFFSET 176 LIMIT 8)
if(NOT image_base STREQUAL "0000000000000000")
    message(FATAL_ERROR "UEFI kernel image should be position independent")
endif()
string(REGEX MATCH "c705[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]01000000" memory_map_ready "${image_hex}")
if(memory_map_ready STREQUAL "")
    message(FATAL_ERROR "UEFI kernel image does not mark KernelBootInfo ready after the handoff")
endif()
string(REGEX MATCH "488d3d[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]c705" boot_info_argument "${image_hex}")
if(boot_info_argument STREQUAL "")
    message(FATAL_ERROR "UEFI kernel image does not pass KernelBootInfo in RDI")
endif()
string(FIND "${image_hex}" "f348ab" allocator_metadata_clear)
if(allocator_metadata_clear EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image does not clear its page-allocator metadata page")
endif()
string(FIND "${image_hex}" "c7472403000000" allocator_ready)
if(allocator_ready EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image does not publish the physical-page allocator state")
endif()
string(FIND "${image_hex}" "410f22d8" page_table_root)
if(page_table_root EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image does not activate its kernel-owned PML4 through CR3")
endif()
string(FIND "${image_hex}" "c7472407000000" virtual_memory_ready)
if(virtual_memory_ready EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image does not publish its virtual-memory state")
endif()
string(FIND "${image_hex}" "48c1e006" memory_map_reserve)
if(memory_map_reserve EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image does not reserve retry capacity for the memory map")
endif()
string(FIND "${image_hex}" "41ffc74183ff08" exit_boot_services_retry)
if(exit_boot_services_retry EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image does not retry ExitBootServices")
endif()
string(FIND "${image_hex}" "5b004b00450052004e0045004c005d0020004c0065006100760069006e00670020005500450046004900200062006f006f0074002000730065007200760069006300650073002e000d000a00" handoff_message)
if(handoff_message EQUAL -1)
    message(FATAL_ERROR "UEFI kernel image is missing its pre-handoff status message")
endif()

get_filename_component(output_dir "${OUTPUT_FILE}" DIRECTORY)
set(invalid_source "${output_dir}/uefi_invalid_handoff_order.hy")
set(invalid_output "${output_dir}/uefi_invalid_handoff_order.efi")
file(WRITE "${invalid_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Kernel.Halt(); System.Uefi.ExitBootServices(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${invalid_source}" --target uefi-x64 -o "${invalid_output}"
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_stdout
    ERROR_VARIABLE invalid_stderr
    TIMEOUT 30
)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted an invalid ExitBootServices/Halt order")
endif()
if(NOT "${invalid_stdout}${invalid_stderr}" MATCHES "System.Kernel.Halt must follow System.Uefi.ExitBootServices")
    message(FATAL_ERROR "UEFI compiler reported an unexpected invalid-handoff error\n${invalid_stdout}\n${invalid_stderr}")
endif()

set(missing_initializer_source "${output_dir}/uefi_missing_memory_map_initializer.hy")
set(missing_initializer_output "${output_dir}/uefi_missing_memory_map_initializer.efi")
file(WRITE "${missing_initializer_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.Halt(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${missing_initializer_source}" --target uefi-x64 -o "${missing_initializer_output}"
    RESULT_VARIABLE missing_initializer_result
    OUTPUT_VARIABLE missing_initializer_stdout
    ERROR_VARIABLE missing_initializer_stderr
    TIMEOUT 30
)
if(missing_initializer_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted a handoff without KernelBootInfo initialization")
endif()
if(NOT "${missing_initializer_stdout}${missing_initializer_stderr}" MATCHES "System.Kernel.Halt must follow System.Kernel.MemoryMap.Initialize")
    message(FATAL_ERROR "UEFI compiler reported an unexpected missing-initializer error\n${missing_initializer_stdout}\n${missing_initializer_stderr}")
endif()

set(missing_memory_source "${output_dir}/uefi_missing_memory_initializer.hy")
set(missing_memory_output "${output_dir}/uefi_missing_memory_initializer.efi")
file(WRITE "${missing_memory_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Halt(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${missing_memory_source}" --target uefi-x64 -o "${missing_memory_output}"
    RESULT_VARIABLE missing_memory_result
    OUTPUT_VARIABLE missing_memory_stdout
    ERROR_VARIABLE missing_memory_stderr
    TIMEOUT 30
)
if(missing_memory_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted a handoff without physical-memory initialization")
endif()
if(NOT "${missing_memory_stdout}${missing_memory_stderr}" MATCHES "System.Kernel.Halt must follow System.Kernel.Memory.Initialize")
    message(FATAL_ERROR "UEFI compiler reported an unexpected missing-memory error\n${missing_memory_stdout}\n${missing_memory_stderr}")
endif()

set(missing_virtual_memory_source "${output_dir}/uefi_missing_virtual_memory_initializer.hy")
set(missing_virtual_memory_output "${output_dir}/uefi_missing_virtual_memory_initializer.efi")
file(WRITE "${missing_virtual_memory_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"kernel\"); System.Uefi.ExitBootServices(); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.Halt(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${missing_virtual_memory_source}" --target uefi-x64 -o "${missing_virtual_memory_output}"
    RESULT_VARIABLE missing_virtual_memory_result
    OUTPUT_VARIABLE missing_virtual_memory_stdout
    ERROR_VARIABLE missing_virtual_memory_stderr
    TIMEOUT 30
)
if(missing_virtual_memory_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted a handoff without virtual-memory initialization")
endif()
if(NOT "${missing_virtual_memory_stdout}${missing_virtual_memory_stderr}" MATCHES "System.Kernel.Halt must follow System.Kernel.VirtualMemory.Initialize")
    message(FATAL_ERROR "UEFI compiler reported an unexpected missing-virtual-memory error\n${missing_virtual_memory_stdout}\n${missing_virtual_memory_stderr}")
endif()

set(post_exit_console_source "${output_dir}/uefi_console_after_exit_boot_services.hy")
set(post_exit_console_output "${output_dir}/uefi_console_after_exit_boot_services.efi")
file(WRITE "${post_exit_console_source}" "public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"before\"); System.Uefi.ExitBootServices(); System.Console.WriteLine(\"after\"); System.Kernel.MemoryMap.Initialize(); System.Kernel.Memory.Initialize(); System.Kernel.VirtualMemory.Initialize(); System.Kernel.Halt(); } }\n")
execute_process(
    COMMAND "${NATIVE_BINARY}" compile "${post_exit_console_source}" --target uefi-x64 -o "${post_exit_console_output}"
    RESULT_VARIABLE post_exit_console_result
    OUTPUT_VARIABLE post_exit_console_stdout
    ERROR_VARIABLE post_exit_console_stderr
    TIMEOUT 30
)
if(post_exit_console_result EQUAL 0)
    message(FATAL_ERROR "UEFI compiler accepted console output after ExitBootServices")
endif()
if(NOT "${post_exit_console_stdout}${post_exit_console_stderr}" MATCHES "UEFI console output must precede System.Uefi.ExitBootServices")
    message(FATAL_ERROR "UEFI compiler reported an unexpected post-ExitBootServices console error\n${post_exit_console_stdout}\n${post_exit_console_stderr}")
endif()
