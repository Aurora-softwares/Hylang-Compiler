# Hydrogen security review checklist

Review date: 17 October 2026; hardening update: 23 October 2026. Scope: the
C++ SDK build/test path, its generated C runtime, the self-hosted Linux x86-64
compiler, its native runtime, and the ELF files it emits. This is a source
review with a sample ELF header check and
the native runtime regression suite; it is not a fuzzing or penetration test.
Priorities follow the Hydrogen Development project. 🟢 means the
specific check has been verified, not that the whole component is secure.

## Confirmed issues

- 🔴 **P0, 0.1.0 — Diagnose collection-dependent parsing in the compiled compiler.**
  The 17 October run reported spurious lexer errors in `DirectMainCompiler.hy`
  with `HYLANG_GC_THRESHOLD=1048576`. On 23 October, the compiled CLI checked
  its complete project closure at that threshold successfully. The earlier
  failure remains unexplained. Reduce the case, identify the cause, and add a
  deterministic regression before closing this release gate.
- 🟢 **P1 — Remove shell interpretation from SDK build and test commands.**
  `src/hylang.cpp` now uses argument-vector process spawning for the compiler,
  archiver, and test executable. `CC` is parsed into a program and literal
  arguments; it is never evaluated by a shell. `hy_sdk_shell_characters` covers
  compiler, archiver, and test paths with spaces, quotes, `$`, command
  substitution, and a shell fragment in `CC`; it verifies that no marker
  command runs on Linux. The Windows spawning path is
  implemented but has not been exercised in this Linux test run.
- 🟢 **P2 — Report short reads and writes in generated C file helpers.**
  The emitted byte helpers now read and write in 4 KiB chunks and fail on a
  short result; the text reader also rejects a short read. The
  `hy_sdk_short_file_io` Linux regression truncates a file during the read,
  injects short `fread` and `fwrite` returns, and checks normal byte roundtrips.
  The native Linux runtime uses separate helpers.

## Native executable hardening

- 🔴 **P0, 0.3.0 — Add address randomisation for native Linux executables.**
  `ElfImageBuilder.WriteElfHeader` emits `ET_EXEC` with entry address based on
  `0x400000`. A checked sample has one fixed-address `PT_LOAD` segment. Plan
  position-independent output and relocations where needed; verify repeated
  launches map code at different addresses and preserve the bootstrap proof.
- 🟢 **P0, 0.3.0 — Emit an explicit non-executable stack program header.**
  Linux native ELF output now includes a read/write `PT_GNU_STACK` header;
  the code/data `PT_LOAD` remains read/execute. The native ELF regression
  checks both header count and stack flags, `readelf -W -l` confirms the
  segment, and a running generated executable had an `rw-p` stack mapping.
- 🟢 **P0, 0.3.0 — Bound compiler source and manifest reads.** The SDK
  compiler, its generated C runtime, and the native runtime cap text reads at
  16 MiB. They reject short or growing reads; the SDK and native paths check
  seek and close outcomes. The regressions exercise oversized `.hy` and
  `.hyproj` inputs and inconsistent sysfs/procfs lengths.
- 🔴 **P1, 0.3.0 — Make compiler output replacement atomic and symlink aware.** The
  native file writer opens output paths with `O_CREAT|O_TRUNC` and follows
  symlinks. For build artifacts, write a temporary file in the destination
  directory, check the final write and close, then rename it. Decide and test
  the intended behaviour when an output path is a symlink or is in a shared
  writable directory.

## Verification to add

The 17 October full Hydrogen CTest suite passed (175/175), including the
bootstrap proof, HexLab PNG assertion, self-hosted source check, and native
runtime tests. On 23 October, the SDK file-I/O, interpreted and compiled
native-runtime, native ELF, and stage 1–3 bootstrap proof regressions passed
after this hardening. The generated HexLab test executable also passed one
manual undefined-behaviour sanitizer run on 17 October. PIE, atomic output,
fuzzing, and sanitizer CI remain release work.

- 🔴 Fuzz the lexer, parser, project manifest reader, and native compiler
  with time and memory limits. Keep crash and timeout inputs as regressions.
- 🔴 Run the C++ SDK and generated C runtime tests with address and undefined
  behaviour sanitizers in CI; test malformed lengths, arrays, file I/O, and
  failed allocations.
- 🔴 Verify Linux native output under a restrictive address-space limit and
  inspect emitted ELF headers for write/execute mappings, stack permissions,
  and load-address assumptions.

## Checks already made

- 🟢 The reviewed native ELF sample's code/data load segment has read/execute
  flags rather than write/execute flags (`readelf -l` on a native runtime
  regression executable).
- 🟢 Native runtime regressions cover null and out-of-range indices, negative
  array sizes, file errors, packed byte/int arrays, GC traversal, and byte
  comparisons. These checks cover the tested paths, not all malformed inputs.
