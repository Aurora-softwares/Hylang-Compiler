# Hylang Roadmap

This document is the rough long-range plan for Hylang: from the current bootstrap compiler and basic scripts, through self-hosting, to a full standard library and an OS stack that can be built primarily in Hylang.

It is intentionally directional rather than rigid. The order matters more than the dates.

## Vision

Hylang should become:

- a C#-like systems language with high-level ergonomics
- capable of both managed application development and low-level OS work
- self-hosted, so the compiler can eventually be written in Hylang itself
- backed by a real standard library, tooling ecosystem, and package/build workflow
- the primary language for Australis OS userland and, over time, larger parts of the OS stack

## Current State

Today the project already has:

- `hy` as the primary workflow CLI for scaffolding, build/run/test/check/fmt/package tasks
- `hyrun` for direct `.hy` and `.hyproj` execution
- `hyc build` for host-native executables and static libraries through a C backend
- v2 `.hyproj` manifests with workspace support and local path dependencies
- a real pipeline: lexer, parser, AST, binder, type checker, and shared bound IR
- classes, structs, interfaces, enums, namespaces, fields, constructors, methods, access modifiers, and static members
- control flow including `if`, `while`, `for`, `break`, `continue`, and `return`
- inheritance, `base(...)`, `base.Member`, `virtual`, `override`, generics, and `var`
- strings, arrays, `.Length`, indexing, basic string concatenation, and console/file builtins
- enough language surface to build compiler-flavored multi-file console tools
- build caching, basic debug/source-map metadata, and JSON diagnostics
- byte-oriented helpers including `ReadAllBytes`, `WriteAllBytes`, bootstrap `BinaryPrimitives`, and `System.Testing.Assert`
- `samples/hexlab` as the current end-to-end workflow showcase

That means Hylang is past the “toy parser” stage and is now in the bootstrap language phase.

## Guiding Principles

- Keep the language usable at every stage. Do not chase advanced features before the basics are solid.
- Do not rush self-hosting. A weak self-hosted compiler is slower progress than a strong bootstrap compiler.
- Keep one typed semantic core shared by all execution modes and backends.
- Add low-level power deliberately, with clear boundaries between safe managed code and unsafe systems code.
- Build the standard library and tooling in parallel with the language, not as an afterthought.

## Phase Snapshot

Checked items reflect the current repo state as of now.

- [x] Phase 0: Bootstrap Foundation is effectively complete enough to move beyond the bootstrap-only stage
- [x] Phase 1: Language Hardening is complete
- [x] Phase 2: Core Language Expansion is complete
- [x] Phase 3: Runtime and Memory Model is complete at bootstrap scope
- [x] Phase 4: Tooling and Developer Workflow is complete at local-first bootstrap scope
- [x] Phase 5: Self-Hosting Preparation is complete at prototype scope
- [ ] Phase 6: Self-Hosted Compiler has not started
- [ ] Phase 7: Full Standard Library has not started in earnest
- [ ] Phase 8: Backend Evolution has not started in earnest
- [ ] Phase 9: Hylang for Australis OS Userland has not started
- [ ] Phase 10: Hylang for System Software and Kernel-Adjacent Code has not started
- [ ] Phase 11: Full OS and Ecosystem Vision remains the long-term destination

## Phase 0: Bootstrap Foundation

Status: largely complete

Goals:

- run simple Hylang programs in the terminal
- build host-native binaries through a portable backend
- prove the core class-based programming model

Checklist:

- [x] `hyrun` can execute `.hy` scripts and `.hyproj` projects
- [x] `hyc build` can build host-native executables
- [x] `hyc build --target lib` can build static libraries
- [x] The compiler has a real frontend and semantic pipeline
- [x] Core OO syntax works: namespaces, classes, fields, constructors, methods, and static members
- [x] Basic control flow works across interpreter and compiled output
- [x] Minimal `System.Console` support exists
- [x] Minimal `System.IO.File` support exists
- [x] Multi-file console tools can be written and run today
- [x] The bootstrap is strong enough to move into language hardening work

Delivered / near-delivered scope:

- script and project execution
- executable and static library output
- core OO syntax
- basic control flow
- minimal `System.Console` and `System.IO.File`
- sample multi-file console tooling

Exit criteria:

- the bootstrap can support non-trivial command-line tools
- interpreter mode and compiled mode behave consistently for the supported subset

## Phase 1: Language Hardening

Status: complete

Goals:

- make the bootstrap language reliable enough for larger tools
- expand the standard library just enough to build real developer utilities
- improve diagnostics and confidence in compiler behavior

Checklist:

- [x] Add `for`, `break`, and `continue`
- [x] Add `string.Length`
- [x] Add basic string concatenation for string/int/bool combinations
- [x] Add `System.Console.Write(...)`
- [x] Add basic `System.IO.File` read/write/exists APIs
- [x] Add array indexing for command-line argument and array workflows
- [x] Add a non-trivial multi-file sample Hylang console tool
- [x] Add negative coverage for new control-flow and builtin misuse cases
- [x] Validate interpreter mode and compiled mode against the new feature set
- [x] Improve parser error recovery so one syntax issue does not cascade as badly
- [x] Harden overload resolution and method/constructor selection rules
- [x] Expand regression coverage further until refactors feel cheap and safe
- [x] Prove the language on at least one medium-sized Hylang tool beyond the current samples

Main work:

- stronger tests across parser, binder, interpreter, and C backend
- more complete expression and statement support
- better diagnostics and error recovery
- more string, array, and file APIs
- cleaner project/reference behavior
- more sample applications written in Hylang

Delivered features:

- `else if` and more loop/test coverage
- constructor and method overloading with ambiguity detection
- full arithmetic, comparison, logical, and unary operators (`-`, `*`, `/`, `%`, `&&`, `||`, `!`)
- basic enums with equality, static fields, and printing
- string character indexing
- modulo operator
- parser error recovery (missing semicolons, bad expressions continue parsing)
- `this`/member semantics
- `token_dump` sample tool (431 lines, 4 files) as proof of medium-sized Hylang programs

Deferred to Phase 2:

- basic inheritance
- library authoring and project-reference quality improvements

Exit criteria:

- Hylang can build a medium-sized console tool cleanly
- regression coverage is broad enough to refactor the compiler without fear

## Phase 2: Core Language Expansion

Status: complete

Milestones delivered:

- basic single inheritance with `class Derived : Base`
- inherited member lookup for fields and methods
- subclass `protected` access
- derived-to-base assignability across locals, fields, parameters, returns, equality, and overload resolution
- implicit and explicit base-constructor chaining across interpreter and compiled output
- `base.Member`, `virtual`, and `override`
- interfaces and interface inheritance
- namespace-scope structs with bootstrap by-value semantics
- generic classes, interfaces, and methods
- `var` local inference
- language-spec notes for the implemented Phase 2 rules
- `mini_frontend_model` as the compiler-flavored proof project

Goals:

- move from “small tool language” to “general-purpose application language”
- fill in the missing object model and type system pieces needed before self-hosting

Checklist:

- [x] Add basic inheritance
- [x] Add inherited member lookup
- [x] Add derived-to-base assignability
- [x] Make `protected` work across subclasses
- [x] Add implicit parameterless base-constructor chaining
- [x] Add `base(...)` constructor chaining and `base.Member`
- [x] Add virtual/override behavior
- [x] Add interfaces
- [x] Decide and implement value-type or struct design
- [x] Add generics
- [x] Improve overload resolution further
- [x] Improve namespace and import resolution behavior
- [x] Add any minimal type inference needed for ergonomic compiler/library code
- [x] Capture the implemented rules in language-spec notes

Main work:

- `base(...)` and `base.Member`
- virtual/override behavior
- interfaces
- structs or value-type design
- generics
- namespaces/import resolution hardening
- richer overload resolution beyond current inheritance-aware matching
- better type inference where appropriate

Supporting work:

- improve symbol tables and type representation
- formalize language spec notes for each feature as it lands

Delivered features:

- `base(...)` constructor initializers and `base.Member` binding
- non-static virtual dispatch with required `override`
- namespace-scope interfaces with interface inheritance and interface dispatch
- namespace-scope structs with zero-initialization, copy semantics, and boxing to interfaces
- invariant generic classes, interfaces, and methods
- `var` local inference for ergonomic compiler-style code
- name resolution by current namespace, imported namespaces, then global namespace, with ambiguity diagnostics
- arity-aware generic type lookup and specialization
- the Hylang-Docs Phase 2 bootstrap spec capturing the implemented rules and deliberate exclusions:
  <https://aurora-softwares.github.io/Hylang-Docs/implementation/phase2-bootstrap-spec.html>
- `samples/mini_frontend_model` proving the language on a small compiler-flavored model

Exit criteria:

- the language can model compiler data structures cleanly
- reusable library code no longer feels awkward or artificially limited
- the proof project runs identically in interpreter and compiled modes

## Phase 3: Runtime and Memory Model

Status: complete at bootstrap scope

Goals:

- define how Hylang manages memory in normal applications
- define how low-level code can opt into more explicit control

Checklist:

- [x] Replace the bootstrap process-lifetime allocation path in compiled output with an in-tree managed runtime
- [x] Define stable runtime object and metadata layout
- [x] Make strings and arrays behave consistently across all backends at the language-semantics level
- [x] Design `unsafe` blocks
- [x] Design pointer support
- [x] Design stack allocation support
- [x] Design manual allocation/free APIs
- [x] Add a safe bootstrap buffer primitive for byte-oriented systems utilities
- [x] Add executable raw memory and unsafe primitives suitable for systems code
- [x] Define the safe/unsafe boundary clearly in docs and compiler rules

Main work:

- replace the bootstrap allocation model with a real cross-platform GC integration
- define object layout and runtime metadata more clearly
- make strings, arrays, and runtime allocations stable across backends
- add a planned low-level model:
  - `unsafe` blocks
  - pointers
  - stack allocation
  - manual allocation APIs
  - raw memory and buffer types

Important design choice:

- managed-by-default should remain the normal experience
- unsafe/system code should be explicit and easy to audit

Delivered foundation:

- compiled output now uses an in-tree non-moving mark-sweep collector
- managed strings and general `T[]` arrays are part of the runtime surface
- `new T[count]` works across interpreter and compiled modes
- bootstrap `System.Collections.List<T>` exists and is proven via `samples/managed_collections`
- bootstrap `System.Runtime.Buffer` now provides safe allocation, slicing, copying, and explicit free semantics
- executable bootstrap `unsafe { ... }`, `T*`, address-of, dereference, pointer indexing/arithmetic, `stackalloc`, `sizeof`, and explicit manual allocation APIs now run in both `hyrun` and compiled mode
- compiled runtime failures for the low-level/runtime surface now report Hylang file/line/column context
- GC stress controls exist for compiled output via `HYLANG_GC_STRESS` and `HYLANG_GC_THRESHOLD`
- the Hylang-Docs runtime pages capture the runtime and unsafe contracts:
  <https://aurora-softwares.github.io/Hylang-Docs/runtime/runtime-model.html>
  <https://aurora-softwares.github.io/Hylang-Docs/runtime/unsafe-design.html>

Bootstrap caveats:

- the language/runtime behavior is aligned across both execution modes, while the interpreter still keeps a bootstrap reference-managed implementation internally
- `Buffer.DangerousData()` still bridges through a checked bootstrap path rather than a fully native unmanaged backing store
- non-zero integer-to-pointer casts remain intentionally rejected in the bootstrap runtime
- unmanaged-struct pointer loads/stores still need broader cleanup beyond primitive, enum, and `bool` element types

Exit criteria:

- ordinary Hylang code has predictable managed behavior
- systems code can reach low-level memory and platform APIs without fighting the language

## Phase 4: Tooling and Developer Workflow

Status: complete at local-first bootstrap scope

Goals:

- make Hylang pleasant to use for real projects, not just experiments

Checklist:

- [x] Stabilize the project/package manifest format
- [x] Add a first-class `hy` CLI workflow
- [x] Add a formatter
- [x] Add a test runner workflow
- [x] Add bootstrap linting or static analysis
- [x] Add light editor support
- [x] Improve diagnostics and incremental build behavior
- [x] Add debug metadata/source mapping support
- [x] Make project creation and dependency management coherent for new users
- [x] Add a showcase workspace that proves the end-to-end workflow
- [x] Expand static analysis beyond the first bootstrap lint set
- [x] Add local package registry publish/search/install workflow
- [x] Add lightweight semantic language-server support
- [x] Add SDK demo workspace proving package and tooling flow
- [x] Keep interpreter and compiled low-level runtime behavior aligned at the visible language/runtime level

Main work:

- stable project format
- package/dependency model
- test runner story
- formatter
- linter / static analysis
- language server support
- source maps or debug metadata
- better build diagnostics and incremental compilation

Delivered slice:

- `hy new`, `hy build`, `hy run`, `hy test`, `hy fmt`, `hy check`, and `hy package`
- v2 `.hyproj` manifests with workspaces, package metadata, and local path dependencies
- backward-compatible loading of older v1 manifests
- explicit `type = "test"` projects and workspace test discovery
- `.hylang/cache/` build caching
- simple `.hymap.json` files from `hy build --debug`
- JSON diagnostics from `hy check --json`
- bootstrap lint warnings for unused imports/locals/parameters/private members, unreachable statements, local shadowing, unsafe-block issues, dependency/package metadata, and obvious `Buffer` use-after-free
- bootstrap `System.Testing.Assert`
- byte-oriented file helpers, bootstrap `System.Runtime.Buffer`, and bootstrap `BinaryPrimitives` through 64-bit helpers
- `samples/hexlab` as the current workflow showcase
- filesystem-backed local registry commands for init, publish, search, and install
- `hy lsp` with diagnostics, document symbols, basic hover, and formatting over stdio
- `samples/sdk_demo` as the Phase 4 tooling/package proof workspace
- in-repo VS Code assets for highlighting, snippets, tasks, launch templates, language-server integration, and format-on-save settings

Desired tools:

- [x] `hy new`
- [x] `hy build`
- [x] `hy run`
- [x] `hy test`
- [x] `hy fmt`
- [x] `hy package`

Exit criteria:

- a new developer can create, build, test, and publish a Hylang project with a coherent workflow

Deferred beyond Phase 4:

- hosted registry service, authentication, signing, and semver range solving
- full semantic LSP features such as completion, go-to-definition, references, rename, semantic tokens, and workspace indexing
- debugger integration beyond source-mapped runtime failures

## Phase 5: Self-Hosting Preparation

Status: complete at prototype scope

Goals:

- make the compiler architecture clean enough to be reimplemented in Hylang without losing momentum

Checklist:

- [x] Document the bootstrap compiler pipeline and Phase 6 boundary
- [x] Document the bound IR and semantic model contracts at architecture level
- [x] Stabilize the frontend-facing compiler data shapes needed for a first Hydrogen prototype
- [x] Move compiler support types into Hydrogen libraries
- [x] Build a tokenizer in Hydrogen
- [x] Build a parser prototype in Hydrogen
- [x] Build a code-processing CLI utility in Hydrogen
- [x] Prove Hydrogen is comfortable for compiler-style data processing

Main work:

- document the compiler layers and contracts without a risky C++ source split
- document the bound IR and semantic rules
- stabilize core data structures needed by a future self-hosted compiler
- build compiler support libraries in Hydrogen
- prove that Hylang can implement parsing, binding, and data-heavy algorithms comfortably

Delivered proof project:

- `samples/self_hosting/Hydrogen.Compiler.Core`
- `samples/self_hosting/Hydrogen.Compiler.Syntax`
- `samples/self_hosting/Hydrogen.Compiler.Cli`
- `samples/self_hosting/Hydrogen.Compiler.Tests`
- golden token and parse fixtures under `tests/phase5`

Exit criteria:

- the compiler can be decomposed into pieces that are realistic to rewrite incrementally in Hylang

Deferred to Phase 6:

- binding and type checking in Hydrogen
- typed IR generation in Hydrogen
- backend integration
- self-compilation

## Phase 6: Self-Hosted Compiler

Goals:

- write a Hylang compiler in Hylang
- keep the bootstrap compiler only as the trusted seed until the self-hosted one is proven

Checklist:

- [ ] Write foundational compiler utilities in Hylang
- [ ] Write frontend pieces in Hylang
- [ ] Reuse or mirror the existing semantic model/backend strategy
- [ ] Build a Hylang compiler that can compile meaningful Hylang programs
- [ ] Reach self-compilation
- [ ] Compare bootstrap and self-hosted compiler output on a shared test corpus
- [ ] Promote the self-hosted compiler to primary status only after validation

Suggested path:

1. write utility libraries in Hylang first
2. write frontend pieces in Hylang while the bootstrap compiler still builds them
3. write a Hylang compiler that targets the existing IR/backend strategy
4. reach a stage where the self-hosted compiler can compile itself
5. compare outputs of bootstrap and self-hosted compilers on a shared test corpus
6. gradually promote the self-hosted compiler to primary status

Important rule:

- do not delete the bootstrap compiler too early

Exit criteria:

- Hylang can compile the Hylang compiler
- self-hosted output is stable and verified against the bootstrap implementation

## Phase 7: Full Standard Library

Goals:

- grow from a minimal bootstrap library to a real platform library

Checklist:

- [ ] Build out `System`
- [ ] Build out `System.IO`
- [ ] Build out `System.Text`
- [ ] Build out `System.Collections`
- [ ] Build out `System.Threading`
- [ ] Build out `System.Diagnostics`
- [ ] Build out networking/platform APIs as needed
- [ ] Add reusable testing/assertion helpers
- [ ] Move stdlib implementation increasingly into Hylang itself
- [ ] Make the compiler and core tools depend mostly on stdlib code instead of ad hoc helpers

Core stdlib areas:

- `System`
- `System.IO`
- `System.Text`
- `System.Collections`
- `System.Threading`
- `System.Diagnostics`
- `System.Net`
- `System.Reflection` or equivalent metadata APIs
- OS-facing abstractions for processes, paths, filesystems, devices, and IPC

Library priorities:

- collections: lists, maps, sets, queues
- text: builders, encoding, parsing
- filesystem and streams
- process and environment APIs
- testing/assertion helpers
- math and numerics
- serialization

Exit criteria:

- Hylang applications no longer depend on ad hoc runtime helpers for common tasks
- the compiler and core tools can rely mostly on Hylang stdlib code

## Phase 8: Backend Evolution

Goals:

- move beyond the bootstrap C backend into a language/runtime toolchain that can better serve OS development

Checklist:

- [ ] Keep the C backend healthy as a portability path
- [ ] Improve emitted C quality and runtime shims
- [ ] Add native x64 code generation
- [ ] Add object-file emission
- [ ] Add linker/ABI integration
- [ ] Add better debug information
- [ ] Improve generated-code performance
- [ ] Add broader cross-compilation support if needed

Near-term:

- keep the C backend as a portability path and fallback
- improve emitted C quality and runtime shims

Long-term:

- native x64 codegen
- object file emission
- linker/ABI integration
- better debug information
- performance work

Possible future branches:

- AOT native executable pipeline
- optional JIT or IR interpreter tooling
- cross-compilation support

Exit criteria:

- Hylang can generate reliable native binaries for its target platforms without going through C for the main production path

## Phase 9: Hylang for Australis OS Userland

Goals:

- make Hylang the primary language for user-space tooling and core applications on Australis OS

Checklist:

- [ ] Define the Hylang runtime boundary for Australis OS processes
- [ ] Add startup/runtime initialization for Australis OS targets
- [ ] Add filesystem, process, console, and IPC bindings
- [ ] Add any needed windowing/application bindings
- [ ] Write shell and service tooling in Hylang
- [ ] Write build/install/package-management tooling in Hylang
- [ ] Prove that meaningful day-to-day Australis OS userland can ship in Hylang

Main work:

- libc/runtime boundary for Australis OS
- startup/runtime initialization for Hylang processes
- filesystem, process, console, windowing, and IPC bindings
- package manager / system distribution format support
- shell tools, build tools, service tools, and installers written in Hylang

Target outcome:

- most default userland software can be authored in Hylang

Exit criteria:

- Australis OS can ship meaningful day-to-day tooling written in Hylang

## Phase 10: Hylang for System Software and Kernel-Adjacent Code

Goals:

- extend Hylang into the lower layers of the OS stack where it makes sense

Checklist:

- [ ] Finalize the unsafe systems-programming model
- [ ] Finalize ABI and calling-convention control where needed
- [ ] Support explicit layout and low-level interop requirements
- [ ] Define panic/error behavior for low-level code
- [ ] Support reduced-runtime or no-runtime profiles where needed
- [ ] Prove Hylang can handle kernel-adjacent libraries and helpers safely
- [ ] Move selected lower-level OS components into Hylang only when the model is mature

Likely order:

- userland first
- system daemons and drivers/helpers second
- kernel-adjacent libraries next
- carefully selected kernel components only after the unsafe/runtime model is mature

Required before serious kernel work:

- explicit unsafe model
- stable ABI story
- strong control over layout and calling conventions
- panic/error strategy for low-level code
- reliable no-runtime or reduced-runtime profiles where needed

Exit criteria:

- parts of the OS stack can be safely and intentionally written in Hylang without hidden runtime assumptions

## Phase 11: Full OS and Ecosystem Vision

Checklist:

- [ ] Hylang compiler is self-hosted
- [ ] The standard library is substantial and mostly written in Hylang
- [ ] Australis OS userland is primarily written in Hylang
- [ ] Selected systems components are written in Hylang
- [ ] Tooling, docs, package workflow, and ecosystem are mature
- [ ] Third-party developers can build serious software in Hylang without depending on compiler internals

End-state goals:

- Hylang compiler written in Hylang
- substantial standard library written in Hylang
- Australis OS userland primarily written in Hylang
- selected systems components written in Hylang
- strong docs, package ecosystem, and tooling
- enough maturity that third parties can build serious software in Hylang without depending on the compiler internals

This is the point where Hylang stops being “the language for one OS project” and becomes a true platform language.

## Recommended Next Steps

From where the repo is now, the highest-value next moves are:

1. finish hardening the language subset that already exists
2. add missing core type-system features needed before self-hosting
3. define the real runtime and memory model
4. build more tools and library code in Hylang itself
5. start self-hosting only after the language is comfortable for compiler implementation

## What Not To Rush

- self-hosting before the type system and stdlib are ready
- kernel ambitions before the unsafe/runtime model is explicit
- advanced language features before tests and diagnostics are strong
- ecosystem tooling before the project/build model is stable

## Living Document Notes

This roadmap should be updated whenever one of these changes:

- a phase is meaningfully completed
- a major feature moves earlier or later
- the runtime strategy changes
- the self-hosting plan changes
- Australis OS integration requirements become more concrete
