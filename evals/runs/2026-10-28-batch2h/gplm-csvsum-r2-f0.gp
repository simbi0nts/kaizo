# csvsum: group and sum a CSV file read from standard input.

type Fld = { text: String, stop: Int } end
type Rec = { cells: List[String], after: Int } end
type Row = { g: String, v: Int } end

fn is_delim(c: Int) -> Bool
  or(eq(c, 44), eq(c, 10))
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn at_quote(s: String, n: Int, p: Int) -> Bool
  if ge(p, n) then false
  else eq(str_byte(s, p), 34)
  end
end

# Unquoted field: scans to a delimiter (',' or newline) or the end of input.
fn plain_field(s: String, n: Int, start: Int, j: Int) -> Result[Fld, String]
  if ge(j, n) then Ok(Fld { text: str_slice(s, start, n), stop: n })
  elif is_delim(str_byte(s, j)) then Ok(Fld { text: str_slice(s, start, j), stop: j })
  elif eq(str_byte(s, j), 34) then Err("quote in unquoted field")
  else plain_field(s, n, start, add(j, 1))
  end
end

# Inside a quoted field; acc holds the unescaped bytes in reverse order.
fn quoted_field(s: String, n: Int, i: Int, acc: List[Int]) -> Result[Fld, String]
  if ge(i, n) then Err("unclosed quote")
  elif eq(str_byte(s, i), 34) then close_quote(s, n, i, acc)
  else quoted_field(s, n, add(i, 1), list_cons(str_byte(s, i), acc))
  end
end

# s[i] is a quote: either an escaped "" or the closing quote.
fn close_quote(s: String, n: Int, i: Int, acc: List[Int]) -> Result[Fld, String]
  if ge(add(i, 1), n) then Ok(Fld { text: str_from_bytes(list_reverse(acc)), stop: n })
  elif eq(str_byte(s, add(i, 1)), 34) then quoted_field(s, n, add(i, 2), list_cons(34, acc))
  elif is_delim(str_byte(s, add(i, 1))) then Ok(Fld { text: str_from_bytes(list_reverse(acc)), stop: add(i, 1) })
  else Err("bad quote")
  end
end

fn parse_field(s: String, n: Int, p: Int) -> Result[Fld, String]
  if at_quote(s, n, p) then quoted_field(s, n, add(p, 1), [])
  else plain_field(s, n, p, p)
  end
end

fn record_from(s: String, n: Int, p: Int, acc: List[String]) -> Result[Rec, String]
  let f = try parse_field(s, n, p)
  let cells = list_cons(f.text, acc)
  if ge(f.stop, n) then Ok(Rec { cells: list_reverse(cells), after: n })
  elif eq(str_byte(s, f.stop), 10) then Ok(Rec { cells: list_reverse(cells), after: add(f.stop, 1) })
  else record_from(s, n, add(f.stop, 1), cells)
  end
end

fn parse_record(s: String, n: Int, p: Int) -> Result[Rec, String]
  record_from(s, n, p, [])
end

fn digits_ok(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_digit(str_byte(s, i)) then digits_ok(s, add(i, 1), n)
  else false
  end
end

fn digits_value(s: String, i: Int, n: Int, acc: Int) -> Int
  if ge(i, n) then acc
  else digits_value(s, add(i, 1), n, add(mul(acc, 10), sub(str_byte(s, i), 48)))
  end
end

fn signed_int(s: String, n: Int) -> Option[Int]
  if and(gt(n, 1), digits_ok(s, 1, n)) then Some(sub(0, digits_value(s, 1, n, 0)))
  else None
  end
end

fn parse_int(s: String) -> Option[Int]
  let n = str_len(s)
  if eq(n, 0) then None
  elif eq(str_byte(s, 0), 45) then signed_int(s, n)
  elif digits_ok(s, 0, n) then Some(digits_value(s, 0, n, 0))
  else None
  end
end

fn cell_at(cells: List[String], i: Int) -> String
  unwrap_or(list_get(cells, i), "")
end

fn find_from(cols: List[String], name: String, i: Int) -> Option[Int]
  match cols
    case [] -> None
    case [c, ..rest] ->
      if eq(c, name) then Some(i)
      else find_from(rest, name, add(i, 1))
      end
  end
end

fn col_of(cols: List[String], name: String) -> Result[Int, String]
  match find_from(cols, name, 0)
    case None -> Err(str_cat("error: no column ", name))
    case Some(i) -> Ok(i)
  end
end

fn bad_record(recno: Int) -> String
  str_cat("error: record ", show(recno))
end

# Parses data records from position p, collecting rows (in reverse order).
fn load(s: String, n: Int, p: Int, recno: Int, width: Int, gi: Int, si: Int, acc: List[Row]) -> Result[List[Row], String]
  if ge(p, n) then Ok(acc)
  else
    match parse_record(s, n, p)
      case Err(_) -> Err(bad_record(recno))
      case Ok(rec) ->
        if ne(list_len(rec.cells), width) then Err(bad_record(recno))
        else
          match parse_int(cell_at(rec.cells, si))
            case None -> Err(bad_record(recno))
            case Some(v) -> load(s, n, rec.after, add(recno, 1), width, gi, si, list_cons(Row { g: cell_at(rec.cells, gi), v: v }, acc))
          end
        end
    end
  end
end

fn needs_quote(g: String) -> Bool
  or(is_some(str_find(g, ",")), is_some(str_find(g, "\"")), is_some(str_find(g, "\n")))
end

fn quote_group(g: String) -> String
  if needs_quote(g) then str_cat("\"", str_join(str_split(g, "\""), "\"\""), "\"")
  else g
  end
end

fn line_of(g: String, total: Int) -> String
  str_cat(quote_group(g), ",", show(total))
end

# Sums adjacent equal groups; the result is in reverse order.
fn group_run(g: String, total: Int, rest: List[Row], out: List[String]) -> List[String]
  match rest
    case [] -> list_cons(line_of(g, total), out)
    case [r, ..more] ->
      if eq(r.g, g) then group_run(g, add(total, r.v), more, out)
      else group_run(r.g, r.v, more, list_cons(line_of(g, total), out))
      end
  end
end

fn group_lines(rows: List[Row], out: List[String]) -> List[String]
  match rows
    case [] -> out
    case [first, ..rest] -> group_run(first.g, first.v, rest, out)
  end
end

fn render(rows: List[Row]) -> String
  let sorted = list_sort_by(rows, fn(a, b) lt(a.g, b.g) end)
  let lines = list_reverse(group_lines(sorted, []))
  str_join(list_map(lines, fn(l) str_cat(l, "\n") end), "")
end

fn csv_columns(gname: String, sname: String, s: String, n: Int, head: Rec) -> Result[String, String]
  let gi = try col_of(head.cells, gname)
  let si = try col_of(head.cells, sname)
  let rows = try load(s, n, head.after, 2, list_len(head.cells), gi, si, [])
  Ok(render(rows))
end

fn csv_header(gname: String, sname: String, s: String, n: Int) -> Result[String, String]
  match parse_record(s, n, 0)
    case Err(_) -> Err("error: record 1")
    case Ok(head) -> csv_columns(gname, sname, s, n, head)
  end
end

fn csvsum(gname: String, sname: String, s: String) -> Result[String, String]
  let n = str_len(s)
  if eq(n, 0) then Err("error: no header")
  else csv_header(gname, sname, s, n)
  end
end

fn report(r: Result[String, String]) -> Int ! [io]
  match r
    case Ok(text) ->
      print(text)
      0
    case Err(msg) ->
      println(msg)
      1
  end
end

fn usage() -> Int ! [io]
  println("usage: csvsum <group-column> <sum-column>")
  2
end

fn exit_code(argv: List[String]) -> Int ! [io]
  match argv
    case [gname, sname] -> report(csvsum(gname, sname, read_all()))
    case _ -> usage()
  end
end

fn main() -> Unit ! [io]
  exit(exit_code(args()))
end

test "spec example"
  expect_eq(csvsum("city", "amount", "city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n"), Ok("Oslo,7\n\"Rome, IT\",5\n"))
end

test "quoted newline in group"
  expect_eq(csvsum("g", "v", "g,v\n\"a\nb\",1\n"), Ok("\"a\nb\",1\n"))
end

test "bad record number"
  expect_eq(csvsum("a", "b", "a,b\nx,1\ny,z\n"), Err("error: record 3"))
end

test "missing column"
  expect_eq(csvsum("q", "zz", "a,b\n"), Err("error: no column q"))
end

test "empty input"
  expect_eq(csvsum("a", "b", ""), Err("error: no header"))
end

test "header only prints nothing"
  expect_eq(csvsum("a", "b", "a,b\n"), Ok(""))
end
