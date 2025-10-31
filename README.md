# Hydrogen C Compiler (`hydrogenc`)

Hydrogen C is a tiny experimental C-like language that compiles directly to native Windows PE/COFF executables without using the Microsoft CRT. The compiler is implemented in modern C++20 on top of LLVM and links programs by driving `lld-link`.

## Requirements

* Windows 10/11 x64
* Visual Studio 2022 (Desktop development with C++)
* CMake 3.16+
* Prebuilt LLVM 16+ for Windows (make sure the package includes `lld-link`)

## Environment setup

1. Install LLVM from the official prebuilt archive. Extract it to `C:\LLVM` (or any directory of your choice).
2. Open an "x64 Native Tools Command Prompt for VS".
3. Point `LLVM_DIR` at the LLVM CMake configuration directory and make sure `lld-link.exe` is on `PATH`:

   ```bat
   set LLVM_DIR=C:\LLVM\lib\cmake\llvm
   set PATH=C:\LLVM\bin;%PATH%
   ```

## Configure & build

```bat
cmake -S . -B build -G "Ninja"
cmake --build build --config Release
```

The `hydrogenc` executable will be located in `build` (or `build\Release` when using multi-config generators).

## Running the compiler

Basic usage:

```bat
hydrogenc source.hy
```

Options:

* `-o <path>` — override output executable name (`source.exe` by default)
* `--emit-ir <path>` — dump the generated LLVM IR to a file
* `--emit-obj <path>` — keep the intermediate COFF object file
* `-v` — verbose mode (prints each pipeline stage)

Example:

```bat
hydrogenc tests\Test.hy -o out\Test.exe -v
out\Test.exe
```

Expected output for `tests\Test.hy`:

```
1
```

## Testing

CTest is configured to build and run the sample program:

```bat
cmake --build build --config Release
ctest --test-dir build --config Release -V
```

## Project structure

```
CMakeLists.txt
cmake/FindLLVM.cmake
src/
  ast.hpp             – AST node definitions
  codegen.cpp/.hpp    – LLVM IR generation
  diag.cpp/.hpp       – diagnostics with caret underlines
  lexer.cpp/.hpp      – lexical analysis
  linker.cpp/.hpp     – thin wrapper for invoking lld-link
  main.cpp            – command-line driver
  object_emit.cpp/.hpp– emits COFF object files via LLVM TargetMachine
  parser.cpp/.hpp     – recursive-descent parser
  sema.cpp/.hpp       – semantic analysis and symbol tables
  tokens.hpp          – token definitions
  util.cpp/.hpp       – shared utilities (file IO, string helpers)
  winrt.cpp/.hpp      – Win32 runtime helpers injected into generated modules

tests/
  Test.hy             – sample program
  CTest.cmake         – CTest driver script
```

## Language quick reference (v0.1)

* Single built-in type: `Int`
* Global variables (`Var Int X = 1;`)
* Functions declared with `Function`
* Statements: variable declarations, expression statements, `Return`
* Expressions: identifiers, integer literals, assignments, function calls, parentheses
* Built-in `Print(Int)` writes to stdout using the Win32 API (`GetStdHandle` + `WriteFile`)

Keywords are case-insensitive; identifiers are case-sensitive.

Enjoy experimenting with Hydrogen C!
