# Hydrogen OS Target Roadmap

This document is the plan for making Hydrogen a viable language for producing native UEFI EFI binaries — culminating in Australis OS being written 100% in Hydrogen.

It is a companion to ROADMAP.md. It does not replace the main compiler roadmap; it tracks the narrower goal of UEFI output and OS-level code generation.

## Goal

Produce a bootable UEFI EFI binary compiled entirely from Hydrogen source, with no C, no bflat, and no external assembler or linker — only the Hydrogen native compiler pipeline.

## The Two Hard Blockers

Two fundamental gaps currently prevent any Hydrogen program from running as a UEFI application.

### Blocker 1: No PE/COFF Output Target

The Phase 6 native codegen (`ElfImageBuilder.hy`) emits Linux x64 ELF binaries. UEFI firmware requires PE32+ (Portable Executable) format — the same binary format used by Windows executables, with a specific subsystem flag of `EFI_APPLICATION` (10).

ELF and PE/COFF are completely different binary formats. An ELF binary cannot be loaded by UEFI firmware regardless of what code it contains. The fix is a new output path: `PeImageBuilder.hy` alongside the existing `ElfImageBuilder.hy`.

PE32+ differs from ELF in the following ways that matter here:

- **MZ/PE header chain**: PE files begin with a DOS MZ stub (magic `0x4D 0x5A`), a PE offset at byte `0x3C`, then a 4-byte PE signature (`PE\0\0`), followed by a COFF header and a PE32+ optional header. None of this structure exists in ELF.
- **Section layout**: PE uses named sections (`.text`, `.rdata`) with file alignment of 512 bytes and memory alignment of 4096 bytes. ELF uses program headers with arbitrary load addresses.
- **Subsystem field**: The PE optional header's `Subsystem` word must be set to `10` (`EFI_APPLICATION`) for UEFI firmware to accept the image.
- **Image base**: UEFI loads images at firmware-chosen addresses. A non-relocatable image must either include a relocation directory or use a fixed load address with no base relocation table (a simplification valid for a first proof).
- **Calling convention**: UEFI uses the Microsoft x64 ABI (first four integer arguments in RCX, RDX, R8, R9 with 32 bytes of shadow space on the stack). The existing Phase 6 codegen targets the Linux System V AMD64 ABI (arguments in RDI, RSI, RDX, RCX, R8, R9). These are incompatible. UEFI entry points and all UEFI protocol calls must use Microsoft x64.

### Blocker 2: GC Runtime Initialization

The Hydrogen runtime always initializes the mark-sweep garbage collector at program startup. On Linux this works because the OS provides a heap allocator (`malloc`/`free`) that the GC builds on. On bare-metal UEFI there is no OS — the only memory services available are those exposed by the UEFI firmware itself (`EFI_BOOT_SERVICES.AllocatePool`, `AllocatePages`).

The GC initialization code assumes a POSIX-like heap and will not execute correctly in a bare-metal UEFI environment. More fundamentally, OS kernel code needs to own its own memory model from the first instruction — it cannot accept GC pauses or runtime overhead it did not arrange.

The fix has two parts: a compile-time mode that suppresses GC initialization for UEFI targets, and an entry-point mechanism that matches the UEFI ABI instead of the standard `Main(string[] args)` convention.

## Recommended Path

The recommended path is five phases. Each phase ends with a concrete working artifact that proves the foundation before the next phase is built on top of it.

### Phase 0: UEFI-A: PE/COFF Output

This phase resolves Blocker 1.

Goal: the Hydrogen native compiler can emit a valid PE32+ EFI binary that UEFI firmware will load and execute.

Checklist:

- [ ] Add `Hydrogen.Compiler.CodeGen.Uefi` alongside the existing `Hydrogen.Compiler.CodeGen.X64` project
- [ ] Write `PeImageBuilder.hy` that emits a well-formed PE32+ image:
  - MZ stub with PE offset at byte `0x3C`
  - PE signature (`0x50 0x45 0x00 0x00`)
  - COFF header: machine `0x8664` (x86-64), section count, zero symbol table
  - PE32+ optional header: magic `0x020B`, entry point RVA, image base, section alignment `0x1000`, file alignment `0x200`
  - Subsystem field set to `10` (EFI_APPLICATION)
  - DLL characteristics: `0x0140` (no bind, NX compatible)
  - `.text` section header and section data, file-aligned to 512 bytes
  - `.rdata` section for string literals
- [ ] Add a `NativeRuntimeContract` for target name `uefi-x64-pe` with object model `uefi-phase-a`
- [ ] Add `--target uefi-x64` flag to the Hydrogen compiler CLI that selects `PeImageBuilder`
- [ ] Update the x64 code emitter to use Microsoft x64 ABI when the target is `uefi-x64-pe`:
  - Pass first argument in RCX, second in RDX, third in R8, fourth in R9
  - Allocate 32 bytes of shadow space before any call
  - Adjust the function prologue/epilogue to match the Microsoft x64 frame layout
- [ ] Emit a proof program: a tiny Hydrogen source that calls a UEFI ConOut output function via raw pointer and exits — no managed runtime, no GC, only `unsafe` pointer operations
- [ ] Boot the proof binary in QEMU with OVMF firmware and confirm it reaches the entry point

Exit criteria:

- `hyc compile proof.hy --target uefi-x64 -o BOOTX64.EFI` produces a file that OVMF loads without an error
- The proof program executes at least one instruction inside UEFI before exiting or hanging

---

### Phase 1: UEFI-B: No-Runtime Entry Mode

This phase resolves Blocker 2.

Goal: the compiler has a supported way to produce UEFI entry points that skip GC initialization and match the UEFI entry signature.

The standard `Main(string[] args)` entry point cannot be used for UEFI. A UEFI entry point has the signature:

```
EFI_STATUS ImageEntryPoint(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE* SystemTable)
```

Where `EFI_HANDLE` and `EFI_SYSTEM_TABLE*` are both raw 64-bit pointers. This needs a dedicated attribute and compiler support.

Checklist:

- [ ] Add a `[UefiEntry]` attribute to the language (or to the Hylang.Uefi package)
- [ ] When the compiler sees `[UefiEntry]` on a `static` method it must:
  - Accept the signature `static ulong EntryPoint(ulong imageHandle, ulong systemTable)` (raw pointer-sized integers) rather than `Main(string[] args)`
  - Emit a UEFI-ABI-compatible entry stub: the PE optional header entry point RVA points to generated code that calls this method with `RCX` and `RDX` as the two arguments
  - Suppress all GC initialization: no heap setup, no root frame registration, no GC threshold configuration
  - Suppress the standard argument vector (`argc`/`argv`) setup
- [ ] Add a compile-time error when managed `new` expressions appear in the same compilation unit as a `[UefiEntry]` method without an explicit UEFI allocator in scope (prevents accidental GC dependency)
- [ ] Allow all `unsafe` blocks to appear at top level (not nested inside a managed class) for UEFI source files
- [ ] Update `NativeRuntimeContract` for `uefi-x64-pe` to record entry mode as `uefi-no-runtime`
- [ ] Prove: a `[UefiEntry]` Hydrogen method that dereferences the SystemTable pointer and reads the firmware revision field, compiled and booted in QEMU

Exit criteria:

- A Hydrogen source file with `[UefiEntry]` compiles to a PE binary that boots without any GC or runtime initialization
- The entry point receives valid `ImageHandle` and `SystemTable` pointer values from UEFI firmware

---

### Phase 2: UEFI-C: UEFI Protocol Interop Layer

Goal: a `Hydrogen.Uefi.Core` package that provides unsafe struct definitions for the core UEFI data tables, so Hydrogen code can interact with firmware services without writing raw byte offsets by hand.

This phase does not add any runtime. Everything is `unsafe` struct layouts and pointer operations.

Checklist:

- [ ] Add a `Hydrogen.Uefi.Core` project under `samples/australis` or a dedicated location
- [ ] Define the following as `unsafe struct` types with explicit field layout matching the UEFI 2.x specification:
  - `EfiTableHeader` (signature, revision, headerSize, crc32, reserved)
  - `EfiSystemTable` (hdr, firmwareVendor, firmwareRevision, consoleInHandle, conIn, consoleOutHandle, conOut, standardErrorHandle, stdErr, runtimeServices, bootServices, numTableEntries, configTable)
  - `EfiBootServices` (hdr, then all function pointer fields as `ulong` initially; expand to typed function pointers as needed)
  - `EfiRuntimeServices` (hdr, then function pointer fields)
  - `EfiSimpleTextOutputProtocol` (reset and outputString function pointers, plus mode pointer)
  - `EfiMemoryDescriptor` (type, physStart, virtStart, numPages, attribute)
- [ ] Define `EfiStatus` as an enum over `ulong` with the standard UEFI status codes (`Success = 0`, `LoadError`, `InvalidParameter`, etc.)
- [ ] Define `EfiMemoryType` as an enum for `AllocatePool` / `AllocatePages` calls
- [ ] Add helper methods for calling UEFI function pointers from Hydrogen unsafe code (calling convention must be Microsoft x64)
- [ ] Validate struct sizes match the UEFI specification using `sizeof` assertions at compile time
- [ ] Write a proof program that uses `EfiSystemTable` to call `ConOut.OutputString` and print text to the UEFI console

Exit criteria:

- A Hydrogen program can read the UEFI firmware vendor string and print it to the console using only `Hydrogen.Uefi.Core` types
- No raw byte offsets appear in the application source — all struct access goes through named fields

---

### Phase 3: UEFI-D: Minimal UEFI Standard Library

Goal: a thin but ergonomic UEFI standard library (`Hydrogen.Uefi`) that covers the operations needed to write a minimal OS kernel: console output, memory allocation, memory map retrieval, and exit from boot services.

Checklist:

- [ ] Add `Hydrogen.Uefi.Console` with safe wrappers over `EfiSimpleTextOutputProtocol`:
  - `UefiConsole.Write(string text)` — outputs a null-terminated UCS-2 string via ConOut
  - `UefiConsole.Clear()` — clears the console
  - `UefiConsole.SetAttribute(int attribute)` — sets foreground/background color
- [ ] Add `Hydrogen.Uefi.Memory` with wrappers over UEFI boot services memory calls:
  - `UefiMemory.Allocate(ulong size)` — calls `AllocatePool(EfiLoaderData, size, out ptr)`
  - `UefiMemory.Free(ulong* ptr)` — calls `FreePool(ptr)`
  - `UefiMemory.GetMemoryMap(...)` — wraps `GetMemoryMap` for retrieving the UEFI memory map before `ExitBootServices`
- [ ] Add `Hydrogen.Uefi.Boot` with:
  - `UefiBootServices.ExitBootServices(ulong imageHandle, ulong mapKey)` — calls `EFI_BOOT_SERVICES.ExitBootServices`; after this call no boot services may be used
  - `UefiBootServices.Stall(ulong microseconds)` — busy waits via firmware
- [ ] Store the SystemTable pointer in a module-level `unsafe` global set during `[UefiEntry]` so all library functions can access it without threading it through every call
- [ ] Write a proof application that: prints a boot banner via `UefiConsole`, allocates and frees a memory block, retrieves the memory map, calls `ExitBootServices`, then halts
- [ ] Confirm the proof application boots cleanly in QEMU/OVMF

Exit criteria:

- A Hydrogen source file under 100 lines can produce a UEFI application that prints output and exits boot services without any raw pointer arithmetic in the application code
- All UEFI protocol calls are wrapped; application code does not dereference struct fields manually

---

### Phase 4: OS-A: Australis OS Boot in Hydrogen

Goal: the Australis OS `Program.hy` (currently the reference file that mirrors the C# version) becomes the canonical boot implementation, compiled by the Hydrogen native compiler into a valid `BOOTX64.EFI` that boots and prints the boot message.

This is the milestone where Australis OS is 100% Hydrogen, end to end.

Checklist:

- [ ] Translate the current Australis boot program into Hydrogen using `[UefiEntry]` and `Hydrogen.Uefi.Console`
- [ ] Wire the Australis build system (Makefile or `.hyproj`) to invoke `hyc compile --target uefi-x64` and place the output at `EFI/BOOT/BOOTX64.EFI` inside the FAT image
- [ ] Remove the bflat / C# dependency from the Australis OS build entirely
- [ ] Boot the resulting image in QEMU/OVMF and confirm the boot message is displayed
- [ ] Confirm the binary is a well-formed PE32+ EFI image (checkable with `file` or a PE parser)
- [ ] Update the Australis OS README to document the Hydrogen build path

Exit criteria:

- `make` in the Australis OS repo produces a bootable FAT image with a UEFI binary compiled entirely from Hydrogen source
- The image boots in QEMU/OVMF and reaches the boot message with no C, no bflat, and no external assembler or linker involved

---

## Phase Dependencies

These phases must be completed in order. Each one unblocks the next.

```
UEFI-A (PE/COFF output)
  └── UEFI-B (no-runtime entry)
        └── UEFI-C (UEFI protocol structs)
              └── UEFI-D (UEFI standard library)
                    └── OS-A (Australis OS in Hydrogen)
```

UEFI-A and UEFI-B together resolve the two hard blockers. UEFI-C and UEFI-D are ergonomic layers that make OS-A feasible to write cleanly.

## Relationship to the Main Roadmap

These phases sit between Phase 6 (Self-Hosted Compiler) and Phase 10 (System Software) in the main ROADMAP.md. They are not a replacement for Phase 10 — they are the earliest viable slice of it, targeting only the minimal OS boot case.

The full Phase 10 scope (kernel-adjacent libraries, drivers, memory management beyond boot services, process isolation) remains future work after OS-A proves the pipeline.

Phase 7 (Full Standard Library) and Phase 8 (Backend Evolution) do not need to be complete before UEFI-A through OS-A. These UEFI phases are narrow enough to proceed in parallel.

## What Each Phase Does Not Cover

**UEFI-A through OS-A do not cover:**

- Exception handling in UEFI/kernel context — no UEFI equivalent of try/catch; panics should halt or print and hang
- Floating-point in UEFI — UEFI firmware disables SSE/AVX before boot services exit; keep all OS-A code integer-only
- Multi-processor startup (AP bringup) — out of scope until after a working single-core boot
- Memory paging and virtual address space — `ExitBootServices` leaves a flat identity-mapped address space; paging setup is a future kernel milestone
- Drivers, filesystems, input handling — all follow-on work after OS-A lands

## Notes on the Microsoft x64 ABI

Every function pointer in a UEFI protocol table uses the Microsoft x64 calling convention. This is different from what the existing Phase 6 codegen targets (Linux System V). The key differences that must be handled in Phase UEFI-A:

| Rule | System V (Linux) | Microsoft x64 (UEFI) |
|---|---|---|
| Integer arg 1 | RDI | RCX |
| Integer arg 2 | RSI | RDX |
| Integer arg 3 | RDX | R8 |
| Integer arg 4 | RCX | R9 |
| Shadow space | None | 32 bytes always |
| Volatile registers | RAX, RCX, RDX, RSI, RDI, R8-R11 | RAX, RCX, RDX, R8-R11 |
| Callee-saved | RBX, RBP, R12-R15 | RBX, RBP, RDI, RSI, R12-R15 |

The simplest approach in Phase UEFI-A is to add a `MsX64` calling convention flag to the IR and emit the correct prologue, argument moves, and shadow space allocation when calling UEFI function pointers. Internal Hydrogen-to-Hydrogen calls can continue using System V within the binary; only calls through UEFI protocol function pointers need Microsoft x64.

## Living Document Notes

This document should be updated when:

- a phase checklist item is completed
- a technical detail (struct layout, ABI rule, or PE field) is found to be wrong during implementation
- the Australis OS roadmap changes its boot architecture
- Phase 6 native codegen advances in ways that simplify or change the approach here
