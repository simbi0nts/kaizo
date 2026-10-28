type Op = OpAdd | OpSub | OpMul | OpDiv | OpMod end
type Node = Num(Int) | Neg(Node) | Bin(Op, Node, Node) end
type Parsed = { node: Node, pos: Int } end

fn is_space(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 13))
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_add_op(c: Int) -> Bool
  or(eq(c, 43), eq(c, 45))
end

fn is_mul_op(c: Int) -> Bool
  or(eq(c, 42), eq(c, 47), eq(c, 37))
end

fn op_of(c: Int) -> Op
  if eq(c, 43) then OpAdd
  elif eq(c, 45) then OpSub
  elif eq(c, 42) then OpMul
  elif eq(c, 47) then OpDiv
  else OpMod end
end

# byte at i, or -1 at end of line
fn peek(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then str_byte(s, i) else -1 end
end

fn skip_ws(s: String, i: Int) -> Int
  if is_space(peek(s, i)) then skip_ws(s, add(i, 1)) else i end
end

fn is_blank(line: String) -> Bool
  eq(skip_ws(line, 0), str_len(line))
end

fn number_from(s: String, i: Int, acc: Int) -> Parsed
  if is_digit(peek(s, i)) then number_from(s, add(i, 1), add(mul(acc, 10), sub(peek(s, i), 48)))
  else Parsed { node: Num(acc), pos: i } end
end

fn parse_primary(s: String, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = peek(s, j)
  if is_digit(c) then Ok(number_from(s, j, 0))
  elif eq(c, 40) then
    let e = try parse_expr(s, add(j, 1))
    let k = skip_ws(s, e.pos)
    if eq(peek(s, k), 41) then Ok(Parsed { node: e.node, pos: add(k, 1) })
    else Err(add(k, 1)) end
  else Err(add(j, 1)) end
end

fn parse_unary(s: String, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  if eq(peek(s, j), 45) then
    let u = try parse_unary(s, add(j, 1))
    Ok(Parsed { node: Neg(u.node), pos: u.pos })
  else parse_primary(s, j) end
end

fn term_rest(s: String, left: Parsed) -> Result[Parsed, Int]
  let i = skip_ws(s, left.pos)
  let c = peek(s, i)
  if is_mul_op(c) then
    let right = try parse_unary(s, add(i, 1))
    term_rest(s, Parsed { node: Bin(op_of(c), left.node, right.node), pos: right.pos })
  else Ok(Parsed { node: left.node, pos: i }) end
end

fn parse_term(s: String, i: Int) -> Result[Parsed, Int]
  let u = try parse_unary(s, i)
  term_rest(s, u)
end

fn expr_rest(s: String, left: Parsed) -> Result[Parsed, Int]
  let i = skip_ws(s, left.pos)
  let c = peek(s, i)
  if is_add_op(c) then
    let right = try parse_term(s, add(i, 1))
    expr_rest(s, Parsed { node: Bin(op_of(c), left.node, right.node), pos: right.pos })
  else Ok(Parsed { node: left.node, pos: i }) end
end

fn parse_expr(s: String, i: Int) -> Result[Parsed, Int]
  let t = try parse_term(s, i)
  expr_rest(s, t)
end

# whole line must be consumed; errors carry the 1-based column
fn parse_line(s: String) -> Result[Node, Int]
  let p = try parse_expr(s, 0)
  let k = skip_ws(s, p.pos)
  if eq(k, str_len(s)) then Ok(p.node) else Err(add(k, 1)) end
end

fn trunc_abs(x: Int) -> Int
  if lt(x, 0) then sub(0, x) else x end
end

# C-style division: rounds toward zero
fn trunc_div(x: Int, y: Int) -> Int
  let q = div(trunc_abs(x), trunc_abs(y))
  if eq(lt(x, 0), lt(y, 0)) then q else sub(0, q) end
end

# C-style remainder: sign follows the dividend
fn trunc_mod(x: Int, y: Int) -> Int
  let r = mod(trunc_abs(x), trunc_abs(y))
  if lt(x, 0) then sub(0, r) else r end
end

fn apply_op(op: Op, x: Int, y: Int) -> Result[Int, String]
  match op
    case OpAdd -> Ok(add(x, y))
    case OpSub -> Ok(sub(x, y))
    case OpMul -> Ok(mul(x, y))
    case OpDiv -> if eq(y, 0) then Err("error: division by zero") else Ok(trunc_div(x, y)) end
    case OpMod -> if eq(y, 0) then Err("error: division by zero") else Ok(trunc_mod(x, y)) end
  end
end

fn evaluate(n: Node) -> Result[Int, String]
  match n
    case Num(v) -> Ok(v)
    case Neg(a) ->
      let v = try evaluate(a)
      Ok(sub(0, v))
    case Bin(op, a, b) ->
      let x = try evaluate(a)
      let y = try evaluate(b)
      apply_op(op, x, y)
  end
end

fn run_line(s: String) -> Result[Int, String]
  match parse_line(s)
    case Err(c) -> Err(str_cat("error: syntax at ", show(c)))
    case Ok(n) -> evaluate(n)
  end
end

fn report(r: Result[Int, String]) -> Bool ! [io]
  match r
    case Ok(v) ->
      println(show(v))
      false
    case Err(m) ->
      println(m)
      true
  end
end

# returns true if this line failed; blank lines print nothing
fn handle(line: String) -> Bool ! [io]
  if is_blank(line) then false else report(run_line(line)) end
end

fn process(lines: List[String], failed: Bool) -> Bool ! [io]
  match lines
    case [] -> failed
    case [first, ..rest] ->
      let bad = handle(first)
      process(rest, or(failed, bad))
  end
end

fn main() -> Unit ! [io]
  let text = read_all()
  let lines = str_split(text, "\n")
  let failed = process(lines, false)
  exit(if failed then 1 else 0 end)
end

test "precedence and nesting"
  expect_eq(run_line("1 + 2 * 3"), Ok(7))
  expect_eq(run_line("(1+2)*3"), Ok(9))
  expect_eq(run_line("-(4 - 10) % 4"), Ok(2))
  expect_eq(run_line("2*3%4"), Ok(2))
end

test "associativity and signed division"
  expect_eq(run_line("8-3-2"), Ok(3))
  expect_eq(run_line("-7/2"), Ok(-3))
  expect_eq(run_line("-7%2"), Ok(-1))
  expect_eq(run_line("7%-2"), Ok(1))
end

test "syntax and division errors"
  expect_eq(run_line("2 *"), Err("error: syntax at 4"))
  expect_eq(run_line("1 2"), Err("error: syntax at 3"))
  expect_eq(run_line("(1"), Err("error: syntax at 3"))
  expect_eq(run_line("7 / (3 - 3)"), Err("error: division by zero"))
end
