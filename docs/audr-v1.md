# AUDR v1: Australis kernel driver image

`type = "driver"` projects produce `.driver` images. Build with `hy build
ExampleDriver.hyproj -o Example.driver`; `hy check` also validates that the
freestanding entry can be emitted. The entry must be
`public static int DriverMain.Run(long context)`. `context` is the physical
`KernelBootInfo` address used by the Australis kernel. An 11-byte entry shim
bridges the kernel's register call to Hydrogen's stack-argument calling
convention. Return zero for success;
any other value rejects initialization.

All integers in the image header are little endian. The image is exactly 24
bytes of header followed by 1–65,536 bytes of native x86-64 code:

| Offset | Size | Value |
| --- | ---: | --- |
| 0 | 4 | ASCII `AUDR` |
| 4 | 1 | format version `1` |
| 5 | 1 | entry ABI `1` |
| 6 | 2 | flags `0` |
| 8 | 4 | code length |
| 12 | 4 | entry offset `0` |
| 16 | 4 | IEEE CRC-32 of code bytes |
| 20 | 4 | reserved `0` |
| 24 | code length | position-independent code |

Australis loads only paths listed, one per line, in `/drivers.list` on the
system volume. Paths must be absolute, end in `.driver`, and use ASCII letters,
digits, `/`, `-`, `_`, or `.`. Example:

```text
/Example.driver
```

The loader accepts at most eight drivers and retains successfully initialized
code until shutdown. An absent manifest has no effect on existing built-in
drivers. A bad manifest or image is rejected and logged on the serial console.

**Trust boundary:** AUDR modules run with kernel privileges and can access
hardware and kernel memory. CRC-32 detects accidental damage; it does not
authenticate a publisher. Only install modules from trusted sources on a
trusted system volume. AUDR v1 supplies one boot-time entry point. Device
matching, typed hardware access, interrupt registration, callbacks, unload,
signatures, and isolation are not defined yet; networking, graphics, and USB
drivers require those later contracts before they can replace built-in drivers.
