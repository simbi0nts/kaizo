type Field = { ftext: String, fnext: Int, fsep: Int } end
type Rec = { pfields: List[String], pnext: Int } end
type Row = { rnum: Int, rbad: Bool, rfields: List[String] } end
type Pair = { pkey: String, pval: Int } end
type Cols = { cgroup: Int, csum: Int } end

# ---------- record parsing ----------

# index of the next double quote at or after i, or n
fn quote_end(s: String, i: Int, n: Int) -> Int
  if lt(i, n) then
    if eq(str_byte(s, i), 34) then i
    else quote_end(s, add(i, 1), n)
    end
  else n
  end
end

# index of the first ',' '\n' or '"' at or after i, or n
fn plain_end(s: String, i: Int, n: Int) -> Int
  if lt(i, n) then
    let b = str_byte(s, i)
    if or(eq(b, 44), eq(b, 10), eq(b, 34)) then i
    else plain_end(s, add(i, 1), n)
    end
  else n
  end
end

fn parse_plain(s: String, start: Int, n: Int) -> Result[Field, String]
  let j = plain_end(s, start, n)
  let text = str_slice(s, start, j)
  if eq(j, n) then Ok(Field { ftext: text, fnext: n, fsep: -1 })
  else
    let c = str_byte(s, j)
    if eq(c, 34) then Err("quote inside unquoted field")
    elif eq(c, 44) then Ok(Field { ftext: text, fnext: add(j, 1), fsep: 44 })
    else Ok(Field { ftext: text, fnext: add(j, 1), fsep: 10 })
    end
  end
end

# i is the position just after the closing quote
fn close_quoted(s: String, i: Int, n: Int, acc: String) -> Result[Field, String]
  if eq(i, n) then Ok(Field { ftext: acc, fnext: n, fsep: -1 })
  else
    let c = str_byte(s, i)
    if eq(c, 44) then Ok(Field { ftext: acc, fnext: add(i, 1), fsep: 44 })
    elif eq(c, 10) then Ok(Field { ftext: acc, fnext: add(i, 1), fsep: 10 })
    else Err("text after closing quote")
    end
  end
end

# i is the position just after the opening quote
fn parse_quoted(s: String, i: Int, n: Int, acc: String) -> Result[Field, String]
  let q = quote_end(s, i, n)
  let acc2 = str_cat(acc, str_slice(s, i, q))
  if eq(q, n) then Err("unclosed quote")
  else
    if eq(add(q, 1), n) then close_quoted(s, add(q, 1), n, acc2)
    elif eq(str_byte(s, add(q, 1)), 34) then parse_quoted(s, add(q, 2), n, str_cat(acc2, "\""))
    else close_quoted(s, add(q, 1), n, acc2)
    end
  end
end

fn parse_field(s: String, pos: Int) -> Result[Field, String]
  let n = str_len(s)
  if lt(pos, n) then
    if eq(str_byte(s, pos), 34) then parse_quoted(s, add(pos, 1), n, "")
    else parse_plain(s, pos, n)
    end
  else Ok(Field { ftext: "", fnext: n, fsep: -1 })
  end
end

fn parse_rec(s: String, pos: Int, acc: List[String]) -> Result[Rec, String]
  let f = try parse_field(s, pos)
  let fields = list_push(acc, f.ftext)
  if eq(f.fsep, 44) then parse_rec(s, f.fnext, fields)
  else Ok(Rec { pfields: fields, pnext: f.fnext })
  end
end

# all records in order; the first malformed record is included as a bad row and parsing stops
fn parse_all(s: String, pos: Int, n: Int, rec_no: Int, acc: List[Row]) -> List[Row]
  if lt(pos, n) then
    match parse_rec(s, pos, [])
      case Err(_) -> list_reverse(list_cons(Row { rnum: rec_no, rbad: true, rfields: [] }, acc))
      case Ok(r) -> parse_all(s, r.pnext, n, add(rec_no, 1), list_cons(Row { rnum: rec_no, rbad: false, rfields: r.pfields }, acc))
    end
  else list_reverse(acc)
  end
end

# ---------- column and value checks ----------

fn field_at(l: List[String], i: Int) -> String
  unwrap_or(list_get(l, i), "")
end

fn index_of(names: List[String], name: String, i: Int) -> Option[Int]
  match names
    case [] -> None
    case [first, ..rest] -> if eq(first, name) then Some(i) else index_of(rest, name, add(i, 1)) end
  end
end

fn find_sum_col(names: List[String], sumc: String, gi: Int) -> Result[Cols, String]
  match index_of(names, sumc, 0)
    case None -> Err(str_cat("error: no column ", sumc))
    case Some(si) -> Ok(Cols { cgroup: gi, csum: si })
  end
end

fn find_cols(names: List[String], group: String, sumc: String) -> Result[Cols, String]
  match index_of(names, group, 0)
    case None -> Err(str_cat("error: no column ", group))
    case Some(gi) -> find_sum_col(names, sumc, gi)
  end
end

fn all_digits(s: String, i: Int, n: Int) -> Bool
  if lt(i, n) then
    let b = str_byte(s, i)
    if and(le(48, b), le(b, 57)) then all_digits(s, add(i, 1), n)
    else false
    end
  else true
  end
end

fn is_int_text(s: String) -> Bool
  let n = str_len(s)
  if lt(0, n) then
    if eq(str_byte(s, 0), 45) then and(lt(1, n), all_digits(s, 1, n))
    else all_digits(s, 0, n)
    end
  else false
  end
end

fn digits_value(s: String, i: Int, n: Int, acc: Int) -> Int
  if lt(i, n) then digits_value(s, add(i, 1), n, add(mul(acc, 10), sub(str_byte(s, i), 48)))
  else acc
  end
end

# only called on text accepted by is_int_text
fn int_value(s: String) -> Int
  if eq(str_byte(s, 0), 45) then sub(0, digits_value(s, 1, str_len(s), 0))
  else digits_value(s, 0, str_len(s), 0)
  end
end

fn check_row(r: Row, rest: List[Row], width: Int, cols: Cols, acc: List[Pair]) -> Result[List[Pair], Int]
  if r.rbad then Err(r.rnum)
  elif ne(list_len(r.rfields), width) then Err(r.rnum)
  else
    let sv = field_at(r.rfields, cols.csum)
    if is_int_text(sv) then
      validate(rest, width, cols, list_cons(Pair { pkey: field_at(r.rfields, cols.cgroup), pval: int_value(sv) }, acc))
    else Err(r.rnum)
    end
  end
end

fn validate(rows: List[Row], width: Int, cols: Cols, acc: List[Pair]) -> Result[List[Pair], Int]
  match rows
    case [] -> Ok(acc)
    case [r, ..rest] -> check_row(r, rest, width, cols, acc)
  end
end

# ---------- grouping and output ----------

fn sort_pairs(ps: List[Pair]) -> List[Pair]
  list_sort_by(ps, fn(a: Pair, b: Pair) lt(a.pkey, b.pkey) end)
end

# acc is the reversed list of groups; the top is the most recent group
fn add_pair(acc: List[Pair], p: Pair) -> List[Pair]
  match acc
    case [] -> [p]
    case [top, ..rest] ->
      if eq(top.pkey, p.pkey) then list_cons(Pair { pkey: top.pkey, pval: add(top.pval, p.pval) }, rest)
      else list_cons(p, acc)
      end
  end
end

fn group_pairs(ps: List[Pair], acc: List[Pair]) -> List[Pair]
  match ps
    case [] -> list_reverse(acc)
    case [p, ..rest] -> group_pairs(rest, add_pair(acc, p))
  end
end

fn quote_field(g: String) -> String
  if or(is_some(str_find(g, ",")), is_some(str_find(g, "\"")), is_some(str_find(g, "\n"))) then
    str_cat("\"", str_cat(str_join(str_split(g, "\""), "\"\""), "\""))
  else g
  end
end

fn print_groups(gs: List[Pair]) -> Unit ! [io]
  match gs
    case [] -> Unit
    case [g, ..rest] ->
      println(str_cat(quote_field(g.pkey), str_cat(",", show(g.pval))))
      print_groups(rest)
  end
end

fn summarize(rest: List[Row], width: Int, cols: Cols) -> Unit ! [io]
  match validate(rest, width, cols, [])
    case Err(n) -> fail_with(str_cat("error: record ", show(n)), 1)
    case Ok(pairs) -> print_groups(group_pairs(sort_pairs(pairs), []))
  end
end

# ---------- program flow ----------

fn fail_with(msg: String, code: Int) -> Unit ! [io]
  println(msg)
  exit(code)
end

fn usage_exit() -> Unit ! [io]
  println("usage: csvsum <group-column> <sum-column>")
  exit(2)
end

fn check_header(h: Row, rest: List[Row], group: String, sumc: String) -> Unit ! [io]
  if h.rbad then fail_with("error: record 1", 1)
  else
    match find_cols(h.rfields, group, sumc)
      case Err(msg) -> fail_with(msg, 1)
      case Ok(cols) -> summarize(rest, list_len(h.rfields), cols)
    end
  end
end

fn check_all(rows: List[Row], group: String, sumc: String) -> Unit ! [io]
  match rows
    case [] -> fail_with("error: no header", 1)
    case [h, ..rest] -> check_header(h, rest, group, sumc)
  end
end

fn run_csv(group: String, sumc: String) -> Unit ! [io]
  let input = read_all()
  check_all(parse_all(input, 0, str_len(input), 1, []), group, sumc)
end

fn main() -> Unit ! [io]
  match args()
    case [g, s] -> run_csv(g, s)
    case _ -> usage_exit()
  end
end

# ---------- tests ----------

fn fields_of(r: Result[Rec, String]) -> List[String]
  match r
    case Ok(rec) -> rec.pfields
    case Err(_) -> []
  end
end

test "plain and quoted fields"
  expect_eq(fields_of(parse_rec("a,b,c\n", 0, [])), ["a", "b", "c"])
  expect_eq(fields_of(parse_rec("\"x,\"\"y\",z\n", 0, [])), ["x,\"y", "z"])
end

test "quoted newline and empty last field"
  expect_eq(fields_of(parse_rec("\"l1\nl2\",\n", 0, [])), ["l1\nl2", ""])
end

test "malformed records are rejected"
  expect_eq(is_ok(parse_rec("\"open", 0, [])), false)
  expect_eq(is_ok(parse_rec("\"a\"b,c", 0, [])), false)
  expect_eq(is_ok(parse_rec("a\"b,c", 0, [])), false)
end

test "integer sums"
  expect_eq(is_int_text("-12"), true)
  expect_eq(is_int_text("-"), false)
  expect_eq(is_int_text("1-2"), false)
  expect_eq(int_value("-0042"), -42)
end
