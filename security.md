# Hydrogen security review evidence

The 17 October 2026 source review covered the C++ SDK build and test path,
generated C runtime, self-hosted Linux x86-64 compiler, native runtime, and
emitted ELF files. The 23 October hardening pass added focused regression
coverage. This review and its sample ELF inspection are not a fuzzing or
penetration test. The [Hydrogen Development Project](https://github.com/orgs/Aurora-softwares/projects/4)
tracks the work and current status.

The SDK now starts compilers, archivers, and test executables with literal
argument vectors. The `hy_sdk_shell_characters` regression covers paths with
spaces, quotes, `$`, command substitution, and a shell fragment in `CC` on
Linux. The Windows spawning path is implemented, with real Windows host
verification tracked by [#75](https://github.com/Aurora-softwares/Hylang-Compiler/issues/75).
The file-I/O helpers use checked 4 KiB reads and writes and report short
results; the Linux `hy_sdk_short_file_io` regression exercises truncated and
injected-short reads and writes. These changes are recorded in
[#67](https://github.com/Aurora-softwares/Hylang-Compiler/issues/67) and
[#68](https://github.com/Aurora-softwares/Hylang-Compiler/issues/68).

The native ELF output declares a read/write, non-executable stack. A checked
sample had a read/execute load segment and an `rw-p` stack mapping. Compiler
source and manifest reads are capped at 16 MiB and reject short or growing
reads. The relevant regressions cover oversized inputs and inconsistent
sysfs/procfs lengths; see [#91](https://github.com/Aurora-softwares/Hylang-Compiler/issues/91)
and [#92](https://github.com/Aurora-softwares/Hylang-Compiler/issues/92).
Native runtime regressions cover null and out-of-range indexes, negative
array sizes, file errors, packed arrays, GC traversal, and byte comparisons.
These are tests of the named paths, not a general security guarantee.

The 17 October full CTest run passed 175 tests. On 23 October, the SDK file-I/O,
interpreted and compiled native-runtime, native ELF, and stage 1–3 bootstrap
proof regressions passed after hardening. A generated HexLab executable also
passed one manual undefined-behaviour sanitizer run on 17 October.

The remaining investigations have dedicated project issues: the unexplained
GC-threshold-dependent parser report [#70](https://github.com/Aurora-softwares/Hylang-Compiler/issues/70),
ASLR-compatible PIE output [#90](https://github.com/Aurora-softwares/Hylang-Compiler/issues/90),
atomic and symlink-aware output replacement [#93](https://github.com/Aurora-softwares/Hylang-Compiler/issues/93),
fuzzing [#94](https://github.com/Aurora-softwares/Hylang-Compiler/issues/94),
and sanitizer CI [#95](https://github.com/Aurora-softwares/Hylang-Compiler/issues/95).
Restrictive address-space testing and emitted ELF permission review are part
of the release security gate [#142](https://github.com/Aurora-softwares/Hylang-Compiler/issues/142).
