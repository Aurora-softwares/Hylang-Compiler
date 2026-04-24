# Hylang Phase 3 Unsafe Design Notes

This document freezes the intended unsafe/manual-memory surface for a later phase. These forms are design-only in Phase 3. The parser, binder, interpreter, and compiled runtime do not execute them yet.

## Intended Surface

Planned syntax and APIs:

- `unsafe { ... }`
- pointer types: `T*`
- address-of: `&expr`
- dereference: `*ptr`
- pointer indexing: `ptr[index]`
- `stackalloc T[count]`
- `System.Runtime.Memory` manual allocation APIs

## Safety Boundary

Managed Hylang code remains the default experience:

- normal object allocation uses the managed runtime
- strings and arrays remain managed objects
- normal class/library code should not require unsafe features

Unsafe code is intended to be:

- explicit
- locally auditable
- opt-in at the block or API boundary
- required only for low-level runtime, OS, or interop scenarios

## Planned Rules

The later unsafe phase is expected to follow these rules:

- pointer creation and dereference require `unsafe`
- unsafe operations do not silently leak into safe code
- `stackalloc` memory is scoped to the current stack lifetime
- manual allocation APIs are explicit and never implied by normal object creation
- low-level memory APIs live in a dedicated runtime namespace rather than being mixed into everyday collection APIs

## Not Implemented In Phase 3

Phase 3 does not implement:

- pointer parsing/binding
- pointer arithmetic
- stack allocation codegen
- manual heap allocation/free codegen
- raw span/buffer library types
- ABI/layout controls for low-level interop

## Rationale

Phase 3 is about stabilizing the managed runtime first. Unsafe/manual-memory features should land only after:

- strings and arrays are stable
- the compiled runtime GC contract is proven
- bootstrap collections exist
- the safe/unsafe boundary is documented clearly enough to enforce intentionally
