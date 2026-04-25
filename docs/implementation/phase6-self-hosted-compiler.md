# Phase 6 Self-Hosted Compiler

Phase 6 is the real self-hosting effort. The C++ compiler remains the trusted stage0 builder and oracle while the Hydrogen-written compiler grows into a complete stage1 compiler.

## Current Implementation

The Phase 6 foundation lives in `samples/self_hosting`:

- `Hydrogen.Compiler.Binding`: first Hydrogen-owned checker path
- `Hydrogen.Compiler.IR`: first typed IR-style program model
- `Hydrogen.Compiler.RuntimeModel`: native runtime contract surface
- `Hydrogen.Compiler.CodeGen.X64`: direct Linux x64 ELF byte writer
- `Hydrogen.Compiler.Cli`: adds `check`, `compile`, and a reserved `stage-compare` interface

The current native backend is intentionally tiny. It recognizes a `System.Console.WriteLine("...")` proof program, lowers it to a small IR object, and writes a Linux x64 ELF executable directly from Hydrogen code. This path does not emit C and does not call a C compiler, assembler, or linker.

## Commands

```bash
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- check tests/phase6/native_hello.hy
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- compile tests/phase6/native_hello.hy -o build/native_hello
chmod +x build/native_hello
./build/native_hello
```

Expected output from the generated executable:

```text
Hydrogen native hello
```

## Remaining Work

Phase 6 is not complete until Hydrogen can compile itself. The remaining major work is:

- expand binding/type checking beyond the tiny proof subset
- add the managed runtime clone for strings, arrays, classes, static fields, calls, and file IO
- expand Linux x64 codegen to compiler-shaped programs
- build stage1 with the C++ bootstrap
- use stage1 to build stage2
- compare stage1/stage2 diagnostics and runtime behavior on a shared corpus

The bootstrap compiler should stay in-tree after Phase 6 as the historical seed and fallback.
