# inventory: stock keeper driven by commands on standard input.

type Entry = { loc: String, item: String, qty: Int } end

type Outcome = { stock: List[Entry], out: List[String], failed: Bool } end

# ---------- names and quantities ----------

fn is_digit(b: Int) -> Bool
  and(ge(b, 48), le(b, 57))
end

fn is_name_byte(b: Int) -> Bool
  or(and(ge(b, 97), le(b, 122)), is_digit(b), eq(b, 95))
end

fn name_chars_from(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_name_byte(str_byte(s, i)) then name_chars_from(s, add(i, 1), n)
  else false end
end

fn name_ok(s: String) -> Bool
  if eq(str_len(s), 0) then false
  else name_chars_from(s, 0, str_len(s)) end
end

fn digits_from(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_digit(str_byte(s, i)) then digits_from(s, add(i, 1), n)
  else false end
end

fn digits_ok(s: String) -> Bool
  if eq(str_len(s), 0) then false
  else digits_from(s, 0, str_len(s)) end
end

fn parse_qty(s: String) -> Option[Int]
  if digits_ok(s) then
    match str_to_int(s)
      case Some(k) -> if gt(k, 0) then Some(k) else None end
      case None -> None
    end
  else None end
end

# ---------- stock as a list of non-zero entries ----------

fn same_key(e: Entry, loc: String, item: String) -> Bool
  and(eq(e.loc, loc), eq(e.item, item))
end

fn stock_qty(stock: List[Entry], loc: String, item: String) -> Int
  match stock
    case [] -> 0
    case [e, ..rest] ->
      if same_key(e, loc, item) then e.qty
      else stock_qty(rest, loc, item) end
  end
end

fn total_of(stock: List[Entry], item: String, acc: Int) -> Int
  match stock
    case [] -> acc
    case [e, ..rest] ->
      if eq(e.item, item) then total_of(rest, item, add(acc, e.qty))
      else total_of(rest, item, acc) end
  end
end

# Sets the quantity of (loc, item). A quantity of 0 removes the entry.
fn stock_set(stock: List[Entry], loc: String, item: String, q: Int) -> List[Entry]
  stock_set_go(stock, [], loc, item, q)
end

fn stock_set_go(rest: List[Entry], seen: List[Entry], loc: String, item: String, q: Int) -> List[Entry]
  match rest
    case [] ->
      if gt(q, 0) then list_reverse(list_cons(Entry { loc: loc, item: item, qty: q }, seen))
      else list_reverse(seen) end
    case [e, ..tail] ->
      if same_key(e, loc, item) then
        let kept = if gt(q, 0) then list_cons(Entry { loc: loc, item: item, qty: q }, seen) else seen end
        list_concat(list_reverse(kept), tail)
      else stock_set_go(tail, list_cons(e, seen), loc, item, q)
      end
  end
end

# ---------- report ----------

fn entry_before(a: Entry, b: Entry) -> Bool
  if lt(a.loc, b.loc) then true
  elif eq(a.loc, b.loc) then lt(a.item, b.item)
  else false end
end

fn entry_line(e: Entry) -> String
  str_cat(e.loc, " ", e.item, " ", show(e.qty))
end

fn report_lines(stock: List[Entry]) -> List[String]
  if eq(list_len(stock), 0) then ["(empty)"]
  else list_map(
    list_sort_by(stock, fn(a: Entry, b: Entry) entry_before(a, b) end),
    fn(e: Entry) entry_line(e) end)
  end
end

# ---------- command handling (pure) ----------

fn ok_out(stock: List[Entry], out: List[String]) -> Outcome
  Outcome { stock: stock, out: out, failed: false }
end

fn err_out(stock: List[Entry], msg: String) -> Outcome
  Outcome { stock: stock, out: [msg], failed: true }
end

fn bad_out(stock: List[Entry], n: Int) -> Outcome
  err_out(stock, str_cat("error: line ", show(n), ": bad command"))
end

fn not_enough_msg(item: String, loc: String, n: Int) -> String
  str_cat("error: line ", show(n), ": not enough ", item, " at ", loc)
end

fn cmd_add(stock: List[Entry], loc: String, item: String, q: String, n: Int) -> Outcome
  if and(name_ok(loc), name_ok(item)) then
    match parse_qty(q)
      case Some(k) ->
        ok_out(stock_set(stock, loc, item, add(stock_qty(stock, loc, item), k)), [])
      case None -> bad_out(stock, n)
    end
  else bad_out(stock, n) end
end

fn cmd_remove(stock: List[Entry], loc: String, item: String, q: String, n: Int) -> Outcome
  if and(name_ok(loc), name_ok(item)) then
    match parse_qty(q)
      case Some(k) ->
        let have = stock_qty(stock, loc, item)
        if lt(have, k) then err_out(stock, not_enough_msg(item, loc, n))
        else ok_out(stock_set(stock, loc, item, sub(have, k)), []) end
      case None -> bad_out(stock, n)
    end
  else bad_out(stock, n) end
end

fn cmd_move(stock: List[Entry], item: String, q: String, src: String, dst: String, n: Int) -> Outcome
  if and(name_ok(item), name_ok(src), name_ok(dst)) then
    if eq(src, dst) then bad_out(stock, n)
    else
      match parse_qty(q)
        case Some(k) ->
          let have = stock_qty(stock, src, item)
          if lt(have, k) then err_out(stock, not_enough_msg(item, src, n))
          else
            let moved = stock_set(stock, src, item, sub(have, k))
            ok_out(stock_set(moved, dst, item, add(stock_qty(moved, dst, item), k)), [])
          end
        case None -> bad_out(stock, n)
      end
    end
  else bad_out(stock, n) end
end

fn run_command(stock: List[Entry], line: String, n: Int) -> Outcome
  match str_split(line, " ")
    case ["add", loc, item, q] -> cmd_add(stock, loc, item, q, n)
    case ["remove", loc, item, q] -> cmd_remove(stock, loc, item, q, n)
    case ["move", item, q, src, dst] -> cmd_move(stock, item, q, src, dst, n)
    case ["report"] -> ok_out(stock, report_lines(stock))
    case ["total", item] ->
      if name_ok(item) then ok_out(stock, [str_cat(item, " ", show(total_of(stock, item, 0)))])
      else bad_out(stock, n) end
    case _ -> bad_out(stock, n)
  end
end

# ---------- input and output ----------

# Removes a trailing carriage return (for CRLF input).
fn strip_cr(s: String) -> String
  let n = str_len(s)
  if eq(n, 0) then s
  elif eq(str_byte(s, sub(n, 1)), 13) then str_slice(s, 0, sub(n, 1))
  else s end
end

fn print_all(lines: List[String]) -> Unit ! [io]
  match lines
    case [] -> Unit
    case [l, ..rest] ->
      println(l)
      print_all(rest)
  end
end

fn process_lines(lines: List[String], n: Int, stock: List[Entry], failed: Bool) -> Bool ! [io]
  match lines
    case [] -> failed
    case [raw, ..rest] ->
      let line = strip_cr(raw)
      if or(eq(str_len(line), 0), str_starts(line, "#")) then
        process_lines(rest, add(n, 1), stock, failed)
      else
        let r = run_command(stock, line, n)
        print_all(r.out)
        process_lines(rest, add(n, 1), r.stock, or(failed, r.failed))
      end
  end
end

fn main() -> Unit ! [io]
  let text = read_all()
  let lines = str_split(text, "\n")
  let failed = process_lines(lines, 1, [], false)
  let code = if failed then 1 else 0 end
  exit(code)
end

# ---------- unit tests of the pure logic ----------

test "names and quantities"
  expect(name_ok("main_2"), "valid name")
  expect_eq(name_ok("Main"), false)
  expect_eq(name_ok(""), false)
  expect_eq(parse_qty("12"), Some(12))
  expect_eq(parse_qty("0"), None)
  expect_eq(parse_qty("-3"), None)
  expect_eq(parse_qty("1x"), None)
end

test "stock set and quantity"
  let s = stock_set([], "main", "apple", 5)
  expect_eq(stock_qty(s, "main", "apple"), 5)
  let t = stock_set(s, "main", "apple", 0)
  expect_eq(stock_qty(t, "main", "apple"), 0)
  expect_eq(list_len(t), 0)
end

test "remove too much changes nothing and reports"
  let r = run_command([], "remove main apple 1", 3)
  expect_eq(r.out, ["error: line 3: not enough apple at main"])
  expect_eq(r.failed, true)
  expect_eq(list_len(r.stock), 0)
end

test "move and report"
  let s = stock_set([], "main", "apple", 5)
  let r = run_command(s, "move apple 3 main shop", 2)
  expect_eq(r.failed, false)
  expect_eq(report_lines(r.stock), ["main apple 2", "shop apple 3"])
end

test "bad command"
  let r = run_command([], "move apple 3 main main", 7)
  expect_eq(r.out, ["error: line 7: bad command"])
end
