# Tokens and Lexical Rules

The lexer recognizes the minimal vocabulary required for the hello-world style program.

## Keywords
- `namespace`
- `fn`
- `return`
- `int`

## Punctuation & Operators
- Braces `{` `}`
- Parentheses `(` `)`
- Semicolon `;`
- Arrow `->`
- Dot `.` (reserved for future member access)
- Double colon `::` (reserved for future scope resolution)
- Equals `=` (reserved for upcoming assignments)

## Literals
- Decimal integer literals (e.g., `0`, `42`).

## Trivia
- Whitespace (spaces, tabs, newlines) is skipped.
- Line comments start with `//` and continue to the end of the line.

// TODO: Support string literals, block comments, operators, numeric bases, and contextual keywords.
