# Hydrogen C Compiler (`hydrogenc`)

Hydrogen C is a tiny, experimental, C-like language that lowers directly to Windows
x64 executables through LLVM. The `hydrogenc` tool implements the full pipeline:

```
.hy source → AST → LLVM IR → COFF object → PE/COFF executable
```

The runtime is minimal and only depends on `kernel32.dll`. `Print(Int)` is
implemented via `GetStdHandle` and `WriteFile`, avoiding the MSVCRT.

## Language v0.1 Highlights

* Single built-in type: 32-bit signed `Int`.
* Case-insensitive keywords: `Var`, `Function`, `Return`, `Print`, `Int`.
* Blocks with braces, semicolon-terminated statements.
* Only built-in is `Print(Int)`.
* Entry point: `Function main()` returning `Int` (defaults to `0`).

See [`tests/Test.hy`](tests/Test.hy) for a reference program.

## Prerequisites

* **Operating system:** Windows 10 or later (x64).
* **Compiler:** MSVC toolchain (Visual Studio 2022 or Build Tools).
* **CMake:** 3.20 or newer.
* **LLVM:** Prebuilt Windows LLVM installation (matching architecture).
  * Set the environment variable `LLVM_DIR` to the `lib/cmake/llvm` directory of the installation.
  * Ensure `lld-link.exe` is on `PATH` (or pass `--lld` to `hydrogenc`).

Example using the official LLVM installer (default path):

```
set LLVM_DIR=C:\Program Files\LLVM\lib\cmake\llvm
set PATH=%PATH%;C:\Program Files\LLVM\bin
```

## Building `hydrogenc`

```
mkdir build
cd build
cmake -G "Visual Studio 17 2022" -A x64 ..
cmake --build . --config Release
```

The compiler executable will be placed at `build/Release/hydrogenc.exe` (or the
corresponding configuration folder).

## Using the Compiler

Basic usage:

```
hydrogenc <file.hy> [options]
```

Options:

* `-o <file>` – set output executable path (default: `<input>.exe`).
* `--emit-ir <file>` – dump generated LLVM IR to a file.
* `--emit-obj <file>` – keep the intermediate COFF object file.
* `--lld <path>` – explicit path to `lld-link.exe`.
* `-v` / `--verbose` – print pipeline steps.

Example:

```
# Compile and run the sample program
hydrogenc ..\tests\Test.hy -o Test.exe -v
Test.exe
```

Expected output:

```
1
```

## Testing

CTest is configured to compile and execute the sample program. From the build
folder:

```
ctest -C Release -V
```

(Ensure you can execute Windows binaries produced by the compiler on your system.)

## Project Layout

```
src/              # Compiler sources (frontend, IR generation, runtime glue)
cmake/            # Custom CMake find scripts
tests/            # Sample Hydrogen C program + CTest script
CMakeLists.txt    # Build configuration
README.md         # This document
```

## Design Notes

* The parser is a hand-written recursive descent parser following the grammar in
  the project brief.
* Semantic analysis enforces static typing, declaration-before-use, and validates
  `Function main()`.
* Code generation targets `x86_64-pc-windows-msvc`, emitting COFF objects with
  LLVM's `TargetMachine` APIs.
* Linking is performed via `lld-link`, invoked as a subprocess. The generated
  runtime defines a custom entry point that calls user `main()` and then
  `ExitProcess`.
