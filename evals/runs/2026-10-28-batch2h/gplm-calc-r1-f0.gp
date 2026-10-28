# calc: integer calculator, one expression per input line.

type Tok = TNum(Int) | TOp(String) | TLp | TRp end
type Pt = { tok: Tok, col: Int } end
type Expr = Lit(Int) | Neg(Expr) | Bin(String, Expr, Expr) end
type PE = { ex: Expr, rest: List[Pt] } end

fn is_digit(c: String) -> Bool
  and(ge(c, "0"), le(c, "9"))
end

fn is_op(c: String) -> Bool
  or(eq(c, "+"), eq(c, "-"), eq(c, "*"), eq(c, "/"), eq(c, "%"))
end

fn digits_end(s: String, j: Int) -> Int
  if ge(j, str_len(s)) then j
  elif is_digit(str_slice(s, j, add(j, 1))) then digits_end(s, add(j, 1))
  else j
  end
end

# Tokenizer. Err carries the 1-based column of the first bad character.
fn tokenize(s: String, i: Int, acc: List[Pt]) -> Result[List[Pt], Int]
  if ge(i, str_len(s)) then Ok(list_reverse(acc))
  else tokenize_at(s, i, str_slice(s, i, add(i, 1)), acc)
  end
end

fn push_tok(s: String, i: Int, t: Tok, acc: List[Pt]) -> Result[List[Pt], Int]
  tokenize(s, add(i, 1), list_cons(Pt { tok: t, col: add(i, 1) }, acc))
end

fn lex_number(s: String, i: Int, acc: List[Pt]) -> Result[List[Pt], Int]
  let j = digits_end(s, i)
  match str_to_int(str_slice(s, i, j))
    case Some(n) -> tokenize(s, j, list_cons(Pt { tok: TNum(n), col: add(i, 1) }, acc))
    case None -> Err(add(i, 1))
  end
end

fn tokenize_at(s: String, i: Int, c: String, acc: List[Pt]) -> Result[List[Pt], Int]
  if or(eq(c, " "), eq(c, "\t"), eq(c, "\r")) then tokenize(s, add(i, 1), acc)
  elif is_digit(c) then lex_number(s, i, acc)
  elif is_op(c) then push_tok(s, i, TOp(c), acc)
  elif eq(c, "(") then push_tok(s, i, TLp, acc)
  elif eq(c, ")") then push_tok(s, i, TRp, acc)
  else Err(add(i, 1))
  end
end

# Recursive descent parser. Err carries the error column.
fn parse_expr(ts: List[Pt], endcol: Int) -> Result[PE, Int]
  let first = try parse_term(ts, endcol)
  expr_loop(first.ex, first.rest, endcol)
end

fn expr_loop(acc: Expr, ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match ts
    case [p, ..tail] -> expr_step(acc, p, tail, ts, endcol)
    case _ -> Ok(PE { ex: acc, rest: ts })
  end
end

fn expr_step(acc: Expr, p: Pt, tail: List[Pt], ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match p.tok
    case TOp(o) -> additive_step(acc, o, tail, ts, endcol)
    case _ -> Ok(PE { ex: acc, rest: ts })
  end
end

fn additive_step(acc: Expr, o: String, tail: List[Pt], ts: List[Pt], endcol: Int) -> Result[PE, Int]
  if or(eq(o, "+"), eq(o, "-")) then add_term(acc, o, tail, endcol)
  else Ok(PE { ex: acc, rest: ts })
  end
end

fn add_term(acc: Expr, o: String, tail: List[Pt], endcol: Int) -> Result[PE, Int]
  let t = try parse_term(tail, endcol)
  expr_loop(Bin(o, acc, t.ex), t.rest, endcol)
end

fn parse_term(ts: List[Pt], endcol: Int) -> Result[PE, Int]
  let first = try parse_unary(ts, endcol)
  term_loop(first.ex, first.rest, endcol)
end

fn term_loop(acc: Expr, ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match ts
    case [p, ..tail] -> term_step(acc, p, tail, ts, endcol)
    case _ -> Ok(PE { ex: acc, rest: ts })
  end
end

fn term_step(acc: Expr, p: Pt, tail: List[Pt], ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match p.tok
    case TOp(o) -> multiplicative_step(acc, o, tail, ts, endcol)
    case _ -> Ok(PE { ex: acc, rest: ts })
  end
end

fn multiplicative_step(acc: Expr, o: String, tail: List[Pt], ts: List[Pt], endcol: Int) -> Result[PE, Int]
  if or(eq(o, "*"), eq(o, "/"), eq(o, "%")) then mul_unary(acc, o, tail, endcol)
  else Ok(PE { ex: acc, rest: ts })
  end
end

fn mul_unary(acc: Expr, o: String, tail: List[Pt], endcol: Int) -> Result[PE, Int]
  let u = try parse_unary(tail, endcol)
  term_loop(Bin(o, acc, u.ex), u.rest, endcol)
end

fn parse_unary(ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match ts
    case [p, ..tail] -> unary_on(p, tail, ts, endcol)
    case _ -> Err(endcol)
  end
end

fn unary_on(p: Pt, tail: List[Pt], ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match p.tok
    case TOp(o) -> minus_or_error(o, p.col, tail, endcol)
    case _ -> parse_primary(ts, endcol)
  end
end

fn minus_or_error(o: String, col: Int, tail: List[Pt], endcol: Int) -> Result[PE, Int]
  if eq(o, "-") then neg_of(tail, endcol)
  else Err(col)
  end
end

fn neg_of(tail: List[Pt], endcol: Int) -> Result[PE, Int]
  let u = try parse_unary(tail, endcol)
  Ok(PE { ex: Neg(u.ex), rest: u.rest })
end

fn parse_primary(ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match ts
    case [p, ..tail] -> primary_on(p, tail, endcol)
    case _ -> Err(endcol)
  end
end

fn primary_on(p: Pt, tail: List[Pt], endcol: Int) -> Result[PE, Int]
  match p.tok
    case TNum(n) -> Ok(PE { ex: Lit(n), rest: tail })
    case TLp -> paren_body(tail, endcol)
    case _ -> Err(p.col)
  end
end

fn paren_body(tail: List[Pt], endcol: Int) -> Result[PE, Int]
  let e = try parse_expr(tail, endcol)
  close_paren(e.ex, e.rest, endcol)
end

fn close_paren(ex: Expr, ts: List[Pt], endcol: Int) -> Result[PE, Int]
  match ts
    case [q, ..tail] -> expect_rparen(ex, q, tail)
    case _ -> Err(endcol)
  end
end

fn expect_rparen(ex: Expr, q: Pt, tail: List[Pt]) -> Result[PE, Int]
  match q.tok
    case TRp -> Ok(PE { ex: ex, rest: tail })
    case _ -> Err(q.col)
  end
end

fn parse_line(ts: List[Pt], endcol: Int) -> Result[Expr, Int]
  let p = try parse_expr(ts, endcol)
  match p.rest
    case [q, .._] -> Err(q.col)
    case _ -> Ok(p.ex)
  end
end

# Evaluation (after the whole line has parsed).
fn abs_int(n: Int) -> Int
  if lt(n, 0) then sub(0, n) else n end
end

fn trunc_div(x: Int, y: Int) -> Int
  let q = div(abs_int(x), abs_int(y))
  if eq(lt(x, 0), lt(y, 0)) then q else sub(0, q) end
end

fn trunc_mod(x: Int, y: Int) -> Int
  let r = mod(abs_int(x), abs_int(y))
  if lt(x, 0) then sub(0, r) else r end
end

fn apply_op(o: String, x: Int, y: Int) -> Result[Int, String]
  if eq(o, "+") then Ok(add(x, y))
  elif eq(o, "-") then Ok(sub(x, y))
  elif eq(o, "*") then Ok(mul(x, y))
  elif eq(y, 0) then Err("error: division by zero")
  elif eq(o, "/") then Ok(trunc_div(x, y))
  else Ok(trunc_mod(x, y))
  end
end

fn eval_neg(x: Expr) -> Result[Int, String]
  let v = try eval(x)
  Ok(sub(0, v))
end

fn eval_bin(o: String, a: Expr, b: Expr) -> Result[Int, String]
  let x = try eval(a)
  let y = try eval(b)
  apply_op(o, x, y)
end

fn eval(e: Expr) -> Result[Int, String]
  match e
    case Lit(n) -> Ok(n)
    case Neg(x) -> eval_neg(x)
    case Bin(o, a, b) -> eval_bin(o, a, b)
  end
end

fn syntax_error(c: Int) -> String
  str_cat("error: syntax at ", show(c))
end

fn render(r: Result[Int, String]) -> Result[String, String]
  match r
    case Ok(v) -> Ok(show(v))
    case Err(m) -> Err(m)
  end
end

fn solve_expr(ts: List[Pt], endcol: Int) -> Result[String, String]
  match parse_line(ts, endcol)
    case Err(c) -> Err(syntax_error(c))
    case Ok(e) -> render(eval(e))
  end
end

fn solve_tokens(ts: List[Pt], endcol: Int) -> Result[String, String]
  match ts
    case [] -> Ok("")
    case _ -> solve_expr(ts, endcol)
  end
end

# Ok("") means the line printed nothing (blank line). Err carries the printed error text.
fn solve_line(line: String) -> Result[String, String]
  match tokenize(line, 0, [])
    case Err(c) -> Err(syntax_error(c))
    case Ok(ts) -> solve_tokens(ts, add(str_len(line), 1))
  end
end

# Driver.
fn strip_cr(l: String) -> String
  if str_ends(l, "\r") then str_slice(l, 0, sub(str_len(l), 1)) else l end
end

fn run_all(ls: List[String], ok: Bool) -> Bool ! [io]
  match ls
    case [] -> ok
    case [l, ..rest] -> run_one(solve_line(l), rest, ok)
  end
end

fn run_one(r: Result[String, String], rest: List[String], ok: Bool) -> Bool ! [io]
  match r
    case Ok(text) -> print_then(text, rest, ok)
    case Err(msg) -> print_then(msg, rest, false)
  end
end

fn print_then(text: String, rest: List[String], ok: Bool) -> Bool ! [io]
  if eq(text, "") then run_all(rest, ok)
  else print_and_run(text, rest, ok)
  end
end

fn print_and_run(text: String, rest: List[String], ok: Bool) -> Bool ! [io]
  println(text)
  run_all(rest, ok)
end

fn finish(good: Bool) -> Unit ! [io]
  if good then Unit else exit(1) end
end

fn main() -> Unit ! [io]
  finish(run_all(list_map(str_split(read_all(), "\n"), strip_cr), true))
end

test "precedence and associativity"
  expect_eq(solve_line("1 + 2 * 3"), Ok("7"))
  expect_eq(solve_line("(1+2)*3"), Ok("9"))
  expect_eq(solve_line("8-3-2"), Ok("3"))
  expect_eq(solve_line("2*3%4"), Ok("2"))
end

test "truncating division and remainder"
  expect_eq(solve_line("-7/2"), Ok("-3"))
  expect_eq(solve_line("-7%2"), Ok("-1"))
  expect_eq(solve_line("7%-2"), Ok("1"))
  expect_eq(solve_line("-(4 - 10) % 4"), Ok("2"))
end

test "syntax and division errors"
  expect_eq(solve_line("2 *"), Err("error: syntax at 4"))
  expect_eq(solve_line("1 2"), Err("error: syntax at 3"))
  expect_eq(solve_line("(1"), Err("error: syntax at 3"))
  expect_eq(solve_line("7 / (3 - 3)"), Err("error: division by zero"))
  expect_eq(solve_line("1/0 +"), Err("error: syntax at 6"))
  expect_eq(solve_line("   "), Ok(""))
end
