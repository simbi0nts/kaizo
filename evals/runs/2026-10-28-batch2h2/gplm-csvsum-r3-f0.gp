# csvsum: group a CSV read from standard input and sum one column per group.
# Usage: csvsum <group-column> <sum-column>

type Field = { ftext: String, fstop: Int } end
type Rec = { rcols: List[String], rnext: Int } end
type Row = { rkey: String, rval: Int } end

# ---- CSV parsing ----

# Index of the first ',' or '\n' at or after j (or n).
fn plain_end(s: String, j: Int, n: Int) -> Int
  if ge(j, n) then j
  elif or(eq(str_byte(s, j), 44), eq(str_byte(s, j), 10)) then j
  else plain_end(s, add(j, 1), n)
  end
end

fn parse_plain(s: String, i: Int, n: Int) -> Result[Field, String]
  let j = plain_end(s, i, n)
  let t = str_slice(s, i, j)
  if is_some(str_find(t, "\"")) then Err("bad field")
  else Ok(Field { ftext: t, fstop: j })
  end
end

fn after_quote_ok(s: String, k: Int, n: Int) -> Bool
  if ge(k, n) then true
  elif eq(str_byte(s, k), 44) then true
  elif eq(str_byte(s, k), 10) then true
  else false
  end
end

# j is the index of the closing quote; pieces are finished segments, newest first.
fn finish_quoted(s: String, seg: Int, j: Int, n: Int, pieces: List[String]) -> Result[Field, String]
  let text = str_join(list_reverse(list_cons(str_slice(s, seg, j), pieces)), "")
  if after_quote_ok(s, add(j, 1), n) then Ok(Field { ftext: text, fstop: add(j, 1) })
  else Err("bad quote")
  end
end

# j: index inside the quoted field; seg: start of the current segment.
fn parse_quoted(s: String, j: Int, n: Int, seg: Int, pieces: List[String]) -> Result[Field, String]
  if ge(j, n) then Err("unclosed quote")
  elif eq(str_byte(s, j), 34) then
    if ge(add(j, 1), n) then finish_quoted(s, seg, j, n, pieces)
    elif eq(str_byte(s, add(j, 1)), 34) then parse_quoted(s, add(j, 2), n, add(j, 2), list_cons(str_slice(s, seg, add(j, 1)), pieces))
    else finish_quoted(s, seg, j, n, pieces)
    end
  else parse_quoted(s, add(j, 1), n, seg, pieces)
  end
end

fn parse_field(s: String, i: Int, n: Int) -> Result[Field, String]
  if ge(i, n) then Ok(Field { ftext: "", fstop: i })
  elif eq(str_byte(s, i), 34) then parse_quoted(s, add(i, 1), n, add(i, 1), [])
  else parse_plain(s, i, n)
  end
end

# Parses one record starting at i. acc holds the fields so far, newest first.
fn parse_record(s: String, i: Int, n: Int, acc: List[String]) -> Result[Rec, String]
  let f = try parse_field(s, i, n)
  let cols = list_cons(f.ftext, acc)
  if ge(f.fstop, n) then Ok(Rec { rcols: list_reverse(cols), rnext: f.fstop })
  elif eq(str_byte(s, f.fstop), 44) then parse_record(s, add(f.fstop, 1), n, cols)
  else Ok(Rec { rcols: list_reverse(cols), rnext: add(f.fstop, 1) })
  end
end

fn parse_first(s: String) -> Result[Rec, String]
  parse_record(s, 0, str_len(s), [])
end

# ---- integers ----

fn all_digits(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif and(ge(str_byte(s, i), 48), le(str_byte(s, i), 57)) then all_digits(s, add(i, 1), n)
  else false
  end
end

fn valid_int(s: String) -> Bool
  let n = str_len(s)
  let start = if gt(n, 0) then if eq(str_byte(s, 0), 45) then 1 else 0 end else 0 end
  and(lt(start, n), all_digits(s, start, n))
end

fn digits_value(s: String, i: Int, n: Int, acc: Int) -> Int
  if ge(i, n) then acc
  else digits_value(s, add(i, 1), n, add(mul(acc, 10), sub(str_byte(s, i), 48)))
  end
end

fn int_value(s: String) -> Int
  let n = str_len(s)
  let neg = if gt(n, 0) then eq(str_byte(s, 0), 45) else false end
  let start = if neg then 1 else 0 end
  let mag = digits_value(s, start, n, 0)
  if neg then sub(0, mag) else mag end
end

# ---- columns and rows ----

fn index_of(cols: List[String], name: String, i: Int) -> Option[Int]
  match cols
    case [] -> None
    case [c, ..rest] -> if eq(c, name) then Some(i) else index_of(rest, name, add(i, 1)) end
  end
end

# Reads data records, one row per record, newest first. Stops with the first bad record.
fn collect(s: String, i: Int, n: Int, recno: Int, width: Int, gi: Int, si: Int, acc: List[Row]) -> Result[List[Row], String]
  if ge(i, n) then Ok(acc)
  else
    let bad = str_cat("error: record ", show(recno))
    match parse_record(s, i, n, [])
      case Err(_) -> Err(bad)
      case Ok(rr) ->
        let sv = unwrap_or(list_get(rr.rcols, si), "")
        if and(eq(list_len(rr.rcols), width), valid_int(sv)) then
          collect(s, rr.rnext, n, add(recno, 1), width, gi, si, list_cons(Row { rkey: unwrap_or(list_get(rr.rcols, gi), ""), rval: int_value(sv) }, acc))
        else Err(bad)
        end
    end
  end
end

# Adds rows with equal keys. acc is descending by key (newest first).
fn add_row(acc: List[Row], r: Row) -> List[Row]
  match acc
    case [] -> [r]
    case [top, ..others] ->
      if eq(top.rkey, r.rkey) then list_cons(Row { rkey: top.rkey, rval: add(top.rval, r.rval) }, others)
      else list_cons(r, acc)
      end
  end
end

fn merge_rows(rows: List[Row], acc: List[Row]) -> List[Row]
  match rows
    case [] -> acc
    case [r, ..rest] -> merge_rows(rest, add_row(acc, r))
  end
end

fn quote_key(k: String) -> String
  if or(is_some(str_find(k, ",")), or(is_some(str_find(k, "\"")), is_some(str_find(k, "\n")))) then str_cat("\"", str_join(str_split(k, "\""), "\"\""), "\"")
  else k
  end
end

fn render(rows: List[Row]) -> String
  str_join(list_map(rows, fn(r: Row) str_cat(quote_key(r.rkey), ",", show(r.rval), "\n") end), "")
end

# ---- driver ----

fn data_output(s: String, start: Int, width: Int, gi: Int, si: Int) -> Result[String, String]
  let n = str_len(s)
  match collect(s, start, n, 2, width, gi, si, [])
    case Err(e) -> Err(e)
    case Ok(rows) ->
      let sorted = list_sort_by(rows, fn(a: Row, b: Row) lt(a.rkey, b.rkey) end)
      Ok(render(list_reverse(merge_rows(sorted, []))))
  end
end

fn pick_sum(s: String, cols: List[String], start: Int, gi: Int, sname: String) -> Result[String, String]
  match index_of(cols, sname, 0)
    case None -> Err(str_cat("error: no column ", sname))
    case Some(si) -> data_output(s, start, list_len(cols), gi, si)
  end
end

fn pick_columns(s: String, cols: List[String], start: Int, gname: String, sname: String) -> Result[String, String]
  match index_of(cols, gname, 0)
    case None -> Err(str_cat("error: no column ", gname))
    case Some(gi) -> pick_sum(s, cols, start, gi, sname)
  end
end

fn run(argv: List[String], s: String) -> Result[String, String]
  if eq(str_len(s), 0) then Err("error: no header")
  else
    let gname = unwrap_or(list_get(argv, 0), "")
    let sname = unwrap_or(list_get(argv, 1), "")
    match parse_first(s)
      case Err(_) -> Err("error: record 1")
      case Ok(hdr) -> pick_columns(s, hdr.rcols, hdr.rnext, gname, sname)
    end
  end
end

fn usage_error() -> Unit ! [io]
  println("usage: csvsum <group-column> <sum-column>")
  exit(2)
end

fn report(r: Result[String, String]) -> Unit ! [io]
  match r
    case Ok(out) -> print(out)
    case Err(msg) ->
      println(msg)
      exit(1)
  end
end

fn main() -> Unit ! [io]
  let argv = args()
  if ne(list_len(argv), 2) then usage_error()
  else report(run(argv, read_all()))
  end
end

# ---- tests ----

fn cols_text(r: Result[Rec, String]) -> String
  match r
    case Ok(rr) -> str_join(rr.rcols, "|")
    case Err(e) -> str_cat("ERR:", e)
  end
end

test "quoted field keeps comma and doubled quote"
  expect_eq(cols_text(parse_first("\"Rome, IT\",5,\"says \"\"hi\"\"\"\n")), "Rome, IT|5|says \"hi\"")
end

test "unclosed quote and text after closing quote are errors"
  expect_eq(cols_text(parse_first("\"abc\n")), "ERR:unclosed quote")
  expect_eq(cols_text(parse_first("\"ab\"x,1\n")), "ERR:bad quote")
end

test "integer validation and value"
  expect(valid_int("-12"), "leading minus allowed")
  expect(not(valid_int("1-2")), "inner minus rejected")
  expect(not(valid_int("-")), "lone minus rejected")
  expect_eq(int_value("-42"), -42)
end
