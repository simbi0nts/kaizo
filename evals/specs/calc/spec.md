# Spec: calc

An integer calculator. Each line of standard input is one expression; for each line print one result line.

Grammar (whitespace between tokens is allowed anywhere and ignored):
```
expr   := term (('+' | '-') term)*
term   := unary (('*' | '/' | '%') unary)*
unary  := '-' unary | primary
primary:= number | '(' expr ')'
number := one or more digits 0-9
```
- Operators of the same level are left-associative: `8-3-2` is 3, `2*3%4` is 2.
- `/` and `%` are integer division and remainder that round toward zero (like C):
  `-7/2` is -3, `-7%2` is -1, `7%-2` is 1.
- Numbers and results fit in signed 64-bit integers (inputs are chosen so there is no overflow).
- Empty lines (or lines with only whitespace) print nothing.
- Output per expression: the value, or one of these errors:
  - `error: division by zero` (for `/` or `%` by zero),
  - `error: syntax at <col>` where `<col>` is the 1-based column of the first character where the input
    cannot continue (for an unexpected end of line, the column is the line length + 1).
- A syntax error anywhere in a line is reported even if evaluating the line would also divide by zero
  (check the whole line's syntax first).
- After all lines, exit 0 if every expression succeeded, otherwise exit 1.

Examples (one line each): `1 + 2 * 3` -> `7`; `(1+2)*3` -> `9`; `-(4 - 10) % 4` -> `2`; `2 *` -> `error: syntax at 4`;
`7 / (3 - 3)` -> `error: division by zero`; `1 2` -> `error: syntax at 3`; `(1` -> `error: syntax at 3`.

The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test feeds many expressions (precedence, associativity, signs, nesting, errors).
