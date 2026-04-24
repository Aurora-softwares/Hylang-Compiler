# HexLab

HexLab is the current showcase project for Hylang’s workflow and byte-oriented file tooling. It is a pure-Hylang workspace with:

- `HexLab.Core`
- `HexLab.Cli`
- `HexLab.Tests`

From the repo root:

```bash
./build/hy build samples/hexlab/HexLab.hyproj
./build/hy test samples/hexlab/HexLab.hyproj
./build/hy fmt --check samples/hexlab
./build/hy check samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj --json
./build/hy package pack samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj
```

Useful demo commands:

```bash
./build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- inspect samples/hexlab/demo.bin
./build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- dump samples/hexlab/demo.bin 8
./build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- search samples/hexlab/demo.bin 89504E47
./build/hy run samples/hexlab/HexLab.Cli/HexLab.Cli.hyproj -- diff samples/hexlab/demo.bin samples/hexlab/demo.bin
```

Current expected outputs:

```text
format=PNG width=1 height=1
0: 89 50 4E 47 0D 0A 1A 0A 00 00 00 0D 49 48 44 52
16: 00 00 00 01 00 00 00 01
found offset=0
equal
```

Current implementation notes:

- `HexLab.Core` now routes dump, diff, search, and slice hot paths through the bootstrap `System.Runtime.Buffer`
- PNG inspection now exercises the 64-bit `BinaryPrimitives` path
- search includes an explicit `unsafe` fast path through `Buffer.DangerousData()` to demonstrate the systems surface

Command surface:

```text
usage: hexlab dump <file> [width] [start] [count]
   or: hexlab inspect <file>
   or: hexlab diff <left> <right>
   or: hexlab search <file> <hex-pattern>
   or: hexlab slice <file> <start> <count> <out>
```
