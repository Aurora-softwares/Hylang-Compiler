# Compiler workspace architecture

The Hydrogen compiler lives in `samples/self_hosting` in Hylang-Compiler. Its executable project is `Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj`; the workspace manifest additionally includes its tests.

| Project | Responsibility |
| --- | --- |
| `Hydrogen.Compiler.Core` | Source text, spans, locations, diagnostic storage |
| `Hydrogen.Compiler.Syntax` | Lexer, outline parser, AST parser, syntax declarations/statements/expressions |
| `Hydrogen.Compiler.IR` | Executable module, types, fields, methods, structured operations |
| `Hydrogen.Compiler.Binding` | Project-aware type resolution and body checking |
| `Hydrogen.Compiler.RuntimeModel` | Native runtime contracts |
| `Hydrogen.Compiler.CodeGen.X64` | Method-body lowering, runtime emission, ELF image construction |
| `Hydrogen.Compiler.Cli` | Tokens, parse, check, compile, build, artifact comparison |
| `Hydrogen.Compiler.Tests` | Compiler library regressions |

The lexer preserves source positions. The CLI `parse` command uses an outline view for stable syntax dumps; this is distinct from the AST parser and executable IR used by `check`/compilation. Parsing a construct does not establish its native executable support.

The binder registers a complete project/reference closure before checking declarations and bodies. Each file keeps its namespace/import context. Declared types and resolved calls become canonical names in IR; methods carry bodies with allocations, fields, calls, casts, indexing, returns, branches, and loops.

The x64 backend consumes executable IR and emits reachable methods and a native runtime into one Linux ELF. See [native compilation and bootstrapping](phase6-self-hosted-compiler.md) for the internal convention and rebuild checks.

The SDK is a separate implementation: its interpreter and C emitter share the C++ bound semantic model. SDK-only generics, inheritance, struct semantics, overloads, and tooling are not inferred to exist in the Hydrogen backend merely because SDK builds accept its compiler sources.
