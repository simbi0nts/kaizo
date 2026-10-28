# calc: integer calculator. One expression per input line.

type Expr = Num(Int) | Neg(Expr) | Bin(Int, Expr, Expr) end
type Parsed = { tree: Expr, pos: Int } end

fn is_ws(b: Int) -> Bool
  or(eq(b, 32), eq(b, 9), eq(b, 13))
end

# byte at index p, or -1 at end of line
fn byte_at(s: String, p: Int) -> Int
  if lt(p, str_len(s)) then str_byte(s, p) else -1 end
end

# first non-blank index at or after p
fn skip_ws(s: String, p: Int) -> Int
  if is_ws(byte_at(s, p)) then skip_ws(s, add(p, 1)) else p end
end

fn digits(s: String, p: Int, acc: Int) -> Parsed
  let c = byte_at(s, p)
  if and(ge(c, 48), le(c, 57)) then
    digits(s, add(p, 1), add(mul(acc, 10), sub(c, 48)))
  else
    Parsed { tree: Num(acc), pos: p }
  end
end

# Parsers return Err(index of the first offending byte, 0-based).
fn parse_expr(s: String, p: Int) -> Result[Parsed, Int]
  let t = try parse_term(s, p)
  expr_rest(s, t.tree, t.pos)
end

fn expr_rest(s: String, left: Expr, p: Int) -> Result[Parsed, Int]
  let q = skip_ws(s, p)
  let c = byte_at(s, q)
  if or(eq(c, 43), eq(c, 45)) then
    let r = try parse_term(s, add(q, 1))
    expr_rest(s, Bin(c, left, r.tree), r.pos)
  else
    Ok(Parsed { tree: left, pos: q })
  end
end

fn parse_term(s: String, p: Int) -> Result[Parsed, Int]
  let u = try parse_unary(s, p)
  term_rest(s, u.tree, u.pos)
end

fn term_rest(s: String, left: Expr, p: Int) -> Result[Parsed, Int]
  let q = skip_ws(s, p)
  let c = byte_at(s, q)
  if or(eq(c, 42), eq(c, 47), eq(c, 37)) then
    let r = try parse_unary(s, add(q, 1))
    term_rest(s, Bin(c, left, r.tree), r.pos)
  else
    Ok(Parsed { tree: left, pos: q })
  end
end

fn parse_unary(s: String, p: Int) -> Result[Parsed, Int]
  let q = skip_ws(s, p)
  let c = byte_at(s, q)
  if eq(c, 45) then
    let u = try parse_unary(s, add(q, 1))
    Ok(Parsed { tree: Neg(u.tree), pos: u.pos })
  else
    parse_primary(s, q)
  end
end

fn parse_primary(s: String, p: Int) -> Result[Parsed, Int]
  let c = byte_at(s, p)
  if and(ge(c, 48), le(c, 57)) then
    Ok(digits(s, p, 0))
  elif eq(c, 40) then
    parse_group(s, add(p, 1))
  else
    Err(p)
  end
end

fn parse_group(s: String, p: Int) -> Result[Parsed, Int]
  let e = try parse_expr(s, p)
  if eq(byte_at(s, e.pos), 41) then
    Ok(Parsed { tree: e.tree, pos: add(e.pos, 1) })
  else
    Err(e.pos)
  end
end

# whole line must be consumed; Err(index) otherwise
fn parse_line(s: String) -> Result[Expr, Int]
  let r = try parse_expr(s, 0)
  let q = skip_ws(s, r.pos)
  if lt(q, str_len(s)) then Err(q) else Ok(r.tree) end
end

fn abs_int(n: Int) -> Int
  if lt(n, 0) then sub(0, n) else n end
end

fn negate_if(flag: Bool, n: Int) -> Int
  if flag then sub(0, n) else n end
end

# C-style division: truncates toward zero
fn trunc_div(a: Int, b: Int) -> Int
  negate_if(ne(lt(a, 0), lt(b, 0)), div(abs_int(a), abs_int(b)))
end

# C-style remainder: sign follows the dividend
fn trunc_rem(a: Int, b: Int) -> Int
  negate_if(lt(a, 0), mod(abs_int(a), abs_int(b)))
end

fn apply_op(op: Int, a: Int, b: Int) -> Result[Int, String]
  if eq(op, 43) then Ok(add(a, b))
  elif eq(op, 45) then Ok(sub(a, b))
  elif eq(op, 42) then Ok(mul(a, b))
  elif eq(b, 0) then Err("division by zero")
  elif eq(op, 47) then Ok(trunc_div(a, b))
  else Ok(trunc_rem(a, b))
  end
end

fn eval_expr(e: Expr) -> Result[Int, String]
  match e
    case Num(n) -> Ok(n)
    case Neg(x) ->
      let v = try eval_expr(x)
      Ok(sub(0, v))
    case Bin(op, l, r) ->
      let a = try eval_expr(l)
      let b = try eval_expr(r)
      apply_op(op, a, b)
  end
end

# pure: result value, or the error text after "error: "
fn compute(line: String) -> Result[Int, String]
  match parse_line(line)
    case Err(col) -> Err(str_cat("syntax at ", show(add(col, 1))))
    case Ok(tree) -> eval_expr(tree)
  end
end

fn report(r: Result[Int, String]) -> Bool ! [io]
  match r
    case Ok(v) ->
      println(show(v))
      true
    case Err(msg) ->
      println(str_cat("error: ", msg))
      false
  end
end

# returns true when the line succeeded (blank lines print nothing)
fn handle_line(line: String) -> Bool ! [io]
  if eq(skip_ws(line, 0), str_len(line)) then
    true
  else
    report(compute(line))
  end
end

fn run_lines(all_ok: Bool) -> Bool ! [io]
  match read_line()
    case None -> all_ok
    case Some(line) ->
      let good = handle_line(line)
      run_lines(and(all_ok, good))
  end
end

fn main() -> Unit ! [io]
  let ok = run_lines(true)
  let code = if ok then 0 else 1 end
  exit(code)
end

test "precedence and associativity"
  expect_eq(compute("1 + 2 * 3"), Ok(7))
  expect_eq(compute("(1+2)*3"), Ok(9))
  expect_eq(compute("8-3-2"), Ok(3))
  expect_eq(compute("2*3%4"), Ok(2))
end

test "signs and truncating division"
  expect_eq(compute("-7/2"), Ok(-3))
  expect_eq(compute("-7%2"), Ok(-1))
  expect_eq(compute("7%-2"), Ok(1))
  expect_eq(compute("-(4 - 10) % 4"), Ok(2))
end

test "syntax and division errors"
  expect_eq(compute("2 *"), Err("syntax at 4"))
  expect_eq(compute("1 2"), Err("syntax at 3"))
  expect_eq(compute("(1"), Err("syntax at 3"))
  expect_eq(compute("7 / (3 - 3)"), Err("division by zero"))
  expect_eq(compute("7 / (3 - 3) +"), Err("syntax at 14"))
  expect_eq(compute("7 / (3 - 3) 2"), Err("syntax at 13"))
end
