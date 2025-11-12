# Namespaces

Hydrogen organizes code using C#-style namespaces. A compilation unit must begin with a `namespace` declaration that wraps all
contained functions.

```hydrogen
namespace Demo {
    fn main() -> int {
        return 0;
    }
}
```

## Syntax
- `namespace` keyword followed by an identifier.
- Body wrapped by `{` and `}` containing zero or more function declarations.

## Semantics
- Only a single namespace per file is recognized at the moment.
- Namespace names map directly into LLVM module naming for organization.

// TODO: Nested namespaces, `using` directives, and cross-namespace symbol resolution.
