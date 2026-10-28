# calc: integer expression calculator, one expression per input line

type Tok = TNum(Int, Int) | TSym(String, Int) | TBad(Int) end
type Expr = Num(Int) | Neg(Expr) | Bin(String, Expr, Expr) end
type PR = { e: Expr, rest: List[Tok] } end
type Out = Blank | Good(Int) | Fail(String) end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_sym(c: Int) -> Bool
  or(eq(c, 43), eq(c, 45), eq(c, 42), eq(c, 47), eq(c, 37), eq(c, 40), eq(c, 41))
end

fn is_space(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 13))
end

fn digits_end(s: String, i: Int, n: Int) -> Int
  if ge(i, n) then i
  elif is_digit(str_byte(s, i)) then digits_end(s, add(i, 1), n)
  else i
  end
end

fn digits_val(s: String, i: Int, j: Int, acc: Int) -> Int
  if ge(i, j) then acc
  else digits_val(s, add(i, 1), j, add(mul(acc, 10), sub(str_byte(s, i), 48)))
  end
end

fn tokenize(s: String, i: Int, n: Int, acc: List[Tok]) -> List[Tok]
  if ge(i, n) then list_reverse(acc)
  else
    let c = str_byte(s, i)
    if is_space(c) then tokenize(s, add(i, 1), n, acc)
    elif is_digit(c) then
      let j = digits_end(s, i, n)
      let v = digits_val(s, i, j, 0)
      tokenize(s, j, n, list_cons(TNum(v, add(i, 1)), acc))
    elif is_sym(c) then
      tokenize(s, add(i, 1), n, list_cons(TSym(str_slice(s, i, add(i, 1)), add(i, 1)), acc))
    else
      tokenize(s, add(i, 1), n, list_cons(TBad(add(i, 1)), acc))
    end
  end
end

fn tok_col(t: Tok) -> Int
  match t
    case TNum(_, c) -> c
    case TSym(_, c) -> c
    case TBad(c) -> c
  end
end

fn parse_expr(ts: List[Tok], eol: Int) -> Result[PR, Int]
  let first = try parse_term(ts, eol)
  expr_loop(first.e, first.rest, eol)
end

fn expr_loop(lhs: Expr, ts: List[Tok], eol: Int) -> Result[PR, Int]
  match ts
    case [TSym(op, _), ..rest] ->
      if or(eq(op, "+"), eq(op, "-")) then
        let r = try parse_term(rest, eol)
        expr_loop(Bin(op, lhs, r.e), r.rest, eol)
      else
        Ok(PR { e: lhs, rest: ts })
      end
    case _ -> Ok(PR { e: lhs, rest: ts })
  end
end

fn parse_term(ts: List[Tok], eol: Int) -> Result[PR, Int]
  let first = try parse_unary(ts, eol)
  term_loop(first.e, first.rest, eol)
end

fn term_loop(lhs: Expr, ts: List[Tok], eol: Int) -> Result[PR, Int]
  match ts
    case [TSym(op, _), ..rest] ->
      if or(eq(op, "*"), eq(op, "/"), eq(op, "%")) then
        let r = try parse_unary(rest, eol)
        term_loop(Bin(op, lhs, r.e), r.rest, eol)
      else
        Ok(PR { e: lhs, rest: ts })
      end
    case _ -> Ok(PR { e: lhs, rest: ts })
  end
end

fn parse_unary(ts: List[Tok], eol: Int) -> Result[PR, Int]
  match ts
    case [TSym("-", _), ..rest] ->
      let r = try parse_unary(rest, eol)
      Ok(PR { e: Neg(r.e), rest: r.rest })
    case _ -> parse_primary(ts, eol)
  end
end

fn parse_primary(ts: List[Tok], eol: Int) -> Result[PR, Int]
  match ts
    case [TNum(v, _), ..rest] -> Ok(PR { e: Num(v), rest: rest })
    case [TSym("(", _), ..rest] ->
      let r = try parse_expr(rest, eol)
      match r.rest
        case [TSym(")", _), ..r2] -> Ok(PR { e: r.e, rest: r2 })
        case [t, .._] -> Err(tok_col(t))
        case [] -> Err(eol)
      end
    case [t, .._] -> Err(tok_col(t))
    case [] -> Err(eol)
  end
end

fn parse_line(s: String) -> Result[Expr, Int]
  let n = str_len(s)
  let eol = add(n, 1)
  let ts = tokenize(s, 0, n, [])
  let r = try parse_expr(ts, eol)
  match r.rest
    case [] -> Ok(r.e)
    case [t, .._] -> Err(tok_col(t))
  end
end

fn iabs(x: Int) -> Int
  if lt(x, 0) then sub(0, x) else x end
end

fn tdiv(a: Int, b: Int) -> Int
  let q = div(iabs(a), iabs(b))
  if ne(lt(a, 0), lt(b, 0)) then sub(0, q) else q end
end

fn trem(a: Int, b: Int) -> Int
  sub(a, mul(b, tdiv(a, b)))
end

fn apply_op(op: String, x: Int, y: Int) -> Result[Int, String]
  if eq(op, "+") then Ok(add(x, y))
  elif eq(op, "-") then Ok(sub(x, y))
  elif eq(op, "*") then Ok(mul(x, y))
  elif eq(op, "/") then
    if eq(y, 0) then Err("division by zero") else Ok(tdiv(x, y)) end
  else
    if eq(y, 0) then Err("division by zero") else Ok(trem(x, y)) end
  end
end

fn eval_expr(e: Expr) -> Result[Int, String]
  match e
    case Num(v) -> Ok(v)
    case Neg(x) ->
      let v = try eval_expr(x)
      Ok(sub(0, v))
    case Bin(op, a, b) ->
      let x = try eval_expr(a)
      let y = try eval_expr(b)
      apply_op(op, x, y)
  end
end

fn strip_cr(line: String) -> String
  if str_ends(line, "\r") then str_slice(line, 0, sub(str_len(line), 1)) else line end
end

fn run_line(raw: String) -> Out
  let line = strip_cr(raw)
  if eq(str_trim(line), "") then Blank
  else
    match parse_line(line)
      case Err(col) -> Fail(str_cat("error: syntax at ", show(col)))
      case Ok(e) ->
        match eval_expr(e)
          case Ok(v) -> Good(v)
          case Err(msg) -> Fail(str_cat("error: ", msg))
        end
    end
  end
end

fn read_loop(all_ok: Bool) -> Bool ! [io]
  match read_line()
    case None -> all_ok
    case Some(line) ->
      match run_line(line)
        case Blank -> read_loop(all_ok)
        case Good(v) ->
          println(show(v))
          read_loop(all_ok)
        case Fail(msg) ->
          println(msg)
          read_loop(false)
      end
  end
end

fn main() -> Unit ! [io]
  let ok = read_loop(true)
  if ok then exit(0) else exit(1) end
end

test "precedence and parens"
  expect_eq(run_line("1 + 2 * 3"), Good(7))
  expect_eq(run_line("(1+2)*3"), Good(9))
  expect_eq(run_line("8-3-2"), Good(3))
  expect_eq(run_line("2*3%4"), Good(2))
end

test "signs and truncating division"
  expect_eq(run_line("-(4 - 10) % 4"), Good(2))
  expect_eq(run_line("-7/2"), Good(-3))
  expect_eq(run_line("-7%2"), Good(-1))
  expect_eq(run_line("7%-2"), Good(1))
  expect_eq(run_line("--3"), Good(3))
end

test "errors"
  expect_eq(run_line("2 *"), Fail("error: syntax at 4"))
  expect_eq(run_line("7 / (3 - 3)"), Fail("error: division by zero"))
  expect_eq(run_line("1 2"), Fail("error: syntax at 3"))
  expect_eq(run_line("(1"), Fail("error: syntax at 3"))
  expect_eq(run_line("1/0 +"), Fail("error: syntax at 6"))
  expect_eq(run_line("1 + a"), Fail("error: syntax at 5"))
  expect_eq(run_line("   "), Blank)
end
