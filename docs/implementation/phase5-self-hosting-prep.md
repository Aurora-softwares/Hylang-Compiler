# Phase 5 Self-Hosting Preparation

Phase 5 prepares Hydrogen to implement its own compiler incrementally while keeping the C++ bootstrap compiler as the trusted implementation.

## Bootstrap Compiler Contract

The C++ compiler currently flows through these layers:

- lexer: source text to tokens with file/line/column locations
- parser: tokens to syntax declarations, statements, and expressions with recovery diagnostics
- semantic model: namespaces, types, members, builtins, generics, inheritance, interfaces, structs, and primitive types
- binder/type checker: syntax to bound IR with overload resolution, conversions, control-flow checks, and diagnostics
- execution backends: interpreter and C emitter share the same bound IR
- runtime: managed strings/arrays/objects, GC, unsafe/manual-memory helpers, file/console/test builtins, and source-mapped runtime failures

The Phase 5 Hydrogen frontend mirrored the lexer/parser side only. Phase 6 now extends that workspace with the first binding, IR, runtime-contract, and direct native codegen projects, but the C++ bootstrap compiler remains the trusted stage0 implementation.

## Hydrogen Proof Workspace

The proof workspace lives at `samples/self_hosting`:

- `Hydrogen.Compiler.Core`: `SourceText`, `TextSpan`, `TextLocation`, `Diagnostic`, and `DiagnosticBag`
- `Hydrogen.Compiler.Syntax`: `SyntaxKind`, `SyntaxToken`, `SyntaxNode`, `SyntaxTree`, `Lexer`, and `Parser`
- `Hydrogen.Compiler.IR`: first compiler IR object model
- `Hydrogen.Compiler.Binding`: first Hydrogen-owned checking path
- `Hydrogen.Compiler.RuntimeModel`: native runtime contract notes
- `Hydrogen.Compiler.CodeGen.X64`: direct Linux x64 ELF proof backend
- `Hydrogen.Compiler.Cli`: `tokens <file>`, `parse <file>`, `check <file>`, and `compile <file> -o <output>` commands
- `Hydrogen.Compiler.Tests`: self-hosting preparation regression tests

The parser prototype covers usings, namespaces, classes, structs, interfaces, enums, members, parameters, blocks, statements, and core expressions including calls, member access, indexing, object/array creation, casts-shaped syntax, `sizeof`, `stackalloc`, and unsafe blocks.

## Phase Boundary

Phase 5 is complete. Phase 6 is in progress: the current native path can emit a tiny Linux x64 ELF directly from Hydrogen code for a `System.Console.WriteLine("...")` proof program. Full self-hosting still requires the managed runtime clone, broad semantic binding, native codegen expansion, and stage1/stage2 comparison before promotion.
