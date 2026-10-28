type Tok = { kind: String, val: Int, col: Int } end
type NumR = { v: Int, j: Int } end
type Expr = Lit(Int) | Neg(Expr) | Bin(String, Expr, Expr) end
type PR = { e: Expr, rest: List[Tok] } end
type Out = Skip | Good(String) | Bad(String) end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn lex_num(s: String, i: Int, n: Int, v: Int) -> NumR
  if ge(i, n) then NumR { v: v, j: i }
  else
    let c = str_byte(s, i)
    if is_digit(c) then lex_num(s, add(i, 1), n, add(mul(v, 10), sub(c, 48)))
    else NumR { v: v, j: i }
    end
  end
end

fn lex(s: String, i: Int, n: Int, acc: List[Tok]) -> List[Tok]
  if ge(i, n) then list_reverse(list_cons(Tok { kind: "eof", val: 0, col: add(n, 1) }, acc))
  else
    let c = str_byte(s, i)
    if or(eq(c, 32), eq(c, 9), eq(c, 13)) then lex(s, add(i, 1), n, acc)
    elif is_digit(c) then
      let r = lex_num(s, i, n, 0)
      lex(s, r.j, n, list_cons(Tok { kind: "num", val: r.v, col: add(i, 1) }, acc))
    else lex(s, add(i, 1), n, list_cons(Tok { kind: str_from_bytes([c]), val: 0, col: add(i, 1) }, acc))
    end
  end
end

fn peek(ts: List[Tok]) -> Tok
  match ts
    case [t, .._] -> t
    case [] -> Tok { kind: "eof", val: 0, col: 0 }
  end
end

fn tail(ts: List[Tok]) -> List[Tok]
  match ts
    case [_, ..r] -> r
    case [] -> []
  end
end

fn parse_expr(ts: List[Tok]) -> Result[PR, Int]
  let l = try parse_term(ts)
  expr_loop(l.e, l.rest)
end

fn expr_loop(acc: Expr, ts: List[Tok]) -> Result[PR, Int]
  let t = peek(ts)
  if or(eq(t.kind, "+"), eq(t.kind, "-")) then
    let r = try parse_term(tail(ts))
    expr_loop(Bin(t.kind, acc, r.e), r.rest)
  else Ok(PR { e: acc, rest: ts })
  end
end

fn parse_term(ts: List[Tok]) -> Result[PR, Int]
  let l = try parse_unary(ts)
  term_loop(l.e, l.rest)
end

fn term_loop(acc: Expr, ts: List[Tok]) -> Result[PR, Int]
  let t = peek(ts)
  if or(eq(t.kind, "*"), eq(t.kind, "/"), eq(t.kind, "%")) then
    let r = try parse_unary(tail(ts))
    term_loop(Bin(t.kind, acc, r.e), r.rest)
  else Ok(PR { e: acc, rest: ts })
  end
end

fn parse_unary(ts: List[Tok]) -> Result[PR, Int]
  let t = peek(ts)
  if eq(t.kind, "-") then
    let r = try parse_unary(tail(ts))
    Ok(PR { e: Neg(r.e), rest: r.rest })
  else parse_primary(ts)
  end
end

fn parse_primary(ts: List[Tok]) -> Result[PR, Int]
  let t = peek(ts)
  if eq(t.kind, "num") then Ok(PR { e: Lit(t.val), rest: tail(ts) })
  elif eq(t.kind, "(") then
    let r = try parse_expr(tail(ts))
    let c = peek(r.rest)
    if eq(c.kind, ")") then Ok(PR { e: r.e, rest: tail(r.rest) })
    else Err(c.col)
    end
  else Err(t.col)
  end
end

fn parse_line(s: String) -> Result[Expr, Int]
  let ts = lex(s, 0, str_len(s), [])
  let r = try parse_expr(ts)
  let t = peek(r.rest)
  if eq(t.kind, "eof") then Ok(r.e) else Err(t.col) end
end

fn abs_i(x: Int) -> Int
  if lt(x, 0) then sub(0, x) else x end
end

fn cdiv(a: Int, b: Int) -> Int
  let q = div(abs_i(a), abs_i(b))
  if ne(lt(a, 0), lt(b, 0)) then sub(0, q) else q end
end

fn apply(op: String, a: Int, b: Int) -> Result[Int, String]
  if eq(op, "+") then Ok(add(a, b))
  elif eq(op, "-") then Ok(sub(a, b))
  elif eq(op, "*") then Ok(mul(a, b))
  elif eq(b, 0) then Err("division by zero")
  elif eq(op, "/") then Ok(cdiv(a, b))
  else Ok(sub(a, mul(b, cdiv(a, b))))
  end
end

fn eval(e: Expr) -> Result[Int, String]
  match e
    case Lit(n) -> Ok(n)
    case Neg(x) ->
      let v = try eval(x)
      Ok(sub(0, v))
    case Bin(op, x, y) ->
      let a = try eval(x)
      let b = try eval(y)
      apply(op, a, b)
  end
end

fn strip_cr(s: String) -> String
  if str_ends(s, "\r") then str_slice(s, 0, sub(str_len(s), 1)) else s end
end

fn calc_line(raw: String) -> Out
  let s = strip_cr(raw)
  if eq(str_trim(s), "") then Skip
  else
    match parse_line(s)
      case Err(col) -> Bad(str_cat("error: syntax at ", show(col)))
      case Ok(e) ->
        match eval(e)
          case Ok(v) -> Good(show(v))
          case Err(m) -> Bad(str_cat("error: ", m))
        end
    end
  end
end

fn run(ok: Bool) -> Unit ! [io]
  match read_line()
    case None -> if ok then exit(0) else exit(1) end
    case Some(l) ->
      match calc_line(l)
        case Skip -> run(ok)
        case Good(v) ->
          println(v)
          run(ok)
        case Bad(m) ->
          println(m)
          run(false)
      end
  end
end

fn main() -> Unit ! [io]
  run(true)
end

test "precedence and parens"
  expect_eq(calc_line("1 + 2 * 3"), Good("7"))
  expect_eq(calc_line("(1+2)*3"), Good("9"))
  expect_eq(calc_line("-(4 - 10) % 4"), Good("2"))
  expect_eq(calc_line("8-3-2"), Good("3"))
  expect_eq(calc_line("2*3%4"), Good("2"))
end

test "truncating division"
  expect_eq(calc_line("-7/2"), Good("-3"))
  expect_eq(calc_line("-7%2"), Good("-1"))
  expect_eq(calc_line("7%-2"), Good("1"))
  expect_eq(calc_line("7 / (3 - 3)"), Bad("error: division by zero"))
end

test "syntax errors"
  expect_eq(calc_line("2 *"), Bad("error: syntax at 4"))
  expect_eq(calc_line("1 2"), Bad("error: syntax at 3"))
  expect_eq(calc_line("(1"), Bad("error: syntax at 3"))
  expect_eq(calc_line("1/0 +"), Bad("error: syntax at 6"))
  expect_eq(calc_line("   "), Skip)
end
