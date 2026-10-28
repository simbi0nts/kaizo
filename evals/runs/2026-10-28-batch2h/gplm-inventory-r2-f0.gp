type Entry = { loc: String, item: String, qty: Int } end
type St = { stock: List[Entry], err: Bool } end

fn empty_state() -> St
  St { stock: [], err: false }
end

# ---- pure helpers ----

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_name_char(c: Int) -> Bool
  or(and(ge(c, 97), le(c, 122)), is_digit(c), eq(c, 95))
end

fn names_from(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then true
  else
    if is_name_char(str_byte(s, i)) then names_from(s, add(i, 1)) else false end
  end
end

fn valid_name(s: String) -> Bool
  and(gt(str_len(s), 0), names_from(s, 0))
end

fn valid_pair(loc: String, item: String) -> Bool
  and(valid_name(loc), valid_name(item))
end

fn digits_from(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then true
  else
    if is_digit(str_byte(s, i)) then digits_from(s, add(i, 1)) else false end
  end
end

fn qty_of(s: String) -> Option[Int]
  if and(gt(str_len(s), 0), le(str_len(s), 15), digits_from(s, 0)) then
    match str_to_int(s)
      case Some(n) -> if gt(n, 0) then Some(n) else None end
      case None -> None
    end
  else
    None
  end
end

fn is_key(e: Entry, loc: String, item: String) -> Bool
  and(eq(e.loc, loc), eq(e.item, item))
end

fn stock_qty(stock: List[Entry], loc: String, item: String) -> Int
  let found = list_filter(stock, fn(e) is_key(e, loc, item) end)
  match found
    case [e] -> e.qty
    case _ -> 0
  end
end

fn set_stock(stock: List[Entry], loc: String, item: String, q: Int) -> List[Entry]
  let rest = list_filter(stock, fn(e) not(is_key(e, loc, item)) end)
  if gt(q, 0) then list_cons(Entry { loc: loc, item: item, qty: q }, rest) else rest end
end

fn with_stock(st: St, loc: String, item: String, q: Int) -> St
  { st with stock: set_stock(st.stock, loc, item, q) }
end

fn add_if_item(acc: Int, e: Entry, item: String) -> Int
  if eq(e.item, item) then add(acc, e.qty) else acc end
end

fn item_total(stock: List[Entry], item: String) -> Int
  list_fold(stock, 0, fn(acc, e) add_if_item(acc, e, item) end)
end

fn comes_before(a: Entry, b: Entry) -> Bool
  or(lt(a.loc, b.loc), and(eq(a.loc, b.loc), lt(a.item, b.item)))
end

fn entry_line(e: Entry) -> String
  str_cat(e.loc, " ", e.item, " ", show(e.qty))
end

# ---- effectful command handling ----

fn bad(st: St, n: Int) -> St ! [io]
  println(str_cat("error: line ", show(n), ": bad command"))
  { st with err: true }
end

fn shortage(st: St, n: Int, item: String, loc: String) -> St ! [io]
  println(str_cat("error: line ", show(n), ": not enough ", item, " at ", loc))
  { st with err: true }
end

fn cmd_add(st: St, n: Int, loc: String, item: String, q: String) -> St ! [io]
  if valid_pair(loc, item) then
    match qty_of(q)
      case Some(k) -> with_stock(st, loc, item, add(stock_qty(st.stock, loc, item), k))
      case None -> bad(st, n)
    end
  else
    bad(st, n)
  end
end

fn take(st: St, n: Int, loc: String, item: String, k: Int) -> St ! [io]
  let have = stock_qty(st.stock, loc, item)
  if lt(have, k) then
    shortage(st, n, item, loc)
  else
    with_stock(st, loc, item, sub(have, k))
  end
end

fn cmd_remove(st: St, n: Int, loc: String, item: String, q: String) -> St ! [io]
  if valid_pair(loc, item) then
    match qty_of(q)
      case Some(k) -> take(st, n, loc, item, k)
      case None -> bad(st, n)
    end
  else
    bad(st, n)
  end
end

fn move_qty(st: St, n: Int, item: String, k: Int, src: String, dst: String) -> St ! [io]
  let have = stock_qty(st.stock, src, item)
  if lt(have, k) then
    shortage(st, n, item, src)
  else
    let moved = with_stock(st, src, item, sub(have, k))
    with_stock(moved, dst, item, add(stock_qty(moved.stock, dst, item), k))
  end
end

fn cmd_move(st: St, n: Int, item: String, q: String, src: String, dst: String) -> St ! [io]
  if and(valid_pair(src, item), valid_name(dst)) then
    match qty_of(q)
      case Some(k) -> if eq(src, dst) then bad(st, n) else move_qty(st, n, item, k, src, dst) end
      case None -> bad(st, n)
    end
  else
    bad(st, n)
  end
end

fn cmd_report(st: St) -> St ! [io]
  let sorted = list_sort_by(st.stock, fn(a, b) comes_before(a, b) end)
  match sorted
    case [] -> println("(empty)")
    case _ -> println(str_join(list_map(sorted, fn(e) entry_line(e) end), "\n"))
  end
  st
end

fn cmd_total(st: St, n: Int, item: String) -> St ! [io]
  if valid_name(item) then
    println(str_cat(item, " ", show(item_total(st.stock, item))))
    st
  else
    bad(st, n)
  end
end

fn exec(st: St, n: Int, words: List[String]) -> St ! [io]
  match words
    case ["add", loc, item, q] -> cmd_add(st, n, loc, item, q)
    case ["remove", loc, item, q] -> cmd_remove(st, n, loc, item, q)
    case ["move", item, q, src, dst] -> cmd_move(st, n, item, q, src, dst)
    case ["report"] -> cmd_report(st)
    case ["total", item] -> cmd_total(st, n, item)
    case _ -> bad(st, n)
  end
end

fn step(st: St, n: Int, line: String) -> St ! [io]
  if or(eq(line, ""), str_starts(line, "#")) then
    st
  else
    exec(st, n, str_split(line, " "))
  end
end

fn run_lines(lines: List[String], n: Int, st: St) -> St ! [io]
  match lines
    case [] -> st
    case [line, ..rest] -> run_lines(rest, add(n, 1), step(st, n, line))
  end
end

fn main() -> Unit ! [io]
  let st = run_lines(str_split(read_all(), "\n"), 1, empty_state())
  exit(if st.err then 1 else 0)
end

# ---- unit tests of the pure logic ----

test "names are a-z 0-9 and underscore"
  expect(valid_name("main_2"), "lowercase, digit and underscore are allowed")
  expect(not(valid_name("Main")), "uppercase is rejected")
  expect(not(valid_name("")), "empty name is rejected")
end

test "quantities are positive digits"
  expect_eq(qty_of("12"), Some(12))
  expect_eq(qty_of("0"), None)
  expect_eq(qty_of("-3"), None)
  expect_eq(qty_of("1x"), None)
end

test "stock lookup and update"
  let st = with_stock(empty_state(), "main", "apple", 5)
  expect_eq(stock_qty(st.stock, "main", "apple"), 5)
  let st2 = with_stock(st, "main", "apple", 0)
  expect_eq(stock_qty(st2.stock, "main", "apple"), 0)
  expect_eq(list_len(st2.stock), 0)
end
