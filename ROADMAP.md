# Hylang Roadmap

This document is the rough long-range plan for Hylang: from the current bootstrap compiler and basic scripts, through self-hosting, to a full standard library and an OS stack that can be built primarily in Hylang.

It is intentionally directional rather than rigid. The order matters more than the dates.

## Vision

Hylang should become:

- a C#-like systems language with high-level ergonomics
- capable of both managed application development and low-level OS work
- self-hosted, so the compiler can eventually be written in Hylang itself
- backed by a real standard library, tooling ecosystem, and package/build workflow
- the primary language for Aura OS userland and, over time, larger parts of the OS stack

## Current State

Today the project already has:

- `hyrun` for direct `.hy` and `.hyproj` execution
- `hyc build` for host-native executables and static libraries through a C backend
- a real pipeline: lexer, parser, AST, binder, type checker, and shared bound IR
- classes, namespaces, fields, constructors, methods, access modifiers, and static members
- control flow including `if`, `while`, `for`, `break`, `continue`, and `return`
- strings, arrays, `.Length`, array indexing, basic string concatenation, and console/file builtins
- enough language surface to build small multi-file console tools

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
- [ ] Phase 1: Language Hardening is in progress
- [ ] Phase 2: Core Language Expansion has not started in earnest
- [ ] Phase 3: Runtime and Memory Model has not started in earnest
- [ ] Phase 4: Tooling and Developer Workflow has not started in earnest
- [ ] Phase 5: Self-Hosting Preparation has not started in earnest
- [ ] Phase 6: Self-Hosted Compiler has not started
- [ ] Phase 7: Full Standard Library has not started in earnest
- [ ] Phase 8: Backend Evolution has not started in earnest
- [ ] Phase 9: Hylang for Aura OS Userland has not started
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

Status: current active zone

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
- [ ] Improve parser error recovery so one syntax issue does not cascade as badly
- [ ] Harden overload resolution and method/constructor selection rules
- [ ] Expand regression coverage further until refactors feel cheap and safe
- [ ] Prove the language on at least one medium-sized Hylang tool beyond the current samples

Main work:

- stronger tests across parser, binder, interpreter, and C backend
- more complete expression and statement support
- better diagnostics and error recovery
- more string, array, and file APIs
- cleaner project/reference behavior
- more sample applications written in Hylang

Likely features in this phase:

- `else if` polish and more loop/test coverage
- constructors and overload behavior hardening
- more operators and conversions
- basic enums
- basic inheritance
- `this`/member semantics cleanup
- library authoring and project-reference quality improvements

Exit criteria:

- Hylang can build a medium-sized console tool cleanly
- regression coverage is broad enough to refactor the compiler without fear

## Phase 2: Core Language Expansion

Goals:

- move from “small tool language” to “general-purpose application language”
- fill in the missing object model and type system pieces needed before self-hosting

Checklist:

- [ ] Add inheritance
- [ ] Add virtual/override behavior
- [ ] Add interfaces
- [ ] Add enums
- [ ] Decide and implement value-type or struct design
- [ ] Add generics
- [ ] Improve overload resolution
- [ ] Improve namespace and import resolution behavior
- [ ] Add any minimal type inference needed for ergonomic compiler/library code
- [ ] Capture the implemented rules in language-spec notes

Main work:

- inheritance
- virtual/override behavior
- interfaces
- enums
- structs or value-type design
- generics
- namespaces/import resolution hardening
- richer overload resolution
- better type inference where appropriate

Supporting work:

- improve symbol tables and type representation
- formalize language spec notes for each feature as it lands

Exit criteria:

- the language can model compiler data structures cleanly
- reusable library code no longer feels awkward or artificially limited

## Phase 3: Runtime and Memory Model

Goals:

- define how Hylang manages memory in normal applications
- define how low-level code can opt into more explicit control

Checklist:

- [ ] Replace the bootstrap allocation strategy with a real GC-backed managed runtime
- [ ] Define stable runtime object and metadata layout
- [ ] Make strings and arrays behave consistently across all backends
- [ ] Design `unsafe` blocks
- [ ] Design pointer support
- [ ] Design stack allocation support
- [ ] Design manual allocation/free APIs
- [ ] Add raw memory and buffer primitives suitable for systems code
- [ ] Define the safe/unsafe boundary clearly in docs and compiler rules

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

Exit criteria:

- ordinary Hylang code has predictable managed behavior
- systems code can reach low-level memory and platform APIs without fighting the language

## Phase 4: Tooling and Developer Workflow

Goals:

- make Hylang pleasant to use for real projects, not just experiments

Checklist:

- [ ] Stabilize the project/package manifest format
- [ ] Add a first-class `hy` CLI workflow
- [ ] Add a formatter
- [ ] Add a test runner workflow
- [ ] Add linting or static analysis
- [ ] Add language-server/editor support
- [ ] Improve diagnostics and incremental build behavior
- [ ] Add debug metadata/source mapping support
- [ ] Make project creation and dependency management coherent for new users

Main work:

- stable project format
- package/dependency model
- test runner story
- formatter
- linter / static analysis
- language server support
- source maps or debug metadata
- better build diagnostics and incremental compilation

Desired tools:

- `hy new`
- `hy build`
- `hy run`
- `hy test`
- `hy fmt`
- `hy package`

Exit criteria:

- a new developer can create, build, test, and publish a Hylang project with a coherent workflow

## Phase 5: Self-Hosting Preparation

Goals:

- make the compiler architecture clean enough to be reimplemented in Hylang without losing momentum

Checklist:

- [ ] Split the compiler into clearer libraries/modules
- [ ] Document the bound IR and semantic model
- [ ] Stabilize core compiler data structures
- [ ] Move more support libraries into Hylang
- [ ] Build a tokenizer in Hylang
- [ ] Build a parser prototype in Hylang
- [ ] Build at least one code-processing utility in Hylang
- [ ] Prove Hylang is comfortable for compiler-style data processing

Main work:

- split the compiler into clearer layers and libraries
- document the bound IR and semantic rules
- stabilize core data structures needed by a future self-hosted compiler
- build more of the standard library in Hylang
- prove that Hylang can implement parsing, binding, and data-heavy algorithms comfortably

Recommended proof projects:

- tokenizer in Hylang
- parser prototype in Hylang
- small codegen utility in Hylang
- stdlib components in Hylang

Exit criteria:

- the compiler can be decomposed into pieces that are realistic to rewrite incrementally in Hylang

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

## Phase 9: Hylang for Aura OS Userland

Goals:

- make Hylang the primary language for user-space tooling and core applications on Aura OS

Checklist:

- [ ] Define the Hylang runtime boundary for Aura OS processes
- [ ] Add startup/runtime initialization for Aura OS targets
- [ ] Add filesystem, process, console, and IPC bindings
- [ ] Add any needed windowing/application bindings
- [ ] Write shell and service tooling in Hylang
- [ ] Write build/install/package-management tooling in Hylang
- [ ] Prove that meaningful day-to-day Aura OS userland can ship in Hylang

Main work:

- libc/runtime boundary for Aura OS
- startup/runtime initialization for Hylang processes
- filesystem, process, console, windowing, and IPC bindings
- package manager / system distribution format support
- shell tools, build tools, service tools, and installers written in Hylang

Target outcome:

- most default userland software can be authored in Hylang

Exit criteria:

- Aura OS can ship meaningful day-to-day tooling written in Hylang

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
- [ ] Aura OS userland is primarily written in Hylang
- [ ] Selected systems components are written in Hylang
- [ ] Tooling, docs, package workflow, and ecosystem are mature
- [ ] Third-party developers can build serious software in Hylang without depending on compiler internals

End-state goals:

- Hylang compiler written in Hylang
- substantial standard library written in Hylang
- Aura OS userland primarily written in Hylang
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
- Aura OS integration requirements become more concrete
