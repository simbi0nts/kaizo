# inventory: stock keeper driven by commands on standard input

type Entry = { loc: String, item: String, qty: Int } end
type State = { stock: List[Entry], errs: Int } end

fn name_byte(b: Int) -> Bool
  or(and(ge(b, 97), le(b, 122)), and(ge(b, 48), le(b, 57)), eq(b, 95))
end

fn name_chars(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then true
  elif name_byte(str_byte(s, i)) then name_chars(s, add(i, 1))
  else false end
end

fn valid_name(s: String) -> Bool
  and(gt(str_len(s), 0), name_chars(s, 0))
end

fn digit_chars(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then true
  elif and(ge(str_byte(s, i), 48), le(str_byte(s, i), 57)) then digit_chars(s, add(i, 1))
  else false end
end

fn to_qty(s: String) -> Int
  unwrap_or(str_to_int(s), 0)
end

fn valid_qty(s: String) -> Bool
  and(gt(str_len(s), 0), digit_chars(s, 0), gt(to_qty(s), 0))
end

fn valid_add(loc: String, item: String, q: String) -> Bool
  and(valid_name(loc), valid_name(item), valid_qty(q))
end

fn find_qty(stock: List[Entry], loc: String, item: String) -> Int
  match stock
    case [] -> 0
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then e.qty
      else find_qty(rest, loc, item) end
  end
end

fn set_qty(stock: List[Entry], loc: String, item: String, qty: Int) -> List[Entry]
  match stock
    case [] -> [Entry { loc: loc, item: item, qty: qty }]
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then list_cons(Entry { loc: loc, item: item, qty: qty }, rest)
      else list_cons(e, set_qty(rest, loc, item, qty)) end
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

fn before_entry(a: Entry, b: Entry) -> Bool
  or(lt(a.loc, b.loc), and(eq(a.loc, b.loc), lt(a.item, b.item)))
end

fn print_rows(rows: List[Entry]) -> Unit ! [io]
  match rows
    case [] -> Unit
    case [e, ..rest] ->
      println(str_cat(e.loc, " ", e.item, " ", show(e.qty)))
      print_rows(rest)
  end
end

fn show_rows(rows: List[Entry]) -> Unit ! [io]
  match rows
    case [] -> println("(empty)")
    case _ -> print_rows(rows)
  end
end

fn add_to(st: State, loc: String, item: String, k: Int) -> State
  { st with stock: set_qty(st.stock, loc, item, add(find_qty(st.stock, loc, item), k)) }
end

fn take_raw(st: State, loc: String, item: String, k: Int) -> State
  { st with stock: set_qty(st.stock, loc, item, sub(find_qty(st.stock, loc, item), k)) }
end

fn bad(st: State, n: Int) -> State ! [io]
  println(str_cat("error: line ", show(n), ": bad command"))
  { st with errs: add(st.errs, 1) }
end

fn short(st: State, n: Int, loc: String, item: String) -> State ! [io]
  println(str_cat("error: line ", show(n), ": not enough ", item, " at ", loc))
  { st with errs: add(st.errs, 1) }
end

fn cmd_add(st: State, n: Int, loc: String, item: String, q: String) -> State ! [io]
  if valid_add(loc, item, q) then add_to(st, loc, item, to_qty(q))
  else bad(st, n) end
end

fn cmd_remove(st: State, n: Int, loc: String, item: String, q: String) -> State ! [io]
  if valid_add(loc, item, q) then
    if lt(find_qty(st.stock, loc, item), to_qty(q)) then short(st, n, loc, item)
    else take_raw(st, loc, item, to_qty(q)) end
  else bad(st, n) end
end

fn cmd_move(st: State, n: Int, item: String, q: String, src: String, dst: String) -> State ! [io]
  if and(valid_add(src, item, q), valid_name(dst)) then
    if eq(src, dst) then bad(st, n)
    elif lt(find_qty(st.stock, src, item), to_qty(q)) then short(st, n, src, item)
    else add_to(take_raw(st, src, item, to_qty(q)), dst, item, to_qty(q)) end
  else bad(st, n) end
end

fn cmd_report(st: State) -> State ! [io]
  let nonempty = list_filter(st.stock, fn(e: Entry) gt(e.qty, 0) end)
  show_rows(list_sort_by(nonempty, fn(a, b) before_entry(a, b) end))
  st
end

fn cmd_total(st: State, n: Int, item: String) -> State ! [io]
  if valid_name(item) then
    println(str_cat(item, " ", show(total_of(st.stock, item, 0))))
    st
  else bad(st, n) end
end

fn dispatch(st: State, n: Int, words: List[String]) -> State ! [io]
  match words
    case ["add", loc, item, q] -> cmd_add(st, n, loc, item, q)
    case ["remove", loc, item, q] -> cmd_remove(st, n, loc, item, q)
    case ["move", item, q, src, dst] -> cmd_move(st, n, item, q, src, dst)
    case ["report"] -> cmd_report(st)
    case ["total", item] -> cmd_total(st, n, item)
    case _ -> bad(st, n)
  end
end

fn step(st: State, n: Int, line: String) -> State ! [io]
  if or(eq(line, ""), str_starts(line, "#")) then st
  else dispatch(st, n, str_split(line, " ")) end
end

fn run(st: State, n: Int) -> State ! [io]
  match read_line()
    case None -> st
    case Some(line) -> run(step(st, n, line), add(n, 1))
  end
end

fn main() -> Unit ! [io]
  let fin = run(State { stock: [], errs: 0 }, 1)
  exit(if gt(fin.errs, 0) then 1 else 0 end)
end

test "names"
  expect(valid_name("main_2"), "digits and underscore are valid")
  expect(not(valid_name("Main")), "uppercase is invalid")
  expect(not(valid_name("")), "empty name is invalid")
end

test "quantities"
  expect(valid_qty("12"), "12 is valid")
  expect(not(valid_qty("0")), "zero is invalid")
  expect(not(valid_qty("-3")), "sign is invalid")
  expect(not(valid_qty("1x")), "letters are invalid")
end

test "stock arithmetic"
  let s = set_qty([], "main", "apple", 4)
  let t = set_qty(s, "main", "apple", 7)
  expect_eq(find_qty(t, "main", "apple"), 7)
  expect_eq(find_qty(t, "shop", "apple"), 0)
  expect_eq(total_of(t, "apple", 0), 7)
end
