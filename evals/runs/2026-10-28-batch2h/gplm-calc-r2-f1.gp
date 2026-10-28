# calc: integer calculator. One expression per stdin line.

type Op = Add | Sub | Mul | Div | Mod end
type Node = Num(Int) | Neg(Node) | Bin(Op, Node, Node) end
type Parsed = { node: Node, next: Int } end

# Byte at index i, or -1 at end of line.
fn code_at(s: String, i: Int) -> Int
  if ge(i, str_len(s)) then -1 else str_byte(s, i) end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn skip_ws(s: String, i: Int) -> Int
  let c = code_at(s, i)
  if or(eq(c, 32), eq(c, 9), eq(c, 13)) then skip_ws(s, add(i, 1)) else i end
end

fn magnitude(x: Int) -> Int
  if lt(x, 0) then sub(0, x) else x end
end

# Truncating division (C semantics): divide magnitudes, then apply the sign.
fn trunc_div(x: Int, y: Int) -> Int
  let q = div(magnitude(x), magnitude(y))
  let negative = or(and(lt(x, 0), ge(y, 0)), and(ge(x, 0), lt(y, 0)))
  if negative then sub(0, q) else q end
end

# Remainder takes the sign of the dividend.
fn trunc_mod(x: Int, y: Int) -> Int
  let r = mod(magnitude(x), magnitude(y))
  if lt(x, 0) then sub(0, r) else r end
end

fn digits(s: String, i: Int, acc: Int) -> Result[Parsed, Int]
  let c = code_at(s, i)
  if is_digit(c) then digits(s, add(i, 1), add(mul(acc, 10), sub(c, 48)))
  else Ok(Parsed { node: Num(acc), next: i }) end
end

fn parse_primary(s: String, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = code_at(s, j)
  if is_digit(c) then digits(s, j, 0)
  elif eq(c, 40) then
    let e = try parse_expr(s, add(j, 1))
    let k = skip_ws(s, e.next)
    if eq(code_at(s, k), 41) then Ok(Parsed { node: e.node, next: add(k, 1) })
    else Err(k) end
  else Err(j) end
end

fn parse_unary(s: String, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = code_at(s, j)
  if eq(c, 45) then
    let u = try parse_unary(s, add(j, 1))
    Ok(Parsed { node: Neg(u.node), next: u.next })
  else parse_primary(s, j) end
end

fn term_rest(s: String, left: Node, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = code_at(s, j)
  if eq(c, 42) then
    let r = try parse_unary(s, add(j, 1))
    term_rest(s, Bin(Mul, left, r.node), r.next)
  elif eq(c, 47) then
    let r = try parse_unary(s, add(j, 1))
    term_rest(s, Bin(Div, left, r.node), r.next)
  elif eq(c, 37) then
    let r = try parse_unary(s, add(j, 1))
    term_rest(s, Bin(Mod, left, r.node), r.next)
  else Ok(Parsed { node: left, next: j }) end
end

fn parse_term(s: String, i: Int) -> Result[Parsed, Int]
  let first = try parse_unary(s, i)
  term_rest(s, first.node, first.next)
end

fn expr_rest(s: String, left: Node, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = code_at(s, j)
  if eq(c, 43) then
    let r = try parse_term(s, add(j, 1))
    expr_rest(s, Bin(Add, left, r.node), r.next)
  elif eq(c, 45) then
    let r = try parse_term(s, add(j, 1))
    expr_rest(s, Bin(Sub, left, r.node), r.next)
  else Ok(Parsed { node: left, next: j }) end
end

fn parse_expr(s: String, i: Int) -> Result[Parsed, Int]
  let first = try parse_term(s, i)
  expr_rest(s, first.node, first.next)
end

# Whole line must be one expression. Err holds the 0-based index of the
# first character that cannot continue (line length at end of line).
fn parse_line(s: String) -> Result[Node, Int]
  let e = try parse_expr(s, 0)
  let k = skip_ws(s, e.next)
  if ge(k, str_len(s)) then Ok(e.node) else Err(k) end
end

fn apply_op(op: Op, x: Int, y: Int) -> Result[Int, String]
  match op
    case Add -> Ok(add(x, y))
    case Sub -> Ok(sub(x, y))
    case Mul -> Ok(mul(x, y))
    case Div -> if eq(y, 0) then Err("error: division by zero") else Ok(trunc_div(x, y)) end
    case Mod -> if eq(y, 0) then Err("error: division by zero") else Ok(trunc_mod(x, y)) end
  end
end

fn eval_node(n: Node) -> Result[Int, String]
  match n
    case Num(v) -> Ok(v)
    case Neg(x) ->
      let v = try eval_node(x)
      Ok(sub(0, v))
    case Bin(op, a, b) ->
      let x = try eval_node(a)
      let y = try eval_node(b)
      apply_op(op, x, y)
  end
end

# Syntax is checked over the whole line before any evaluation.
fn describe(line: String) -> Result[Int, String]
  match parse_line(line)
    case Err(col) -> Err(str_cat("error: syntax at ", show(add(col, 1))))
    case Ok(n) -> eval_node(n)
  end
end

fn render(r: Result[Int, String]) -> String
  match r
    case Ok(v) -> show(v)
    case Err(m) -> m
  end
end

fn failure_count(r: Result[Int, String]) -> Int
  match r
    case Ok(_) -> 0
    case Err(_) -> 1
  end
end

fn run_lines(lines: List[String], failures: Int) -> Int ! [io]
  match lines
    case [] -> failures
    case [first, ..rest] ->
      let k = skip_ws(first, 0)
      if ge(k, str_len(first)) then run_lines(rest, failures)
      else
        let result = describe(first)
        println(render(result))
        run_lines(rest, add(failures, failure_count(result)))
      end
  end
end

fn main() -> Unit ! [io]
  let text = read_all()
  let failures = run_lines(str_split(text, "\n"), 0)
  if eq(failures, 0) then exit(0) else exit(1) end
end

test "precedence and parentheses"
  expect_eq(render(describe("1 + 2 * 3")), "7")
  expect_eq(render(describe("(1+2)*3")), "9")
  expect_eq(render(describe("-(4 - 10) % 4")), "2")
end

test "left associativity and truncating division"
  expect_eq(render(describe("8-3-2")), "3")
  expect_eq(render(describe("2*3%4")), "2")
  expect_eq(render(describe("-7/2")), "-3")
  expect_eq(render(describe("-7%2")), "-1")
  expect_eq(render(describe("7%-2")), "1")
end

test "syntax error columns and division by zero"
  expect_eq(render(describe("2 *")), "error: syntax at 4")
  expect_eq(render(describe("1 2")), "error: syntax at 3")
  expect_eq(render(describe("(1")), "error: syntax at 3")
  expect_eq(render(describe("7 / (3 - 3)")), "error: division by zero")
  expect_eq(render(describe("7 / (3 - 3) +")), "error: syntax at 14")
end
