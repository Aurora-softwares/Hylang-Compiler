# Functions

Hydrogen functions are introduced with the `fn` keyword and currently support a parameterless form that returns `int`.

```hydrogen
fn main() -> int {
    return 0;
}
```

## Syntax
- `fn` keyword introduces a function declaration.
- Identifier names follow C-style rules (letter or `_` followed by alphanumerics/underscores).
- Parameter list is enclosed in `(` `)`; the scaffold expects it to be empty for now.
- Return type is specified after `->`. Only `int` is recognized today.
- Function body is a block delimited by `{` and `}`.

## Semantics
- The entry point must be named `main`. Code generation lowers it to a C-compatible `int main()`.
- All functions must end with a `return` statement yielding an integer literal.

// TODO: Support parameters, multiple return types, generic functions, async functions, and richer return statements.
