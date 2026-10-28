# csvsum: group and sum a CSV file read from standard input

type Fld = { val: String, pos: Int, stop: Bool } end
type Rec = { fields: List[String], next: Int } end
type Pair = { key: String, amt: Int } end

# ---------- CSV parsing ----------

fn scan_unq(s: String, n: Int, i: Int) -> Result[Int, Unit]
  if ge(i, n) then
    Ok(i)
  else
    let c = str_byte(s, i)
    if or(eq(c, 44), eq(c, 10)) then
      Ok(i)
    elif eq(c, 34) then
      Err(Unit)
    else
      scan_unq(s, n, add(i, 1))
    end
  end
end

fn after_field(s: String, n: Int, v: String, e: Int) -> Result[Fld, Unit]
  if ge(e, n) then
    Ok(Fld { val: v, pos: n, stop: true })
  else
    let c = str_byte(s, e)
    if eq(c, 44) then
      Ok(Fld { val: v, pos: add(e, 1), stop: false })
    elif eq(c, 10) then
      Ok(Fld { val: v, pos: add(e, 1), stop: true })
    else
      Err(Unit)
    end
  end
end

fn scan_q(s: String, n: Int, start: Int, j: Int, parts: List[String]) -> Result[Fld, Unit]
  if ge(j, n) then
    Err(Unit)
  elif eq(str_byte(s, j), 34) then
    let k = add(j, 1)
    let doubled = if lt(k, n) then eq(str_byte(s, k), 34) else false end
    if doubled then
      scan_q(s, n, add(j, 2), add(j, 2), list_push(parts, str_slice(s, start, k)))
    else
      let v = str_join(list_push(parts, str_slice(s, start, j)), "")
      after_field(s, n, v, k)
    end
  else
    scan_q(s, n, start, add(j, 1), parts)
  end
end

fn parse_unq(s: String, n: Int, i: Int) -> Result[Fld, Unit]
  let e = try scan_unq(s, n, i)
  after_field(s, n, str_slice(s, i, e), e)
end

fn parse_field(s: String, n: Int, i: Int) -> Result[Fld, Unit]
  if lt(i, n) then
    if eq(str_byte(s, i), 34) then
      scan_q(s, n, add(i, 1), add(i, 1), [])
    else
      parse_unq(s, n, i)
    end
  else
    parse_unq(s, n, i)
  end
end

fn parse_record(s: String, n: Int, i: Int, acc: List[String]) -> Result[Rec, Unit]
  let f = try parse_field(s, n, i)
  let acc2 = list_cons(f.val, acc)
  if f.stop then
    Ok(Rec { fields: list_reverse(acc2), next: f.pos })
  else
    parse_record(s, n, f.pos, acc2)
  end
end

# ---------- integers ----------

fn digits(s: String, i: Int, n: Int, acc: Int) -> Option[Int]
  if ge(i, n) then
    Some(acc)
  else
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then
      digits(s, add(i, 1), n, add(mul(acc, 10), sub(c, 48)))
    else
      None
    end
  end
end

fn parse_amount(s: String) -> Option[Int]
  let n = str_len(s)
  if eq(n, 0) then
    None
  elif eq(str_byte(s, 0), 45) then
    if eq(n, 1) then
      None
    else
      match digits(s, 1, n, 0)
        case Some(v) -> Some(sub(0, v))
        case None -> None
      end
    end
  else
    digits(s, 0, n, 0)
  end
end

# ---------- grouping and output ----------

fn index_of(l: List[String], x: String, i: Int) -> Option[Int]
  match l
    case [] -> None
    case [h, ..rest] ->
      if eq(h, x) then Some(i) else index_of(rest, x, add(i, 1)) end
  end
end

fn quote_field(g: String) -> String
  let needs = or(is_some(str_find(g, ",")), is_some(str_find(g, "\"")), is_some(str_find(g, "\n")))
  if needs then
    str_cat("\"", str_join(str_split(g, "\""), "\"\""), "\"")
  else
    g
  end
end

fn fmt_line(key: String, sum: Int) -> String
  str_cat(quote_field(key), ",", show(sum))
end

fn emit(ps: List[Pair], key: String, sum: Int, out: List[String]) -> List[String]
  match ps
    case [] -> list_cons(fmt_line(key, sum), out)
    case [p, ..rest] ->
      if eq(p.key, key) then
        emit(rest, key, add(sum, p.amt), out)
      else
        emit(rest, p.key, p.amt, list_cons(fmt_line(key, sum), out))
      end
  end
end

fn render(ps: List[Pair]) -> String
  let sorted = list_sort_by(ps, fn(a, b) lt(a.key, b.key) end)
  match sorted
    case [] -> ""
    case [p, ..rest] ->
      let lines = list_reverse(emit(rest, p.key, p.amt, []))
      str_cat(str_join(lines, "\n"), "\n")
  end
end

fn collect(s: String, n: Int, i: Int, recno: Int, gi: Int, si: Int, ncols: Int, acc: List[Pair]) -> Result[List[Pair], Int]
  if ge(i, n) then
    Ok(acc)
  else
    match parse_record(s, n, i, [])
      case Err(_) -> Err(recno)
      case Ok(r) ->
        if ne(list_len(r.fields), ncols) then
          Err(recno)
        else
          let g = unwrap_or(list_get(r.fields, gi), "")
          match parse_amount(unwrap_or(list_get(r.fields, si), ""))
            case None -> Err(recno)
            case Some(v) ->
              collect(s, n, r.next, add(recno, 1), gi, si, ncols, list_cons(Pair { key: g, amt: v }, acc))
          end
        end
    end
  end
end

fn process(s: String, gname: String, sname: String) -> Result[String, String]
  let n = str_len(s)
  if eq(n, 0) then
    Err("error: no header")
  else
    match parse_record(s, n, 0, [])
      case Err(_) -> Err("error: record 1")
      case Ok(h) ->
        match index_of(h.fields, gname, 0)
          case None -> Err(str_cat("error: no column ", gname))
          case Some(gi) ->
            match index_of(h.fields, sname, 0)
              case None -> Err(str_cat("error: no column ", sname))
              case Some(si) ->
                match collect(s, n, h.next, 2, gi, si, list_len(h.fields), [])
                  case Err(k) -> Err(str_cat("error: record ", show(k)))
                  case Ok(ps) -> Ok(render(ps))
                end
            end
        end
    end
  end
end

fn run(gname: String, sname: String, input: String) -> Unit ! [io]
  match process(input, gname, sname)
    case Ok(out) -> print(out)
    case Err(m) ->
      println(m)
      exit(1)
  end
end

fn main() -> Unit ! [io]
  let a = args()
  if ne(list_len(a), 2) then
    println("usage: csvsum <group-column> <sum-column>")
    exit(2)
  else
    run(unwrap_or(list_get(a, 0), ""), unwrap_or(list_get(a, 1), ""), read_all())
  end
end

# ---------- tests ----------

test "parse_amount"
  expect_eq(parse_amount("10"), Some(10))
  expect_eq(parse_amount("-3"), Some(-3))
  expect_eq(parse_amount("-"), None)
  expect_eq(parse_amount(""), None)
  expect_eq(parse_amount("+4"), None)
  expect_eq(parse_amount("1a"), None)
end

test "example from spec"
  let input = "city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n"
  expect_eq(process(input, "city", "amount"), Ok("Oslo,7\n\"Rome, IT\",5\n"))
end

test "quote_field"
  expect_eq(quote_field("plain"), "plain")
  expect_eq(quote_field("a\"b"), "\"a\"\"b\"")
  expect_eq(quote_field("x\ny"), "\"x\ny\"")
end

test "errors"
  expect_eq(process("", "a", "b"), Err("error: no header"))
  expect_eq(process("a,b\n", "c", "b"), Err("error: no column c"))
  expect_eq(process("a,b\nx,1\ny\n", "a", "b"), Err("error: record 3"))
  expect_eq(process("a,b\nx,1\n\"y,2\n", "a", "b"), Err("error: record 3"))
  expect_eq(process("a,b\nx,1.5\n", "a", "b"), Err("error: record 2"))
  expect_eq(process("a,b\n\"x\"y,1\n", "a", "b"), Err("error: record 2"))
  expect_eq(process("a,b\n", "a", "b"), Ok(""))
end

test "multiline quoted group"
  expect_eq(process("g,v\n\"l1\nl2\",3\n\"l1\nl2\",4", "g", "v"), Ok("\"l1\nl2\",7\n"))
end
