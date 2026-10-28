# calc: integer calculator. One expression per input line.

type Node = Num(Int) | Neg(Node) | Bin(String, Node, Node) end
type Parsed = { node: Node, stop: Int } end

# ---- character helpers ----

fn ch(s: String, i: Int) -> String
  if lt(i, str_len(s)) then str_slice(s, i, add(i, 1)) else "" end
end

fn is_digit(c: String) -> Bool
  and(ne(c, ""), is_some(str_find("0123456789", c)))
end

fn is_ws(c: String) -> Bool
  or(eq(c, " "), eq(c, "\t"), eq(c, "\r"))
end

fn skip_ws(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then
    if is_ws(ch(s, i)) then skip_ws(s, add(i, 1)) else i end
  else
    i
  end
end

# ---- parser (recursive descent; Err carries the 0-based index of the failure) ----

fn parse_line(s: String) -> Result[Node, Int]
  let r = try parse_expr(s, 0)
  let k = skip_ws(s, r.stop)
  if lt(k, str_len(s)) then Err(k) else Ok(r.node) end
end

fn parse_expr(s: String, i: Int) -> Result[Parsed, Int]
  let t = try parse_term(s, i)
  expr_rest(s, t.stop, t.node)
end

fn expr_rest(s: String, i: Int, left: Node) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = ch(s, j)
  if or(eq(c, "+"), eq(c, "-")) then
    let r = try parse_term(s, add(j, 1))
    expr_rest(s, r.stop, Bin(c, left, r.node))
  else
    Ok(Parsed { node: left, stop: i })
  end
end

fn parse_term(s: String, i: Int) -> Result[Parsed, Int]
  let u = try parse_unary(s, i)
  term_rest(s, u.stop, u.node)
end

fn term_rest(s: String, i: Int, left: Node) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = ch(s, j)
  if or(eq(c, "*"), eq(c, "/"), eq(c, "%")) then
    let r = try parse_unary(s, add(j, 1))
    term_rest(s, r.stop, Bin(c, left, r.node))
  else
    Ok(Parsed { node: left, stop: i })
  end
end

fn parse_unary(s: String, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  if eq(ch(s, j), "-") then
    let r = try parse_unary(s, add(j, 1))
    Ok(Parsed { node: Neg(r.node), stop: r.stop })
  else
    parse_primary(s, j)
  end
end

fn parse_primary(s: String, i: Int) -> Result[Parsed, Int]
  let j = skip_ws(s, i)
  let c = ch(s, j)
  if eq(c, "(") then
    let r = try parse_expr(s, add(j, 1))
    let k = skip_ws(s, r.stop)
    if eq(ch(s, k), ")") then Ok(Parsed { node: r.node, stop: add(k, 1) }) else Err(k) end
  elif is_digit(c) then
    Ok(read_digits(s, j, 0))
  else
    Err(j)
  end
end

fn read_digits(s: String, i: Int, acc: Int) -> Parsed
  if is_digit(ch(s, i)) then
    read_digits(s, add(i, 1), add(mul(acc, 10), sub(str_byte(s, i), 48)))
  else
    Parsed { node: Num(acc), stop: i }
  end
end

# ---- evaluation ----

fn abs_int(x: Int) -> Int
  if lt(x, 0) then sub(0, x) else x end
end

# C-style: truncate toward zero
fn trunc_div(a: Int, b: Int) -> Int
  let q = div(abs_int(a), abs_int(b))
  if ne(lt(a, 0), lt(b, 0)) then sub(0, q) else q end
end

# C-style: sign follows the dividend
fn trunc_mod(a: Int, b: Int) -> Int
  let r = mod(abs_int(a), abs_int(b))
  if lt(a, 0) then sub(0, r) else r end
end

fn apply_op(op: String, a: Int, b: Int) -> Result[Int, String]
  if eq(op, "+") then Ok(add(a, b))
  elif eq(op, "-") then Ok(sub(a, b))
  elif eq(op, "*") then Ok(mul(a, b))
  elif eq(b, 0) then Err("division by zero")
  elif eq(op, "/") then Ok(trunc_div(a, b))
  else Ok(trunc_mod(a, b))
  end
end

fn eval(n: Node) -> Result[Int, String]
  match n
    case Num(v) -> Ok(v)
    case Neg(x) ->
      let v = try eval(x)
      Ok(sub(0, v))
    case Bin(op, l, r) ->
      let a = try eval(l)
      let b = try eval(r)
      apply_op(op, a, b)
  end
end

# ---- per-line rendering (pure) ----
# Ok(text) is a result line ("" for a blank line); Err(text) is an error line.

fn render(line: String) -> Result[String, String]
  if eq(skip_ws(line, 0), str_len(line)) then
    Ok("")
  else
    match parse_line(line)
      case Err(p) -> Err(str_cat("error: syntax at ", show(add(p, 1))))
      case Ok(n) ->
        match eval(n)
          case Ok(v) -> Ok(show(v))
          case Err(msg) -> Err(str_cat("error: ", msg))
        end
    end
  end
end

# ---- effectful driver ----

fn emit(text: String) -> Unit ! [io]
  if eq(text, "") then Unit else println(text) end
end

fn handle_line(line: String) -> Int ! [io]
  match render(line)
    case Ok(text) ->
      emit(text)
      0
    case Err(text) ->
      println(text)
      1
  end
end

fn count_failures(lines: List[String], acc: Int) -> Int ! [io]
  match lines
    case [] -> acc
    case [first, ..rest] -> count_failures(rest, add(acc, handle_line(first)))
  end
end

fn main() -> Unit ! [io]
  let failures = count_failures(str_split(read_all(), "\n"), 0)
  exit(if eq(failures, 0) then 0 else 1 end)
end

# ---- unit tests ----

test "precedence and associativity"
  expect_eq(render("1 + 2 * 3"), Ok("7"))
  expect_eq(render("(1+2)*3"), Ok("9"))
  expect_eq(render("8-3-2"), Ok("3"))
  expect_eq(render("2*3%4"), Ok("2"))
  expect_eq(render("-(4 - 10) % 4"), Ok("2"))
end

test "division and remainder truncate toward zero"
  expect_eq(render("-7/2"), Ok("-3"))
  expect_eq(render("-7%2"), Ok("-1"))
  expect_eq(render("7%-2"), Ok("1"))
  expect_eq(render("   "), Ok(""))
end

test "error reporting"
  expect_eq(render("2 *"), Err("error: syntax at 4"))
  expect_eq(render("(1"), Err("error: syntax at 3"))
  expect_eq(render("1 2"), Err("error: syntax at 3"))
  expect_eq(render("7 / (3 - 3)"), Err("error: division by zero"))
  expect_eq(render("1 / 0 +"), Err("error: syntax at 8"))
end
