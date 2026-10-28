# csvsum: group and sum a CSV file read from standard input.
# Usage: csvsum <group-column> <sum-column>

type Cell = { ctext: String, stop: Int } end
type Rec = { fields: List[String], after: Int } end
type Entry = { key: String, num: Int } end

fn main() -> Unit ! [io]
  match args()
    case [groupcol, sumcol] -> finish(process(read_all(), groupcol, sumcol))
    case _ -> usage()
  end
end

fn usage() -> Unit ! [io]
  println("usage: csvsum <group-column> <sum-column>")
  exit(2)
end

fn finish(r: Result[String, String]) -> Unit ! [io]
  match r
    case Ok(out) -> print(out)
    case Err(msg) -> fail(msg)
  end
end

fn fail(msg: String) -> Unit ! [io]
  println(msg)
  exit(1)
end

# Pure core: whole input in, output text or error message out.
fn process(input: String, groupcol: String, sumcol: String) -> Result[String, String]
  let n = str_len(input)
  if eq(n, 0) then Err("error: no header")
  else header_result(input, n, groupcol, sumcol)
  end
end

fn header_result(input: String, n: Int, groupcol: String, sumcol: String) -> Result[String, String]
  match parse_rec(input, n, 0, [])
    case None -> Err("error: record 1")
    case Some(head) -> columns_result(input, n, head, groupcol, sumcol)
  end
end

fn columns_result(input: String, n: Int, head: Rec, groupcol: String, sumcol: String) -> Result[String, String]
  if not(list_contains(head.fields, groupcol)) then Err(str_cat("error: no column ", groupcol))
  elif not(list_contains(head.fields, sumcol)) then Err(str_cat("error: no column ", sumcol))
  else collect(input, n, head.after, unwrap_or(index_of(head.fields, groupcol, 0), 0), unwrap_or(index_of(head.fields, sumcol, 0), 0), list_len(head.fields), 2, [])
  end
end

fn index_of(names: List[String], name: String, i: Int) -> Option[Int]
  match names
    case [] -> None
    case [first, ..rest] -> if eq(first, name) then Some(i) else index_of(rest, name, add(i, 1)) end
  end
end

fn collect(input: String, n: Int, pos: Int, g: Int, k: Int, width: Int, recno: Int, acc: List[Entry]) -> Result[String, String]
  if ge(pos, n) then Ok(render_all(acc))
  else collect_one(input, n, pos, g, k, width, recno, acc)
  end
end

fn collect_one(input: String, n: Int, pos: Int, g: Int, k: Int, width: Int, recno: Int, acc: List[Entry]) -> Result[String, String]
  match parse_rec(input, n, pos, [])
    case None -> Err(record_error(recno))
    case Some(r) -> take_row(input, n, r, g, k, width, recno, acc)
  end
end

fn take_row(input: String, n: Int, r: Rec, g: Int, k: Int, width: Int, recno: Int, acc: List[Entry]) -> Result[String, String]
  let key = unwrap_or(list_get(r.fields, g), "")
  let num_text = unwrap_or(list_get(r.fields, k), "")
  if ne(list_len(r.fields), width) then Err(record_error(recno))
  elif valid_int(num_text) then collect(input, n, r.after, g, k, width, add(recno, 1), list_cons(Entry { key: key, num: int_value(num_text) }, acc))
  else Err(record_error(recno))
  end
end

fn record_error(recno: Int) -> String
  str_cat("error: record ", show(recno))
end

# ---- CSV parsing ----

# Parses one record starting at pos. None means invalid quoting.
fn parse_rec(s: String, n: Int, pos: Int, acc: List[String]) -> Option[Rec]
  match parse_cell(s, n, pos)
    case None -> None
    case Some(c) -> rec_after(s, n, c, acc)
  end
end

fn rec_after(s: String, n: Int, c: Cell, acc: List[String]) -> Option[Rec]
  let fields = list_push(acc, c.ctext)
  if ge(c.stop, n) then Some(Rec { fields: fields, after: n })
  elif eq(str_byte(s, c.stop), 44) then parse_rec(s, n, add(c.stop, 1), fields)
  else Some(Rec { fields: fields, after: add(c.stop, 1) })
  end
end

fn parse_cell(s: String, n: Int, pos: Int) -> Option[Cell]
  if ge(pos, n) then Some(Cell { ctext: "", stop: n })
  elif eq(str_byte(s, pos), 34) then scan_quoted(s, n, add(pos, 1), add(pos, 1), "")
  else scan_plain(s, n, pos, pos)
  end
end

fn scan_plain(s: String, n: Int, j: Int, start: Int) -> Option[Cell]
  if ge(j, n) then Some(Cell { ctext: str_slice(s, start, n), stop: n })
  elif or(eq(str_byte(s, j), 44), eq(str_byte(s, j), 10)) then Some(Cell { ctext: str_slice(s, start, j), stop: j })
  elif eq(str_byte(s, j), 34) then None
  else scan_plain(s, n, add(j, 1), start)
  end
end

# j scans for a quote; start is the beginning of the pending chunk; acc holds finished chunks.
fn scan_quoted(s: String, n: Int, j: Int, start: Int, acc: String) -> Option[Cell]
  if ge(j, n) then None
  elif ne(str_byte(s, j), 34) then scan_quoted(s, n, add(j, 1), start, acc)
  elif is_doubled(s, n, add(j, 1)) then scan_quoted(s, n, add(j, 2), add(j, 2), str_cat(acc, str_slice(s, start, add(j, 1))))
  else after_quote(s, n, add(j, 1), str_cat(acc, str_slice(s, start, j)))
  end
end

fn is_doubled(s: String, n: Int, k: Int) -> Bool
  if lt(k, n) then eq(str_byte(s, k), 34) else false end
end

fn after_quote(s: String, n: Int, k: Int, text: String) -> Option[Cell]
  if ge(k, n) then Some(Cell { ctext: text, stop: n })
  elif or(eq(str_byte(s, k), 44), eq(str_byte(s, k), 10)) then Some(Cell { ctext: text, stop: k })
  else None
  end
end

# ---- integers ----

fn all_digits(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif and(ge(str_byte(s, i), 48), le(str_byte(s, i), 57)) then all_digits(s, add(i, 1), n)
  else false
  end
end

fn digits_start(s: String) -> Int
  if str_starts(s, "-") then 1 else 0 end
end

fn valid_int(s: String) -> Bool
  let start_at = digits_start(s)
  and(lt(start_at, str_len(s)), all_digits(s, start_at, str_len(s)))
end

fn digits_value(s: String, i: Int, n: Int, acc: Int) -> Int
  if ge(i, n) then acc
  else digits_value(s, add(i, 1), n, add(mul(acc, 10), sub(str_byte(s, i), 48)))
  end
end

fn int_value(s: String) -> Int
  let magnitude = digits_value(s, digits_start(s), str_len(s), 0)
  if str_starts(s, "-") then sub(0, magnitude) else magnitude end
end

# ---- grouping and output ----

fn add_entry(out: List[Entry], e: Entry) -> List[Entry]
  match out
    case [] -> list_cons(e, out)
    case [top, ..others] -> if eq(top.key, e.key) then list_cons(Entry { key: e.key, num: add(top.num, e.num) }, others) else list_cons(e, out) end
  end
end

# es must be sorted by key; out is built reversed.
fn merge_groups(es: List[Entry], out: List[Entry]) -> List[Entry]
  match es
    case [] -> out
    case [e, ..rest] -> merge_groups(rest, add_entry(out, e))
  end
end

fn render_all(acc: List[Entry]) -> String
  let sorted = list_sort_by(acc, fn(a, b) lt(a.key, b.key) end)
  let merged = list_reverse(merge_groups(sorted, []))
  str_join(list_map(merged, fn(e) str_cat(quote_key(e.key), ",", show(e.num), "\n") end), "")
end

fn needs_quote(s: String) -> Bool
  or(is_some(str_find(s, ",")), or(is_some(str_find(s, "\"")), is_some(str_find(s, "\n"))))
end

fn quote_key(s: String) -> String
  if needs_quote(s) then str_cat("\"", str_join(str_split(s, "\""), "\"\""), "\"")
  else s
  end
end

# ---- tests ----

test "spec example"
  expect_eq(process("city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n", "city", "amount"), Ok("Oslo,7\n\"Rome, IT\",5\n"))
end

test "empty input has no header"
  expect_eq(process("", "a", "b"), Err("error: no header"))
end

test "bad record reports its number"
  expect_eq(process("a,b\n1,2\n3\n", "a", "b"), Err("error: record 3"))
end

test "missing column is reported"
  expect_eq(process("a,b\n", "x", "b"), Err("error: no column x"))
end
