<div align="center">

<img src="assets/hydrogen.icon.svg" width="30%" />

# Hydrogen (Hylang)

</div>

Hydrogen is a C#-inspired language with classes, methods, managed strings and arrays, and explicit low-level facilities. Source files use `.hy`; project manifests use `.hyproj`.

The Hydrogen-written compiler produces Linux x86-64 ELF and Windows x64 PE32+ executables from the same direct language backend, constrained x86-64 UEFI images, and can compile itself. The C++ SDK provides additional language features, an interpreter, packaging, formatting, and editor integration. Choose the tool according to the features your program needs.

| Tool | Use it for | Output or execution |
| --- | --- | --- |
| `hydrogen-stage1` (Hydrogen) | Direct native compilation, source/project checking, IR inspection, UEFI boot/kernel images, and project scaffolding | Linux x64 ELF, Windows x64 PE32+ console executable, constrained `uefi-x64` PE32+, raw `AUKR` kernel, checked AUEX `.exec`, or narrow AUN1; no external compiler or linker for these outputs |
| `hy` (C++ SDK) | Build/run/test/check/fmt/new/package/LSP workflows; UEFI console proof | Interpreter, host C backend, or constrained `uefi-x64` PE32+ output |
| `hyrun` | Direct interpreted execution | Shares the SDK semantic pipeline |
| `hyc build` | Compatibility build command | Host C backend, executables or static libraries |

See the [language and tool reference](https://aurora-softwares.github.io/Hylang-Docs/) and [native compiler guide](samples/self_hosting/README.md) for the supported features of each route.
For runtime performance measurements and planned work, see the [optimisation notes](optimisations.md).
The [runtime comparison harness](benchmarks/runtime/README.md) times equivalent Hydrogen, C, C++, and Rust programs.
The [security review](security.md) records confirmed issues and hardening work.

The [Hydrogen Development project](https://github.com/orgs/Aurora-softwares/projects/4)
tracks the 0.2.0 development target. Fixed-width bitwise operators, integral
compound assignment, increment/decrement, conditional expressions, null
coalescing, null-conditional access, `foreach` over arrays and strings, interpolated strings,
switch statements and expressions, and range-based slicing are implemented across the
SDK, Linux native, and Windows native paths under Wine. The top ten language
features are tracked on that project. The next 0.2.0 language target is
[full-width unsigned hexadecimal literals](https://github.com/Aurora-softwares/Hylang-Compiler/issues/166);
real Windows-host validation remains an open release gate.
The SDK self-hosting workspace and formatter checks are required CI gates;
the local CTest suite also covers preservation of the Windows manifest output name.
Format 2 project manifests now accept arrays of quoted strings spread across
lines. The self-hosted compiler builds `collection` projects and allows an OS
project to include one; Australis's application collection builds all twelve
listed applications. Full OS integration remains pending while its separate
driver, filesystem, and userland project manifests are being reorganized.
Native text assembly now has a [byte-buffer builder sample](samples/native_text_builder/README.md)
for Linux and Windows; its `FromBytes` finishing intrinsic is native only.
The native collector now groups adjacent dead-span releases on Linux; the
[GC profiling notes](optimisations.md) retain its before/after measurements.
The 0.8.0 optimisation work has completed
[proven packed-array bounds elimination](https://github.com/Aurora-softwares/Hylang-Compiler/issues/167)
for guarded native loops. Broader local register and loop code generation in
[#127](https://github.com/Aurora-softwares/Hylang-Compiler/issues/127) is the
next performance target; real Windows-host validation remains a release gate.
Native source package work for the 0.5.0 target is in progress under
[#111](https://github.com/Aurora-softwares/Hylang-Compiler/issues/111).
The native CLI now packs and adds local source archives, removes direct
dependencies, resolves exact transitive dependencies from `.hylang/packages`,
and verifies the SHA-256 hashes in `hy.lock` during builds. It can search the
curated static registry, fetch a pinned package and its transitive dependencies,
restore a project from its lockfile, and upgrade a direct dependency to an
explicit version. Windows release packaging and the `hy.cmd` launcher have a
Wine-checked candidate. The PowerShell lifecycle and website installer pass
fixture tests on GitHub-hosted Windows runners. Published installer-ready assets
and a live Windows install from those assets remain open release gates.

## Build output

`hy build`, `hyc build`, and the self-hosted `hy build` update one terminal line per action. The braille spinner and bar show overall build progress, with a separate percentage for the active action. The bar uses up to 60 characters and shrinks in narrow terminals; long interactive progress text ends in `...` instead of wrapping. Terminal width is checked on each redraw, so resizing takes effect during a build. The line becomes its `100%` result when that action completes. Overall progress counts completed milestones, while lexing and parsing use source and token positions for their action percentages. Stages without measurable internal work stay at 0% until completion. The SDK spinner animates while a terminal build is busy. Redirected output uses full plain text without terminal escape codes.

Use `--hide-progress`, `--hide-spinner`, or `--hide-log` to remove individual parts. For example, `hy build MyApp/MyApp.hyproj --hide-progress` keeps the spinner and messages. Using all three flags leaves the normal output path or `wrote` result, plus any errors.

## Manage a released Hydrogen installation

The **packaged native compiler** for Linux x86-64 includes a shell launcher and
safe lifecycle commands. These are not commands of the C++ development SDK
binary (`./build/hy`) or an unbundled `hydrogen-stage1` binary.

```bash
hy --version
hy update-check
hy update
hy update --force
hy uninstall
hy uninstall --force
hy remove --force # alias for uninstall
```

The launcher detects APT/dpkg, DNF/YUM/RPM, Pacman and Homebrew ownership and
delegates package-management operations. Manual installations use an included
file manifest and GitHub Releases checksums/digests; they refuse to touch any
unmanaged files. `--force` skips prompts, but never disables safety checks.

This is available in newly packaged releases, not in old standalone compiler
binaries. See [Linux release installation details](release/README.md) and
[Windows release installation details](release/README-windows.md). The isolated
Linux lifecycle checks run with `ctest -R hy_release_lifecycle --output-on-failure`.
The Windows ZIP layout, `hy.cmd` launcher, and compiler delegation run under
Wine with `ctest -R hy_stage1_windows_release --output-on-failure`. GitHub
Actions also exercises the PowerShell lifecycle on a Windows runner; the
published release smoke test runs manually after installer-ready assets exist.

## Native source packages in development

The self-hosted compiler accepts exact package versions in a format 2 project:

```toml
[dependencies]
example = "1.0.0"
```

The package library must declare the same `version` and `[package] id`, and
live at `.hylang/packages/example/1.0.0/example.hyproj` beneath the project.
`hy package pack example.hyproj -o example.hypkg` creates a source-only archive.
`hy package add App.hyproj example.hypkg` installs a local archive. For the
curated website registry, use `hy package search math`,
`hy package add App.hyproj hydrogen.math@0.1.0`,
`hy package restore App.hyproj`, or
`hy package upgrade App.hyproj hydrogen.math@0.2.0` when that version exists.
`hy package remove App.hyproj example` removes the direct dependency and
refreshes the lock. `hy package lock App.hyproj` records a pre-existing local
package tree when each package directory also contains `package.hypkg`. Builds
verify the lock and fail if package files change. Commit `hy.lock`; the
`.hylang/packages` directory is a project-local cache. Development can point
at another HTTPS or local-file registry with `--registry <origin>`.

## Package a self-hosted release

The release candidate command compiles the current self-hosted compiler source
for Linux x86-64 and Windows x64, then creates both installer-compatible
archives and their `.sha256` sidecars. Pass a verified self-hosted compiler:

```bash
RELEASE_VERSION=alpha-0.0.3
cmake -DSOURCE_DIR="$PWD" -DHOST_COMPILER="/path/to/verified/hy" \
  -DVERSION="$RELEASE_VERSION" -DRELEASES_DIR="$PWD/releases" \
  -P cmake/MakeHydrogenReleaseCandidate.cmake
```

The command stages outputs until both platforms build and their archive
checksums pass. It refuses to overwrite existing assets unless `-DFORCE=ON` is
set. Australis is not included: its current AUEX/AUN1 targets are constrained
OS program formats, and there is no self-hosted compiler CLI project that runs
on Australis.

If CMake is already configured with `HYDROGEN_RELEASE_VERSION` and
`HYDROGEN_RELEASE_BINARY`, use
`cmake --build build --target hydrogen_release_candidate`.

To package only a previously verified Linux compiler at `safe/hy`, run:

```bash
RELEASE_VERSION=your-next-version
cmake -DSOURCE_DIR="$PWD" -DVERSION="$RELEASE_VERSION" -P cmake/PackageHydrogenRelease.cmake
```

This writes `releases/hydrogen-<version>-linux-x86_64.tar.gz` and its adjacent
`.sha256` checksum. The archive contains `bin/hy`, a release README, build
metadata, and `SHA256SUMS` for the executable. The command refuses to overwrite
an existing release; pass `-DFORCE=ON` only when intentionally rebuilding it.

If CMake is already configured, the Linux-only target is:

```bash
cmake -S . -B build -DHYDROGEN_RELEASE_VERSION="$RELEASE_VERSION"
cmake --build build --target hydrogen_package_release
```

To build and package the Windows x64 compiler from the same verified
self-hosted compiler, run:

```bash
cmake -DSOURCE_DIR="$PWD" -DHOST_COMPILER="/path/to/verified/hy" \
  -DVERSION="$RELEASE_VERSION" -DRELEASES_DIR="$PWD/releases" \
  -P cmake/MakeHydrogenWindowsRelease.cmake
```

This builds the Windows compiler executable, checks its PE header, then writes
`releases/hydrogen-<version>-windows-x86_64.zip` and its `.sha256` sidecar.
Like the Linux script, it refuses to overwrite an existing release unless
`-DFORCE=ON` is set. The ZIP contains `bin/hy.cmd`, `libexec/hy-core.exe`, a
PowerShell lifecycle helper, and the same manifest/checksum contract as the
Linux archive. Keep both platform archives and their sidecars together for an
installer-compatible GitHub release.

If CMake is already configured with `HYDROGEN_RELEASE_VERSION` and
`HYDROGEN_RELEASE_BINARY`, the equivalent target is
`cmake --build build --target hydrogen_package_windows_release`.
To package an already-built Windows executable without rebuilding it, use
`cmake/PackageHydrogenWindowsRelease.cmake` with `-DINPUT_BINARY=<path>`.

## Build the tools

Run these commands from this repository's root. The SDK requires CMake 3.20 or newer and a C++20 compiler. Its executable builds also require a host C compiler; static-library builds require an archiver. The direct native compiler targets Linux x86-64 and Windows x64.

```bash
cd /path/to/Hylang-Compiler

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

## UEFI and early kernel output

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
transport prefers a discovered NVMe controller, using depth-two admin and I/O
queues, namespace Identify, and bounded polling reads. It falls back to AHCI
READ DMA EXT when no NVMe aperture is mapped. Both paths read LBA 0, LBA 1,
and the GPT primary entry array. The builder validates the
protective MBR, the GPT 1.0 header and CRC, and the primary entry-array CRC;
the current bootstrap accepts 512-byte logical sectors and up to 256 standard
128-byte GPT entries. It records the controller kind and first present GPT
partition in KernelBootInfo ABI version 7. The image does not yet mount a
filesystem.
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
UEFI application, `type = "kernel"` for a raw freestanding kernel image,
`type = "exec"` for an Australis AUEX v1 program, and `type = "os"` for an
aggregate project. The older `type = "australis"` spelling remains accepted
for existing AUEX projects.

The AUEX backend supports scalar and string locals, assignment,
arithmetic including division and remainder, comparisons, short-circuit
Boolean expressions, `if`/`else`, `while`, `for`, `break`, and `continue`.
`System.Console.Write` and `WriteLine` accept strings and scalar values, and
`System.Console.ReadLine()` returns a string. `System.IO.File.Exists(path)`
and `ReadAllText(path)`, `System.IO.File.WriteAllText(path, text)`, and
`System.Convert.ToInt32(text)` use the same source API as native programs.
AUEX text values are currently limited to 255 bytes. `Main` may return a
computed integer exit code. Australis-specific file, metadata, directory,
yield, and checked-memory intrinsics remain available for lower-level work.
The current development AUEX backend also supports application method calls,
bounded strings and byte arrays, and concurrent child processes. These calls
remain software-checked inside the kernel interpreter.

Arrays such as `sources` and `project_references` can span lines, with one
quoted path per line and an optional trailing comma. A `collection` groups
independently built projects without naming the group an OS. It can also be
included by an OS project. Each child still declares its own relative `output`.

An OS project lists component `.hyproj` files in `project_references` and has
no sources of its own. Each component sets an `output` path relative to the
build directory, such as `EFI/BOOT/BOOTX64.EFI`. Hydrogen compiles each
component independently:

```toml
# OS.hyproj
format = 2
type = "os"
project_references = [
    "Components.hyproj",
]

# In Components.hyproj: type = "collection"
# project_references = ["Boot/Boot.hyproj", "Kernel/Kernel.hyproj"]

# In Boot/Boot.hyproj: type = "efi", output = "EFI/BOOT/BOOTX64.EFI"
# In Kernel/Kernel.hyproj: type = "kernel", output = "EFI/OS/KERNEL.BIN"
```

```bash
./build/self_hosting/hydrogen-stage1 build OS/OS.hyproj -o build/efi
```

The output directory contains a PE32+ EFI bootloader and a separate raw `AUKR`
kernel image ready for packaging. You can also build an `efi`, `kernel`, or `exec` project directly
with `-o` pointing to its output file. Scaffold them with
`hydrogen-stage1 new efi <name>`, `hydrogen-stage1 new kernel <name>`,
`hydrogen-stage1 new exec <name>`, or `hydrogen-stage1 new os <name>`.
Use `hydrogen-stage1 new collection <name>` to scaffold a collection.
These project types are currently available in
`hydrogen-stage1`.

For Windows x64, use `--target windows-x64` on a source file or a format-2
`type = "windows"` project. Both routes produce PE32+ console programs with
the same direct language subset and managed runtime APIs as Linux:

```bash
./build/self_hosting/hydrogen-stage1 compile tests/phase6/native_hello.hy --target windows-x64 -o build/hello.exe
./build/self_hosting/hydrogen-stage1 build tests/phase6/WindowsFullRuntime.hyproj -o build/WindowsFullRuntime.exe
```

The [native compiler guide](samples/self_hosting/README.md#windows-x64-target)
has the Windows runtime and verification details.

Australis OS additionally loads bounded AUN1 machine-code children in hardware
ring 3. Hydrogen's `exec` backend emits AUEX; a separate `native` project emits
AUN1 version 2 for a single static `Main(string[] args)` with ASCII literal
`System.Australis.Terminal.Write` calls and a literal integer return status.
The native target has no general-purpose runtime yet. See the
[AUN1 v2 contract](https://github.com/Aurora-Softwares/Australis-OS/blob/main/docs/aun1-v2.md).

SDK projects additionally support workspaces, test projects, local package dependencies, caching, and static-library artifacts. Useful SDK commands:

```bash
./build/hy new app MyApp
./build/hy check MyApp/MyApp.hyproj --json
./build/hy build MyApp/MyApp.hyproj
./build/hy run MyApp/MyApp.hyproj -- argument
./build/hy fmt MyApp --check
```

## Language and runtime

The direct native route supports classes, inheritance, interfaces, virtual dispatch, structs, overloads, static and instance fields/methods, constructors, recursion, enums, signed and unsigned integer widths, `bool`, strings, arrays, `var`, `if`/`else`, `while`, `for`, `break`, `continue`, and returns. `int` is signed 32-bit. Strings have byte-based length/indexing; indexing returns a one-byte string. Native literals accept ASCII and common escaped control characters; file contents and arguments preserve raw bytes.

The SDK and native compiler support fixed-width integer `&`, `|`, `^`, `~`,
`<<`, and `>>`. Shift counts are masked by the left operand's width minus one;
signed right shifts preserve the sign bit, while unsigned right shifts fill
with zero.
Integral lvalues also support `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`,
`<<=`, and `>>=`. The assignment returns the stored value and evaluates an
indexed or field target once. Compound shifts use the target's integer width.
Prefix and postfix `++` and `--` work on integral lvalues. Prefix returns the
new value; postfix returns the old value. Both evaluate the target once.
The conditional `condition ? whenTrue : whenFalse` expression requires a bool
condition and compatible branch types; only the selected branch runs.
Null coalescing with `left ?? fallback` accepts references, evaluates the left
once, and evaluates the fallback only when the left is null.
Null-conditional `receiver?.member`, `receiver?.Method(args)`, and
`receiver?[index]` evaluate the receiver once. A null receiver produces null
without evaluating call arguments or an index. The result must be a reference;
primitive-valued access and assignment through a null-conditional access are
rejected until nullable value types are supported.
`foreach (T value in collection)` captures the collection once and reads each
element at its current index. `break` and `continue` use ordinary loop rules.
Arrays and strings work in both compilers; strings use the language's current
byte-index semantics. The SDK also iterates `List<T>` through `Count()` and
`Get(index)`. Its count is checked each iteration, so additions can extend the
loop and `Set` changes are observed. No enumerator is created or disposed.
Interpolated strings use `$"literal {expression}"`. Literal text accepts the
ordinary `\\`, `\"`, `\n`, `\r`, and `\t` escapes; `{{` and `}}` write braces.
Embedded expressions run once in left-to-right order and use the existing
string-concatenation conversion for strings, numbers, and booleans. Formatting
suffixes such as `{value:x}` are rejected. Literal UTF-8 bytes are preserved
without normalization, and string length and indexing remain byte based.
`switch (value) { case constant: statements; default: statements; }` selects one
branch without fallthrough. A branch can use `break` to leave the switch.
`switch (value) { case constant => expression, default => expression }` yields a
value; a bool switch may omit `default` when it covers both `true` and `false`.
Cases accept constant numbers, strings, and booleans, and duplicate cases and
branches after `default` are errors. The switch value is evaluated once.
`continue` cannot target an outer loop across a switch; put the continuation
in a loop nested inside the selected branch.
`collection[start..end]` creates a new array or string containing positions
from `start` up to but excluding `end`. Both bounds are required and must be
`int`; the source and bounds are evaluated once, left to right. Bounds outside
`0..Length` or a reversed range fail at runtime. Arrays copy their element
slots once, so changing the source array does not change the slice; referenced
objects remain shared. String positions count UTF-8 bytes, matching existing
string length and indexing. Slicing may therefore select a partial UTF-8
sequence. Null-conditional slicing is not supported.

Native builtins include `System.Console.Write`/`WriteLine`, `System.IO.File` text/byte reads and writes and existence checks, `System.Convert.ToInt32`, and `System.Runtime.GC` collection/accounting. Objects are managed by a conservative non-moving mark/sweep collector using Linux memory mappings or Windows `VirtualAlloc`/`VirtualFree`. Windows file paths are converted from Hydrogen UTF-8 strings to Win32 UTF-16. File reads require seekable files.

The SDK additionally supports generics, string exceptions, `List<T>`, checked unsafe/manual-memory operations, `Buffer`, and `BinaryPrimitives`. These additional facilities are not implemented by the native compiler. The SDK interpreter evaluates both sides of `&&` and `||`; generated native and C-backed programs short-circuit. Write explicit conditional guards when sharing code with the interpreter.

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
