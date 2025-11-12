# Hydrogen Compiler Scaffold

Hydrogen (`.hy`) is an experimental systems programming language with a C-family surface. This scaffold provides a minimal lexer,
parser, and LLVM-based code generator that can produce LLVM IR or a native executable for the canonical "hello, world" style
program (`return 0`).

## Prerequisites
- A recent LLVM installation (LLVM 15+ recommended) with development libraries and `lld`.
- CMake 3.15 or newer.
- A C++17-compatible compiler.

## Building
```bash
mkdir build
cd build
cmake ..
cmake --build .
```

## Usage
From the build directory:

```bash
./hyc version
./hyc ir ../tests/hello.hy
./hyc build ../tests/hello.hy
```

- `hyc ir` lexes, parses, and lowers the input source file, writing LLVM IR to `stdout`.
- `hyc build` emits a temporary object file and links it into a native executable (`a.out` on Unix, `a.exe` on Windows). The
  temporary object is deleted once linking succeeds; the executable remains next to the command invocation.

## Documentation
See the [`docs/`](docs/index.md) directory for a growing reference on language constructs, tokens, and CLI behavior.

## Extending
The source is organized into modular components (lexer, parser, AST, code generation) with `// TODO:` breadcrumbs indicating
likely extension points for expressions, richer types, async, and other language features.
