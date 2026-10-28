# csvsum: group and sum a CSV file read from standard input

type Rec = { fields: List[String], next: Int } end
type Pair = { g: String, v: Int } end
type Acc = { done: List[Pair], cur: String, total: Int, has: Bool } end

fn finish(acc: List[String], field: String, next: Int) -> Option[Rec]
  Some(Rec { fields: list_reverse(list_cons(field, acc)), next: next })
end

# parse one record starting at the beginning of a field at position i
fn parse_record(s: String, len: Int, i: Int, acc: List[String]) -> Option[Rec]
  if ge(i, len) then
    finish(acc, "", i)
  elif eq(str_byte(s, i), 34) then
    parse_quoted(s, len, add(i, 1), add(i, 1), [], acc)
  else
    parse_unquoted(s, len, i, i, acc)
  end
end

fn parse_unquoted(s: String, len: Int, start: Int, j: Int, acc: List[String]) -> Option[Rec]
  if ge(j, len) then
    finish(acc, str_slice(s, start, j), j)
  else
    let c = str_byte(s, j)
    if eq(c, 44) then
      parse_record(s, len, add(j, 1), list_cons(str_slice(s, start, j), acc))
    elif eq(c, 10) then
      finish(acc, str_slice(s, start, j), add(j, 1))
    elif eq(c, 34) then
      None
    else
      parse_unquoted(s, len, start, add(j, 1), acc)
    end
  end
end

fn parse_quoted(s: String, len: Int, start: Int, j: Int, parts: List[String], acc: List[String]) -> Option[Rec]
  if ge(j, len) then
    None
  elif eq(str_byte(s, j), 34) then
    let k = add(j, 1)
    if and(lt(k, len), eq(str_byte(s, k), 34)) then
      parse_quoted(s, len, add(k, 1), add(k, 1), list_cons(str_slice(s, start, k), parts), acc)
    else
      let field = str_join(list_reverse(list_cons(str_slice(s, start, j), parts)), "")
      if ge(k, len) then
        finish(acc, field, k)
      elif eq(str_byte(s, k), 44) then
        parse_record(s, len, add(k, 1), list_cons(field, acc))
      elif eq(str_byte(s, k), 10) then
        finish(acc, field, add(k, 1))
      else
        None
      end
    end
  else
    parse_quoted(s, len, start, add(j, 1), parts, acc)
  end
end

fn all_digits(s: String, i: Int, len: Int) -> Bool
  if ge(i, len) then
    true
  else
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then all_digits(s, add(i, 1), len) else false end
  end
end

fn is_int(s: String) -> Bool
  let len = str_len(s)
  if eq(len, 0) then
    false
  elif eq(str_byte(s, 0), 45) then
    and(gt(len, 1), all_digits(s, 1, len))
  else
    all_digits(s, 0, len)
  end
end

fn find_index(l: List[String], name: String, i: Int) -> Option[Int]
  match list_get(l, i)
    case None -> None
    case Some(x) -> if eq(x, name) then Some(i) else find_index(l, name, add(i, 1)) end
  end
end

fn bad(n: Int) -> String
  str_cat("error: record ", show(n))
end

fn process(s: String, len: Int, pos: Int, n: Int, gi: Int, si: Int, ncols: Int, acc: List[Pair]) -> Result[List[Pair], String]
  if ge(pos, len) then
    Ok(acc)
  else
    let r = try parse_record(s, len, pos, []) else Err(bad(n))
    if ne(list_len(r.fields), ncols) then
      Err(bad(n))
    else
      let gv = try list_get(r.fields, gi) else Err(bad(n))
      let sv = try list_get(r.fields, si) else Err(bad(n))
      if is_int(sv) then
        let v = try str_to_int(sv) else Err(bad(n))
        process(s, len, r.next, add(n, 1), gi, si, ncols, list_cons(Pair { g: gv, v: v }, acc))
      else
        Err(bad(n))
      end
    end
  end
end

fn step(acc: Acc, p: Pair) -> Acc
  if and(acc.has, eq(acc.cur, p.g)) then
    { acc with total: add(acc.total, p.v) }
  elif acc.has then
    Acc { done: list_cons(Pair { g: acc.cur, v: acc.total }, acc.done), cur: p.g, total: p.v, has: true }
  else
    { acc with cur: p.g, total: p.v, has: true }
  end
end

fn sum_groups(ps: List[Pair]) -> List[Pair]
  let sorted = list_sort_by(ps, fn(x, y) lt(x.g, y.g) end)
  let start = Acc { done: [], cur: "", total: 0, has: false }
  let fin = list_fold(sorted, start, fn(a, p) step(a, p) end)
  if fin.has then
    list_reverse(list_cons(Pair { g: fin.cur, v: fin.total }, fin.done))
  else
    list_reverse(fin.done)
  end
end

fn quote_field(g: String) -> String
  if or(is_some(str_find(g, ",")), is_some(str_find(g, "\"")), is_some(str_find(g, "\n"))) then
    str_cat("\"", str_join(str_split(g, "\""), "\"\""), "\"")
  else
    g
  end
end

fn format_line(p: Pair) -> String
  str_cat(quote_field(p.g), ",", show(p.v), "\n")
end

fn run(a: List[String], s: String) -> Result[String, String]
  let gname = try list_get(a, 0) else Err("usage: csvsum <group-column> <sum-column>")
  let sname = try list_get(a, 1) else Err("usage: csvsum <group-column> <sum-column>")
  let len = str_len(s)
  if eq(len, 0) then
    Err("error: no header")
  else
    let h = try parse_record(s, len, 0, []) else Err("error: record 1")
    let gi = try find_index(h.fields, gname, 0) else Err(str_cat("error: no column ", gname))
    let si = try find_index(h.fields, sname, 0) else Err(str_cat("error: no column ", sname))
    let pairs = try process(s, len, h.next, 2, gi, si, list_len(h.fields), [])
    let groups = sum_groups(pairs)
    Ok(str_join(list_map(groups, fn(p) format_line(p) end), ""))
  end
end

fn main() -> Unit ! [io]
  let a = args()
  if ne(list_len(a), 2) then
    println("usage: csvsum <group-column> <sum-column>")
    exit(2)
  else
    let input = read_all()
    match run(a, input)
      case Ok(out) -> print(out)
      case Err(msg) ->
        println(msg)
        exit(1)
    end
  end
end

test "is_int"
  expect(is_int("10"), "10")
  expect(is_int("-3"), "-3")
  expect(not(is_int("-")), "-")
  expect(not(is_int("")), "empty")
  expect(not(is_int("1a")), "1a")
  expect(not(is_int(" 1")), "space")
end

test "parse quoted record"
  let s = "\"Rome, IT\",5,\"says \"\"hi\"\"\"\nx"
  match parse_record(s, str_len(s), 0, [])
    case Some(r) ->
      expect_eq(r.fields, ["Rome, IT", "5", "says \"hi\""])
      expect_eq(r.next, sub(str_len(s), 1))
    case None -> expect(false, "should parse")
  end
end

test "unclosed quote is bad"
  let s = "a,\"bc\nd"
  expect(not(is_some(parse_record(s, str_len(s), 0, []))), "unclosed")
  let t = "a,\"b\"c\n"
  expect(not(is_some(parse_record(t, str_len(t), 0, []))), "char after quote")
end

test "quote_field"
  expect_eq(quote_field("Oslo"), "Oslo")
  expect_eq(quote_field("Rome, IT"), "\"Rome, IT\"")
  expect_eq(quote_field("a\"b"), "\"a\"\"b\"")
end

test "run example"
  let input = "city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n"
  expect_eq(run(["city", "amount"], input), Ok("Oslo,7\n\"Rome, IT\",5\n"))
  expect_eq(run(["city", "nope"], input), Err("error: no column nope"))
  expect_eq(run(["city", "amount"], "city,amount\nOslo,x\n"), Err("error: record 2"))
  expect_eq(run(["city", "amount"], ""), Err("error: no header"))
end
