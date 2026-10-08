# Hydrogen (Hylang)

<img src="assets/hydrogen.icon.svg" style="display: block;margin-left: auto; margin-right: auto; width: 30%;" />

Hydrogen is a C#-inspired language with classes, methods, managed strings and arrays, and explicit low-level facilities. Source files use `.hy`; project manifests use `.hyproj`.

The Hydrogen-written compiler produces standalone Linux x86-64 executables, a constrained x86_64 UEFI proof image, and can compile itself. The C++ SDK provides additional language features, an interpreter, project scaffolding, packaging, formatting, and editor integration. Choose the tool according to the features your program needs.

| Tool | Use it for | Output or execution |
| --- | --- | --- |
| `hydrogen-stage1` (Hydrogen) | Direct native compilation, source/project checking, IR inspection, UEFI console and chain-loading proof | Linux x64 ELF or constrained `uefi-x64` PE32+ output; no external compiler or linker |
| `hy` (C++ SDK) | Build/run/test/check/fmt/new/package/LSP workflows; UEFI console proof | Interpreter, host C backend, or constrained `uefi-x64` PE32+ output |
| `hyrun` | Direct interpreted execution | Shares the SDK semantic pipeline |
| `hyc build` | Compatibility build command | Host C backend, executables or static libraries |

See the [language and tool reference](https://aurora-softwares.github.io/Hylang-Docs/) and [native compiler guide](samples/self_hosting/README.md) for the supported features of each route.

## Package a self-hosted release

After you have verified and renamed the final self-hosted compiler to `safe/hy`,
create a Linux x86-64 release archive with:

```bash
cmake -DSOURCE_DIR="$PWD" -DVERSION=alpha-0.0.1 -P cmake/PackageHydrogenRelease.cmake
```

This writes `releases/hydrogen-alpha-0.0.1-linux-x86_64.tar.gz` and its adjacent
`.sha256` checksum. The archive contains `bin/hy`, a release README, build
metadata, and `SHA256SUMS` for the executable. The command refuses to overwrite
an existing release; pass `-DFORCE=ON` only when intentionally rebuilding it.

If CMake is already configured, the equivalent target is:

```bash
cmake -S . -B build -DHYDROGEN_RELEASE_VERSION=alpha-0.0.1
cmake --build build --target hydrogen_package_release
```

## Build the tools

Run these commands from this repository's root. The SDK requires CMake 3.20 or newer and a C++20 compiler. Its executable builds also require a host C compiler; static-library builds require an archiver. The direct native compiler targets Linux x86-64.

```bash
cd /home/rsmith/Projects/Aurora-Softwares/Hylang-Compiler

# Build the C++ stage 0 compiler.
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target hy --parallel

./build/hy --help

# Use stage 0 to produce the temporary Hydrogen bootstrap compiler.
mkdir -p build/self_hosting
rm -f build/self_hosting/hydrogen-bootstrap

./build/hy build samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o build/self_hosting/hydrogen-bootstrap

chmod +x build/self_hosting/hydrogen-bootstrap

# This is the temporary Hydrogen bootstrap compiler.
./build/self_hosting/hydrogen-bootstrap --help

# Bootstrap compiler -> stage 1.
rm -f build/self_hosting/hydrogen-stage1.pending

./build/self_hosting/hydrogen-bootstrap build ./samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o ./build/self_hosting/hydrogen-stage1.pending

chmod +x build/self_hosting/hydrogen-stage1.pending
mv build/self_hosting/hydrogen-stage1.pending build/self_hosting/hydrogen-stage1

# This is stage 1.
./build/self_hosting/hydrogen-stage1 --help

# Stage 1 -> stage 2.
rm -f build/self_hosting/hydrogen-stage2.pending

./build/self_hosting/hydrogen-stage1 build ./samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o ./build/self_hosting/hydrogen-stage2.pending

chmod +x build/self_hosting/hydrogen-stage2.pending
mv build/self_hosting/hydrogen-stage2.pending build/self_hosting/hydrogen-stage2

# This is stage 2.
./build/self_hosting/hydrogen-stage2 --help

# Stage 2 -> stage 3.
rm -f build/self_hosting/hydrogen-stage3.pending

./build/self_hosting/hydrogen-stage2 build ./samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o ./build/self_hosting/hydrogen-stage3.pending

chmod +x build/self_hosting/hydrogen-stage3.pending
mv build/self_hosting/hydrogen-stage3.pending build/self_hosting/hydrogen-stage3

# This is stage 3.
./build/self_hosting/hydrogen-stage3 --help

# Stage 2 and stage 3 should be byte-identical.
sha256sum build/self_hosting/hydrogen-stage2 build/self_hosting/hydrogen-stage3

cmp build/self_hosting/hydrogen-stage2 build/self_hosting/hydrogen-stage3
```

The native target initially uses the SDK's C backend to create a seed, then Hydrogen's own backend compiles the complete compiler CLI project and its referenced libraries. The resulting `build/self_hosting/hydrogen-stage1` has no C/C++ toolchain dependency when compiling supported programs.

For a manual SDK build:

```bash
mkdir -p build
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hy_main.cpp -o build/hy
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyrun_main.cpp -o build/hyrun
c++ -std=c++20 -Wall -Wextra -Wpedantic -Iinclude src/hylang.cpp src/hyc_main.cpp -o build/hyc
```

## Write and run a program

Save this as `hello.hy`:

```hylang
namespace Hello {
    public class Program {
        public static int Twice(int value) {
            return value * 2;
        }

        public static int Main(string[] args) {
            string name = "World";
            if (args.Length > 0) { name = args[0]; }
            System.Console.WriteLine("Hello, " + name);
            System.Console.WriteLine(Twice(21));
            return 0;
        }
    }
}
```

Compile directly with Hydrogen:

```bash
./build/self_hosting/hydrogen-stage1 check hello.hy
./build/self_hosting/hydrogen-stage1 compile hello.hy -o build/hello
chmod +x build/hello
./build/hello Hydrogen
```

Expected output:

```text
Hello, Hydrogen
42
```

Native output files need execute permission. Compilation failures return a nonzero status and do not create or overwrite the output; check that status before running an existing artifact.

## UEFI console proof

The self-hosted compiler can emit a bootable x86_64 UEFI PE32+ application.
Its `Main` method can call `System.Uefi.ClearScreen()` before console output,
call `System.Uefi.Await()` to wait for and consume one keyboard event, and
contain multiple `System.Console.WriteLine` calls with ASCII string literals. A
UEFI program may also call
`System.Uefi.StartImage("\\EFI\\AUSTRALIS\\KERNEL.EFI")` to read an EFI
application from the same FAT volume and start it through UEFI boot services.
For the first freestanding kernel handoff, call
`System.Uefi.ExitBootServices()`, `System.Kernel.MemoryMap.Initialize()`,
`System.Kernel.Memory.Initialize()`,
`System.Kernel.VirtualMemory.Initialize()`,
`System.Kernel.VirtualMemory.ApplyPolicy()`, optional
`System.Kernel.Memory.AllocatePage()` calls,
`System.Kernel.Heap.Initialize()`, optional
`System.Kernel.Heap.Allocate(<literal-byte-count>)` calls,
`System.Kernel.Framebuffer.Initialize()`, and literal
`System.Kernel.Framebuffer.WriteLine(<text>)` calls, then
`System.Kernel.Halt()`. The
generated image captures a final UEFI memory map, chooses the largest
`EfiConventionalMemory` descriptor, reserves and clears its first 4 KiB page,
and writes the resulting physical-page range to a writable `KernelBootInfo`
record. It reserves 64 descriptor slots, retries the final
`GetMemoryMap`/`ExitBootServices` pair up to eight times, then copies every
present PML4, PDPT, PD, and PT page into allocator pages, records the new root,
and switches `CR3` to it. Leaf mappings retain their existing physical frames
and attributes. The PE32+ image has a zero image base and RIP-relative internal
references. Post-handoff Hydrogen code receives the record pointer in `RDI`; its
state is `127` after the framebuffer console is active. An interrupt-enabled
kernel then calls `Gdt.Initialize()`, `Idt.Initialize()`,
`Interrupts.Initialize()`, and `Timer.Initialize()`. It may call
`Pci.Initialize()`, `Mmio.Initialize()`, `Dma.Initialize()`, and one or more
literal `Dma.AllocatePages(<1..1024>)` calls before it enables interrupts and
idles. PCI enumeration uses configuration mechanism #1 at ports `0xcf8` and
`0xcfc`, records the first xHCI, AHCI, and NVMe functions, and maps a guarded,
uncached, non-executable 64 KiB high register aperture for each valid memory
BAR. DMA pages are contiguous, zeroed, and selected from conventional memory
below 4 GiB. The compiler reserves the literal DMA requests from that interval;
if the reserved slice overlaps the main page allocator, that slice is removed
before allocations begin. Each `AllocatePage()` call reserves and zeros one 4 KiB page and
writes its physical address to `KernelBootInfo + 72`. `Heap.Initialize()` adds
a zeroed heap page; `Heap.Allocate()` accepts a literal size from 1 through
1 MiB, aligns it to 16 bytes, grows the heap with contiguous physical pages,
and writes its address to `KernelBootInfo + 104`. This bootstrap heap is
monotonic and does not free or reuse allocations.
After a DMA allocation, the interrupt kernel may call
`System.Kernel.Storage.Initialize()` before `Interrupts.Enable()`. The emitted
transport uses the discovered AHCI aperture and a bounded polling READ DMA EXT
path to read LBA 0, LBA 1, and the GPT primary entry array. It validates the
protective MBR, the GPT 1.0 header and CRC, and the primary entry-array CRC;
the current bootstrap accepts 512-byte logical sectors and up to 256 standard
128-byte GPT entries. It records the selected AHCI port and the first present
GPT partition in KernelBootInfo ABI version 7. The image does not yet emit an
NVMe transport or filesystem driver.
Framebuffer initialization locates GOP before `ExitBootServices`, stores its
base, size, geometry, and pixel format in `KernelBootInfo`, clears the display
directly after the handoff, and renders printable ASCII with an embedded 8x8
font. It accepts the standard RGB and BGR 32-bit GOP modes.
The paging walker supports the normal four-level x86_64 mode; it detects LA57
and halts before replacing `CR3` on a five-level firmware hierarchy.
The SDK compiler's older UEFI path still accepts only one printable ASCII
`WriteLine` literal.

```bash
./build/self_hosting/hydrogen-stage1 compile tests/uefi_hello.hy --target uefi-x64 -o build/BOOTX64.EFI
file build/BOOTX64.EFI
```

The result is an EFI application, not a Linux ELF. The self-hosted compiler
emits a PE32+ image, uses the UEFI Microsoft x64 entry ABI, writes an ASCII
message as UTF-16 through the firmware `OutputString` function pointer, and
then remains on screen. The chain-loading intrinsic uses the loaded-image,
simple-file-system, and file protocols to pass an in-memory EFI application to
`LoadImage` and `StartImage`. The kernel handoff collects the final memory map,
materializes `KernelBootInfo`, invokes `ExitBootServices`, initializes a
bootstrap physical-page range, copies every present paging-structure page into
allocator-owned memory, removes the null page mapping, then halts with interrupts disabled. This target has no
managed runtime, Linux syscalls, arbitrary method compilation, raw freestanding
kernel-image format, or general post-handoff runtime yet.

Alternatively, interpret or build with the SDK:

```bash
./build/hy run hello.hy -- Hydrogen
./build/hy build hello.hy -o build/hello-sdk
./build/hello-sdk Hydrogen
```

`Main` is a static class method returning `int` or `void`, with no parameters or one `string[]` parameter. Its argument array excludes the executable name; an integer return supplies the process exit status. Hydrogen has no top-level statements or free functions.

## Projects

An executable project can reference library projects by source closure:

```toml
format = 2
name = "Hello"
type = "exe"
sources = ["Program.hy"]
project_references = ["../Shared/Shared.hyproj"]
```

Paths are relative to the containing manifest. Use `type = "lib"` for a referenced library. The native compiler binds referenced sources together and emits one executable:

```bash
./build/self_hosting/hydrogen-stage1 build Hello/Hello.hyproj -o build/hello-project
chmod +x build/hello-project
./build/hello-project
```

For OS development, the self-hosted compiler supports `type = "efi"` for a
UEFI application, `type = "kernel"` for a kernel image, and `type = "os"` for
an aggregate project. Both `efi` and `kernel` currently emit x86-64 PE32+ UEFI
applications. The `kernel` type identifies the image's role; a raw freestanding
kernel format is not yet available.

An OS project lists component `.hyproj` files in `project_references` and has
no sources of its own. Each component sets an `output` path relative to the
build directory, such as `EFI/BOOT/BOOTX64.EFI`. Hydrogen compiles each
component independently:

```toml
# OS.hyproj
format = 2
type = "os"
project_references = ["Boot/Boot.hyproj", "Kernel/Kernel.hyproj"]

# In Boot/Boot.hyproj: type = "efi", output = "EFI/BOOT/BOOTX64.EFI"
# In Kernel/Kernel.hyproj: type = "kernel", output = "EFI/OS/KERNEL.EFI"
```

```bash
./build/self_hosting/hydrogen-stage1 build OS/OS.hyproj -o build/efi
```

The output directory contains separate EFI applications ready for image
packaging. You can also build an `efi` or `kernel` project directly with `-o`
pointing to one EFI file. Scaffold them with `hydrogen-stage1 new efi <name>`,
`hydrogen-stage1 new kernel <name>`, or `hydrogen-stage1 new os <name>`.
These project types are currently available in
`hydrogen-stage1`.

SDK projects additionally support workspaces, test projects, local package dependencies, caching, and static-library artifacts. Useful SDK commands:

```bash
./build/hy new app MyApp
./build/hy check MyApp/MyApp.hyproj --json
./build/hy build MyApp/MyApp.hyproj
./build/hy run MyApp/MyApp.hyproj -- argument
./build/hy fmt MyApp --check
```

## Language and runtime

The direct native route supports classes with instance fields and constructors, static/instance methods, recursion, `var`, enums, `int`/`byte`/`bool`, strings, arrays, `if`/`else`, `while`, `break`, `continue`, and returns. `int` is signed 64-bit. Strings have byte-based length/indexing; indexing returns a one-byte string. Native literals accept ASCII and common escaped control characters; file contents and arguments preserve raw bytes.

Native builtins include `System.Console.Write`/`WriteLine`, `System.IO.File` text/byte reads and writes and existence checks, `System.Convert.ToInt32`, and `System.Runtime.GC` collection/accounting. Objects are managed by a conservative non-moving mark/sweep collector using Linux memory mappings. File reads require seekable files.

The SDK also supports inheritance, virtual/interface dispatch, structs with value semantics, generics, overloads, static fields, `for`, string exceptions, `List<T>`, checked unsafe/manual-memory operations, `Buffer`, and `BinaryPrimitives`. These additional facilities are not implemented by the native compiler. The SDK interpreter evaluates both sides of `&&` and `||`; generated native and C-backed programs short-circuit. Write explicit conditional guards when sharing code with the interpreter.

## Examples and editor support

- [Native compiler](samples/self_hosting/README.md): commands, runtime, project binding, self-compilation.
- [HexLab](samples/hexlab/README.md): binary-file inspection with the SDK's buffer and unsafe APIs.
- [SDK demo](samples/sdk_demo/README.md): projects, testing, and local package registries.
- [VS Code assets](tools/vscode/hylang/README.md): highlighting, snippets, check/format tasks, and the LSP process launcher.

## Compiler development

```bash
ctest --test-dir build --output-on-failure
cmake --build build --target hydrogen_bootstrap_proof
cat build/self_hosting/bootstrap-proof.txt
```

The proof recompiles the native compiler through three generations, runs the same behavioral corpus with each, and requires identical stage 2/3 compiler and representative application artifacts. Retain a verified native seed to rebuild without C++; a source-only checkout still needs a bootstrap route. Native self-hosting does not replace the SDK's broader language and tooling surface.

See [compiler architecture](docs/implementation/phase6-self-hosted-compiler.md), [future work](ROADMAP.md), and the [OS design plan](OS_ROADMAP.md).
