# csvsum: group and sum a CSV file read from standard input

type FRes = { text: String, next: Int, more: Bool } end
type Rec = { fields: List[String], stop: Int } end
type Pair = { g: String, v: Int } end
type Acc = { has: Bool, cur: String, total: Int, out: List[String] } end

fn scan_unq(s: String, n: Int, i: Int) -> Int
  if ge(i, n) then n
  else
    let c = str_byte(s, i)
    if or(eq(c, 44), eq(c, 10), eq(c, 34)) then i else scan_unq(s, n, add(i, 1)) end
  end
end

fn scan_q(s: String, n: Int, i: Int) -> Int
  if ge(i, n) then n
  elif eq(str_byte(s, i), 34) then i
  else scan_q(s, n, add(i, 1))
  end
end

fn finish(s: String, n: Int, e: Int, t: String) -> Option[FRes]
  if ge(e, n) then Some(FRes { text: t, next: n, more: false })
  else
    let c = str_byte(s, e)
    if eq(c, 44) then Some(FRes { text: t, next: add(e, 1), more: true })
    elif eq(c, 10) then Some(FRes { text: t, next: add(e, 1), more: false })
    else None
    end
  end
end

fn parse_quoted(s: String, n: Int, i: Int, parts: List[String]) -> Option[FRes]
  let q = scan_q(s, n, i)
  if ge(q, n) then None
  elif and(lt(add(q, 1), n), eq(str_byte(s, add(q, 1)), 34)) then
    parse_quoted(s, n, add(q, 2), list_cons(str_slice(s, i, add(q, 1)), parts))
  else
    finish(s, n, add(q, 1), str_join(list_reverse(list_cons(str_slice(s, i, q), parts)), ""))
  end
end

fn parse_field(s: String, n: Int, pos: Int) -> Option[FRes]
  if ge(pos, n) then Some(FRes { text: "", next: n, more: false })
  elif eq(str_byte(s, pos), 34) then parse_quoted(s, n, add(pos, 1), [])
  else
    let e = scan_unq(s, n, pos)
    finish(s, n, e, str_slice(s, pos, e))
  end
end

fn parse_record(s: String, n: Int, pos: Int, acc: List[String]) -> Option[Rec]
  match parse_field(s, n, pos)
    case None -> None
    case Some(f) ->
      let acc2 = list_cons(f.text, acc)
      if f.more then parse_record(s, n, f.next, acc2)
      else Some(Rec { fields: list_reverse(acc2), stop: f.next })
      end
  end
end

fn digits(s: String, i: Int, n: Int, acc: Int) -> Option[Int]
  if ge(i, n) then Some(acc)
  else
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then digits(s, add(i, 1), n, add(mul(acc, 10), sub(c, 48)))
    else None
    end
  end
end

fn parse_num(s: String) -> Option[Int]
  let n = str_len(s)
  if eq(n, 0) then None
  elif eq(str_byte(s, 0), 45) then
    if eq(n, 1) then None
    else
      match digits(s, 1, n, 0)
        case Some(v) -> Some(sub(0, v))
        case None -> None
      end
    end
  else digits(s, 0, n, 0)
  end
end

fn index_of(l: List[String], name: String, i: Int) -> Option[Int]
  match list_get(l, i)
    case None -> None
    case Some(x) -> if eq(x, name) then Some(i) else index_of(l, name, add(i, 1)) end
  end
end

fn record_pair(fs: List[String], hc: Int, gi: Int, si: Int) -> Option[Pair]
  if ne(list_len(fs), hc) then None
  else
    let g = try list_get(fs, gi) else None
    let v = try list_get(fs, si) else None
    let x = try parse_num(v) else None
    Some(Pair { g: g, v: x })
  end
end

fn process(s: String, n: Int, pos: Int, rec: Int, hc: Int, gi: Int, si: Int, acc: List[Pair]) -> Result[List[Pair], String]
  if ge(pos, n) then Ok(acc)
  else
    match parse_record(s, n, pos, [])
      case None -> Err(str_cat("error: record ", show(rec)))
      case Some(r) ->
        match record_pair(r.fields, hc, gi, si)
          case None -> Err(str_cat("error: record ", show(rec)))
          case Some(p) -> process(s, n, r.stop, add(rec, 1), hc, gi, si, list_cons(p, acc))
        end
    end
  end
end

fn quote_group(g: String) -> String
  if or(is_some(str_find(g, ",")), is_some(str_find(g, "\"")), is_some(str_find(g, "\n"))) then
    str_cat("\"", str_join(str_split(g, "\""), "\"\""), "\"")
  else g
  end
end

fn line(g: String, t: Int) -> String
  str_cat(quote_group(g), ",", show(t))
end

fn render(pairs: List[Pair]) -> String
  let sorted = list_sort_by(pairs, fn(a, b) lt(a.g, b.g) end)
  let init = Acc { has: false, cur: "", total: 0, out: [] }
  let st = list_fold(sorted, init, fn(st, p)
    if and(st.has, eq(st.cur, p.g)) then { st with total: add(st.total, p.v) }
    else
      let flushed = if st.has then list_cons(line(st.cur, st.total), st.out) else st.out end
      Acc { has: true, cur: p.g, total: p.v, out: flushed }
    end
  end)
  let lines = if st.has then list_cons(line(st.cur, st.total), st.out) else st.out end
  if eq(list_len(lines), 0) then ""
  else str_cat(str_join(list_reverse(lines), "\n"), "\n")
  end
end

fn header(s: String, n: Int) -> Result[Rec, String]
  match parse_record(s, n, 0, [])
    case None -> Err("error: record 1")
    case Some(r) -> Ok(r)
  end
end

fn compute(gc: String, sc: String, s: String) -> Result[String, String]
  let n = str_len(s)
  if eq(n, 0) then Err("error: no header")
  else
    let h = try header(s, n)
    let gi = try index_of(h.fields, gc, 0) else Err(str_cat("error: no column ", gc))
    let si = try index_of(h.fields, sc, 0) else Err(str_cat("error: no column ", sc))
    let pairs = try process(s, n, h.stop, 2, list_len(h.fields), gi, si, [])
    Ok(render(pairs))
  end
end

fn run(gc: String, sc: String, s: String) -> Unit ! [io]
  match compute(gc, sc, s)
    case Ok(out) -> print(out)
    case Err(msg) ->
      println(msg)
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

test "parse_num"
  expect_eq(parse_num("42"), Some(42))
  expect_eq(parse_num("-3"), Some(-3))
  expect_eq(parse_num(""), None)
  expect_eq(parse_num("-"), None)
  expect_eq(parse_num("1a"), None)
  expect_eq(parse_num("+1"), None)
end

test "quote_group"
  expect_eq(quote_group("Oslo"), "Oslo")
  expect_eq(quote_group("Rome, IT"), "\"Rome, IT\"")
  expect_eq(quote_group("a\"b"), "\"a\"\"b\"")
end

test "compute example"
  let input = "city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n"
  expect_eq(compute("city", "amount", input), Ok("Oslo,7\n\"Rome, IT\",5\n"))
end

test "compute errors"
  expect_eq(compute("city", "amount", ""), Err("error: no header"))
  expect_eq(compute("x", "amount", "city,amount\n"), Err("error: no column x"))
  expect_eq(compute("city", "amount", "city,amount\nA,1\nB,x\n"), Err("error: record 3"))
  expect_eq(compute("city", "amount", "city,amount\n\"A,1\n"), Err("error: record 2"))
  expect_eq(compute("city", "amount", "city,amount\n"), Ok(""))
end
