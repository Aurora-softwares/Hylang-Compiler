# Hylang

[![Language](https://img.shields.io/badge/language-C%2B%2B20-blue?style=flat-square)](https://en.cppreference.com/w/cpp/20)
[![Language](https://img.shields.io/badge/language-Hydrogen-blue?style=flat-square)](https://en.cppreference.com/w/cpp/20)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20x64-lightgrey?style=flat-square)](#build)
[![Phase](https://img.shields.io/badge/phase-3%20%E2%80%93%20Runtime%20and%20Memory%20Model-orange?style=flat-square)](ROADMAP.md)
[![Docs](https://img.shields.io/badge/docs-online-brightgreen?style=flat-square)](https://aurora-softwares.github.io/Hylang-Docs/)

A C#-inspired systems programming language for [Australis OS](https://github.com/Aurora-Softwares) and general x64 systems.

---

Hylang has a full compiler pipeline — lexer, parser, AST, binder, type checker, and a bound IR shared by both the interpreter and the C code emitter. The current bootstrap is past the toy-parser stage and supports non-trivial multi-file console tools.

## Tools

| Tool        | Purpose                                                          |
|-------------|------------------------------------------------------------------|
| `hyrun`     | Interpret and run `.hy` scripts or `.hyproj` projects directly   |
| `hyc build` | Compile to a native executable or static library via a C backend |

## Language subset

```text
using  namespace  class  struct  interface  enum
public  private  internal  protected  static  virtual  override
int  bool  string  string[]  null  var
if  else  while  for  break  continue  return
new  this  base  :  +  -  *  /  %  ==  !=  <  <=  >  >=  &&  ||  !
```

- Fields, constructors, and methods — with overloading
- Single inheritance with inherited member lookup, `protected` access, `base(...)`, and `base.Member`
- `virtual` / `override` dispatch for non-static instance methods
- Namespace-scope interfaces, interface inheritance, and interface dispatch
- Namespace-scope structs with bootstrap by-value semantics and interface boxing
- Generic classes, interfaces, and methods, plus `var` local inference
- Object creation, method calls, field access, and assignment
- String concatenation across `string`, `int`, and `bool`
- Array and string `.Length`, array indexing, string character indexing
- `System.Console.Write` / `WriteLine` and `System.IO.File` read/write/exists

See the [full language reference](https://aurora-softwares.github.io/Hylang-Docs/) for details on every feature.

## Build

### With CMake (recommended)

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

### Without CMake

```bash
mkdir -p build
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyrun_main.cpp -o build/hyrun
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyc_main.cpp -o build/hyc
```

## Quick start

```bash
# Run a script directly
build/hyrun tests/hello_world.hy

# Compile to an executable
build/hyc build tests/hello_world.hy -o build/hello_world
./build/hello_world

# Compile a multi-file project
build/hyc build tests/projects/app/App.hyproj -o build/demo_app
./build/demo_app

# Run the Phase 2 proof project
build/hyrun samples/mini_frontend_model/MiniFrontendModel.hyproj

# Build a static library
build/hyc build tests/projects/mathlib/Math.hyproj --target lib -o build/libmathlib.a
```

## Runtime model

- The interpreter uses reference-managed runtime objects.
- The C backend emits tracked managed allocations that live for the process lifetime and are released at shutdown.
- A proper GC integration is planned for Phase 3.

## Roadmap

Hylang is developed in phases toward a self-hosted compiler and first-class support for Australis OS userland. **Phase 2 — Core Language Expansion** is now complete, and the active zone is **Phase 3 — Runtime and Memory Model**.

See [ROADMAP.md](ROADMAP.md) for the full plan.
