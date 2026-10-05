# Hydrogen (Hylang)

Hydrogen is a C#-inspired language with classes, methods, managed strings and arrays, and explicit low-level facilities. Source files use `.hy`; project manifests use `.hyproj`.

The Hydrogen-written compiler produces standalone Linux x86-64 executables, a constrained x86_64 UEFI proof image, and can compile itself. The C++ SDK provides additional language features, an interpreter, project scaffolding, packaging, formatting, and editor integration. Choose the tool according to the features your program needs.

| Tool | Use it for | Output or execution |
| --- | --- | --- |
| `hydrogen-stage1` (Hydrogen) | Direct native compilation, source/project checking, IR inspection, UEFI hello-world proof | Linux x64 ELF or constrained `uefi-x64` PE32+ output; no external compiler or linker |
| `hy` (C++ SDK) | Build/run/test/check/fmt/new/package/LSP workflows; UEFI hello-world proof | Interpreter, host C backend, or constrained `uefi-x64` PE32+ output |
| `hyrun` | Direct interpreted execution | Shares the SDK semantic pipeline |
| `hyc build` | Compatibility build command | Host C backend, executables or static libraries |

See the [language and tool reference](https://aurora-softwares.github.io/Hylang-Docs/) and [native compiler guide](samples/self_hosting/README.md) for the supported features of each route.

## Build the tools

Run these commands from this repository's root. The SDK requires CMake 3.20 or newer and a C++20 compiler. Its executable builds also require a host C compiler; static-library builds require an archiver. The direct native compiler targets Linux x86-64.

```bash
cmake -S . -B build
cmake --build build
cmake --build build --target hydrogen_stage1
```

The native target initially uses the SDK's C backend to create a seed, then Hydrogen's own backend compiles the complete compiler CLI project and its referenced libraries. The resulting `build/self_hosting/hydrogen-stage1` has no C/C++ toolchain dependency when compiling supported programs.

For a manual SDK build:

```bash
mkdir -p build
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hy_main.cpp -o build/hy
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyrun_main.cpp -o build/hyrun
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyc_main.cpp -o build/hyc
```

## Write and run a program

Save this as `hello.hy`:

```hylang
namespace Hello {
    public class Program {
        public static int Twice(int value) {
            return value * 2;
        }

        public static int Main(string[] args) {
            string name = "World";
            if (args.Length > 0) { name = args[0]; }
            System.Console.WriteLine("Hello, " + name);
            System.Console.WriteLine(Twice(21));
            return 0;
        }
    }
}
```

Compile directly with Hydrogen:

```bash
./build/self_hosting/hydrogen-stage1 check hello.hy
./build/self_hosting/hydrogen-stage1 compile hello.hy -o build/hello
chmod +x build/hello
./build/hello Hydrogen
```

Expected output:

```text
Hello, Hydrogen
42
```

Native output files need execute permission. Compilation failures return a nonzero status and do not create or overwrite the output; check that status before running an existing artifact.

## UEFI hello-world proof

The SDK compiler can also emit a bootable x86_64 UEFI PE32+ application for a
deliberately constrained proof of concept. The input must have a normal Hylang
`Main` method containing exactly one `System.Console.WriteLine` with a printable
ASCII string literal:

```bash
./build/self_hosting/hydrogen-stage1 compile tests/uefi_hello.hy --target uefi-x64 -o build/BOOTX64.EFI
file build/BOOTX64.EFI
```

The result is an EFI application, not a Linux ELF. The self-hosted compiler
emits a PE32+ image, uses the UEFI Microsoft x64 entry ABI, writes an ASCII
message as UTF-16 through the firmware `OutputString` function pointer, and
then remains on screen. This target has no managed runtime, Linux syscalls,
allocator, or general method support yet; it is the bootability proof on the
path to a complete firmware backend.

Alternatively, interpret or build with the SDK:

```bash
./build/hy run hello.hy -- Hydrogen
./build/hy build hello.hy -o build/hello-sdk
./build/hello-sdk Hydrogen
```

`Main` is a static class method returning `int` or `void`, with no parameters or one `string[]` parameter. Its argument array excludes the executable name; an integer return supplies the process exit status. Hydrogen has no top-level statements or free functions.

## Projects

An executable project can reference library projects by source closure:

```toml
format = 2
name = "Hello"
type = "exe"
sources = ["Program.hy"]
project_references = ["../Shared/Shared.hyproj"]
```

Paths are relative to the containing manifest. Use `type = "lib"` for a referenced library. The native compiler binds referenced sources together and emits one executable:

```bash
./build/self_hosting/hydrogen-stage1 build Hello/Hello.hyproj -o build/hello-project
chmod +x build/hello-project
./build/hello-project
```

SDK projects additionally support workspaces, test projects, local package dependencies, caching, and static-library artifacts. Useful SDK commands:

```bash
./build/hy new app MyApp
./build/hy check MyApp/MyApp.hyproj --json
./build/hy build MyApp/MyApp.hyproj
./build/hy run MyApp/MyApp.hyproj -- argument
./build/hy fmt MyApp --check
```

## Language and runtime

The direct native route supports classes with instance fields and constructors, static/instance methods, recursion, `var`, enums, `int`/`byte`/`bool`, strings, arrays, `if`/`else`, `while`, `break`, `continue`, and returns. `int` is signed 64-bit. Strings have byte-based length/indexing; indexing returns a one-byte string. Native literals accept ASCII and common escaped control characters; file contents and arguments preserve raw bytes.

Native builtins include `System.Console.Write`/`WriteLine`, `System.IO.File` text/byte reads and writes and existence checks, `System.Convert.ToInt32`, and `System.Runtime.GC` collection/accounting. Objects are managed by a conservative non-moving mark/sweep collector using Linux memory mappings. File reads require seekable files.

The SDK also supports inheritance, virtual/interface dispatch, structs with value semantics, generics, overloads, static fields, `for`, string exceptions, `List<T>`, checked unsafe/manual-memory operations, `Buffer`, and `BinaryPrimitives`. These additional facilities are not implemented by the native compiler. The SDK interpreter evaluates both sides of `&&` and `||`; generated native and C-backed programs short-circuit. Write explicit conditional guards when sharing code with the interpreter.

## Examples and editor support

- [Native compiler](samples/self_hosting/README.md): commands, runtime, project binding, self-compilation.
- [HexLab](samples/hexlab/README.md): binary-file inspection with the SDK's buffer and unsafe APIs.
- [SDK demo](samples/sdk_demo/README.md): projects, testing, and local package registries.
- [VS Code assets](tools/vscode/hylang/README.md): highlighting, snippets, check/format tasks, and the LSP process launcher.

## Compiler development

```bash
ctest --test-dir build --output-on-failure
cmake --build build --target hydrogen_bootstrap_proof
cat build/self_hosting/bootstrap-proof.txt
```

The proof recompiles the native compiler through three generations, runs the same behavioral corpus with each, and requires identical stage 2/3 compiler and representative application artifacts. Retain a verified native seed to rebuild without C++; a source-only checkout still needs a bootstrap route. Native self-hosting does not replace the SDK's broader language and tooling surface.

See [compiler architecture](docs/implementation/phase6-self-hosted-compiler.md), [future work](ROADMAP.md), and the [OS design plan](OS_ROADMAP.md).
