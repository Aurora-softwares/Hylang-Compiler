# Hydrogen C Compiler (`hydrogenc`)

Hydrogen C is a minimal, statically typed language that targets 64-bit Windows PE/COFF executables without routing through C or C++. The compiler is written in modern C++20 and uses LLVM for IR construction, object emission, and `lld-link` for final executable generation.

## Language snapshot (v0.1)

* All values are 32-bit signed integers (`Int`).
* Semicolon terminated, C-style syntax.
* Keywords are case-insensitive: `Var`, `Function`, `Return`, `Int`, `Print`.
* Only builtin is `Print(Int)` which writes an integer followed by a newline via the Win32 console API.
* Entry point is `Function main()` which implicitly returns `0` when control reaches the end of the function body.
* Variables must be declared before use; no shadowing or overloading.

Example program (`tests/Test.hy`):

```hydrogen
Var Int X = 1;
Function main(){
    test(X);
}
Function test(int I) {
    Print(I);
}
```

## Project layout

```
CMakeLists.txt        Build configuration
cmake/FindLLVM.cmake  Helper for locating an existing LLVM installation
src/                  Compiler sources (lexer, parser, semantic analysis, LLVM lowering, runtime + linker glue)
tests/                Sample program and CTest script
```

## Prerequisites (Windows x64)

1. **Microsoft Visual C++ Build Tools** (or full Visual Studio with C++ workload). Ensure `cl.exe` is available in the build environment.
2. **CMake 3.20+**
3. **LLVM prebuilt binaries** (version 15 or newer recommended) that provide the libraries and `lld-link.exe`.
4. Optional but recommended: `Ninja` for faster builds.

Set the following environment variables before configuring:

* `LLVM_DIR` – directory containing `LLVMConfig.cmake` (typically `<LLVM>\lib\cmake\llvm`).
* `LLVM_BINDIR` – directory that contains `lld-link.exe` (usually `<LLVM>\bin`).
* Optional `HYDROGENC_LLD` – explicit path to `lld-link.exe` if it is not in `PATH` and differs from `LLVM_BINDIR`.
* Ensure the Windows SDK/VC library directories are discoverable via the standard `LIB` environment variable (set automatically by the MSVC developer command prompt).

## Configure & build

```powershell
# From an x64 Native Tools Command Prompt for VS
cd path\to\Hylang-Compiler
cmake -S . -B build -G "Ninja"
cmake --build build --config Release
```

The resulting executable is `build\hydrogenc.exe`.

To run the example program and emit an executable:

```powershell
build\hydrogenc.exe tests\Test.hy -o tests\Test.exe -v
```

Running `tests\Test.exe` prints `1` followed by a newline.

### Optional outputs

* `--emit-ir file.ll` – dump the LLVM IR module to the specified path.
* `--emit-obj file.obj` – keep the intermediate COFF object instead of deleting it after linking.
* `-v` – verbose mode (shows linking command and final output path).

## Testing

CTest integrates a simple end-to-end test that builds and runs `tests/Test.hy`. The test is skipped automatically on non-Windows hosts.

```powershell
cmake --build build --config Release
ctest --test-dir build
```

## Notes

* The compiler emits PE/COFF objects for the `x86_64-pc-windows-msvc` triple and links against `kernel32.lib` only.
* `Print` is implemented without the MSVCRT by calling `GetStdHandle` and `WriteFile` directly from the generated IR.
* Future language versions can extend the AST/sema/codegen layers without altering the toolchain pipeline.
