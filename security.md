# Hydrogen security review checklist

Review date: 17 October 2026. Scope: the C++ SDK build/test path, its generated
C runtime, the self-hosted Linux x86-64 compiler, its native runtime, and the
ELF files it emits. This is a source review with a sample ELF header check and
the native runtime regression suite; it is not a fuzzing or penetration test.
Priorities describe what to investigate or fix first. A checked box means the
specific check has been verified, not that the whole component is secure.

## Confirmed issues

- [ ] **P1 — Diagnose collection-dependent parsing in the compiled compiler.**
  Checking the unchanged full compiler project with the compiled CLI and
  `HYLANG_GC_THRESHOLD=1048576` reproducibly reports spurious lexer errors in
  `DirectMainCompiler.hy`; the default collector passes. The same failure
  occurs without an address-space limit. Reduce this to a focused regression,
  identify whether the generated C runtime loses a live parser object, and
  repair the underlying cause before relying on explicit GC thresholds.
- [x] **P1 — Remove shell interpretation from SDK build and test commands.**
  `src/hylang.cpp` now uses argument-vector process spawning for the compiler,
  archiver, and test executable. `CC` is parsed into a program and literal
  arguments; it is never evaluated by a shell. `hy_sdk_shell_characters` covers
  compiler, archiver, and test paths with spaces, quotes, `$`, command
  substitution, and a shell fragment in `CC`; it verifies that no marker
  command runs on Linux. The Windows spawning path is
  implemented but has not been exercised in this Linux test run.
- [x] **P2 — Report short reads and writes in generated C file helpers.**
  The emitted byte helpers now read and write in 4 KiB chunks and fail on a
  short result; the text reader also rejects a short read. The
  `hy_sdk_short_file_io` Linux regression truncates a file during the read,
  injects short `fread` and `fwrite` returns, and checks normal byte roundtrips.
  The native Linux runtime uses separate helpers.

## Native executable hardening

- [ ] **P2 — Add address randomisation for native Linux executables.**
  `ElfImageBuilder.WriteElfHeader` emits `ET_EXEC` with entry address based on
  `0x400000`. A checked sample has one fixed-address `PT_LOAD` segment. Plan
  position-independent output and relocations where needed; verify repeated
  launches map code at different addresses and preserve the bootstrap proof.
- [ ] **P2 — Emit an explicit non-executable stack program header.** The
  checked ELF has no `PT_GNU_STACK` header. Add one with read/write permissions
  and verify the stack mapping is non-executable on supported Linux systems.
  The current code/data `PT_LOAD` segment is read/execute, which should remain
  so.
- [ ] **P2 — Set a bounded source/input budget for untrusted builds.** Native
  `rt_read_text` sizes a whole-file allocation from `lseek`; the current
  allocator permits payloads approaching 1 GiB. A large or changing input can
  exhaust memory or make the compiler unresponsive. Define a documented
  maximum source/manifest size (or stream with explicit limits), check the
  second seek and close results, and exercise oversized and truncated inputs.
- [ ] **P3 — Make compiler output replacement atomic and symlink aware.** The
  native file writer opens output paths with `O_CREAT|O_TRUNC` and follows
  symlinks. For build artifacts, write a temporary file in the destination
  directory, check the final write and close, then rename it. Decide and test
  the intended behaviour when an output path is a symlink or is in a shared
  writable directory.

## Verification to add

The full Hydrogen CTest suite passes (175/175), including the bootstrap proof,
HexLab PNG assertion, self-hosted source check, and native runtime tests.
The generated HexLab test executable also passed one manual undefined-behaviour
sanitizer run. The native executable hardening items still need their own
targeted verification.

- [ ] Fuzz the lexer, parser, project manifest reader, and native compiler
  with time and memory limits. Keep crash and timeout inputs as regressions.
- [ ] Run the C++ SDK and generated C runtime tests with address and undefined
  behaviour sanitizers in CI; test malformed lengths, arrays, file I/O, and
  failed allocations.
- [ ] Verify Linux native output under a restrictive address-space limit and
  inspect emitted ELF headers for write/execute mappings, stack permissions,
  and load-address assumptions.

## Checks already made

- [x] The reviewed native ELF sample's code/data load segment has read/execute
  flags rather than write/execute flags (`readelf -l` on a native runtime
  regression executable).
- [x] Native runtime regressions cover null and out-of-range indices, negative
  array sizes, file errors, packed byte/int arrays, GC traversal, and byte
  comparisons. These checks cover the tested paths, not all malformed inputs.
