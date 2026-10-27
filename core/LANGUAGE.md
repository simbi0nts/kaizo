# GPLM v1 — language reference (for the agent writing code)

Read this whole file before writing GPLM. It is the complete language.

## Rules that make GPLM different
- **No operators.** Every operation is a call: `add(a, mul(b, c))`, `lt(x, 0)`, `and(p, q)`.
  There is no grouping with `( )`; nest calls instead.
- **Every construct is closed by `end`**: `fn`, `type`, `test`, `if`, `match`, lambda.
- **Everything is an expression**; a block's value is its last expression. `if` needs `else`.
- **Immutable values.** `let` binds once. Update records with `{ r with f: v }`.
- **No loops.** Use recursion. A call in tail position (last expression of a body,
  of an `if` branch or `match` arm) is a tail call and runs in constant stack.
- **No exceptions.** Fallible operations return `Result[T, E]` (`Ok`/`Err`) or `Option[T]` (`Some`/`None`).
- **Effects are declared.** A fn that (directly) calls an effectful builtin or fn must list
  the effect: `fn main() -> Unit ! [io, time]`. Effects: `io`, `term`, `time`, `net`, `fs`, `proc`.
  Top-level `let` must be pure. `test` blocks may use any effect.
- **Exhaustive `match`.** The checker rejects a match that can miss a value.
- Names: values and functions `lower_snake`; types and constructors `Capitalized`.
- Comments: `#` to end of line. Strings are one line; escapes `\n \t \r \0 \e \\ \"`
  (`\e` = ESC for terminal codes). Strings are byte strings.

## Top level
```
import http                              # library libs/http/*.gp; use as http.serve(...)

type Dir = Up | Down | Left | Right end  # sum type (ADT)
type Shape = Circle(Int) | Rect(Int, Int) end
type Pos = { x: Int, y: Int } end        # record
type Box[T] = Full(T) | Blank end        # type parameters (not checked yet in v0)

let width = 20                           # constant, pure

fn area(s: Shape) -> Int                 # params and return type required
  match s
    case Circle(r) -> mul(3, mul(r, r))
    case Rect(w, h) -> mul(w, h)
  end
end

fn main() -> Unit ! [io]                 # entry point of an app
  println(show(area(Rect(2, 3))))
end

test "area of rect"                      # run with: kaizo test file.gp
  expect_eq(area(Rect(2, 3)), 6)
end
```
Types: `Int` (63-bit signed), `String`, `Bool`, `Unit`, `List[T]`, `Option[T]`, `Result[T, E]`,
`Fn(A, B) -> C`, `Listener`, `Conn`, single capital letters are type variables.
The checker verifies names, arity, record fields, exhaustiveness and effects; full type checking is planned.

## Expressions
```
42  -7  "text"  true  false  Unit        # literals; Unit is the "nothing" value
0x1F  -0xff                              # hex Int literals (digits any case; 0x alone is an error)
[1, 2, 3]                                # list
Pos { x: 1, y: 2 }                       # record: every field, any order
{ p with x: 5 }                          # copy of p with x changed
p.x                                      # field;  http.serve  = module member
f(a, b)                                  # call;   Some(1)  Circle(2)  = constructors
fn(x) add(x, 1) end                      # lambda (param types optional), captures variables
if c1 then a elif c2 then b else d end
match v
  case Circle(r) -> r                    # an arm body may hold several statements
  case _ -> 0
end
```
Blocks (bodies of fn/test/if/case/lambda) are a sequence of statements:
`let name = expr` or `expr`. The last statement must be an expression.

## Patterns
`_` · `name` (binds) · `42` · `"s"` · `true` · `Ctor` · `Ctor(p1, p2)` ·
`[]` · `[a, b]` (exact length) · `[first, ..rest]` (rest is a list; `.._` ignores it).

## Builtins (core)
Pure:
- Int: `add sub mul div mod` (div/mod are Euclidean: `mod(-7, 3) = 2`)
- Compare: `eq ne` (deep, any values) · `lt le gt ge` (Int or String) · Bool: `not and or`
- Bits: `bit_and bit_or bit_xor` · `bit_shl(x, n)` · `bit_shr(x, n)` (arithmetic) · `target()` → the
  compile target, e.g. `"linux-x64"`, `"windows-x64"`, `"macos-x64"`, `"macos-arm64"`
- Text: `show(v) -> String` (strings unchanged, others printed) · `str_cat(a, b)` ·
  `str_join(list, sep)` · `str_len(s)` (bytes) · `str_slice(s, from, to)` ·
  `str_find(s, sub) -> Option[Int]` · `str_split(s, sep) -> List[String]` · `str_trim` ·
  `str_starts(s, prefix)` · `str_ends(s, suffix)` · `str_repeat(s, n)` · `str_lower` ·
  `str_to_int(s) -> Option[Int]` · `str_byte(s, i) -> Int` · `str_from_bytes(List[Int]) -> String`
- List: `list_len` · `list_get(l, i) -> Option[T]` · `list_cons(x, l)` (prepend) ·
  `list_push(l, x)` (append) · `list_concat(a, b)` · `list_slice(l, from, to)` ·
  `list_reverse` · `list_range(from, to)` (to excluded) · `list_contains(l, x)` ·
  `list_map(l, f)` · `list_filter(l, f)` · `list_fold(l, init, fn(acc, x) ... end)` · `list_sort` (Int/String)
- Prelude (written in GPLM): `is_some(o)` `unwrap_or(o, default)` `is_ok(r)` `max(a, b)` `min(a, b)`
- Abort: `panic(msg)` · tests: `expect(cond, msg)` · `expect_eq(got, expected)`
- Compile time: `embed_file("path")` → the file's contents as a String (path relative to the source file)

Effectful:
- `io`: `print(s)` `println(s)` `read_line() -> Option[String]` `args() -> List[String]` ·
  `exit(code)` · `env_get(name) -> Option[String]`
- `term`: `term_raw() -> Result[Unit, String]` (no echo, no line buffering, hidden cursor;
  the core restores the terminal on every exit) · `term_restore()` ·
  `term_key() -> String`: next pending key or `""`; arrows are `"up" "down" "left" "right"`, `"esc"`, else the character
- `time`: `now_ms() -> Int` · `sleep_ms(n)`
- `net`: `tcp_listen("127.0.0.1:8080") -> Result[Listener, String]` ·
  `tcp_accept(l) -> Result[Conn, String]` · `tcp_read(c, max_bytes, timeout_ms) -> Result[String, String]`
  (`""` = closed) · `tcp_write(c, s) -> Result[Unit, String]` · `tcp_close(c)`
- `fs`: `read_file(path) -> Result[String, String]` · `write_file(path, s, mode) -> Result[Unit, String]`
  (mode as a decimal number, 493 = 0o755, 420 = 0o644) · `list_dir(path) -> Result[List[String], String]` (sorted)
- `proc`: `run_image(executable_bytes, args) -> Result[Unit, String]` replaces the process (returns only on error)

## Libraries
`import name` loads every `.gp` file of `libs/name/` (searched in `$KAIZO_PATH`, then in
`libs/` folders from the app upward). Its fns and lets are used qualified: `name.fn(...)`.
Types and constructors are global (no two modules may define the same name).

## Known gaps of v1 (do not rely on them)
- No static types yet: a wrong-typed argument fails at run time (with file:line:col for
  operators, field access and calls; errors inside library builtins name the builtin only).
- No garbage collector yet: memory is only freed when the program exits.
- Targets: Linux x86-64, Windows x64, macOS x86-64 and arm64.
- Effects passed through function values (e.g. a handler argument) are not tracked.
- A local `let` lambda cannot call itself; write a top-level fn for recursion.

## Tools
```
kaizo check app.gp [--json]     # diagnostics with file/line/col/message/hint
kaizo test  app.gp              # each test runs in its own process
kaizo run   app.gp [args...]    # compiles to native code in memory and runs it
kaizo build app.gp -o app       # native executable for this OS (Linux: no libc at all)
kaizo build app.gp -o app.exe --target windows-x64    # cross-compile: windows-x64, macos-x64, macos-arm64, linux-x64
```
