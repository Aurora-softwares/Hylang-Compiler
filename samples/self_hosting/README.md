# Hydrogen Compiler Prototype

`samples/self_hosting` is the Phase 5 proof workspace. It prepares for self-hosting by implementing reusable compiler-facing libraries in Hydrogen while the C++ bootstrap compiler remains the trusted implementation.

```bash
./build/hy build samples/self_hosting/Hydrogen.Compiler.hyproj
./build/hy test samples/self_hosting/Hydrogen.Compiler.hyproj
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- tokens tests/hello_world.hy
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- parse tests/hello_world.hy
```

The prototype is syntax-only: it lexes and parses source structure, but it does not bind, type-check, lower IR, generate code, or replace the bootstrap compiler.
