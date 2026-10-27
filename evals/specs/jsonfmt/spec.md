# Spec: jsonfmt

Validate a JSON document read from standard input and pretty-print it.

Accepted JSON (a subset): one value, surrounded by optional whitespace (space, tab, `\n`, `\r`).
- `null`, `true`, `false`
- integers: optional `-`, then `0` or a digit 1-9 followed by digits (no fractions, no exponents)
- strings: `"` ... `"`; raw characters below 0x20 are not allowed inside; escapes `\" \\ \/ \b \f \n \r \t`
  and `\u` followed by exactly 4 hex digits (any case)
- arrays `[v, v, ...]` and objects `{"key": v, ...}` (keys are strings; duplicates allowed, kept in order)

Output on success (exit 0): the value pretty-printed with 2-space indentation, one element or member
per line, `": "` after keys, commas at line ends, members/elements in the original order; empty arrays
and objects as `[]` and `{}`; a final newline. Strings are re-escaped: `"` -> `\"`, `\` -> `\\`,
backspace, form feed, newline, carriage return, tab -> `\b \f \n \r \t`, other characters below 0x20
-> `\u00XX` (lowercase hex). A `\uXXXX` escape whose value is below 0x80 is output as that character
(re-escaped by the rule above); any other `\uXXXX` is output as `\u` + the 4 hex digits in lowercase.
`\/` is output as `/`. Bytes 0x80 and above in the input are copied unchanged.

Example: input `{"a":[1,2,{}],"b":"xA\n"}` prints
```
{
  "a": [
    1,
    2,
    {}
  ],
  "b": "xA\n"
}
```
On invalid input print exactly `error: line <l> col <c>` and exit 1, where line/col (1-based; each
`\n` starts a new line; col counts bytes) is the position of the first character that cannot be part
of a valid document — or, for an unexpected end of input, the position just after the last character.
Nothing else is printed in that case.

The program must also contain at least three unit tests of its own pure logic.
A hidden acceptance test feeds valid and invalid documents (nesting, escapes, every error kind, a large file).
