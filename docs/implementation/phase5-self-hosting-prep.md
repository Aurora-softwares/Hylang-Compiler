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

The Phase 5 Hydrogen frontend mirrors the lexer/parser side only. It deliberately does not bind, type-check, lower IR, generate code, or replace the bootstrap compiler.

## Hydrogen Proof Workspace

The proof workspace lives at `samples/self_hosting`:

- `Hydrogen.Compiler.Core`: `SourceText`, `TextSpan`, `TextLocation`, `Diagnostic`, and `DiagnosticBag`
- `Hydrogen.Compiler.Syntax`: `SyntaxKind`, `SyntaxToken`, `SyntaxNode`, `SyntaxTree`, `Lexer`, and `Parser`
- `Hydrogen.Compiler.Cli`: `tokens <file>` and `parse <file>` commands
- `Hydrogen.Compiler.Tests`: self-hosting preparation regression tests

The parser prototype covers usings, namespaces, classes, structs, interfaces, enums, members, parameters, blocks, statements, and core expressions including calls, member access, indexing, object/array creation, casts-shaped syntax, `sizeof`, `stackalloc`, and unsafe blocks.

## Phase Boundary

Phase 5 is complete when the Hydrogen compiler libraries build, test, format-check, check, and pass golden token/parse fixtures. Phase 6 starts when these libraries are used as the foundation for a real self-hosted compiler pipeline with binding, typed IR, and backend integration.
