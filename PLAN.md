# Hylang Bootstrap Plan

## Summary
- Build Hylang as a C++ bootstrap compiler/runtime with C#-inspired syntax, a .NET-like standard library surface, and a long-term path to becoming a primary language for Aura OS.
- Deliver early script execution with `hyrun`, then add `hyc` to build host-native console executables and libraries on Windows, Linux, and macOS.
- Use a hybrid memory model: managed heap by default with the current bootstrap runtime now, then integrate an external GC library before adding explicit low-level `unsafe` features.
- Reach a stable typed compiler plus C backend first, then start a self-hosted compiler in `.hy`, and only after that add a native x64 backend for Aura OS.

## Checklist Status
- [x] C++ bootstrap compiler/runtime with C#-inspired `.hy` syntax
- [x] `hyrun` direct script/project execution in the terminal
- [x] `hyc build` for host-native executables and static libraries
- [x] `lexer -> parser -> AST -> binder -> type checker -> bound IR` pipeline shared by interpreter and C emitter
- [x] Core OO subset validated: namespaces, classes, fields, constructors, methods, access modifiers, static members, locals, `if`, `while`, `return`, and basic expressions
- [x] Minimal `.hyproj` manifests with source and project references
- [x] `System.Console.WriteLine(...)`, strings, arrays, and command-line argument handling (`args.Length`)
- [x] Multi-file project execution and library artifact generation
- [x] Negative diagnostics for missing `Main`, duplicate symbols, unresolved `using`, wrong argument types, invalid return types, and inaccessible private members
- [x] Managed allocations validated across constructors, method calls, and loops in both interpreter and emitted C output
- [ ] External cross-platform GC library integration
- [ ] `unsafe` blocks, pointers, stack allocation, and manual allocation APIs
- [ ] Self-hosted Hylang compiler written in `.hy`
- [ ] Native x64 backend and Aura OS runtime/ABI layer

## Key Changes
- Language surface:
  - Keep `.hy` as the source extension and keep the current C#-like style valid, including `using`, `namespace`, `class`, and `System.Console.WriteLine(...)`.
  - Support in v1: fields, constructors, methods, access modifiers, `static` members, local variables, `if`, `while`, `return`, basic expressions, `args.Length`, and `public static void Main(string[] args)`.
  - Defer generics, interfaces, exceptions, async, and top-level statements until after the core compiler and project model are stable.
- Toolchain:
  - Implement `lexer -> parser -> AST -> binder/name resolution -> type checker -> typed IR`.
  - Use the typed IR as the shared contract for both execution modes so interpreter work is reused by later compilers.
  - Provide `hyrun <file.hy> [args...]` for direct script/program execution through an interpreter.
  - Provide `hyc build <file.hy | *.hyproj>` for console executables and `hyc build <*.hyproj> --target lib` for libraries.
- Project/runtime model:
  - Introduce a minimal `.hyproj` manifest with `name`, `type` (`exe` or `lib`), `sources`, and `references`.
  - Keep the public standard library under `System.*`, starting with `System.Console`, strings, arrays, and argument handling.
  - Use the current bootstrap managed runtime in v1: reference-managed interpreter objects plus tracked process-lifetime allocations in emitted C.
  - Add low-level features in a later milestone: `unsafe` blocks, pointers, stack allocation, and manual allocation APIs.
- Roadmap:
  - Phase 1: interpreter-driven `Hello, World!` and core OO subset.
  - Phase 2: source-to-C backend that emits portable C plus runtime shims, then uses the host C toolchain to produce host-native binaries and libraries.
  - Phase 3: self-hosted Hylang compiler written in `.hy`.
  - Phase 4: native x64 backend and Aura OS runtime/ABI layer.

## Test Plan
- `tests/hello_world.hy` runs via `hyrun` and prints exactly `Hello, World!`.
- The same source builds via `hyc build` into a host-native executable that prints the same output.
- A small library project builds successfully and is referenced from an executable project.
- Multi-file namespace/class programs parse and type-check correctly.
- Negative tests cover missing `Main`, duplicate symbols, unresolved `using`, wrong argument types, invalid return types, and private access violations.
- Managed allocations survive method calls and loops.
- C backend output builds cleanly with the supported host toolchain and matches interpreter behavior for the same test corpus.
- When unsafe features land, add compiled-mode tests for pointers, stack allocation, and explicit manual allocation/free behavior.

## Assumptions
- Phase 2 uses a source-to-C backend because it best fits your goals of direct CLI use plus portable native binaries.
- The first binary-producing release is host-native only; broad cross-compilation from one host is deferred.
- Early execution remains class-based with `Program.Main(...)`; top-level statements come later.
- The first shipping scope is console applications and libraries, not GUI packaging.
- Bootstrap accessibility semantics are currently: `public` everywhere, `private` within the declaring class, `internal` within the current compilation, and `protected` as same-class until inheritance is added.
