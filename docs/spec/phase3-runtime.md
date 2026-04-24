# Hylang Phase 3 Runtime Notes

This document records the Phase 3 runtime foundation that is implemented in the bootstrap compiler today.

## Scope

Phase 3 focuses on the managed runtime surface needed for real Hylang programs:

- managed `string`
- general managed `T[]`
- bootstrap `System.Collections.List<T>`
- compiled-runtime garbage collection
- runtime stress controls

Unsafe/manual-memory features are deliberately excluded from executable behavior in this phase.

## Strings

- `string` is immutable.
- The runtime representation is UTF-8 byte-oriented.
- `string.Length` returns byte length.
- `text[index]` is byte-based and returns a one-byte `string`.
- String concatenation, equality, console output, and file IO continue to use the same source-level syntax as earlier phases.

## Arrays

- `T[]` is a first-class managed reference type.
- Arrays are allocated with `new T[count]`.
- `count` must be `int`.
- `void[]` is invalid.
- Elements are zero/default-initialized.
- Arrays support:
  - `.Length`
  - indexed reads: `array[index]`
  - indexed assignment: `array[index] = value`
- Array indices must be `int`.
- Out-of-range array access is a runtime failure.

## Bootstrap Collections

Phase 3 ships a minimal bootstrap `System.Collections.List<T>` backed by managed arrays.

Supported API:

- `public List()`
- `public void Add(T value)`
- `public T Get(int index)`
- `public void Set(int index, T value)`
- `public int Count()`

Growth strategy:

- capacity starts at 4
- capacity doubles when full

This is intentionally small. Richer collections belong to later library phases.

## Compiled Runtime

The C backend now emits:

- an in-tree non-moving mark-sweep collector
- managed `HyString` string objects
- managed `HyArray` array objects with typed element storage
- class-specific GC trace helpers (one per user-defined class, called by the dispatch table)
- a conservative C stack scanner for runtime roots (static roots are precise)

Collection model:

- single-threaded
- stop-the-world
- non-moving (object addresses are stable)
- conservative stack scanning: the entire C call stack is scanned for candidate pointers
- precise static roots: every reference-type static field is explicitly registered
- no finalizers
- no weak references
- no compaction
- no pinning

Collection trigger:

- `HYLANG_GC_STRESS=1` forces collection before every allocation
- `HYLANG_GC_THRESHOLD=<bytes>` sets the byte threshold between collections (default 1 MiB)
- In both cases collection runs before the new object is allocated, so no in-flight allocation needs to be protected

## Interpreter Note

The interpreter matches the same visible string/array/List semantics but still uses the bootstrap reference-managed runtime internally. Phase 3 standardizes the language/runtime contract first; deeper runtime unification can continue later without changing source behavior.

## Deliberate Exclusions

Phase 3 does not add executable support for:

- `unsafe`
- pointers
- `stackalloc`
- manual allocation/free APIs
- raw buffer primitives
- multidimensional arrays
- array literals
- span-like types

## Proof Target

The sample project [`samples/managed_collections`](../../samples/managed_collections/ManagedCollections.hyproj) is the Phase 3 proof target. It exercises:

- `List<int>`
- `List<string>`
- `List<Node>`
- object-graph retention
- managed strings
- managed arrays
- GC stress behavior in compiled mode
