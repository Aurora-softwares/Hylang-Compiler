# Hydrogen Compiler Workspace

`samples/self_hosting` is the Phase 6 compiler workspace. It keeps the C++ bootstrap compiler as stage0 while growing the Hydrogen-written compiler toward binding, typed IR, native Linux x64 ELF output, and eventual stage1/stage2 self-hosting.

```bash
./build/hy build samples/self_hosting/Hydrogen.Compiler.hyproj
./build/hy test samples/self_hosting/Hydrogen.Compiler.hyproj
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- tokens tests/hello_world.hy
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- parse tests/hello_world.hy
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- check tests/phase6/native_hello.hy
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- compile tests/phase6/native_hello.hy -o build/native_hello
chmod +x build/native_hello
./build/native_hello
```

Current status: the workspace has reusable core/syntax libraries from Phase 5 plus Phase 6 foundation projects for binding, IR, runtime model, and Linux x64 code generation. The direct Linux x64 path now emits executable entrypoints with integer/bool locals, assignment, arithmetic/comparisons, `if`, `while`, literal `System.Console.WriteLine`, and integer returns. Full self-hosting still needs classes/fields at runtime, calls and dispatch, strings and arrays, file I/O, broad binding/type checking, and repeatable stage comparison.

## Stage 1 Skeleton (Phase 6B)

The Hydrogen CLI `check` command can now emit a bound + IR debug dump:

```bash
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- check samples/self_hosting/Hydrogen.Compiler.Cli/Program.hy --emit-ir
```

For source outside that executable subset, the Hydrogen CLI still emits the existing IR-debug ELF bridge while the backend grows. The eventual stage1 compiler must use the direct path for the full compiler workspace.

```bash
./build/hy run samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -- compile samples/self_hosting/Hydrogen.Compiler.Cli/Program.hy -o build/hydrogen_stage1_skeleton
chmod +x build/hydrogen_stage1_skeleton
./build/hydrogen_stage1_skeleton
```
