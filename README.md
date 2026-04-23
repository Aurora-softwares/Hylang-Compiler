# Hylang Compiler

Hylang is a C#-inspired programming language bootstrap aimed at Aura OS and general x64 systems.
This repository now includes:

- `hyrun` for direct terminal execution of `.hy` files or `.hyproj` projects
- `hyc build` for compiling host-native console executables and static libraries through a C backend
- a real compiler pipeline with lexing, parsing, symbol binding, type checking, and a bound IR shared by the interpreter and emitter

## Current language subset

The current bootstrap supports:

- `using`, `namespace`, `class`
- `public`, `private`, `internal`, and `protected` access modifiers with bootstrap semantics
- static methods and static fields
- fields, constructors, methods
- `int`, `bool`, `string`, and `string[]`
- local variables, `if`, `while`, `for`, `break`, `continue`, and `return`
- object creation, method calls, field access, assignment
- array length access through `.Length` and string length access through `string.Length`
- array element access such as `args[0]`
- string concatenation through `+` for string/int/bool combinations
- `System.Console.Write(...)` and `System.Console.WriteLine(...)` for `string`, `int`, and `bool`
- `System.IO.File.Exists(...)`, `ReadAllText(...)`, and `WriteAllText(...)`

Bootstrap accessibility semantics:
- `public` is visible everywhere
- `private` is restricted to the declaring class
- `internal` is visible within the current compilation
- `protected` is currently same-class only until inheritance exists

## Runtime model

- The interpreter uses reference-managed runtime objects.
- The generated C backend uses tracked managed allocations that live for the process lifetime and are released at shutdown.
- External GC library integration is still a follow-up item rather than part of the current bootstrap.

## Build

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

If `cmake` is unavailable, you can build the two tools directly with a C++20 compiler:

```bash
mkdir -p build
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyrun_main.cpp -o build/hyrun
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyc_main.cpp -o build/hyc
```

## Run a script

```bash
build/hyrun tests/hello_world.hy
```

## Build an executable

```bash
build/hyc build tests/hello_world.hy -o build/hello_world
./build/hello_world
```

## Build a project

```bash
build/hyc build tests/projects/app/App.hyproj -o build/demo_app
./build/demo_app
```

## Sample text tool

```bash
printf 'Hello from Hylang' > build/sample_input.txt
build/hyrun samples/text_report/TextReport.hyproj build/sample_input.txt build/sample_report.txt
cat build/sample_report.txt
```

## Build a library

```bash
build/hyc build tests/projects/mathlib/Math.hyproj --target lib -o build/libmathlib.a
```
