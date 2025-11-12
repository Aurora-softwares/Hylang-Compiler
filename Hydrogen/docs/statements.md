# Statements

Only the `return` statement is supported today. It must appear as the sole statement within a function body.

```hydrogen
return 0;
```

## Syntax
- `return` keyword followed by an integer literal.
- Terminated with a semicolon (`;`).

## Semantics
- The literal value is emitted as the return value of `int main()`.
- Missing semicolons or additional statements trigger parser diagnostics.

// TODO: Add expression statements, variable declarations, control-flow constructs, and block-local scopes.
