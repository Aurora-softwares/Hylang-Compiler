# Command Line Interface

The `hyc` executable exposes three subcommands.

## `hyc version`
Prints the compiler version string.

```bash
$ hyc version
hyc 0.1.0
```

## `hyc ir <file.hy>`
- Lexes, parses, and lowers the input Hydrogen source file.
- Emits LLVM IR to standard output.
- Useful for inspecting code generation while iterating on the front end.

## `hyc build <file.hy>`
- Produces an object file via LLVM's target machine and then links it into a native executable.
- On Unix-like systems the executable defaults to `a.out`; on Windows it is `a.exe`.
- A temporary object file (`a.out.o` or `a.exe.o`) is removed after linking.

// TODO: Add flags for specifying output names, optimization levels, linking libraries, and emitting assembly.
