# Types

The Hydrogen scaffold recognizes a single primitive type: `int`.

## `int`
- Represents a 32-bit signed integer.
- Functions must declare `-> int` as their return type.
- Return statements must provide an integer literal compatible with `int`.

```hydrogen
fn main() -> int {
    return 0;
}
```

// TODO: Introduce additional primitives (bool, float), user-defined structs, enums, generics, and type inference.
