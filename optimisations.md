# Self-hosted Hydrogen optimisation evidence

This plan targets **runtime speed of Linux x86-64 executables emitted by the
Hydrogen-written compiler**. Implementation belongs in
`samples/self_hosting/Hydrogen.Compiler.CodeGen.X64/` and
`tools/native-runtime/runtime.S`. The C++ SDK compiler, C backend, and `hy run`
interpreter remain bootstrap or comparison tools; their optimisation is outside
this review. Compiler build latency is tracked separately.

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

## Measured changes

The native compiler now stores string literals in executable data, lowers
signed division by positive constants with reciprocal multiplication, packs
small objects into shared pages, batches `Console.WriteBytes`, uses x64
immediates and inline checked packed-array addresses, compares one-byte
literals directly, and packs native `byte[]` and `int[]` elements. The
[benchmark samples](benchmarks/runtime/README.md) and native regressions
retain the detailed before/after results. The corresponding project work is
recorded in [#44](https://github.com/Aurora-softwares/Hylang-Compiler/issues/44),
[#45](https://github.com/Aurora-softwares/Hylang-Compiler/issues/45),
[#46](https://github.com/Aurora-softwares/Hylang-Compiler/issues/46),
[#47](https://github.com/Aurora-softwares/Hylang-Compiler/issues/47),
[#48](https://github.com/Aurora-softwares/Hylang-Compiler/issues/48), and
[#49](https://github.com/Aurora-softwares/Hylang-Compiler/issues/49).

On 23 October, local right operands and array indexes avoided some stack
traffic. An unsigned length comparison retained negative and upper-bound
failures with fewer instructions. The 10-million-element array median fell
from 139.45 to 129.94 ms (6.8%) and the integer-loop median from 84.72 to
83.37 ms (1.6%) on this host. Local string indexes and one unsigned `rt_char`
length check reduced the 1 MB log-scan median from 7.43 to 7.05 ms (5.0%).
A direct inline string load was slower in a paired 30-run check and was
reverted. The [raw samples](benchmarks/runtime/results-2026-10-23-index-paths.json)
retain 30 timed runs and three warmups for each comparison, with source and
input hashes. Hardware performance counters were unavailable here
(`perf_event_paranoid=4`), so these are whole-process measurements.

On 25 October, Linux small-object span pages were drawn from 16-page mmap
batches; the Windows runtime kept page-wise VirtualAlloc reservations so each
page can still be released independently. The collector also skips hash
lookups for values below 4096, which cannot be managed pointers. On this host,
100,000 live linked nodes made 207 mmap calls instead of 3,232. Twenty-one
paired whole-process runs fell from 21.60 to 18.50 ms median (14.4%). With
one extra full collection of those live nodes, a separate paired check fell
from 27.56 to 26.23 ms after the mark-path change (4.8%). The
[raw samples](benchmarks/runtime/results-2026-10-25-small-span-gc.json)
include binary hashes and output checks. These changes reduce allocation and
collection cost, but the native node case is still well above the C++ result;
[#130](https://github.com/Aurora-softwares/Hylang-Compiler/issues/130) remains
in progress while root scans and span sweeping are investigated.

For [#127](https://github.com/Aurora-softwares/Hylang-Compiler/issues/127),
commutative integer operations now load a right-hand local directly into
`rcx`, avoiding a register move, and multiplication writes its result directly
to `rax`. Assignment also omits a second sign or zero extension when the
arithmetic expression already normalized to its target type. A targeted
five-operation loop binary shrank by 42 bytes; the standard runtime workload
shrank by 66. Disassembly of the targeted function shows seven fewer
`mov rcx,rax` instructions and six fewer duplicate `movsxd rax,eax`
instructions. In 30 paired runs, the targeted loop fell from 9.60 to 8.74 ms
median (9.0%), the standard loop from 86.27 to 82.67 ms (4.2%), and the array
case from 134.25 to 129.00 ms (3.9%). The
[source and raw samples](benchmarks/runtime/results-2026-10-25-local-ops.json)
are retained. Further spill and load profiling is needed before #127 closes.

For [#129](https://github.com/Aurora-softwares/Hylang-Compiler/issues/129),
the [native text builder](samples/native_text_builder/README.md) appends UTF-8
bytes to a geometric `byte[]` and creates one immutable string at the end.
For 10,000 `"abc"` appends, repeated `+` copies 150,015,000 bytes by the
concat algorithm. The builder copies 30,000 input bytes, 32,736 bytes during
11 growth steps, and 30,000 bytes when finalized: 92,736 total. Thirty paired
runs on this host measured 88.54 ms median for `+` versus 1.33 ms for the
builder. The native runtime's live managed heap reading after the loop was
204,800 versus 139,264 bytes; it is not a cumulative allocation counter.
The [raw runs and source hashes](benchmarks/runtime/results-2026-10-25-builder.json)
are retained. The builder currently ships as a reusable native sample while
packaged standard-library distribution remains separate work.

The Development project tracks further code-generation and string-index work
in [#127](https://github.com/Aurora-softwares/Hylang-Compiler/issues/127)
and [#128](https://github.com/Aurora-softwares/Hylang-Compiler/issues/128),
text copying in [#129](https://github.com/Aurora-softwares/Hylang-Compiler/issues/129),
GC profiling in [#130](https://github.com/Aurora-softwares/Hylang-Compiler/issues/130),
console/startup costs in [#131](https://github.com/Aurora-softwares/Hylang-Compiler/issues/131),
bulk-operation vectorisation in [#132](https://github.com/Aurora-softwares/Hylang-Compiler/issues/132),
self-build profiling and caching in [#133](https://github.com/Aurora-softwares/Hylang-Compiler/issues/133),
and safe parallel compilation in [#134](https://github.com/Aurora-softwares/Hylang-Compiler/issues/134).
For performance changes, retain exact output and exit status, raw timings and
input hashes, relevant native regressions, and bootstrap equivalence.
