# Native Hydrogen compiler

This directory contains the Hydrogen-written compiler and its referenced libraries. It emits standalone Linux x86-64 executables and can compile its own complete CLI project. The executable manifest is `Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj`; `Hydrogen.Compiler.hyproj` is the SDK workspace including tests.

## Build and use

From the compiler repository root:

```bash
cmake -S . -B build
cmake --build build --target hydrogen_stage1
./build/self_hosting/hydrogen-stage1 compile tests/phase6/native_hello.hy -o build/hello
chmod +x build/hello
./build/hello
```

The initial target uses the C++ SDK and a host C toolchain to seed a Hydrogen CLI, which emits `build/self_hosting/hydrogen-stage1` using Hydrogen's direct backend. The resulting compiler builds supported sources/projects without a C/C++ compiler, assembler, linker, or C runtime. Output files need execute permission.

## Commands

```text
hydrogen-stage1 tokens <file.hy>
hydrogen-stage1 parse <file.hy>
hydrogen-stage1 check <file.hy|project.hyproj> [--emit-ir]
hydrogen-stage1 compile <file.hy> -o <output>
hydrogen-stage1 build <project.hyproj> -o <output>
hydrogen-stage1 stage-compare <project.hyproj> --stage1 <artifact> --stage2 <artifact>
```

`tokens` prints lexer tokens/locations. `parse` prints a syntax outline. `check` performs semantic checking; `--emit-ir` prints typed executable method-body IR. `compile` emits a source file and `build` emits a format-2 executable project's complete reference closure. `stage-compare` compares existing files exactly; it does not build or behaviorally test them.

The CLI returns nonzero on invalid or unsupported compilation and does not create or overwrite the output on failure. An older output may remain, so check status before running it. Checking does not guarantee emission support. Normal compilation never substitutes a debug IR executable. Semantic positions use `1:1` where AST spans are unavailable; lexer/parser diagnostics have source positions.

The native tool has no SDK `new`, `run`, `test`, `fmt`, `package`, `lsp`, `--json`, or `--debug` options.

## Language support

| Supported | Details |
| --- | --- |
| Class objects | Reference identity, instance fields, initializers, constructors/default constructors |
| Calls | Static and instance methods, parameters, returns, direct/mutual recursion |
| Types | `int` (signed 64-bit), `byte`, `bool`, enums, strings, class references, arrays; `void` returns |
| Expressions | Arithmetic, comparisons, assignment, fields, indexing, numeric casts, short-circuit booleans |
| Statements | Blocks, `var`, `if`/`else`, `while`, `break`, `continue`, returns |
| Entry | Static `Main`, `int`/`void`, zero parameters or `string[]` user arguments |

Inheritance, virtual/interface dispatch, structs with value semantics, generics, overloads, static fields, `for`, exceptions, pointers/manual memory, `Buffer`, `BinaryPrimitives`, and `List<T>` require SDK implementation work before native use. Wider numeric declarations may check successfully but reachable native signatures remain restricted.

Use fully qualified builtin names such as `System.Console.WriteLine`. The SDK interpreter evaluates both logical operands; native code short-circuits. Explicit conditional guards make code safe to execute in both routes.

## Objects, strings, and arrays

A complete example:

```hylang
public class Counter {
    private int value;
    public Counter(int initial) { value = initial; }
    public int Next() { value = value + 1; return value; }
}

public class Program {
    public static int Main(string[] args) {
        Counter counter = new Counter(40);
        int[] values = new int[2];
        values[0] = counter.Next();
        values[1] = counter.Next();
        System.Console.WriteLine("Answer: " + values[1]);
        return 0;
    }
}
```

It prints `Answer: 42`. Arrays are mutable, zero/default-initialized, and bounds checked. Strings are immutable and compare by content. String `.Length` and indexing are byte-based; indexing returns a one-byte string. Concatenation accepts strings, integers, and booleans. Native literals support ASCII and `\n`, `\r`, `\t`, `\\`, `\"`; file/argument bytes are preserved without decoding.

## Runtime APIs

| API | Operations |
| --- | --- |
| `System.Console` | `Write(value)`, `WriteLine(value)`, native-only empty `WriteLine()` |
| `System.IO.File` | `Exists(path)`, `ReadAllText(path)`, `ReadAllBytes(path)`, `WriteAllText(path, text)`, `WriteAllBytes(path, bytes)` |
| `System.Convert` | `ToInt32(text)` returning Hydrogen's `int` |
| `System.Runtime.GC` | `Collect()`, `GetAllocatedBytes()` (native source APIs) |

File reads require seekable files. Null access, invalid indices/sizes, malformed integers, I/O errors, and allocation failures report an error on stderr and exit `1`. `Console.ReadLine` is recognized by the checker but rejected by native generation.

The runtime uses Linux anonymous mappings and conservative non-moving mark/sweep collection. Stack/register and interior roots preserve reachable graphs and cycles. Collection runs under allocation pressure; conservative roots can retain some unreachable objects. A cleared-page reuse pool is bounded at 16 MiB and released by explicit collection. `GetAllocatedBytes` excludes cached free pages. SDK `HYLANG_GC_STRESS`/`HYLANG_GC_THRESHOLD` environment controls do not apply to this runtime.

## Projects and IR

```toml
format = 2
name = "App"
type = "exe"
sources = ["Program.hy"]
project_references = ["../Math/Math.hyproj"]
```

Paths are relative to the manifest; referenced libraries use `type = "lib"`. All declarations in the closure are registered before body checking. Names resolve with the declaring file's namespace/import context. Imports do not leak between files. Native `build` does not emit standalone archives or process SDK workspace/package manifests.

```bash
./build/self_hosting/hydrogen-stage1 check tests/phase6/static_calls/App.hyproj --emit-ir
./build/self_hosting/hydrogen-stage1 build tests/phase6/static_calls/App.hyproj -o build/app
chmod +x build/app
./build/app
```

This fixture intentionally returns `42`. All bodies are semantically checked, including unreachable methods. Executable IR carries resolved types/call owners and actual fields, calls, allocations, indexing, returns, branches, and loops. The backend emits methods reachable from `Main`.

## Compiler development and self-compilation

```bash
./build/hy build samples/self_hosting/Hydrogen.Compiler.hyproj
./build/hy test samples/self_hosting/Hydrogen.Compiler.hyproj
cmake --build build --target hydrogen_bootstrap_proof
cat build/self_hosting/bootstrap-proof.txt
```

The proof uses native stage 1 to build stage 2 and stage 2 to build stage 3, runs the same behavioral corpus with all three, and requires identical stage 2/3 compiler and representative application artifacts. It uses empty `PATH` and a 1 GiB address-space limit for native builds/tests.

Keep a verified compiler as a seed before rebuilding without C++:

```bash
cp build/self_hosting/hydrogen-stage3 build/hydrogen-seed
./build/hydrogen-seed build samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o build/hydrogen-rebuilt
chmod +x build/hydrogen-rebuilt
```

To repeat the full proof from it:

```bash
cmake -DSOURCE_DIR="$PWD" -DOUTPUT_DIR="$PWD/build/native-bootstrap" \
  -DSTAGE1_BINARY="$PWD/build/hydrogen-seed" -P cmake/HyBootstrapProof.cmake
```

Source-only bootstrapping needs an existing native seed or the SDK route. Native self-hosting does not replace the broader SDK language/tooling implementation. See [architecture and calling convention](../../docs/implementation/phase6-self-hosted-compiler.md).

The checked-in [runtime emitter](Hydrogen.Compiler.CodeGen.X64/NativeRuntimeEmitter.hy) is generated from [runtime assembly](../../tools/native-runtime/runtime.S). Regenerate with `python3 tools/native-runtime/generate.py`; GNU binutils are needed only for that development operation.
