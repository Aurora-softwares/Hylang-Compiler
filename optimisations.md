# Self-hosted Hydrogen optimisation checklist

This plan targets **runtime speed of Linux x86-64 executables emitted by the
Hydrogen-written compiler**. Implementation belongs in
`samples/self_hosting/Hydrogen.Compiler.CodeGen.X64/` and
`tools/native-runtime/runtime.S`. The C++ SDK compiler, C backend, and `hy run`
interpreter remain bootstrap or comparison tools; their optimisation is outside
this checklist. Compiler build latency is tracked separately.

## Measurement

The [six-case harness](benchmarks/runtime/README.md) checks matching output
against an independent Python result, then times warmed whole processes. These
local medians use an Intel i7-4790K on Linux, 17 October 2026, seven runs and
two warmups. C and C++ use GCC 15.2 `-O2`; Rust 1.93.1 uses
`-C opt-level=2`. Hydrogen uses the rebuilt native self-hosted stage-1
compiler. Compilation is excluded. The [previous samples](benchmarks/runtime/results-2026-10-17-two-optimisations.json)
and [current samples](benchmarks/runtime/results-2026-10-17-main-issues.json)
record every timing, input/source hash, and tool version.

| Workload | Input | Previous native | Current native | Current C | Current native / C |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dependent integer arithmetic | 10 million iterations | 136.1 ms | 94.7 ms | 46.6 ms | 2.03× |
| Integer array fill and scan | 10 million elements | 194.8 ms | 157.1 ms | 63.9 ms | 2.46× |
| Log line and error scan | 100,000 lines, 1 MB | 25.5 ms | 6.54 ms | 1.78 ms | 3.67× |
| CSV amount aggregation | 100,000 rows, 679 KB | 9.65 ms | 4.27 ms | 1.87 ms | 2.29× |
| Binary rolling checksum | 1.6 MB | 35.2 ms | 15.2 ms | 7.76 ms | 1.96× |
| Linked-object build and scan | 20,000 objects | 3.48 ms | 4.51 ms | 1.52 ms | 2.96× |

The 20,000-node case has substantial startup noise: a separate
[21-run check](benchmarks/runtime/results-2026-10-17-nodes-21-run.json)
measured 3.41 ms native and 1.22 ms C. The object allocator was also checked
at 100,000 nodes in the earlier pass: 25.3 ms native versus 3.99 ms C, with
the same checksum. The [larger-case samples](benchmarks/runtime/results-2026-10-17-nodes-100k.json)
are retained. Input sizes differ, so these ratios locate bottlenecks in these
cases; they are not an overall language speed rating.

## Completed native runtime work

- 🟢 **Store string literals in executable data.** The native compiler used
  to allocate a string each time a literal expression ran. On the same hashed
  1 MB log input, scanning fell from 8.07 s to 25.9 ms, about 312× faster.
  The [pre-change samples](benchmarks/runtime/results-2026-10-17-before-literals.json)
  and a native allocation regression preserve that result.
- 🟢 **Lower signed `int` division by positive constant divisors with a
  reciprocal multiply.** The direct x64 compiler now computes quotient and
  remainder without a hardware `idiv` for constants from 3 through
  2,147,483,647. The variable-divisor path is unchanged. A regression compares
  both paths across signed edge values and 20,000 generated values. The
  arithmetic case fell from 418.6 to 136.1 ms; the array case from 348.2 to
  194.8 ms. This closes the constant-divisor part of code generation, while
  general code generation remains below.
- 🟢 **Pack small objects into shared 4 KiB pages.** The native runtime now
  uses 64, 128, 256, and 512-byte slots, tracks spans with free slots, and
  returns wholly dead spans after collection. The conservative page index
  resolves interior pointers to individual objects within a span. A new
  runtime regression checks 12,000 live objects, collection, traversal, and
  mapped heap size. The 20,000-node case fell from 71.7 to 3.48 ms. An initial
  span scan scaled poorly at 100,000 nodes; the available-span list removed
  that repeated scan. For the 20,000-node executable, a local `/usr/bin/time`
  check saw peak RSS fall from 80,012 to 2,560 KB; `strace -c` counted 20,013
  versus 650 `mmap` calls. These diagnostic counts include process startup.
- 🟢 **Batch native `Console.WriteBytes`.** The first pass packed up to 4 KiB
  per `write` call, taking its 1 MiB diagnostic from 427 to 2.36 ms. The
  packed `byte[]` layout now lets the runtime write directly from array
  storage. The chunk-boundary regression still covers output correctness.
- 🟢 **Use x64 immediates and inline checked packed-array addresses.**
  Numeric literal arithmetic and comparisons now avoid a stack spill and a
  literal load. Native `byte[]` and `int[]` indexing checks null, negative,
  and upper bounds inline before loading or storing. The integer loop fell
  from 136.1 to 94.7 ms and the array pass from 194.8 to 157.1 ms. The
  broader code-generation item remains open for other redundant operations.
- 🟢 **Compare one-byte string literals directly.** Native equality and
  inequality keep null and length checks, then compare one byte without a
  general string helper call. The 1 MB log scan fell from 25.5 to 6.54 ms;
  a regression covers empty, null, longer, and both operand orders.
- 🟢 **Pack `byte[]`/`int[]` and read/write byte files directly.** Linux
  native byte arrays use one-byte slots and integer arrays four-byte slots;
  reference arrays and freestanding arrays retain eight-byte slots. Native
  `ReadAllBytes` reads into the packed array and `WriteAllBytes` and
  `Console.WriteBytes` write it directly. CSV fell from 9.65 to 4.27 ms and
  the binary checksum from 35.2 to 15.2 ms. Regressions check storage,
  signed values, GC, bounds errors, and byte-file round trips.

## Next runtime work, ranked by measured impact

1. 🔴 **Improve general direct x64 code generation.** The integer loop is
   still 2.03× C and the array pass 2.46×. Profile emitted instructions and
   reduce remaining stack spills, redundant loads, and per-element bounds
   checks where loop proofs permit hoisting. Preserve signed-width, overflow,
   and negative-index behaviour. Keep stage 2 and 3 compiler outputs identical.
2. 🔴 **Specialise hot string indexing.** One-byte literal equality is done,
   but the log scan is still 3.67× C and indexing still calls a runtime
   helper. A direct inline checked load was slower in a paired 30-run check
   (7.96 versus 6.89 ms) and was reverted. Profile surrounding spills and
   branches before trying another path; retain empty, multi-byte, null, and
   out-of-range tests.
3. 🔴 **Remove repeated string copying.** Add a builder or buffer-backed
   append path for concatenation in text-heavy programs and compiler
   diagnostics. Measure copied bytes and live heap size before changing the
   representation.
4. 🔴 **Reduce full-GC work and pauses when traces justify it.** Profile
   root scans, the page index, span sweeping, and recycled-page budget on
   allocation-heavy applications. Preserve conservative interior roots and
   cycles; add incremental or generational collection only with evidence.
5. 🔴 **Buffer repeated small console writes and trim startup.** Measure a
   logging workload and a tiny command independently. Preserve terminal and
   flush behaviour.
6. 🔴 **Vectorise proven bulk operations.** Test SIMD or library-backed
   copy/search/compare with scalar fallbacks. Pack other primitive array types
   when a representative workload shows enough benefit.

## Build-time work, separate from runtime ranking

- 🔴 Profile the complete self-build (token and AST allocation, symbol
  lookup, method lowering, image assembly) and cache unchanged parses and
  dependencies by content hash. Retain a clean bootstrap proof mode.
- 🔴 Parse independent files or compile independent methods concurrently
  only when shared state and deterministic output are safe. Measure elapsed
  time and peak RSS together.

For each runtime item, check exact output and exit status, save raw timings
and input hashes, run the relevant native regressions, and verify bootstrap
equivalence. A speedup in SDK C output alone does not close an item here.
