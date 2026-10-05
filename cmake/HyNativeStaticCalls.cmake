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
        RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 60
    )
    if(NOT result STREQUAL "0")
        message(FATAL_ERROR "Could not build Hydrogen CLI: ${result}\n${stdout}\n${stderr}")
    endif()
    set(compiler_command "${NATIVE_BINARY}")
elseif(DEFINED NATIVE_BINARY)
    set(compiler_command "${NATIVE_BINARY}")
endif()

set(INPUT_FILE "${SOURCE_DIR}/tests/phase6/native_static_calls.hy")
set(OUTPUT_FILE "${TEMP_DIR}/static_calls")
set(EXPECTED_OUTPUT "helper returned to caller\nstatic calls and recursion ok\n")
set(EXPECTED_EXIT_CODE 42)
include("${SOURCE_DIR}/cmake/HyCompileNativeAndRun.cmake")

set(INPUT_FILE "${SOURCE_DIR}/tests/phase6/static_calls/App.hyproj")
set(OUTPUT_FILE "${TEMP_DIR}/project_calls")
set(NATIVE_COMMAND build)
set(EXPECTED_OUTPUT "project static calls ok\n")
include("${SOURCE_DIR}/cmake/HyCompileNativeAndRun.cmake")

# Invalid programs must fail before emission, including qualified member calls.
set(source_wrong_arity [=[
public class Program {
    public static int Main() { return Program.Id(); }
    public static int Id(int value) { return value; }
}
]=])
set(reason_wrong_arity "wrong argument count calling 'Id'")
set(source_wrong_type [=[
public class Program {
    public static int Main() { return Program.Id(true); }
    public static int Id(int value) { return value; }
}
]=])
set(reason_wrong_type "argument type mismatch calling 'Id'")
set(source_instance [=[
public class Program {
    public static int Main() { return Program.Id(7); }
    public int Id(int value) { return value; }
}
]=])
set(reason_instance "method receiver does not match static or instance declaration")
set(source_signature [=[
public class Program {
    public static int Main() { return Program.Length(0); }
    public static int Length(long text) { return 1; }
}
]=])
set(reason_signature "Program.Main: unsupported native method parameter type")
set(source_overload [=[
public class Program {
    public static int Main() { return Program.Id(7); }
    public static int Id(int value) { return value; }
    public static int Id(bool value) { return 1; }
}
]=])
set(reason_overload "Program.Main: overloaded native calls are not supported: Program.Id")
set(source_missing_return [=[
public class Program {
    public static int Main() { return Program.Id(7); }
    public static int Id(int value) { if (value > 0) { return value; } }
}
]=])
set(reason_missing_return "not all paths return a value in Program.Id")
set(source_unsupported_body [=[
public class Program {
    public static int Main() { return Program.Id(); }
    public static int Id() { try { return 1; } catch (string error) { return 2; } return 3; }
}
]=])
set(reason_unsupported_body "Program.Id: unsupported statement in direct native backend")
set(source_undefined [=[
public class Program {
    public static int Main() { return Program.Missing(7); }
}
]=])
set(reason_undefined "undefined method: Program.Missing")
set(source_void_argument [=[
public class Program {
    public static int Main() { return Program.Id(Program.Say()); }
    public static int Id(int value) { return value; }
    public static void Say() { return; }
}
]=])
set(reason_void_argument "argument type mismatch calling 'Id'")
set(source_intrinsic_arity [=[
public class Program {
    public static int Main() { System.Console.WriteLine(1, 2); return 0; }
}
]=])
set(reason_intrinsic_arity "console output requires one value")

foreach(case wrong_arity wrong_type instance signature overload missing_return unsupported_body undefined void_argument intrinsic_arity)
    set(input "${TEMP_DIR}/${case}.hy")
    file(WRITE "${input}" "${source_${case}}")
    foreach(existing FALSE TRUE)
        set(output "${TEMP_DIR}/${case}_${existing}")
        file(REMOVE "${output}")
        if(existing)
            file(WRITE "${output}" "existing artifact\n")
        endif()
        execute_process(
            COMMAND ${compiler_command} compile "${input}" -o "${output}"
            RESULT_VARIABLE result OUTPUT_VARIABLE stdout ERROR_VARIABLE stderr TIMEOUT 30
        )
        set(expected "${input}: error: native compilation failed: ${reason_${case}}\n")
        if(case MATCHES "^(wrong_arity|wrong_type|instance|missing_return|undefined|void_argument|intrinsic_arity)$")
            set(expected "${input}:\n1:1 error ${reason_${case}}\n")
        elseif(case STREQUAL "overload")
            set(expected "${input}:\n1:1 error duplicate method in type 'Program': Id\n")
        endif()
        if(NOT result STREQUAL "1" OR NOT stdout STREQUAL expected OR NOT stderr STREQUAL "")
            message(FATAL_ERROR "${case}: expected clean exit 1\nexpected:\n${expected}\nresult: ${result}\nstdout:\n${stdout}\nstderr:\n${stderr}")
        endif()
        if(existing)
            file(READ "${output}" actual)
            if(NOT actual STREQUAL "existing artifact\n")
                message(FATAL_ERROR "${case}: failed compilation overwrote output")
            endif()
        elseif(EXISTS "${output}")
            message(FATAL_ERROR "${case}: failed compilation created output")
        endif()
    endforeach()
endforeach()
