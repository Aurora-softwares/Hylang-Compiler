# Hydrogen C Compiler (`hydrogenc`)

Hydrogen C is a tiny, experimental language that compiles directly to Windows PE/COFF executables using LLVM. The `hydrogenc` tool consumes `.hy` source files, performs lexing, parsing, semantic analysis, lowers the program to LLVM IR, emits a COFF object file, and links it into a standalone Windows console application with no MSVCRT dependency.

## Language overview (v0.1)

* Single 32-bit signed integer type (`Int`).
* Case-insensitive keywords: `Var`, `Function`, `Return`, `Print`, `Int`.
* Identifiers are case-sensitive.
* Semicolon-terminated statements.
* Only built-in is `Print(Int)` which writes the integer and a trailing newline using `GetStdHandle`/`WriteFile` from `kernel32.dll`.
* Entry point is `Function main(){ ... }`. Falling off the end returns `0`.

See `tests/Test.hy` for a minimal example.

## Prerequisites

1. **Windows 10/11 x64** with the MSVC toolchain (Visual Studio or Build Tools) and the "x64 Native Tools" developer command prompt.
2. **CMake 3.20+**.
3. **LLVM for Windows** (prebuilt binaries). Install the release build that includes `lld-link.exe`. Set the environment variable `LLVM_DIR` to the `lib/cmake/llvm` directory of the installation, e.g.
   ```powershell
   setx LLVM_DIR "C:\\Program Files\\LLVM\\lib\\cmake\\llvm"
   ```
   Ensure `lld-link.exe` is on `%PATH%` (normally the LLVM `bin` directory).

## Building

```powershell
# From an x64 Native Tools command prompt
cd path\to\Hylang-Compiler
cmake -S . -B build -G "Ninja" \
      -DLLVM_DIR="C:/Program Files/LLVM/lib/cmake/llvm"
cmake --build build
```

The resulting executable will be at `build/hydrogenc.exe` (or inside `build/Debug`/`build/Release` when using multi-config generators like Visual Studio).

## Running the compiler

```powershell
# Compile a Hydrogen C source file to an executable
build\hydrogenc.exe tests\Test.hy -o Test.exe

# Optional flags
#   --emit-ir out.ll   Save generated LLVM IR
#   --emit-obj out.obj Keep the intermediate COFF object
#   --lld path\to\lld-link.exe Use a custom linker path
#   -v                 Verbose logging
```

Running `Test.exe` prints `1` followed by a newline.

## Tests

Configure and build the project, then run CTest:

```powershell
cmake --build build
ctest --test-dir build
```

CTest invokes `hydrogenc` on `tests/Test.hy`, links the resulting executable, and verifies that it prints `1`.

## Project layout

```
src/
  main.cpp            # CLI driver
  diag.*              # Diagnostics with caret highlighting
  lexer.*             # Lexer/token definitions
  parser.*            # Recursive-descent parser
  ast.hpp             # AST node definitions
  sema.*              # Semantic analysis and symbol tracking
  codegen.*           # LLVM IR code generation
  winrt.*             # WinAPI-backed runtime helpers (Print)
  object_emit.*       # COFF object emission via TargetMachine
  linker.*            # lld-link integration
  util.*              # File + command helpers
cmake/FindLLVM.cmake  # Helper to locate LLVM
CMakeLists.txt        # Build configuration
tests/                # Sample program + CTest script
```

## Notes

* Generated executables link only against `kernel32.lib` and avoid the MSVCRT.
* The compiler emits a small runtime helper that performs integer-to-string conversion and writes to STDOUT using WinAPI.
* Future versions can extend the grammar, add control flow, and support additional built-ins.
