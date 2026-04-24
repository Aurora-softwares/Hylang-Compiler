# Hylang Phase 2 Spec Notes

This document records the Phase 2 language rules that are implemented in the bootstrap compiler today. It is intentionally practical: it describes the supported surface, the active semantics, and the deliberate exclusions that still belong to later phases.

## Scope

Phase 2 completes the core-language expansion from the early bootstrap language into a compiler-flavored application language. The implemented areas are:

- `base(...)`, `base.Member`, `virtual`, and `override`
- namespace-scope `interface`
- namespace-scope `struct`
- invariant generics on classes, interfaces, and methods
- `var` local inference
- harder name resolution and generic arity checking

## Type Declarations

### Classes

- Classes are declared at namespace scope.
- A class may declare type parameters: `class Box<T>`.
- A class may inherit from one base class and implement zero or more interfaces.
- If no base class is specified, the class is a root class.

Example:

```hy
namespace Demo {
    public class Derived<T> : Base, IFoo<T>, IBar {
    }
}
```

### Interfaces

- Interfaces are declared at namespace scope.
- Interface members are public instance method signatures only.
- Interfaces may inherit from multiple interfaces.
- Interfaces do not support fields, constructors, static members, default implementations, events, operators, or properties in Phase 2.

Example:

```hy
public interface INodeVisitor<T> : IVisitor<T> {
    T VisitNode(SyntaxNode node);
}
```

### Structs

- Structs are declared at namespace scope.
- Structs may declare fields, constructors, instance methods, and static methods.
- Structs may implement interfaces.
- Structs do not participate in class inheritance.
- Generic structs are out of scope for Phase 2.

Example:

```hy
public struct TextSpan : ISpanView {
    private int _start;
    private int _length;
}
```

## Base Access and Override Rules

### Constructor Initializers

- `: base(args)` is supported on constructors.
- `: this(args)` is not part of Phase 2.
- If no explicit base initializer is provided, normal implicit parameterless base-constructor chaining still applies.

### `base.Member`

- `base.Member` is valid only inside instance methods and instance constructors.
- `base.Member` may target fields and methods from the base class chain.
- `base.Member` binds statically to the base implementation and bypasses virtual dispatch.
- `base` is not valid in static contexts.

### `virtual` and `override`

- Only non-static instance methods may be `virtual`.
- A derived replacement must be marked `override`.
- The overridden base method must already be virtual.
- Signature matching for override is exact, including static/instance shape and parameter list.
- Invalid overrides are compile-time errors.

## Interface Model

- Interfaces can be used as field, local, parameter, and return types.
- Interface dispatch works in both interpreter and compiled modes.
- A class or struct implementing an interface must satisfy all inherited interface methods.
- Interface inheritance is transitive.

## Struct Semantics

- Structs are value types in the current bootstrap model.
- Struct locals and fields are zero-initialized by default.
- Struct assignment copies the value.
- Passing a struct as a parameter copies the value.
- Returning a struct returns a copy of the value.
- `new S(...)` constructs a struct value.
- `new S()` uses a matching declared constructor if present; otherwise it produces a zero-initialized struct value.
- Calling an instance method on a mutable struct lvalue operates on the original storage.
- Calling an instance method on a temporary operates on a temporary copy.

### Boxing to Interfaces

- Converting a struct to an interface boxes a copy into a managed wrapper object.
- Interface calls on the boxed value observe and mutate the boxed copy, not the original struct variable.
- Boxing to `object` is not part of Phase 2.

## Generics

### Supported Forms

- Generic classes: `class Box<T>`
- Generic interfaces: `interface IVisitor<T>`
- Generic methods: `T Identity<T>(T value)`

### Semantics

- Generics are invariant.
- Closed generic types and methods are specialized by the compiler and cached per unique type-argument set.
- Method type inference uses call arguments only.
- Return-type-based inference is not supported.
- Constraints, variance, and default type arguments are not part of Phase 2.

### Overload Selection

Overload ranking prefers:

1. exact match
2. generic exact match after successful inference/specialization
3. inheritance or interface conversion
4. boxing

Equal-best candidates are ambiguous and produce diagnostics.

## `var`

- `var` is valid for local variables only.
- A `var` local requires an initializer.
- The inferred type is the exact static type after implicit conversion.
- `var` cannot be used when binding fails or when the initializer has no usable value type.

Example:

```hy
var node = new BinaryExpressionSyntax(left, plusToken, right, span);
```

## Name Resolution

- Type lookup uses name plus generic arity.
- Simple-name type lookup prefers:
  1. the current namespace
  2. imported namespaces
  3. the global namespace
- Ambiguous matches produce diagnostics.
- Qualified names win over imported-name lookup.
- `using` remains namespace-only in Phase 2. Alias imports are not supported.

## Deliberate Exclusions

Phase 2 does not include:

- `abstract`, `sealed`, or `new`-hiding
- exceptions or async
- properties, events, or operator overloading
- generic constraints or variance
- generic structs
- boxing to `object`
- top-level statements or free functions
- low-level unsafe/pointer features

## Implementation Note

The semantic model tracks concrete specialized generic types and methods. The C backend still uses a bootstrap-oriented strategy for some generic/interface dispatch paths, so compiled helper signatures may erase some low-level representation details even though language binding and behavior are driven by the specialized semantic model.

## Phase 2 Proof Target

The sample project [`samples/mini_frontend_model`](../../samples/mini_frontend_model/MiniFrontendModel.hyproj) is the Phase 2 proof target. It exercises:

- enum-backed syntax kinds
- `TextSpan` as a struct
- `SyntaxNode` inheritance
- `base(...)`, `base.Member`, `virtual`, and `override`
- a generic visitor interface
- a generic `Box<T>` type
- struct-to-interface boxing
