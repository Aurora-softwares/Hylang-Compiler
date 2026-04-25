# Hylang

[![Language](https://img.shields.io/badge/language-C%2B%2B20-blue?style=flat-square)](https://en.cppreference.com/w/cpp/20)
[![Language](https://img.shields.io/badge/language-Hydrogen-blue?style=flat-square)](https://en.cppreference.com/w/cpp/20)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20x64-lightgrey?style=flat-square)](#build)
[![Phase](https://img.shields.io/badge/phase-5%20%E2%80%93%20Self--Hosting%20Preparation-blue?style=flat-square)](ROADMAP.md)
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
- Executable `unsafe { ... }`, pointer types, address-of, dereference, pointer indexing/arithmetic, `stackalloc`, and `sizeof`
- Bootstrap `System.Runtime.Memory` for explicit allocation, free, copy, set, and compare
- Bootstrap `System.Runtime.BinaryPrimitives` for 16-bit, 32-bit, and 64-bit little-endian/big-endian reads and writes
- Bootstrap `System.Testing.Assert` and `System.Convert.ToInt32`

## Workflow

Phase 4 now has a local-first SDK-style workflow:

- `hy new app|lib|tool|test|workspace <name>`
- `hy build <target> [--target exe|lib] [-o output] [--debug]`
- `hy run <target> [-- args...]`
- `hy test [target]`
- `hy fmt <path...> [--check]`
- `hy check <target> [--json]`
- `hy package pack <target> [-o output]`
- `hy package add <target> <path>`
- `hy package init-registry <path>`
- `hy package publish <project.hyproj> --registry <path>`
- `hy package search <query> --registry <path>`
- `hy package install <target.hyproj> <package-id> [--version <version>] --registry <path>`
- `hy lsp`

Current workflow support includes:

- v2 `.hyproj` manifests with workspace support
- backward-compatible loading of older v1 manifests
- local path dependencies
- filesystem-backed local package registries
- build caching under `.hylang/cache/`
- simple `.hymap.json` debug/source-map files from `hy build --debug`
- warning-bearing `hy check --json` output with severity/file/line/column/message entries
- compiled runtime failures that report Hylang file/line/column context for the executing statement
- lightweight JSON-RPC language-server support through `hy lsp`
- VS Code assets under `tools/vscode/hylang`
- `samples/hexlab` as the systems showcase workspace
- `samples/sdk_demo` as the Phase 4 tooling/package/LSP proof workspace
- `samples/self_hosting` as the Phase 6 Hydrogen compiler workspace

The low-level Phase 3 closeout slice is executable in both `hyrun` and compiled output: raw `System.Runtime.Memory`, `unsafe` blocks, checked pointer indexing/arithmetic, `stackalloc`, `sizeof`, and `Buffer.DangerousData()` all run today. Phase 4 is complete at bootstrap scope with a local package registry, lightweight language server, expanded diagnostics, and a dedicated SDK demo workspace. Phase 5 is complete at prototype scope, and Phase 6 has started: Hydrogen now owns the first checker/IR/runtime-contract/codegen projects and can emit a tiny Linux x64 ELF executable directly from Hydrogen code.

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

# Exercise the SDK/package workflow proof
build/hy build samples/sdk_demo/SdkDemo.hyproj
build/hy test samples/sdk_demo/SdkDemo.hyproj
build/hy package init-registry build/local-registry
build/hy package publish samples/sdk_demo/SdkDemo.Core/SdkDemo.Core.hyproj --registry build/local-registry
build/hy package search SdkDemo --registry build/local-registry

# Exercise the Phase 6 self-hosted compiler foundation
build/hy build samples/self_hosting/Hydrogen.Compiler.hyproj
build/hy test samples/self_hosting/Hydrogen.Compiler.hyproj
build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- tokens tests/hello_world.hy
build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- parse tests/hello_world.hy
build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- check tests/phase6/native_hello.hy
build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- compile tests/phase6/native_hello.hy -o build/native_hello
chmod +x build/native_hello
./build/native_hello

# Emit debug metadata alongside generated output
build/hy build tests/hello_world.hy -o build/hello_world_debug --debug

# Debug builds keep .hymap metadata, and runtime failures point back to .hy locations
build/hy build tests/runtime_fail_location.hy -o build/runtime_fail_location --debug
./build/runtime_fail_location

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
- lightweight `hy lsp` integration for diagnostics, symbols, hover, and formatting
- format-on-save settings templates

This is intentionally lighter than a full semantic IDE experience: completion, go-to-definition, references, rename, semantic tokens, and workspace indexing are still later work.

## Runtime model

- The interpreter keeps bootstrap reference-managed runtime objects while matching the same visible string/array semantics as compiled mode.
- The C backend now emits an in-tree non-moving mark-sweep GC with precise emitted root frames and managed string/array objects.
- Raw manual memory and pointer operations now execute in both modes through checked runtime helpers.
- Compiled runtime failures now carry Hylang file/line/column context instead of only raw generated-runtime messages.
- `HYLANG_GC_STRESS=1` forces collection at runtime safe points, and `HYLANG_GC_THRESHOLD=<bytes>` lowers the compiled-runtime collection threshold for stress/debugging.

Current bootstrap boundaries:

- `Buffer.DangerousData()` currently bridges into raw memory through a checked bootstrap path rather than a fully native unmanaged backing store.
- Non-zero integer-to-pointer casts are intentionally rejected in the bootstrap runtime.
- Pointer loads/stores are implemented for primitive, enum, and `bool` element types; broader unmanaged-struct pointer materialization is still a follow-on cleanup item.

## Roadmap

Hylang is developed in phases toward a self-hosted compiler and first-class support for Australis OS userland. Phase 6 is now in progress under `samples/self_hosting`; the current native path can already write a tiny Linux x64 ELF directly from Hydrogen, while full self-hosting still requires binder/runtime/backend expansion and stage1/stage2 comparison.

See [ROADMAP.md](ROADMAP.md) for the full plan.
