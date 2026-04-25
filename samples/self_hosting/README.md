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

Current status: the workspace has reusable core/syntax libraries from Phase 5 plus Phase 6 foundation projects for binding, IR, runtime model, and Linux x64 code generation. The native compiler path intentionally supports only a tiny `System.Console.WriteLine("...")` proof subset today; full self-hosting still needs the managed runtime clone, broad binding/type checking, and repeatable stage comparison.
