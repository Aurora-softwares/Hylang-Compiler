foreach(required NATIVE_BINARY PROJECT_FILE OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(REMOVE_RECURSE "${OUTPUT_DIR}")
execute_process(
    COMMAND "${NATIVE_BINARY}" new os "${OUTPUT_DIR}/Scaffold"
    RESULT_VARIABLE NEW_RESULT
    OUTPUT_VARIABLE NEW_STDOUT
    ERROR_VARIABLE NEW_STDERR
    TIMEOUT 30
)
if(NOT NEW_RESULT EQUAL 0)
    message(FATAL_ERROR "OS project scaffold failed\n${NEW_STDOUT}\n${NEW_STDERR}")
endif()
file(READ "${OUTPUT_DIR}/Scaffold/Scaffold.hyproj" scaffold)
if(NOT scaffold MATCHES "type = \"os\"" OR NOT scaffold MATCHES "project_references = \\[\\]")
    message(FATAL_ERROR "OS project scaffold has the wrong manifest")
endif()

foreach(kind efi kernel)
    execute_process(
        COMMAND "${NATIVE_BINARY}" new "${kind}" "${OUTPUT_DIR}/${kind}"
        RESULT_VARIABLE NEW_COMPONENT_RESULT
        OUTPUT_VARIABLE NEW_COMPONENT_STDOUT
        ERROR_VARIABLE NEW_COMPONENT_STDERR
        TIMEOUT 30
    )
    if(NOT NEW_COMPONENT_RESULT EQUAL 0)
        message(FATAL_ERROR "${kind} project scaffold failed\n${NEW_COMPONENT_STDOUT}\n${NEW_COMPONENT_STDERR}")
    endif()
    file(READ "${OUTPUT_DIR}/${kind}/${kind}.hyproj" component_manifest)
    if(NOT component_manifest MATCHES "type = \"${kind}\"" OR
       NOT component_manifest MATCHES "output = \"EFI/")
        message(FATAL_ERROR "${kind} project scaffold has the wrong manifest")
    endif()
endforeach()

execute_process(
    COMMAND "${NATIVE_BINARY}" check "${PROJECT_FILE}"
    RESULT_VARIABLE CHECK_RESULT
    OUTPUT_VARIABLE CHECK_STDOUT
    ERROR_VARIABLE CHECK_STDERR
    TIMEOUT 30
)
if(NOT CHECK_RESULT EQUAL 0 OR
   NOT CHECK_STDOUT MATCHES "check ok:.*Boot.hyproj" OR
   NOT CHECK_STDOUT MATCHES "check ok:.*Kernel.hyproj")
    message(FATAL_ERROR "OS project check failed\n${CHECK_STDOUT}\n${CHECK_STDERR}")
endif()

execute_process(
    COMMAND "${NATIVE_BINARY}" build "${PROJECT_FILE}" -o "${OUTPUT_DIR}"
    RESULT_VARIABLE BUILD_RESULT
    OUTPUT_VARIABLE BUILD_STDOUT
    ERROR_VARIABLE BUILD_STDERR
    TIMEOUT 30
)
if(NOT BUILD_RESULT EQUAL 0)
    message(FATAL_ERROR "OS project build failed\n${BUILD_STDOUT}\n${BUILD_STDERR}")
endif()

foreach(relative EFI/BOOT/BOOTX64.EFI EFI/TEST/KERNEL.EFI)
    set(output "${OUTPUT_DIR}/${relative}")
    if(NOT EXISTS "${output}")
        message(FATAL_ERROR "OS project did not emit ${relative}")
    endif()
    file(READ "${output}" magic HEX LIMIT 2)
    if(NOT magic STREQUAL "4d5a")
        message(FATAL_ERROR "OS project output ${relative} has no MZ header")
    endif()
endforeach()

get_filename_component(fixture_dir "${PROJECT_FILE}" DIRECTORY)
foreach(project Boot/Boot Kernel/Kernel)
    string(REPLACE "/" ";" parts "${project}")
    list(GET parts 1 name)
    set(output "${OUTPUT_DIR}/${name}.direct.EFI")
    execute_process(
        COMMAND "${NATIVE_BINARY}" build "${fixture_dir}/${project}.hyproj" -o "${output}"
        RESULT_VARIABLE DIRECT_RESULT
        OUTPUT_VARIABLE DIRECT_STDOUT
        ERROR_VARIABLE DIRECT_STDERR
        TIMEOUT 30
    )
    if(NOT DIRECT_RESULT EQUAL 0)
        message(FATAL_ERROR "direct ${name} build failed\n${DIRECT_STDOUT}\n${DIRECT_STDERR}")
    endif()
    file(READ "${output}" magic HEX LIMIT 2)
    if(NOT magic STREQUAL "4d5a")
        message(FATAL_ERROR "direct ${name} build has no MZ header")
    endif()
endforeach()
