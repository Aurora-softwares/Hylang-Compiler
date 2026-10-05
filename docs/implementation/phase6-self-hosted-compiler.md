# Native compiler architecture and bootstrapping

The Hydrogen-written compiler emits standalone Linux x86-64 ELF executables. It binds its CLI project's complete source/reference closure and can compile itself. User-facing commands and feature limits are documented in the [native compiler guide](../../samples/self_hosting/README.md).

## Executable IR and checking

`ExecutableLowering` copies syntax declarations and bodies into independent structured IR. `ExecutableChecker` resolves types/calls and checks scopes, arguments, returns, fields, access, indexing, assignments, and loop control. All bodies are checked, including methods unreachable from `Main`.

`IrLowering` supplies the executable module to the backend. IR contains parameter and return types plus actual method operations; native compilation does not depend on an outline/signature-only dump. Semantic locations use `1:1` where AST node spans are unavailable. Return-path analysis is conservative.

The backend emits methods reachable from `Main`, patches calls after emission, and supports recursion. Unsupported executable operations or runtime intrinsics cause compilation failure, with no output creation/overwrite. `check --emit-ir` is an explicit inspection command, not a fallback runnable ELF.

## Internal calling convention

Arguments are evaluated left to right and pushed into eight-byte stack slots. Instance receivers precede explicit arguments. Callees establish an `rbp` frame, copy parameters to mutable local slots, and return through `rax`. The caller removes argument slots. `rbp` is preserved; `r14`/`r15` are reserved for runtime state, and other registers are caller-clobbered.

This is a Hydrogen internal convention, not System V or C interoperability. The ELF entry stub adapts Linux process startup to `Main`; only that stub exits after a normal entrypoint return.

## Runtime

The runtime uses raw Linux syscalls and anonymous mappings, with conservative non-moving mark/sweep collection. It preserves interior roots, deep object graphs, and cycles. A temporary page index finds allocation headers during tracing; an intrusive worklist visits marked payloads. Generated frames zero slots and clear locals on normal scope exit to limit stale roots.

A bounded 16 MiB recycled-page pool reduces syscall churn and is released by explicit collection. String indexing uses immutable one-byte runtime strings. This runtime is separate from the SDK's C-generated collector and environment stress controls.

`tools/native-runtime/runtime.S` is the runtime assembly authoring source. `python3 tools/native-runtime/generate.py` regenerates the checked-in Hydrogen byte emitter. GNU binutils are needed for that development step, not for normal native compiler/application builds.

## Initial seed and native generations

From the compiler repository root:

```bash
cmake -S . -B build
cmake --build build --target hydrogen_stage1
cmake --build build --target hydrogen_bootstrap_proof
cat build/self_hosting/bootstrap-proof.txt
```

The initial target uses the C++ SDK's C backend to create `hydrogen-bootstrap`. That Hydrogen CLI emits the native compiler `hydrogen-stage1`. The proof uses stage 1 to build stage 2 and stage 2 to build stage 3 through the same compiler project closure.

All three native compilers run token/parser goldens and the same function/recursion, runtime/GC/files, project-semantic/IR, and compilation-failure suites. Stage 2/3 compiler executables and representative application outputs must have identical hashes. Stage 1 equality is reported as well; an older seed may differ after a backend change but must still pass behavioral checks.

Native proof builds/tests run with an empty `PATH` and a 1 GiB address-space limit. CMake and `prlimit` are test drivers. Artifacts and the success report are published after checks pass.

## Rebuild without stage 0

Preserve a verified native seed outside the new output directory:

```bash
cp build/self_hosting/hydrogen-stage3 build/hydrogen-seed
./build/hydrogen-seed build samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o build/hydrogen-rebuilt
chmod +x build/hydrogen-rebuilt
```

To repeat the full proof from that seed:

```bash
cmake -DSOURCE_DIR="$PWD" -DOUTPUT_DIR="$PWD/build/native-bootstrap" \
  -DSTAGE1_BINARY="$PWD/build/hydrogen-seed" -P cmake/HyBootstrapProof.cmake
```

This establishes repeated native self-compilation for the supported Linux x64 subset. A source-only checkout still needs a seed/bootstrap route. The SDK's broader language and workflow implementation has not been ported wholesale; removing C++ also requires replacing or retiring those features and their build/test dependencies.
