# Hydrogen

This archive contains the self-hosted Hydrogen compiler for Linux x86-64.

## Install

Add the archive's `bin` directory to your shell `PATH`:

```bash
export PATH="/path/to/hydrogen-release/bin:$PATH"
```

Then compile Hydrogen source with `hy`:

```bash
hy check hello.hy
hy compile hello.hy -o hello
chmod +x hello
./hello
```

The default target emits a Linux x86-64 executable. The constrained UEFI
target is available with:

```bash
hy compile uefi_hello.hy --target uefi-x64 -o BOOTX64.EFI
```

`BOOTX64.EFI` is firmware code, not a Linux executable. The UEFI target supports
ASCII-literal console output, screen clearing, one key wait, and EFI image
launch. Its early-kernel profile also supports a fixed boot-services exit,
memory/paging initialization, heap, framebuffer output, and halt sequence. It
does not provide a general UEFI runtime or standard library.

## Verify the compiler

`SHA256SUMS` in this archive contains the checksum of `bin/hy`. The companion
`.tar.gz.sha256` file published with the archive checks the complete download.

See the Hydrogen documentation and issue tracker:

- https://github.com/Aurora-Softwares/Hylang-Docs
- https://github.com/Aurora-Softwares/Hylang-Compiler/issues
