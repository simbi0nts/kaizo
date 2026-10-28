# csvsum: group and sum a CSV file read from standard input.
# Usage: csvsum <group-column> <sum-column>

type CsvField = { ftext: String, fnext: Int } end
type CsvRow = { rcells: List[String], rnext: Int } end
type CsvParsed = { prows: List[List[String]], pbad: Int } end
type CsvGroup = { gname: String, gval: Int } end
type CsvRun = { rsum: Int, rrest: List[CsvGroup] } end

# ---------- CSV parsing (byte level, tail recursive) ----------

fn is_quote_at(s: String, n: Int, j: Int) -> Bool
  if lt(j, n) then eq(str_byte(s, j), 34) else false end
end

# Index of the first byte at or after j that is ',', newline or '"', or n.
fn plain_end(s: String, n: Int, j: Int) -> Int
  if lt(j, n) then
    let c = str_byte(s, j)
    if or(eq(c, 44), eq(c, 10), eq(c, 34)) then j
    else plain_end(s, n, add(j, 1))
    end
  else j
  end
end

fn plain_field(s: String, n: Int, pos: Int) -> Option[CsvField]
  let j = plain_end(s, n, pos)
  if is_quote_at(s, n, j) then None
  else Some(CsvField { ftext: str_slice(s, pos, j), fnext: j })
  end
end

# j scans the body, seg is the start of the current pending segment,
# acc holds finished segments (in reverse order).
fn quoted_body(s: String, n: Int, j: Int, seg: Int, acc: List[String]) -> Option[CsvField]
  if lt(j, n) then
    if eq(str_byte(s, j), 34) then
      if is_quote_at(s, n, add(j, 1)) then
        quoted_body(s, n, add(j, 2), add(j, 2), list_push(acc, str_slice(s, seg, add(j, 1))))
      else
        let text = str_join(list_push(acc, str_slice(s, seg, j)), "")
        let after = add(j, 1)
        if lt(after, n) then
          let c = str_byte(s, after)
          if or(eq(c, 44), eq(c, 10)) then Some(CsvField { ftext: text, fnext: after })
          else None
          end
        else Some(CsvField { ftext: text, fnext: after })
        end
      end
    else quoted_body(s, n, add(j, 1), seg, acc)
    end
  else None
  end
end

fn parse_field(s: String, n: Int, pos: Int) -> Option[CsvField]
  if lt(pos, n) then
    if eq(str_byte(s, pos), 34) then quoted_body(s, n, add(pos, 1), add(pos, 1), [])
    else plain_field(s, n, pos)
    end
  else Some(CsvField { ftext: "", fnext: pos })
  end
end

fn cells_from(s: String, n: Int, pos: Int, acc: List[String]) -> Option[CsvRow]
  match parse_field(s, n, pos)
    case None -> None
    case Some(f) -> after_cell(s, n, f, list_push(acc, f.ftext))
  end
end

fn after_cell(s: String, n: Int, f: CsvField, cells: List[String]) -> Option[CsvRow]
  if lt(f.fnext, n) then
    let c = str_byte(s, f.fnext)
    if eq(c, 44) then cells_from(s, n, add(f.fnext, 1), cells)
    elif eq(c, 10) then Some(CsvRow { rcells: cells, rnext: add(f.fnext, 1) })
    else None
    end
  else Some(CsvRow { rcells: cells, rnext: f.fnext })
  end
end

# Parses all records. pbad is 0 when every record is well formed, otherwise
# the number of the first malformed record (parsing stops there).
fn csv_records(s: String, n: Int, pos: Int, recno: Int, acc: List[List[String]]) -> CsvParsed
  if lt(pos, n) then
    match cells_from(s, n, pos, [])
      case None -> CsvParsed { prows: list_reverse(acc), pbad: recno }
      case Some(r) -> csv_records(s, n, r.rnext, add(recno, 1), list_cons(r.rcells, acc))
    end
  else CsvParsed { prows: list_reverse(acc), pbad: 0 }
  end
end

fn parse_csv(input: String) -> CsvParsed
  csv_records(input, str_len(input), 0, 1, [])
end

# ---------- integer validation and conversion ----------

fn all_digits(s: String, i: Int) -> Bool
  if lt(i, str_len(s)) then
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then all_digits(s, add(i, 1)) else false end
  else true
  end
end

fn is_int_text(s: String) -> Bool
  if str_starts(s, "-") then
    let body = str_slice(s, 1, str_len(s))
    and(gt(str_len(body), 0), all_digits(body, 0))
  else
    and(gt(str_len(s), 0), all_digits(s, 0))
  end
end

fn digits_value(s: String, i: Int, acc: Int) -> Int
  if lt(i, str_len(s)) then digits_value(s, add(i, 1), add(mul(acc, 10), sub(str_byte(s, i), 48)))
  else acc
  end
end

fn int_value(s: String) -> Int
  if str_starts(s, "-") then sub(0, digits_value(str_slice(s, 1, str_len(s)), 0, 0))
  else digits_value(s, 0, 0)
  end
end

# ---------- column lookup and validation ----------

fn index_of(names: List[String], name: String, i: Int) -> Option[Int]
  match names
    case [] -> None
    case [h, ..rest] -> if eq(h, name) then Some(i) else index_of(rest, name, add(i, 1)) end
  end
end

# Validates data rows in order (recno is the record number of the first row).
# bad is the syntax-error record number from parsing (0 if none), reported
# only after all rows have been checked.
fn collect(rows: List[List[String]], recno: Int, width: Int, gi: Int, si: Int, bad: Int, out: List[CsvGroup]) -> Result[List[CsvGroup], Int]
  match rows
    case [] -> if eq(bad, 0) then Ok(out) else Err(bad) end
    case [row, ..rest] ->
      if eq(list_len(row), width) then
        let sv = unwrap_or(list_get(row, si), "")
        if is_int_text(sv) then
          let g = CsvGroup { gname: unwrap_or(list_get(row, gi), ""), gval: int_value(sv) }
          collect(rest, add(recno, 1), width, gi, si, bad, list_cons(g, out))
        else Err(recno)
        end
      else Err(recno)
      end
  end
end

# ---------- grouping and output ----------

fn take_run(rows: List[CsvGroup], name: String, acc: Int) -> CsvRun
  match rows
    case [] -> CsvRun { rsum: acc, rrest: [] }
    case [g, ..rest] ->
      if eq(g.gname, name) then take_run(rest, name, add(acc, g.gval))
      else CsvRun { rsum: acc, rrest: rows }
      end
  end
end

fn emit(rows: List[CsvGroup], out: List[String]) -> List[String]
  match rows
    case [] -> list_reverse(out)
    case [g, ..rest] ->
      let run = take_run(rest, g.gname, g.gval)
      emit(run.rrest, list_cons(line_for(g.gname, run.rsum), out))
  end
end

fn quote_group(g: String) -> String
  if or(is_some(str_find(g, ",")), is_some(str_find(g, "\"")), is_some(str_find(g, "\n"))) then
    str_cat("\"", str_join(str_split(g, "\""), "\"\""), "\"")
  else g
  end
end

fn line_for(g: String, total: Int) -> String
  str_cat(quote_group(g), ",", show(total))
end

fn by_rows(rows: List[List[String]], width: Int, gi: Int, si: Int, bad: Int) -> Result[List[String], String]
  match collect(rows, 2, width, gi, si, bad, [])
    case Err(n) -> Err(str_cat("error: record ", show(n)))
    case Ok(groups) ->
      Ok(emit(list_sort_by(groups, fn(a: CsvGroup, b: CsvGroup) lt(a.gname, b.gname) end), []))
  end
end

fn by_columns(header: List[String], rows: List[List[String]], bad: Int, group: String, sum: String) -> Result[List[String], String]
  match index_of(header, group, 0)
    case None -> Err(str_cat("error: no column ", group))
    case Some(gi) ->
      match index_of(header, sum, 0)
        case None -> Err(str_cat("error: no column ", sum))
        case Some(si) -> by_rows(rows, list_len(header), gi, si, bad)
      end
  end
end

fn summarize(input: String, group: String, sum: String) -> Result[List[String], String]
  let p = parse_csv(input)
  match p.prows
    case [] ->
      if eq(p.pbad, 0) then Err("error: no header")
      else Err(str_cat("error: record ", show(p.pbad)))
      end
    case [header, ..rest] -> by_columns(header, rest, p.pbad, group, sum)
  end
end

# ---------- entry point ----------

fn print_lines(lines: List[String]) -> Unit ! [io]
  if eq(list_len(lines), 0) then Unit
  else print(str_cat(str_join(lines, "\n"), "\n"))
  end
end

fn finish_run(r: Result[List[String], String]) -> Unit ! [io]
  match r
    case Ok(lines) -> print_lines(lines)
    case Err(msg) ->
      println(msg)
      exit(1)
  end
end

fn usage() -> Unit ! [io]
  println("usage: csvsum <group-column> <sum-column>")
  exit(2)
end

fn main() -> Unit ! [io]
  match args()
    case [group, sum] -> finish_run(summarize(read_all(), group, sum))
    case _ -> usage()
  end
end

# ---------- unit tests ----------

test "quoted fields keep commas quotes and newlines"
  let p = parse_csv("x,\"a,\"\"b\"\"\"\n\"multi\nline\",2\n")
  expect_eq(p.prows, [["x", "a,\"b\""], ["multi\nline", "2"]])
  expect_eq(p.pbad, 0)
end

test "unclosed quote makes its record bad"
  expect_eq(parse_csv("a\n\"x\n").pbad, 2)
  expect_eq(parse_csv("a\n\"x\n").prows, [["a"]])
end

test "summarize groups, sums and sorts"
  expect_eq(summarize("city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n", "city", "amount"), Ok(["Oslo,7", "\"Rome, IT\",5"]))
end

test "summarize reports bad sum and missing column"
  expect_eq(summarize("a,b\n1,x\n", "a", "b"), Err("error: record 2"))
  expect_eq(summarize("a,b\n1,2\n", "a", "zz"), Err("error: no column zz"))
  expect_eq(summarize("", "a", "b"), Err("error: no header"))
end
