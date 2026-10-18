# Hydrogen OS and firmware roadmap

This separates the published `alpha-0.0.2` compiler profile from the newer development checkout used by Australis OS. For exact commands and source-language support, see the [compiler README](README.md), [native compiler guide](samples/self_hosting/README.md), and [Australis OS plan](https://github.com/Aurora-Softwares/Australis-OS/blob/main/PLAN.md).

## Working target paths

| Path | Current capability | Boundary |
| --- | --- | --- |
| Linux x86-64 | Direct ELF output with the managed Linux runtime | Linux syscalls and runtime do not apply to UEFI or Australis |
| Published `uefi-x64` profile | Constrained PE32+ firmware/early-kernel sequence | Not a general UEFI library or arbitrary firmware ABI |
| Development `efi` + `kernel` + `os` projects | PE32+ bootloader plus separate raw `AUKR` freestanding kernel | Requires the development compiler checkout for current Australis OS |
| Development `exec` projects | Checked AUEX v1 `.exec` applications | Interpreter-based isolation, not hardware ring 3 |
| Development `native` projects | AUN1 v2 images for a single static entry with literal terminal writes and exit status | Small subset; no general native runtime or syscall parity |

The current Australis image boots under QEMU/OVMF on AHCI and NVMe, mounts a read-only HyFS 2 system root, starts PID 1 and its text shell, and runs AUEX applications with bounded process, terminal, file, and channel APIs. The OS's AUN1 child path has private user mappings, a guarded stack, PID/exit and checked terminal-write syscalls, and contained page/general-protection faults. Hydrogen emits a narrow AUN1 v2 image from source. These checks do not establish physical-machine support or a complete native application runtime.

## Compiler and ABI work

1. Expand the [AUN1 v2 contract](https://github.com/Aurora-Softwares/Australis-OS/blob/main/docs/aun1-v2.md) and Hydrogen's small `native` subset to cover control flow, data, and relocations with checked image validation.
2. Port file, process, and channel APIs from the AUEX contract to native syscalls and extend terminal I/O beyond the bounded serial write. Specify pointer validation, copying, fault behavior, handles, and ownership at the kernel boundary.
3. Provide a freestanding native runtime profile with explicit allocation and lifetime rules. Linux's managed collector and syscalls cannot be reused unchanged in ring 3.
4. Add native preemption/context switching, resource accounting, and tests for concurrent children and cleanup.
5. Expand UEFI bindings through explicit layouts, function pointers, strings, and calling-convention adapters rather than treating internal Hydrogen calls as firmware ABI calls.

Keep the Linux self-compilation comparison as a compiler regression baseline. Use target-specific image validation, QEMU boot tests, AUEX behavior tests, native fault-containment tests, and eventually supported physical machines for OS validation. A bootable image alone proves startup, not general language or runtime parity.
