# csvsum: group and sum a CSV read from standard input.
# Usage: csvsum <group-column> <sum-column>

type Entry = { key: String, total: Int } end

type Parsed = Got(List[String], Int) | Malformed end

type FieldResult = Field(String, Int, Int) | FieldBad end

# ---------- entry point ----------

fn main() -> Unit ! [io]
  match args()
    case [group, sumc] -> run_csv(group, sumc, read_all())
    case _ -> usage()
  end
end

fn usage() -> Unit ! [io]
  println("usage: csvsum <group-column> <sum-column>")
  exit(2)
end

fn die(msg: String, code: Int) -> Unit ! [io]
  println(msg)
  exit(code)
end

fn run_csv(group: String, sumc: String, text: String) -> Unit ! [io]
  let n = str_len(text)
  if eq(n, 0) then die("error: no header", 1)
  else header_step(group, sumc, text, n) end
end

fn header_step(group: String, sumc: String, text: String, n: Int) -> Unit ! [io]
  match parse_row(text, n, 0)
    case Malformed -> die("error: record 1", 1)
    case Got(names, after_header) -> columns_step(names, group, sumc, text, n, after_header)
  end
end

fn columns_step(names: List[String], group: String, sumc: String, text: String, n: Int, after_header: Int) -> Unit ! [io]
  let gi = find_from(names, group, 0)
  let si = find_from(names, sumc, 0)
  if lt(gi, 0) then die(str_cat("error: no column ", group), 1)
  elif lt(si, 0) then die(str_cat("error: no column ", sumc), 1)
  else
    match collect(text, n, after_header, list_len(names), gi, si, 2, [])
      case Err(bad) -> die(str_cat("error: record ", show(bad)), 1)
      case Ok(entries) -> emit(entries)
    end
  end
end

# ---------- header lookup ----------

fn find_from(names: List[String], x: String, k: Int) -> Int
  match names
    case [] -> -1
    case [h, ..rest] -> if eq(h, x) then k else find_from(rest, x, add(k, 1)) end
  end
end

fn nth(l: List[String], k: Int) -> String
  match l
    case [] -> ""
    case [h, ..rest] -> if eq(k, 0) then h else nth(rest, sub(k, 1)) end
  end
end

# ---------- CSV parsing ----------

# Parse one record starting at byte index start.
fn parse_row(s: String, n: Int, start: Int) -> Parsed
  parse_fields(s, n, start, [])
end

fn parse_fields(s: String, n: Int, i: Int, acc: List[String]) -> Parsed
  match parse_field(s, n, i)
    case FieldBad -> Malformed
    case Field(v, p, t) ->
      if eq(t, 1) then parse_fields(s, n, p, list_cons(v, acc))
      else Got(list_reverse(list_cons(v, acc)), p) end
  end
end

# t: 0 = end of input, 1 = comma (p is after it), 2 = newline (p is after it)
fn parse_field(s: String, n: Int, i: Int) -> FieldResult
  if ge(i, n) then Field("", n, 0)
  elif eq(str_byte(s, i), 34) then parse_quoted(s, n, add(i, 1))
  else parse_plain(s, n, i) end
end

fn plain_scan(s: String, n: Int, k: Int) -> Int
  if ge(k, n) then n
  else
    let c = str_byte(s, k)
    if or(eq(c, 44), eq(c, 10)) then k
    elif eq(c, 34) then -1
    else plain_scan(s, n, add(k, 1)) end
  end
end

fn parse_plain(s: String, n: Int, i: Int) -> FieldResult
  let e = plain_scan(s, n, i)
  if lt(e, 0) then FieldBad
  elif ge(e, n) then Field(str_slice(s, i, n), n, 0)
  elif eq(str_byte(s, e), 44) then Field(str_slice(s, i, e), add(e, 1), 1)
  else Field(str_slice(s, i, e), add(e, 1), 2) end
end

# Index of the closing quote for a quoted field whose content starts at j, or -1.
fn quote_end(s: String, n: Int, j: Int) -> Int
  if ge(j, n) then -1
  elif eq(str_byte(s, j), 34) then
    if lt(add(j, 1), n) then
      if eq(str_byte(s, add(j, 1)), 34) then quote_end(s, n, add(j, 2))
      else j end
    else j end
  else quote_end(s, n, add(j, 1)) end
end

fn parse_quoted(s: String, n: Int, j: Int) -> FieldResult
  let c = quote_end(s, n, j)
  if lt(c, 0) then FieldBad
  else
    let v = str_join(str_split(str_slice(s, j, c), "\"\""), "\"")
    let after = add(c, 1)
    if ge(after, n) then Field(v, n, 0)
    elif eq(str_byte(s, after), 44) then Field(v, add(after, 1), 1)
    elif eq(str_byte(s, after), 10) then Field(v, add(after, 1), 2)
    else FieldBad end
  end
end

# ---------- integer check ----------

fn digits_ok(s: String, k: Int, n: Int) -> Bool
  if ge(k, n) then true
  else
    let c = str_byte(s, k)
    if and(ge(c, 48), le(c, 57)) then digits_ok(s, add(k, 1), n) else false end
  end
end

fn is_int_text(s: String) -> Bool
  let n = str_len(s)
  if eq(n, 0) then false
  elif eq(str_byte(s, 0), 45) then and(gt(n, 1), digits_ok(s, 1, n))
  else digits_ok(s, 0, n) end
end

# ---------- records to entries ----------

fn entry_of(fields: List[String], gi: Int, si: Int) -> Option[Entry]
  let sv = nth(fields, si)
  if is_int_text(sv) then
    match str_to_int(sv)
      case Some(v) -> Some(Entry { key: nth(fields, gi), total: v })
      case None -> None
    end
  else None end
end

fn collect(text: String, n: Int, pos: Int, width: Int, gi: Int, si: Int, recno: Int, acc: List[Entry]) -> Result[List[Entry], Int]
  if ge(pos, n) then Ok(list_reverse(acc))
  else
    match parse_row(text, n, pos)
      case Malformed -> Err(recno)
      case Got(fields, after) ->
        if eq(list_len(fields), width) then
          match entry_of(fields, gi, si)
            case Some(e) -> collect(text, n, after, width, gi, si, add(recno, 1), list_cons(e, acc))
            case None -> Err(recno)
          end
        else Err(recno) end
    end
  end
end

# ---------- grouping and output ----------

# Entries are sorted by key; adjacent equal keys are summed.
fn combine(es: List[Entry], out: List[Entry]) -> List[Entry]
  match es
    case [] -> list_reverse(out)
    case [e, ..rest] ->
      match out
        case [top, ..others] ->
          if eq(top.key, e.key) then combine(rest, list_cons({ top with total: add(top.total, e.total) }, others))
          else combine(rest, list_cons(e, out)) end
        case [] -> combine(rest, list_cons(e, out))
      end
  end
end

fn needs_quote(s: String) -> Bool
  or(is_some(str_find(s, ",")), is_some(str_find(s, "\"")), is_some(str_find(s, "\n")))
end

fn quote_field(s: String) -> String
  if needs_quote(s) then str_cat("\"", str_join(str_split(s, "\""), "\"\""), "\"")
  else s end
end

fn print_all(es: List[Entry]) -> Unit ! [io]
  match es
    case [] -> Unit
    case [e, ..rest] ->
      println(str_cat(quote_field(e.key), ",", show(e.total)))
      print_all(rest)
  end
end

fn emit(entries: List[Entry]) -> Unit ! [io]
  print_all(combine(list_sort_by(entries, fn(a, b) lt(a.key, b.key) end), []))
end

# ---------- unit tests ----------

test "plain record"
  expect_eq(parse_row("a,b\n", 4, 0), Got(["a", "b"], 4))
end

test "quoted field with comma and doubled quotes"
  expect_eq(parse_row("\"x,\"\"y\"\"\",2", 11, 0), Got(["x,\"y\"", "2"], 11))
end

test "malformed quoting"
  expect_eq(parse_row("\"abc", 4, 0), Malformed)
  expect_eq(parse_row("a\"b\n", 4, 0), Malformed)
end

test "integer text check"
  expect_eq(is_int_text("-12"), true)
  expect_eq(is_int_text("1-"), false)
  expect_eq(is_int_text("-"), false)
end
