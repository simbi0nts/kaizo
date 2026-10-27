# GPLM as JSON — program-tree reference (for the agent writing code)

Read this whole file before writing a program. It is the complete language. A program is
**one JSON document** describing the program tree directly; there is no other syntax.
Every node is a JSON object whose `"k"` field names the node kind; the other fields are listed
below. All listed fields are required (use `[]`, `""` or `null` where noted).

## Language rules
- **No operators.** Every operation is a call (`ECall`) of a builtin or fn, e.g. `add`, `lt`, `and`.
- **Everything is an expression**; a block (a list of statements) has the value of its last
  statement, which must be an expression statement. `EIf` always has an else block.
- **Immutable values.** A `let` statement binds a name once. Records are updated with `EUpd`
  (copy with some fields changed).
- **No loops.** Use recursion. A call in tail position (last statement of a fn body, of an `EIf`
  branch or of a match arm) is a tail call and runs in constant stack.
- **No exceptions.** Fallible operations return `Result[T, E]` (constructors `Ok`/`Err`) or
  `Option[T]` (`Some`/`None`).
- **Effects are declared.** A fn that (directly) calls an effectful builtin or fn must list the
  effect in `effects`, e.g. `["io", "fs"]`. Effects: `io`, `term`, `time`, `net`, `fs`, `proc`.
  Top-level lets must be pure. Tests may use any effect.
- **Exhaustive match.** The checker rejects an `EMatch` that can miss a value.
- Names: values and functions `lower_snake`; types and constructors `Capitalized`.
- Strings are byte strings. In JSON write them with normal JSON escapes; any byte is allowed.
- `Unit` (the "nothing" value) is the constructor expression `{"k":"ECtor","name":"Unit"}`.

## Program (top level)
```json
{ "imports": [],                     // library names, e.g. ["http"]; members used as EField(EVar "http", "serve")
  "types":   [ TypeDecl, ... ],
  "lets":    [ {"name": "width", "x": Expr}, ... ],      // pure constants
  "fns":     [ FnDecl, ... ],         // an app's entry point is the fn "main" with no params, ret Unit
  "tests":   [ {"name": "area of rect", "body": [Stmt, ...]}, ... ] }
```

`FnDecl`:
```json
{ "name": "area", "params": [ {"name": "s", "ty": TypeX} ], "ret": TypeX,
  "effects": [], "body": [Stmt, ...] }
```
Parameters of a top-level fn require a type (`ty` is never null there).

`TypeDecl` (a sum type has `is_record: false` and `ctors`; a record type has `is_record: true` and `fields`):
```json
{ "name": "Shape", "tparams": [], "is_record": false,
  "ctors": [ {"name": "Circle", "args": [TypeX]}, {"name": "Rect", "args": [TypeX, TypeX]} ], "fields": [] }
{ "name": "Pos", "tparams": [], "is_record": true, "ctors": [],
  "fields": [ {"name": "x", "ty": TypeX}, {"name": "y", "ty": TypeX} ] }
```
`tparams` lists type parameter names like `["T"]` (not checked yet).

`TypeX` (a type): `{"name": "Int", "args": []}`, `{"name": "List", "args": [{"name": "String", "args": []}]}`.
Function types: name `"Fn"`, args = parameter types followed by the return type.
Types: `Int` (63-bit signed), `String`, `Bool`, `Unit`, `List[T]`, `Option[T]`, `Result[T, E]`,
`Fn`, `Listener`, `Conn`; single capital letters are type variables. The checker verifies names,
arity, record fields, exhaustiveness and effects; full type checking is planned.

## Statements
`Stmt` = `{"let_name": "x", "x": Expr}` binds `x`; `{"let_name": "", "x": Expr}` is an expression
statement. The last statement of a block must have `let_name: ""`.

## Expressions (`Expr`)
| kind | fields | meaning |
|------|--------|---------|
| `EInt` | `v`: integer | `42`, `-7` |
| `EStr` | `v`: string | string literal |
| `EBool` | `v`: true/false | |
| `EVar` | `name` | a local, parameter, top-level let/fn, builtin or module name |
| `ECtor` | `name` | a constructor used as a value or callee (`Some`, `None`, `Unit`, `Circle`) |
| `ECall` | `f`: Expr, `args`: [Expr] | call; `f` is usually EVar, ECtor or EField |
| `EField` | `x`: Expr, `name` | record field `p.x`, or module member (`x` = EVar of the module) |
| `EList` | `items`: [Expr] | list literal |
| `ERec` | `type`: type name, `fields`: [FieldInit] | record value; every field, any order |
| `EUpd` | `x`: Expr, `fields`: [FieldInit] | copy of record `x` with these fields changed |
| `EIf` | `conds`: [Expr], `thens`: [[Stmt]], `else`: [Stmt] | `if c1 then b1 elif c2 then b2 ... else e`; `conds` and `thens` have equal length ≥ 1 |
| `EMatch` | `x`: Expr, `arms`: [{"pat": Pat, "body": [Stmt]}] | first matching arm wins |
| `ELam` | `params`: [names], `body`: [Stmt] | lambda; captures variables |

`FieldInit` = `{"name": "x", "x": Expr}`.

## Patterns (`Pat`)
| kind | fields | matches |
|------|--------|---------|
| `PWild` | — | anything |
| `PVar` | `name` | anything, binds it |
| `PInt` / `PStr` / `PBool` | `v` | that literal |
| `PCtor` | `name`, `args`: [Pat] | constructor (`args: []` for `None`, `Up`) |
| `PList` | `items`: [Pat], `rest`: Pat or null | `rest: null` = exact length; `rest` = PVar/PWild binds the remaining list |

## Example
`area` of a shape, and a test:
```json
{ "imports": [], "lets": [],
  "types": [ { "name": "Shape", "tparams": [], "is_record": false, "fields": [],
               "ctors": [ {"name": "Circle", "args": [{"name": "Int", "args": []}]},
                          {"name": "Rect", "args": [{"name": "Int", "args": []}, {"name": "Int", "args": []}]} ] } ],
  "fns": [
    { "name": "area", "params": [{"name": "s", "ty": {"name": "Shape", "args": []}}],
      "ret": {"name": "Int", "args": []}, "effects": [],
      "body": [ {"let_name": "", "x": {"k": "EMatch", "x": {"k": "EVar", "name": "s"}, "arms": [
        {"pat": {"k": "PCtor", "name": "Circle", "args": [{"k": "PVar", "name": "r"}]},
         "body": [{"let_name": "", "x": {"k": "ECall", "f": {"k": "EVar", "name": "mul"}, "args": [
            {"k": "EInt", "v": 3},
            {"k": "ECall", "f": {"k": "EVar", "name": "mul"}, "args": [{"k": "EVar", "name": "r"}, {"k": "EVar", "name": "r"}]} ]}}]},
        {"pat": {"k": "PCtor", "name": "Rect", "args": [{"k": "PVar", "name": "w"}, {"k": "PVar", "name": "h"}]},
         "body": [{"let_name": "", "x": {"k": "ECall", "f": {"k": "EVar", "name": "mul"}, "args": [{"k": "EVar", "name": "w"}, {"k": "EVar", "name": "h"}]}}]} ]}} ] },
    { "name": "main", "params": [], "ret": {"name": "Unit", "args": []}, "effects": ["io"],
      "body": [ {"let_name": "", "x": {"k": "ECall", "f": {"k": "EVar", "name": "println"}, "args": [
        {"k": "ECall", "f": {"k": "EVar", "name": "show"}, "args": [
          {"k": "ECall", "f": {"k": "EVar", "name": "area"}, "args": [
            {"k": "ECall", "f": {"k": "ECtor", "name": "Rect"}, "args": [{"k": "EInt", "v": 2}, {"k": "EInt", "v": 3}]} ]} ]} ]}} ] } ],
  "tests": [ { "name": "area of rect", "body": [ {"let_name": "", "x": {"k": "ECall", "f": {"k": "EVar", "name": "expect_eq"}, "args": [
      {"k": "ECall", "f": {"k": "EVar", "name": "area"}, "args": [{"k": "ECall", "f": {"k": "ECtor", "name": "Rect"}, "args": [{"k": "EInt", "v": 2}, {"k": "EInt", "v": 3}]}]},
      {"k": "EInt", "v": 6} ]}} ] } ] }
```

## Builtins (core)
Pure:
- Int: `add sub mul div mod` (div/mod are Euclidean: `mod(-7, 3) = 2`)
- Compare: `eq ne` (deep, any values) · `lt le gt ge` (Int or String) · Bool: `not and or`
- Bits: `bit_and bit_or bit_xor` · `bit_shl(x, n)` · `bit_shr(x, n)` (arithmetic) · `target()` → the
  compile target, e.g. `"linux-x64"`
- Text: `show(v) -> String` (strings unchanged, others printed) · `str_cat(a, b)` ·
  `str_join(list, sep)` · `str_len(s)` (bytes) · `str_slice(s, from, to)` ·
  `str_find(s, sub) -> Option[Int]` · `str_split(s, sep) -> List[String]` · `str_trim` ·
  `str_starts(s, prefix)` · `str_ends(s, suffix)` · `str_repeat(s, n)` · `str_lower` ·
  `str_to_int(s) -> Option[Int]` · `str_byte(s, i) -> Int` · `str_from_bytes(List[Int]) -> String`
- List: `list_len` · `list_get(l, i) -> Option[T]` · `list_cons(x, l)` (prepend) ·
  `list_push(l, x)` (append) · `list_concat(a, b)` · `list_slice(l, from, to)` ·
  `list_reverse` · `list_range(from, to)` (to excluded) · `list_contains(l, x)` ·
  `list_map(l, f)` · `list_filter(l, f)` · `list_fold(l, init, f)` with `f` = lambda of (acc, x) · `list_sort` (Int/String)
- Prelude: `is_some(o)` `unwrap_or(o, default)` `is_ok(r)` `max(a, b)` `min(a, b)`
- Abort: `panic(msg)` · tests: `expect(cond, msg)` · `expect_eq(got, expected)`

Effectful:
- `io`: `print(s)` `println(s)` `read_line() -> Option[String]` `args() -> List[String]` ·
  `exit(code)` · `env_get(name) -> Option[String]`
- `time`: `now_ms() -> Int` · `sleep_ms(n)`
- `fs`: `read_file(path) -> Result[String, String]` · `write_file(path, s, mode) -> Result[Unit, String]`
  (mode as a decimal number, 420 = 0o644) · `list_dir(path) -> Result[List[String], String]` (sorted)
- (`term`, `net`, `proc` builtins exist but are not needed here.)

## Known gaps (do not rely on them)
- No static types yet: a wrong-typed argument fails at run time.
- No garbage collector yet: memory is only freed when the program exits.
- Effects passed through function values are not tracked.
- A lambda bound by a local `let` cannot call itself; write a top-level fn for recursion.

## Tools
Your JSON is checked by the toolchain; diagnostics name the JSON path of the offending node
(e.g. `fns[2].body[0].x.args[1]`) and a message. `test` blocks each run in their own process.
