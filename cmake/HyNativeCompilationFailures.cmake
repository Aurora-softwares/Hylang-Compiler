foreach(required HY_BINARY PROJECT_TARGET SOURCE_DIR TEMP_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()

file(MAKE_DIRECTORY "${TEMP_DIR}")
set(compiler_command "${HY_BINARY}" run "${PROJECT_TARGET}" --)
if(COMPILE_CLI)
    set(NATIVE_BINARY "${TEMP_DIR}/hydrogen-compiler")
    execute_process(
        COMMAND "${HY_BINARY}" build "${PROJECT_TARGET}" -o "${NATIVE_BINARY}"
        RESULT_VARIABLE build_result
        OUTPUT_VARIABLE build_stdout
        ERROR_VARIABLE build_stderr
        TIMEOUT 60
    )
    if(NOT build_result STREQUAL "0")
        message(FATAL_ERROR "Could not build Hydrogen CLI: ${build_result}\n${build_stdout}\n${build_stderr}")
    endif()
    set(compiler_command "${NATIVE_BINARY}")
elseif(DEFINED NATIVE_BINARY)
    set(compiler_command "${NATIVE_BINARY}")
endif()

set(cases native_unsupported_call native_no_main native_unsupported_string invalid_return parser_broken)
set(reasons
    "Program.Main: unsupported native runtime intrinsic: System.Console.ReadLine"
    "no static Main method"
    "1:1 error assignment target is not writable\n"
    "1:1 error return type mismatch\n"
    "2:20 error Expected identifier\n2:20 error Expected parameter name\n2:20 error Expected ')'\n"
)

foreach(mode compile build)
    foreach(case IN LISTS cases)
        list(FIND cases "${case}" case_index)
        list(GET reasons ${case_index} reason)
        set(source "${SOURCE_DIR}/tests/phase6/${case}.hy")
        if(case STREQUAL "invalid_return")
            set(source "${SOURCE_DIR}/tests/negative/invalid_return.hy")
        elseif(case STREQUAL "parser_broken")
            set(source "${SOURCE_DIR}/tests/phase5/parser_broken.hy")
        endif()
        set(input "${source}")
        if(mode STREQUAL "build")
            set(input "${TEMP_DIR}/${case}.hyproj")
            file(WRITE "${input}"
                "format = 2\nname = \"${case}\"\ntype = \"exe\"\nsources = [\"${source}\"]\n")
        endif()

        # Failure must neither create an artifact nor overwrite an existing one.
        foreach(existing FALSE TRUE)
            set(output "${TEMP_DIR}/${mode}_${case}_${existing}")
            file(REMOVE "${output}")
            if(existing)
                file(WRITE "${output}" "existing artifact\n")
            endif()
            execute_process(
                COMMAND ${compiler_command} "${mode}" "${input}" -o "${output}"
                RESULT_VARIABLE result
                OUTPUT_VARIABLE stdout
                ERROR_VARIABLE stderr
                TIMEOUT 30
            )
            if(NOT result STREQUAL "1")
                message(FATAL_ERROR "${mode} ${case}: expected exit 1, got ${result}\n${stdout}\n${stderr}")
            endif()
            set(expected "${input}: error: native compilation failed: ${reason}\n")
            if(case STREQUAL "invalid_return" OR case STREQUAL "native_unsupported_string")
                set(expected "${input}:\n${reason}")
            elseif(case STREQUAL "parser_broken")
                set(expected "${source}:\n${reason}")
            endif()
            if(NOT stdout STREQUAL expected OR NOT stderr STREQUAL "")
                message(FATAL_ERROR "${mode} ${case}: expected one clean diagnostic\nexpected:\n${expected}\nstdout:\n${stdout}\nstderr:\n${stderr}")
            endif()
            if(existing)
                file(READ "${output}" actual)
                if(NOT actual STREQUAL "existing artifact\n")
                    message(FATAL_ERROR "${mode} ${case}: failed compilation overwrote the existing artifact")
                endif()
            elseif(EXISTS "${output}")
                message(FATAL_ERROR "${mode} ${case}: failed compilation created an artifact")
            endif()
        endforeach()
    endforeach()
endforeach()

# Project builds must still emit real executable code for supported input.
set(hello_project "${TEMP_DIR}/native_hello.hyproj")
file(WRITE "${hello_project}"
    "format = 2\nname = \"native_hello\"\ntype = \"exe\"\nsources = [\"${SOURCE_DIR}/tests/phase6/native_hello.hy\"]\n")
set(INPUT_FILE "${hello_project}")
set(OUTPUT_FILE "${TEMP_DIR}/native_hello")
set(NATIVE_COMMAND build)
set(EXPECTED_OUTPUT "Hydrogen native hello\n")
include("${SOURCE_DIR}/cmake/HyCompileNativeAndRun.cmake")
