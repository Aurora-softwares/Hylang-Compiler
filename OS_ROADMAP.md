# Hydrogen OS and firmware design plan

This is a plan for future targets, not a guide to executable features. The self-hosted compiler now has a deliberately constrained `uefi-x64` proof target: it emits a PE32+ x86_64 EFI application that writes ASCII `System.Console.WriteLine` literals as UTF-16 through the firmware text-output protocol. The complete native runtime remains a Linux x86-64 ELF with Linux syscalls; it cannot become a general UEFI application, an Australis executable, or a freestanding kernel merely by changing its extension.

For present language/runtime support, see the [native compiler guide](samples/self_hosting/README.md). SDK unsafe syntax does not establish native firmware or arbitrary-address interoperability.

## Current target boundary

The native backend emits executable method bodies and a bundled managed runtime. Hydrogen-to-Hydrogen calls use an internal stack convention with `rax` returns, not the System V C ABI. Linux console/file operations and heap memory use raw syscalls. Managed allocations use anonymous mappings with a conservative collector; this runtime does not allocate through `malloc`/`free`.

The SDK's C-backed runtime is separate and does use host runtime allocation. Neither existing route provides a firmware target, external function-pointer ABI, explicit native object layout, or a no-runtime kernel profile.

## Firmware target

A firmware backend would need:

1. A target descriptor covering image format, entry point, relocation, addressing, and external calling conventions.
2. Appropriate firmware image emission rather than the existing Linux ELF wrapper.
3. Native pointer/function-pointer calls, explicit layout, and ABI adapters at firmware service boundaries.
4. A reduced-runtime profile that avoids managed allocation and Linux syscalls during startup.
5. Bindings for console, memory, image loading, and boot-service operations.
6. Emulator-based regression tests and a minimal image that prints a message and returns before adding a kernel handoff.

Internal Hydrogen calls can retain their own convention only if target service calls have explicit adapters. Firmware protocol layouts and call rules must be implemented against the chosen target specification; current Hydrogen object layout is not a substitute.

## Allocation and runtime profiles

Separate managed application allocation from early-boot and kernel ownership. A future profile needs clearly defined allocation/free services, failure behavior, and lifetime rules. Firmware services cannot be assumed available after a kernel handoff. Managed collection should be introduced only after roots, stack scanning, allocator services, and runtime initialization are defined for that target.

Possible profiles include a freestanding core, explicit/manual allocation, and an optional managed runtime. These are design choices, not current compiler flags. Native `unsafe`, `stackalloc`, fixed layout, interrupts, and raw device access still require implementation before systems examples can execute.

## Kernel handoff

After a minimal firmware application works, define an explicit boot-information contract and kernel entry ABI. The handoff should supply the memory information and platform data needed by the kernel, with deliberate ownership of retained allocations and service lifetimes.

Test image loading, entry arguments, stack setup, memory ownership, error reporting, and the transition to kernel-owned allocation independently. Do not assume the existing Linux entry stub or collector is suitable.

## Australis userland

An Australis target needs its own startup, syscall/runtime bindings, process exit, console/filesystem services, process/environment APIs, and executable-loader contract. Port userland tools first once those boundaries are available; device/driver and kernel-adjacent libraries can follow explicit low-level support.

## Validation

Keep Linux native self-compilation as a regression baseline. Add target-specific image validation and emulator smoke tests, then application/runtime tests appropriate to each new profile. A bootable message alone proves image startup, not native language or managed runtime parity.

See the [compiler roadmap](ROADMAP.md) and [standard-library design plan](https://github.com/Aurora-Softwares/Hylang-Stdlib) for the related library and backend work.
