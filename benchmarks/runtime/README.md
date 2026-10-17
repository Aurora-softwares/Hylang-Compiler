# Hydrogen native runtime comparison

This harness tests executables emitted by the **Hydrogen-written Linux x64
compiler** against C, C++, and Rust. It covers two computational kernels and
four application-like areas. The SDK C backend and SDK interpreter are optional
comparison routes; they are not optimisation targets for this benchmark plan.
Every run must print the exact checksum computed independently by Python.

| Case | Work represented | Input |
| --- | --- | --- |
| `loop` | Dependent integer arithmetic | 10 million iterations in the reference run |
| `array` | Numeric array fill and aggregation | 10 million integer elements in four-byte slots |
| `log` | Read a text log and count error lines | 100,000 fixed-format ASCII lines, 1 MB |
| `csv` | Read and aggregate an amount column | 100,000 deterministic `id,amount` rows, 679 KB |
| `bytes` | Read a binary file and calculate a rolling checksum | 1.6 MB |
| `nodes` | Build and traverse a linked object graph | 20,000 objects |

The runner creates the same deterministic files for all languages in one
temporary directory. The log has every fifth line marked `E`; CSV amounts are
`row % 97`; binary bytes repeat `(index * 17 + 3) % 256`. The numeric work
stays in signed range, so overflow rules do not affect the output. Object
lists remain live through traversal and are left to process cleanup in all
routes. These cases are proxies for real work, not full applications.

## Run it

From the Hylang-Compiler repository root:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target hy hydrogen_stage1
python3 benchmarks/runtime/run.py \
  --native build/self_hosting/hydrogen-stage1 \
  --iterations 10000000 --records 100000 --bytes 1600000 --nodes 20000 \
  --runs 7 --warmups 2 \
  --json build/benchmarks/runtime-realworld-results.json
```

After `hydrogen_bootstrap_proof` has rebuilt and verified stage 3, the default
`--native build/self_hosting/hydrogen-stage3` can be used instead. The
runner needs Python 3, `cc`, `c++`, `rustc`, and a native self-hosted compiler.
Use `--cc`, `--cxx`, `--rustc`, or `--native` to select other binaries. Add
`--include-sdk-c` for the SDK's generated C route, or
`--include-interpreter` for `hy run` (use much smaller inputs there). These
optional routes require `build/hy`, selectable with `--sdk`.

For a quick correctness check:

```bash
python3 benchmarks/runtime/run.py \
  --native build/self_hosting/hydrogen-stage1 \
  --iterations 1000 --records 100 --bytes 1024 --nodes 100 \
  --runs 1 --warmups 0
```

`--workloads log,csv,bytes,nodes` runs a subset. All runs time process startup,
input reading, computation, and the checksum print; compilation is reported
separately. C and C++ use `-O2`, Rust uses `-C opt-level=2`, and the native
Hydrogen compiler emits its direct x64 output. The runner checks stdout,
stderr, and exit code on warmups and timed samples, shuffles route order, then
reports median wall time and ratio to C. JSON output records every sample,
compiler versions and hashes, source hashes, input hashes, and build times.

## Local result

On 17 October 2026, an Intel i7-4790K running Linux produced the following
medians with seven timed runs and two warmups. C/C++ used GCC 15.2 and Rust
used 1.93.1. Hydrogen used the rebuilt native stage-1 compiler. Times are in
milliseconds and exclude source compilation.

| Workload | Hydrogen native | C | C++ | Rust | Native / C |
| --- | ---: | ---: | ---: | ---: | ---: |
| Integer loop | 94.7 | 46.6 | 45.8 | 40.4 | 2.03× |
| Array fill/scan | 157.1 | 63.9 | 66.9 | 55.8 | 2.46× |
| Log scan | 6.54 | 1.78 | 5.37 | 2.83 | 3.67× |
| CSV aggregation | 4.27 | 1.87 | 4.59 | 2.43 | 2.29× |
| Binary checksum | 15.2 | 7.76 | 12.1 | 7.86 | 1.96× |
| Linked objects | 4.51 | 1.52 | 2.46 | 2.07 | 2.96× |

The self-hosted compiler previously allocated a new string on every evaluation
of a string literal. On this same hashed log input, the native scan took 8.07
seconds before literals were stored in executable data and 25.9 ms afterwards,
about 312 times faster. The pre-change samples are in
[`results-2026-10-17-before-literals.json`](results-2026-10-17-before-literals.json),
and the first full after-change samples are in
[`results-2026-10-17.json`](results-2026-10-17.json).

The compiler lowers signed `int` division by a positive constant with a
reciprocal multiply, and the runtime packs small objects into shared pages.
The next pass packed native `byte[]` and `int[]`, removed the string copy from
byte-file reads and writes, specialised one-byte literal comparison, encoded
numeric literal operations directly, and inlined checked packed-array
addresses. Against the [previous six-case run](results-2026-10-17-two-optimisations.json),
the loop improved from 136.1 to 94.7 ms, the array pass from 194.8 to
157.1 ms, the log scan from 25.5 to 6.54 ms, CSV from 9.65 to 4.27 ms,
and the binary checksum from 35.2 to 15.2 ms.

The short linked-object case varies with process startup. It measured 4.51 ms
in the seven-run table, while a separate [21-run check](results-2026-10-17-nodes-21-run.json)
measured 3.41 ms native and 1.22 ms C. The allocator's earlier 100,000-object
check measured 25.3 ms native. Its 20,000-object peak RSS diagnostic fell from
80,012 to 2,560 KB, and `mmap` calls from 20,013 to 650 (including startup).
Raw [current six-case](results-2026-10-17-main-issues.json) and
[100,000-object](results-2026-10-17-nodes-100k.json) samples are retained.
See [optimisations.md](../../optimisations.md) for the remaining ranked work.

These ratios depend on CPU, OS, input size, compiler versions, and load. In
particular, process startup dominates tiny runs; use the reference sizes or
larger when assessing steady execution. The six cases do not establish an
overall language speed ranking.
