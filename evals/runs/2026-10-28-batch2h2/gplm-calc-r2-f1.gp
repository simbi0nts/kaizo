# calc: integer calculator. One expression per input line; prints the value or an error.

type Ex = Num(Int) | Neg(Ex) | Bin(String, Ex, Ex) end
type Tok = { kind: String, num: Int, col: Int } end
type Parsed = { ex: Ex, rest: List[Tok] } end

let ops = ["+", "-", "*", "/", "%", "(", ")"]

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_space(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 13))
end

fn digits_end(s: String, j: Int) -> Int
  if ge(j, str_len(s)) then j
  elif is_digit(str_byte(s, j)) then digits_end(s, add(j, 1))
  else j
  end
end

# Lexing never fails: an unknown character becomes a "?" token that the parser rejects
# at its own column, so the first bad character is the one reported.
fn lex(s: String, i: Int, acc: List[Tok]) -> List[Tok]
  if ge(i, str_len(s)) then acc
  else lex_at(s, i, acc)
  end
end

fn lex_at(s: String, i: Int, acc: List[Tok]) -> List[Tok]
  let c = str_byte(s, i)
  let ch = str_slice(s, i, add(i, 1))
  if is_space(c) then lex(s, add(i, 1), acc)
  elif is_digit(c) then
    let j = digits_end(s, i)
    let v = unwrap_or(str_to_int(str_slice(s, i, j)), 0)
    lex(s, j, list_push(acc, Tok { kind: "n", num: v, col: add(i, 1) }))
  elif list_contains(ops, ch) then
    lex(s, add(i, 1), list_push(acc, Tok { kind: ch, num: 0, col: add(i, 1) }))
  else
    lex(s, add(i, 1), list_push(acc, Tok { kind: "?", num: 0, col: add(i, 1) }))
  end
end

fn kind_of(ts: List[Tok]) -> String
  match ts
    case [] -> "eof"
    case [t, .._] -> t.kind
  end
end

fn col_of(ts: List[Tok]) -> Int
  match ts
    case [] -> 0
    case [t, .._] -> t.col
  end
end

fn advance(ts: List[Tok]) -> List[Tok]
  match ts
    case [] -> []
    case [_, ..rest] -> rest
  end
end

# expr := term (('+' | '-') term)*
fn parse_expr(ts: List[Tok]) -> Result[Parsed, Int]
  let p = try parse_term(ts)
  expr_tail(p.ex, p.rest)
end

fn expr_tail(left: Ex, ts: List[Tok]) -> Result[Parsed, Int]
  let k = kind_of(ts)
  if or(eq(k, "+"), eq(k, "-")) then
    let r = try parse_term(advance(ts))
    expr_tail(Bin(k, left, r.ex), r.rest)
  else
    Ok(Parsed { ex: left, rest: ts })
  end
end

# term := unary (('*' | '/' | '%') unary)*
fn parse_term(ts: List[Tok]) -> Result[Parsed, Int]
  let u = try parse_unary(ts)
  term_tail(u.ex, u.rest)
end

fn term_tail(left: Ex, ts: List[Tok]) -> Result[Parsed, Int]
  let k = kind_of(ts)
  if or(eq(k, "*"), eq(k, "/"), eq(k, "%")) then
    let u = try parse_unary(advance(ts))
    term_tail(Bin(k, left, u.ex), u.rest)
  else
    Ok(Parsed { ex: left, rest: ts })
  end
end

# unary := '-' unary | primary
fn parse_unary(ts: List[Tok]) -> Result[Parsed, Int]
  if eq(kind_of(ts), "-") then
    let u = try parse_unary(advance(ts))
    Ok(Parsed { ex: Neg(u.ex), rest: u.rest })
  else
    parse_primary(ts)
  end
end

# primary := number | '(' expr ')'
fn parse_primary(ts: List[Tok]) -> Result[Parsed, Int]
  match ts
    case [] -> Err(1)
    case [t, ..rest] -> primary_tok(t, rest)
  end
end

fn primary_tok(t: Tok, rest: List[Tok]) -> Result[Parsed, Int]
  if eq(t.kind, "n") then
    Ok(Parsed { ex: Num(t.num), rest: rest })
  elif eq(t.kind, "(") then
    let e = try parse_expr(rest)
    close_paren(e)
  else
    Err(t.col)
  end
end

fn close_paren(p: Parsed) -> Result[Parsed, Int]
  if eq(kind_of(p.rest), ")") then
    Ok(Parsed { ex: p.ex, rest: advance(p.rest) })
  else
    Err(col_of(p.rest))
  end
end

# Syntax is checked for the whole line before any evaluation.
fn parse_line(s: String) -> Result[Ex, Int]
  let ts = lex(s, 0, [])
  let all = list_push(ts, Tok { kind: "eof", num: 0, col: add(str_len(s), 1) })
  let p = try parse_expr(all)
  if eq(kind_of(p.rest), "eof") then Ok(p.ex)
  else Err(col_of(p.rest))
  end
end

fn iabs(x: Int) -> Int
  if lt(x, 0) then sub(0, x) else x end
end

# Division and remainder that round toward zero (C semantics).
fn tdiv(a: Int, b: Int) -> Int
  let q = div(iabs(a), iabs(b))
  if ne(lt(a, 0), lt(b, 0)) then sub(0, q) else q end
end

fn tmod(a: Int, b: Int) -> Int
  let r = mod(iabs(a), iabs(b))
  if lt(a, 0) then sub(0, r) else r end
end

fn apply_op(op: String, x: Int, y: Int) -> Result[Int, String]
  if eq(op, "+") then Ok(add(x, y))
  elif eq(op, "-") then Ok(sub(x, y))
  elif eq(op, "*") then Ok(mul(x, y))
  elif eq(y, 0) then Err("division by zero")
  elif eq(op, "/") then Ok(tdiv(x, y))
  else Ok(tmod(x, y))
  end
end

fn eval_ex(e: Ex) -> Result[Int, String]
  match e
    case Num(n) -> Ok(n)
    case Neg(x) ->
      let v = try eval_ex(x)
      Ok(sub(0, v))
    case Bin(op, a, b) ->
      let x = try eval_ex(a)
      let y = try eval_ex(b)
      apply_op(op, x, y)
  end
end

# Returns the value, or the error text after "error: ".
fn calc_line(s: String) -> Result[Int, String]
  match parse_line(s)
    case Err(c) -> Err(str_cat("syntax at ", show(c)))
    case Ok(ex) -> eval_ex(ex)
  end
end

fn handle_line(line: String) -> Bool ! [io]
  if eq(str_trim(line), "") then false
  else
    let r = calc_line(line)
    match r
      case Ok(v) ->
        println(show(v))
        false
      case Err(m) ->
        println(str_cat("error: ", m))
        true
    end
  end
end

fn run_lines(failed: Bool) -> Bool ! [io]
  match read_line()
    case None -> failed
    case Some(line) ->
      let bad = handle_line(line)
      run_lines(or(failed, bad))
  end
end

fn main() -> Unit ! [io]
  let failed = run_lines(false)
  exit(if failed then 1 else 0 end)
end

test "precedence"
  expect_eq(calc_line("1 + 2 * 3"), Ok(7))
  expect_eq(calc_line("(1+2)*3"), Ok(9))
end

test "associativity and signs"
  expect_eq(calc_line("8-3-2"), Ok(3))
  expect_eq(calc_line("2*3%4"), Ok(2))
  expect_eq(calc_line("-(4 - 10) % 4"), Ok(2))
  expect_eq(calc_line("7%-2"), Ok(1))
  expect_eq(calc_line("-7/2"), Ok(-3))
  expect_eq(calc_line("-7%2"), Ok(-1))
end

test "syntax and arithmetic errors"
  expect_eq(calc_line("2 *"), Err("syntax at 4"))
  expect_eq(calc_line("1 2"), Err("syntax at 3"))
  expect_eq(calc_line("(1"), Err("syntax at 3"))
  expect_eq(calc_line("7 / (3 - 3)"), Err("division by zero"))
  expect_eq(calc_line("7 / (3 - 3) +"), Err("syntax at 14"))
end
