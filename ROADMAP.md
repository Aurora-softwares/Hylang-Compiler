# Hydrogen development roadmap

This document describes future work. For available language features and commands, use the [README](README.md), [language reference](https://aurora-softwares.github.io/Hylang-Docs/), and [native compiler guide](samples/self_hosting/README.md).

## Foundation

The C++ SDK includes an interpreter, C backend, extended object/type system, unsafe/manual memory, projects/workspaces, local packages, formatting/checking, and lightweight editor services.

The Hydrogen-written compiler emits Linux x86-64 ELF directly, binds executable project references, supports the class/string/array/runtime subset needed by its own sources, and passes repeated native self-compilation with behavioral checks and identical stage 2/3 compiler/application artifacts. These facts apply to the native subset, not the entire SDK language and workflow surface.

## Native language and SDK parity

- Implement inheritance, virtual/interface dispatch, struct value semantics, and generics in executable native IR/code generation.
- Add overloads, static fields, `for`, wider numerics, exceptions, and remaining runtime APIs.
- Retain clean failure for unsupported programs and add cross-backend semantic regressions.
- Preserve node spans through AST/binding/IR for precise diagnostics.
- Improve collector allocation density, compiler memory use, and generated-code performance.
- Port or replace SDK scaffolding, run/test/fmt/check tooling, workspace/package resolution, and LSP services.
- Migrate build/tests to retained verified native seeds before deciding whether to retire C++ bootstrap sources.

## Standard library

Expand compiler/runtime builtins into reusable Hydrogen-written libraries: collections, text/encoding/builders, streams/filesystems, paths, process/environment APIs, numerics, serialization, and test support. The [stdlib design plan](https://github.com/Aurora-Softwares/Hylang-Stdlib) describes proposed layers, not currently installable packages.

## Backend and platform work

Direct Linux x64 code generation is implemented. Additional work includes object files, linker/external ABI integration, debug information, cross-compilation, and additional platform runtime/startup implementations. Keep the C backend useful as a portability route while parity develops.

UEFI, freestanding execution, Australis userland, and kernel-adjacent use require explicit target contracts, memory ownership, layout/ABI support, and suitable runtime profiles. See [OS_ROADMAP.md](OS_ROADMAP.md); Linux executables do not establish support for those targets.

## Tooling and packages

Improve LSP navigation/completion/indexing, debugger integration, and diagnostic fidelity. Extend local package workflows when needed; hosted registries, authentication/signing, remote downloads, and version-range solving are not implemented.

## Development history

The original phases covered the bootstrap foundation, language hardening, object/type expansion, SDK runtime, local developer workflows, Hydrogen frontend libraries, and native self-hosting. Their implementation notes now describe the actual [SDK/compiler architecture](docs/implementation/phase5-self-hosting-prep.md) and [native bootstrap process](docs/implementation/phase6-self-hosted-compiler.md) rather than a progress checklist.

Future work should retain runnable examples, meaningful regressions, clear feature boundaries, and repeatable compiler generations.
