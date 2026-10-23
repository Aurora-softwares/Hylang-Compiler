# Native Hydrogen compiler

This directory contains the Hydrogen-written compiler and its referenced libraries. It emits Linux x86-64 ELF and Windows x64 PE32+ console executables, constrained x86-64 UEFI images, and can compile its own complete CLI project. The Linux executable manifest is `Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj`; the Windows manifest is `Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Windows.hyproj`. `Hydrogen.Compiler.hyproj` is the SDK workspace including tests.

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
hydrogen-stage1 compile <file.hy> --target windows-x64 -o <output.exe>
hydrogen-stage1 compile <file.hy> --target uefi-x64 -o <output>
hydrogen-stage1 build <project.hyproj> -o <output-file|output-directory>
hydrogen-stage1 new app|lib|tool|test|workspace|os|efi|kernel|exec|windows <name>
hydrogen-stage1 stage-compare <project.hyproj> --stage1 <artifact> --stage2 <artifact>
```

`build` updates one terminal line per action and leaves its `100%` result when complete. Its braille spinner and bar of up to 60 characters show overall completed milestones; the adjacent action percentage uses source position for lexing and consumed tokens for parsing. Narrow terminals get a shorter bar and `...` at the end of long progress text, with the width checked on every redraw. Redirected output keeps the full text. Stages without a known denominator complete at 100%. Append `--hide-progress`, `--hide-spinner`, and/or `--hide-log` to control the display. Using all three flags leaves only the final `wrote` line or an error. OS projects report each referenced image separately.

`tokens` prints lexer tokens/locations. `parse` prints a syntax outline. `check` performs semantic checking; `--emit-ir` prints typed executable method-body IR. `compile` emits a Linux executable by default, a Windows PE32+ console program with `--target windows-x64`, or a constrained UEFI application with `--target uefi-x64`. `build` accepts format-2 `exe`, `windows`, `efi`, `kernel`, `exec`, `native`, and `os` projects. Windows uses the same direct language backend as Linux, with Win32 implementations of the managed runtime's memory, argument, console, and file services. An `exec` project emits an Australis AUEX v1 program. Its structured backend supports control flow, scalar and bounded string/byte-array data, application method calls, terminal/file APIs, and concurrent AUEX child processes. A `native` project emits AUN1 v2 machine code for a single static `Main(string[] args)` with ASCII literal `System.Australis.Terminal.Write` calls and a literal integer return status; it has no general runtime. OS builds emit referenced images below the specified output directory and may include `exec` projects. `stage-compare` compares existing files exactly; it does not build or behaviorally test them.

## Windows x64 target

```bash
./build/self_hosting/hydrogen-stage1 compile tests/phase6/native_hello.hy --target windows-x64 -o build/hello.exe
./build/self_hosting/hydrogen-stage1 build tests/phase6/WindowsFullRuntime.hyproj -o build/WindowsFullRuntime.exe
./build/self_hosting/hydrogen-stage1 build samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Windows.hyproj -o build/hydrogen.exe
```

`hy new windows <name>` scaffolds a `type = "windows"` project. Windows and Linux
share the direct compiler's language features, object layout, checked arrays,
and collector. Windows executables import system APIs from `KERNEL32.dll` and
`SHELL32.dll`; they need no Hydrogen runtime DLL or external compiler/linker.
The PE image has separate executable code and writable data, ASLR and NX
flags, and a relocation directory. Command-line arguments are decoded with
Windows quoting rules and converted from UTF-16 to Hydrogen UTF-8 strings;
file paths are converted back to UTF-16 for Win32 file APIs. Native string
indexing and length remain byte based on both targets. `exe` projects and
untargeted `compile` still select Linux ELF; use the explicit Windows target or
project type for Windows output.

The Windows target is exercised under Wine by the parity and bootstrap tests.
The [Windows full runtime fixture](../../tests/phase6/windows_full_runtime.hy)
checks arguments, Unicode file paths, text/byte files, console output, and GC.

## UEFI console and chain-loading target

```bash
./build/self_hosting/hydrogen-stage1 compile tests/uefi_hello.hy --target uefi-x64 -o build/BOOTX64.EFI
```

The UEFI target accepts static `Main(string[] args)` entry points with
`System.Uefi.ClearScreen()` before console output, `System.Uefi.Await()` to wait
for and consume one keyboard event, and multiple `System.Console.WriteLine`
ASCII string literals. It can also use
`System.Uefi.StartImage` with an ASCII path to load and launch an EFI image from
the boot volume. A bootloader can instead use
`System.Kernel.Boot.Load(<literal-path>)` to load and validate a raw `AUKR`
kernel before the final memory map, followed by
`System.Uefi.ExitBootServices()`, `System.Kernel.MemoryMap.Initialize()`,
`System.Kernel.Memory.Initialize()`,
`System.Kernel.VirtualMemory.Initialize()`,
`System.Kernel.VirtualMemory.ApplyPolicy()`, optional
`System.Kernel.Memory.AllocatePage()` calls,
`System.Kernel.Heap.Initialize()`, optional
`System.Kernel.Heap.Allocate(<literal-byte-count>)` calls,
`System.Kernel.Framebuffer.Initialize()`, literal
`System.Kernel.Framebuffer.WriteLine(<text>)` calls, and
`System.Kernel.Runtime.Execute()`. The
bootloader captures a final memory map, selects the largest
`EfiConventionalMemory` descriptor, reserves and clears its first 4 KiB page,
publishes the remaining physical-page range, retries `ExitBootServices` with a
fresh map key when needed, then copies every present PML4, PDPT, PD, and PT page
into allocator-owned pages and loads the new root through `CR3`. Leaf mappings
retain their current physical frames and attributes. The image has a zero image
base and uses RIP-relative internal references. The `KernelBootInfo` record
pointer is available in `RDI` to post-handoff Hydrogen code. Its state is `127`
once the framebuffer console is active. Each `AllocatePage()` call reserves and clears one 4 KiB
page and publishes its physical address at `KernelBootInfo + 72`. `Heap.Initialize()`
creates a zeroed, 16-byte aligned bump heap, while `Heap.Allocate()` accepts a
literal size from 1 through 1 MiB and publishes its address at `KernelBootInfo + 104`;
the bootstrap heap does not free or reuse allocations. Framebuffer initialization
captures GOP before services end, clears the framebuffer with direct stores, and
renders literal printable-ASCII lines through an embedded 8x8 font; it accepts
the standard RGB and BGR 32-bit GOP formats. The EFI bootloader switches to
a dedicated 64 KiB stack and calls the raw kernel entry after
`ExitBootServices`. The kernel enables interrupts and owns its idle loop.

A format-2 `kernel` project compiles reachable
`static int KernelMain.Run(long bootInfo)` methods into a separate
position-independent binary. Its 16-byte `AUKR` header records version 1,
code length, and entry offset 16. The bootloader verifies the header and exact
file size, then loads it in executable memory before the final map capture.
Freestanding code supports direct 8/16/32/64-bit memory loads and stores, byte
and dword port I/O, CPU pause/halt/interrupt enable, `RDTSC` timestamps,
`MFENCE` DMA synchronization, and a page-backed allocator for
objects, arrays, and ASCII string literals. Managed strings support content
equality, byte-based indexing, `System.Kernel.String.ByteAt`, and
`System.Kernel.String.FromBytes` in freestanding code. The kernel runtime consumes the page
range in `KernelBootInfo`. Each allocation has a 16-byte owner header and
`System.Kernel.Managed.Release(value)` explicitly releases an object, array,
or string. Released pages enter the kernel free-page list; one-page managed
allocations reuse them. An active shell command marker defers reuse above its
rewind point until the command completes. Callers must release a value only
after every reference to it has gone out of use. A failed checked runtime allocation records error
code `5` at `KernelBootInfo + 1160` before it traps, and it does not invoke UEFI
or Linux. Static fields,
other string operations, and unsupported runtime intrinsics are rejected during
freestanding emission.

The paging walker handles standard four-level x86_64 paging. It detects an
active LA57 five-level hierarchy and halts before changing `CR3`.

The CLI returns nonzero on invalid or unsupported compilation and does not create or overwrite the output on failure. An older output may remain, so check status before running it. Checking does not guarantee emission support. Normal compilation never substitutes a debug IR executable. Semantic positions use `1:1` where AST spans are unavailable; lexer/parser diagnostics have source positions.

The native tool has `new` scaffolding, but not the SDK's `run`, `test`, `fmt`, `package`, `lsp`, `--json`, or `--debug` options.

## Language support

| Supported | Details |
| --- | --- |
| Class objects | Reference identity, inheritance, virtual dispatch, instance fields, initializers, constructors |
| Calls | Static and instance methods, overloads, interface calls, parameters, returns, recursion |
| Types | Signed and unsigned integer widths (`int` is 32-bit), `bool`, enums, strings, structs, classes, arrays; `void` returns |
| Expressions | Arithmetic, comparisons, assignment, fields, indexing, numeric casts, short-circuit booleans |
| Statements | Blocks, `var`, `if`/`else`, `while`, `for`, `break`, `continue`, returns |
| Entry | Static `Main`, `int`/`void`, zero parameters or `string[]` user arguments |

Fatal freestanding CPU exceptions use an allocation-free IDT panic path. It
captures the CPU exception frame, `CR2`, and all general registers, writes a
fixed hexadecimal report directly to polled COM1 and the initialized GOP
framebuffer, and halts with interrupts disabled. The report does not depend on
UEFI services or the managed runtime.

Static fields and struct value semantics are supported. Generics, exceptions, pointers/manual memory, `Buffer`, `BinaryPrimitives`, and `List<T>` remain outside native compilation.

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
| `System.Console` | `Write(value)`, `WriteLine(value)`, `WriteBytes(bytes)`, `IsTerminal()`, `TerminalWidth()` (zero when unavailable), `Utf8ByteAt(text, index)`, native-only empty `WriteLine()` |
| `System.IO.File` | `Exists(path)`, `ReadAllText(path)`, `ReadAllBytes(path)`, `WriteAllText(path, text)`, `WriteAllBytes(path, bytes)` |
| `System.Convert` | `ToInt32(text)` returning Hydrogen's `int` |
| `System.Runtime.GC` | `Collect()` in native code and SDK C output (`hy run` treats it as a no-op); `GetAllocatedBytes()` in native code only |

File reads require seekable files. Null access, invalid indices/sizes, malformed integers, I/O errors, and allocation failures report an error on stderr and exit `1`. `Console.ReadLine` is recognized by the checker but rejected by native generation.

The runtime uses Linux anonymous mappings or Windows `VirtualAlloc`/`VirtualFree` and conservative non-moving mark/sweep collection. Small objects occupy 64, 128, 256, or 512-byte slots in shared 4 KiB spans; larger objects have separate mappings. Stack/register and interior roots preserve reachable graphs and cycles, including pointers into individual span slots. Collection runs under allocation pressure, reclaims dead slots, and returns wholly dead spans; conservative roots can retain some unreachable objects. A cleared-page reuse pool is bounded at 16 MiB and released by explicit collection. `GetAllocatedBytes` excludes cached free pages. SDK `HYLANG_GC_STRESS`/`HYLANG_GC_THRESHOLD` environment controls do not apply to this runtime.

Linux and Windows native `byte[]` and `int[]` use one-byte and four-byte elements; other arrays use eight-byte slots. Byte-file reads and writes operate directly on packed array storage. The backend emits inline checked indexing for packed arrays, direct comparisons with one-byte string literals, and immediate x64 instructions for numeric literal operations. Freestanding arrays keep their existing eight-byte layout.

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
