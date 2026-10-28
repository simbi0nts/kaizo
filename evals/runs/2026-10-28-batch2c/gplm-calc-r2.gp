# calc: integer expression calculator in GPLM

type Tok = TNum(Int, Int) | TSym(String, Int) | TEnd(Int) end
type Expr = ELit(Int) | ENeg(Expr) | EBin(String, Expr, Expr) end
type PR = { e: Expr, rest: List[Tok] } end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_space(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 13))
end

fn scan_digits(s: String, j: Int, n: Int) -> Int
  if lt(j, n) then
    if is_digit(str_byte(s, j)) then scan_digits(s, add(j, 1), n) else j end
  else
    j
  end
end

fn tokenize_from(s: String, i: Int, n: Int, acc: List[Tok]) -> List[Tok]
  if ge(i, n) then
    list_reverse(list_cons(TEnd(add(n, 1)), acc))
  else
    let c = str_byte(s, i)
    if is_space(c) then
      tokenize_from(s, add(i, 1), n, acc)
    elif is_digit(c) then
      let j = scan_digits(s, i, n)
      let v = unwrap_or(str_to_int(str_slice(s, i, j)), 0)
      tokenize_from(s, j, n, list_cons(TNum(v, add(i, 1)), acc))
    else
      tokenize_from(s, add(i, 1), n, list_cons(TSym(str_slice(s, i, add(i, 1)), add(i, 1)), acc))
    end
  end
end

fn tokenize(s: String) -> List[Tok]
  tokenize_from(s, 0, str_len(s), [])
end

fn tok_col(t: Tok) -> Int
  match t
    case TNum(_, c) -> c
    case TSym(_, c) -> c
    case TEnd(c) -> c
  end
end

fn col_of(ts: List[Tok]) -> Int
  match ts
    case [t, .._] -> tok_col(t)
    case [] -> 0
  end
end

fn parse_expr(ts: List[Tok]) -> Result[PR, Int]
  let r = try parse_term(ts)
  expr_loop(r.e, r.rest)
end

fn expr_loop(lhs: Expr, ts: List[Tok]) -> Result[PR, Int]
  match ts
    case [TSym(op, _), ..rest] ->
      if or(eq(op, "+"), eq(op, "-")) then
        let r = try parse_term(rest)
        expr_loop(EBin(op, lhs, r.e), r.rest)
      else
        Ok(PR { e: lhs, rest: ts })
      end
    case _ -> Ok(PR { e: lhs, rest: ts })
  end
end

fn parse_term(ts: List[Tok]) -> Result[PR, Int]
  let r = try parse_unary(ts)
  term_loop(r.e, r.rest)
end

fn term_loop(lhs: Expr, ts: List[Tok]) -> Result[PR, Int]
  match ts
    case [TSym(op, _), ..rest] ->
      if or(eq(op, "*"), eq(op, "/"), eq(op, "%")) then
        let r = try parse_unary(rest)
        term_loop(EBin(op, lhs, r.e), r.rest)
      else
        Ok(PR { e: lhs, rest: ts })
      end
    case _ -> Ok(PR { e: lhs, rest: ts })
  end
end

fn parse_unary(ts: List[Tok]) -> Result[PR, Int]
  match ts
    case [TSym("-", _), ..rest] ->
      let r = try parse_unary(rest)
      Ok(PR { e: ENeg(r.e), rest: r.rest })
    case _ -> parse_primary(ts)
  end
end

fn parse_primary(ts: List[Tok]) -> Result[PR, Int]
  match ts
    case [TNum(n, _), ..rest] -> Ok(PR { e: ELit(n), rest: rest })
    case [TSym("(", _), ..rest] ->
      let r = try parse_expr(rest)
      match r.rest
        case [TSym(")", _), ..rest2] -> Ok(PR { e: r.e, rest: rest2 })
        case _ -> Err(col_of(r.rest))
      end
    case _ -> Err(col_of(ts))
  end
end

fn parse_line(ts: List[Tok]) -> Result[Expr, Int]
  let r = try parse_expr(ts)
  match r.rest
    case [TEnd(_), .._] -> Ok(r.e)
    case _ -> Err(col_of(r.rest))
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

fn apply(op: String, x: Int, y: Int) -> Result[Int, String]
  if eq(op, "+") then Ok(add(x, y))
  elif eq(op, "-") then Ok(sub(x, y))
  elif eq(op, "*") then Ok(mul(x, y))
  elif eq(y, 0) then Err("error: division by zero")
  elif eq(op, "/") then Ok(tdiv(x, y))
  else Ok(trem(x, y))
  end
end

fn eval(e: Expr) -> Result[Int, String]
  match e
    case ELit(n) -> Ok(n)
    case ENeg(x) ->
      let v = try eval(x)
      Ok(sub(0, v))
    case EBin(op, a, b) ->
      let x = try eval(a)
      let y = try eval(b)
      apply(op, x, y)
  end
end

fn process(line: String) -> Result[Int, String]
  match parse_line(tokenize(line))
    case Err(c) -> Err(str_cat("error: syntax at ", show(c)))
    case Ok(e) -> eval(e)
  end
end

fn strip_cr(l: String) -> String
  let n = str_len(l)
  if gt(n, 0) then
    if eq(str_byte(l, sub(n, 1)), 13) then str_slice(l, 0, sub(n, 1)) else l end
  else
    l
  end
end

fn loop(ok: Bool) -> Bool ! [io]
  match read_line()
    case None -> ok
    case Some(raw) ->
      let l = strip_cr(raw)
      if eq(str_trim(l), "") then
        loop(ok)
      else
        match process(l)
          case Ok(v) ->
            println(show(v))
            loop(ok)
          case Err(m) ->
            println(m)
            loop(false)
        end
      end
  end
end

fn main() -> Unit ! [io]
  let ok = loop(true)
  if ok then exit(0) else exit(1) end
end

test "precedence and associativity"
  expect_eq(process("1 + 2 * 3"), Ok(7))
  expect_eq(process("(1+2)*3"), Ok(9))
  expect_eq(process("8-3-2"), Ok(3))
  expect_eq(process("2*3%4"), Ok(2))
end

test "truncating division and signs"
  expect_eq(process("-7/2"), Ok(-3))
  expect_eq(process("-7%2"), Ok(-1))
  expect_eq(process("7%-2"), Ok(1))
  expect_eq(process("-(4 - 10) % 4"), Ok(2))
  expect_eq(process("--3"), Ok(3))
end

test "errors"
  expect_eq(process("2 *"), Err("error: syntax at 4"))
  expect_eq(process("7 / (3 - 3)"), Err("error: division by zero"))
  expect_eq(process("1 2"), Err("error: syntax at 3"))
  expect_eq(process("(1"), Err("error: syntax at 3"))
  expect_eq(process("1/0 +"), Err("error: syntax at 6"))
  expect_eq(process("1 $ 2"), Err("error: syntax at 3"))
end
