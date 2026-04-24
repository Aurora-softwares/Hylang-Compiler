# Hylang

[![Language](https://img.shields.io/badge/language-C%2B%2B20-blue?style=flat-square)](https://en.cppreference.com/w/cpp/20)
[![Language](https://img.shields.io/badge/language-Hydrogen-blue?style=flat-square)](https://en.cppreference.com/w/cpp/20)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20x64-lightgrey?style=flat-square)](#build)
[![Phase](https://img.shields.io/badge/phase-4%20%E2%80%93%20Tooling%20and%20Workflow-orange?style=flat-square)](ROADMAP.md)
[![Docs](https://img.shields.io/badge/docs-online-brightgreen?style=flat-square)](https://aurora-softwares.github.io/Hylang-Docs/)

A C#-inspired systems programming language for [Australis OS](https://github.com/Aurora-Softwares) and general x64 systems.

---

Hylang has a full compiler pipeline — lexer, parser, AST, binder, type checker, and a bound IR shared by both the interpreter and the C code emitter. The current bootstrap is well past the toy-parser stage: it can run or compile multi-file projects, manage workspaces, and exercise a growing SDK-style workflow through the `hy` CLI.

## Tools

| Tool        | Purpose                                                                 |
|-------------|-------------------------------------------------------------------------|
| `hy`        | Primary workflow CLI for scaffolding, building, running, testing, formatting, checking, and packaging |
| `hyrun`     | Compatibility runner for direct `.hy` or `.hyproj` execution            |
| `hyc build` | Compatibility compiler path for native executables and static libraries via the C backend |

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
- General managed arrays via `new T[count]`
- String concatenation across `string`, `int`, and `bool`
- Array and string `.Length`, array indexing, string character indexing
- Minimal bootstrap `System.Collections.List<T>`
- `System.Console.Write` / `WriteLine` and `System.IO.File` text read/write/exists
- `System.IO.File.ReadAllBytes` / `WriteAllBytes`
- Bootstrap `System.Runtime.Buffer` for safe byte-buffer allocation, slicing, copying, and explicit free semantics
- Bootstrap `System.Runtime.BinaryPrimitives` for 16-bit, 32-bit, and 64-bit little-endian/big-endian reads and writes
- Bootstrap `System.Testing.Assert` and `System.Convert.ToInt32`

## Workflow

Phase 4 is now underway with a real SDK-style workflow:

- `hy new app|lib|tool|test|workspace <name>`
- `hy build <target> [--target exe|lib] [-o output] [--debug]`
- `hy run <target> [-- args...]`
- `hy test [target]`
- `hy fmt <path...> [--check]`
- `hy check <target> [--json]`
- `hy package pack <target> [-o output]`
- `hy package add <target> <path>`

Current workflow support includes:

- v2 `.hyproj` manifests with workspace support
- backward-compatible loading of older v1 manifests
- local path dependencies
- build caching under `.hylang/cache/`
- simple `.hymap.json` debug/source-map files from `hy build --debug`
- warning-bearing `hy check --json` output with severity/file/line/column/message entries
- light VS Code assets under `tools/vscode/hylang`
- `samples/hexlab` as the current showcase workspace for the full build/test/package loop

The remaining low-level Phase 4 systems surface is still in progress. Safe bootstrap `Buffer` support is shipped, but executable `unsafe`, pointers, `stackalloc`, `sizeof`, and manual memory APIs are not shipped yet.

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
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hy_main.cpp -o build/hy
```

## Quick start

```bash
# Run a script directly through the new CLI
build/hy run tests/hello_world.hy

# Compile to an executable
build/hy build tests/hello_world.hy -o build/hello_world
./build/hello_world

# Check and format a project
build/hy check tests/projects/app/App.hyproj --json
build/hy fmt --check tests samples

# Build and run a multi-file project
build/hy build tests/projects/app/App.hyproj -o build/demo_app
./build/demo_app

# Run the current showcase workspace
build/hy build samples/hexlab/HexLab.hyproj
build/hy test samples/hexlab/HexLab.hyproj
build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- inspect samples/hexlab/demo.bin
build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- dump samples/hexlab/demo.bin 8
build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- search samples/hexlab/demo.bin 89504E47

# Emit debug metadata alongside generated output
build/hy build tests/hello_world.hy -o build/hello_world_debug --debug

# Compatibility shims still work
build/hyrun samples/mini_frontend_model/MiniFrontendModel.hyproj
build/hyc build tests/projects/mathlib/Math.hyproj --target lib -o build/libmathlib.a
```

See the Phase 4 tooling page in Hylang-Docs: <https://aurora-softwares.github.io/Hylang-Docs/implementation/phase4-tooling-slice.html>.

## Editor Assets

Light VS Code integration lives in [`tools/vscode/hylang`](tools/vscode/hylang). It currently includes:

- syntax highlighting for `.hy` and `.hyproj`
- snippets
- task and launch templates
- a JSON-diagnostic wrapper for `hy check --json`
- format-on-save settings templates

This is intentionally lighter than a full language server.

## Runtime model

- The interpreter keeps bootstrap reference-managed runtime objects while matching the same visible string/array semantics as compiled mode.
- The C backend now emits an in-tree non-moving mark-sweep GC with precise emitted root frames and managed string/array objects.
- `HYLANG_GC_STRESS=1` forces collection at runtime safe points, and `HYLANG_GC_THRESHOLD=<bytes>` lowers the compiled-runtime collection threshold for stress/debugging.

## Roadmap

Hylang is developed in phases toward a self-hosted compiler and first-class support for Australis OS userland. Runtime foundation work from Phase 3 is landed, and the active zone is now **Phase 4 — Tooling and Developer Workflow**, with executable unsafe/manual-memory systems work still pending.

See [ROADMAP.md](ROADMAP.md) for the full plan.
