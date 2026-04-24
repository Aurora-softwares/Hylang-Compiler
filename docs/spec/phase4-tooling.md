# Phase 4 Tooling Slice

This document records the Phase 4 workflow surface that is implemented in the bootstrap compiler today. It is intentionally narrower than the original long-range Phase 4 plan: it captures what exists in the repo now, plus the deliberate exclusions that still remain open.

## Summary

The shipped Phase 4 slice focuses on developer workflow:

- a primary `hy` CLI
- v2 `.hyproj` manifests
- workspaces and local path dependencies
- build, run, test, format, check, and package workflows
- incremental build caching
- simple debug/source-map metadata
- a pure-Hylang showcase workspace: `samples/hexlab`

The raw-memory systems surface is not complete yet. `Buffer`, executable `unsafe`, pointers, `stackalloc`, `sizeof`, and `System.Runtime.Memory` are still deferred follow-on work.

## CLI

The `hy` executable is now the default entry point.

Supported commands:

- `hy new app|lib|tool|test|workspace <name>`
- `hy build <target> [--target exe|lib] [-o output] [--debug]`
- `hy run <target> [-- args...]`
- `hy test [target]`
- `hy fmt <path...> [--check]`
- `hy check <target> [--json]`
- `hy package pack <target> [-o output]`
- `hy package add <target> <path>`

Compatibility shims remain available:

- `hyrun <file.hy|project.hyproj> [args...]`
- `hyc build <file.hy|project.hyproj> [--target exe|lib] [-o output]`

## Manifest v2

New projects scaffolded by `hy new` use the v2 manifest format.

Current supported fields:

- `format = 2`
- `name`
- `version`
- `type = "exe" | "lib" | "test" | "workspace"`
- `sources = [...]`
- `project_references = [...]`
- `members = [...]`
- `[package]`
  - `id`
  - `description`
  - `authors`
  - `license`
- `[dependencies]`
  - inline tables with `path`
  - optional `id`
  - optional `version`

Current manifest rules:

- workspace manifests use `type = "workspace"` and `members = [...]`
- test projects use `type = "test"`
- v1 manifests still load for compatibility
- dependencies without `path` are parsed, but fail with a clear registry-not-implemented diagnostic
- `hy fmt` canonicalizes v2 manifests only

## Build and Test Workflow

Current behavior:

- `hy build` can build a script, a project, or every member of a workspace
- `hy run` executes a script or project through the direct run path
- `hy test` runs explicit `type = "test"` projects inside a workspace
- if a workspace has no explicit test projects, `hy test` falls back to its member projects
- build caching lives under `.hylang/cache/`
- cache keys include manifest data, source hashes, compiler version, target type, and debug flags
- `hy build --debug` emits a simple `.hymap.json` next to generated output

`hy check` currently performs parse/bind/type-check validation and emits diagnostics. `--json` writes machine-readable diagnostics for editor and task integration.

## Bootstrap Standard Library Additions Used By Phase 4

The workflow and showcase slice currently depends on these additional builtin/runtime pieces:

- `System.IO.File.ReadAllBytes(string path) -> byte[]`
- `System.IO.File.WriteAllBytes(string path, byte[] data)`
- `System.Convert.ToInt32(string text)`
- `System.Testing.Assert.True`
- `System.Testing.Assert.False`
- `System.Testing.Assert.Equal`
- `System.Testing.Assert.NotEqual`
- `System.Testing.Assert.Fail`
- `System.Runtime.BinaryPrimitives`
  - `ReadUInt16LE`, `ReadUInt16BE`
  - `ReadUInt32LE`, `ReadUInt32BE`
  - `ReadInt16LE`, `ReadInt16BE`
  - `ReadInt32LE`, `ReadInt32BE`
  - matching 16-bit and 32-bit write helpers

The current integral-family work is bootstrap-oriented. Additional numeric and systems semantics are still planned.

## Showcase: HexLab

`samples/hexlab` is the current showcase workspace for the delivered Phase 4 slice.

Workspace members:

- `HexLab.Core`
- `HexLab.Cli`
- `HexLab.Tests`

CLI surface:

- `dump <file> [width] [start] [count]`
- `inspect <file>`
- `diff <left> <right>`
- `search <file> <hex-pattern>`
- `slice <file> <start> <count> <out>`

Implemented showcase behavior:

- hex dump output for binary files
- binary signature inspection for PNG, ZIP, ELF, and PE/DOS headers
- file diff reporting
- byte-pattern search from hex strings
- byte slicing and write-back
- package/build/test/fmt/check flow through the `hy` CLI

## Deliberate Exclusions

The following Phase 4 goals are still open:

- richer lint warnings beyond the current diagnostic/check flow
- full VS Code extension assets and editor integration
- mapped compiled runtime failures that translate every generated-C failure back to Hylang source
- raw `System.Runtime.Buffer`
- executable `unsafe`
- pointer types and pointer arithmetic
- `stackalloc`
- `sizeof`
- `System.Runtime.Memory`
- 64-bit `BinaryPrimitives` helpers

These will be documented and moved from roadmap to shipped spec only when the implementation lands.
