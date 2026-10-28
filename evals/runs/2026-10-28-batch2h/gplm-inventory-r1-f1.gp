# inventory: stock keeper driven by commands on standard input

type Entry = { loc: String, item: String, qty: Int } end
type Step = { stock: List[Entry], msg: String, failed: Bool } end

# ---------- name and quantity validation ----------

fn is_digit(b: Int) -> Bool
  and(ge(b, 48), le(b, 57))
end

fn is_name_byte(b: Int) -> Bool
  or(and(ge(b, 97), le(b, 122)), is_digit(b), eq(b, 95))
end

fn name_bytes_ok(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_name_byte(str_byte(s, i)) then name_bytes_ok(s, add(i, 1), n)
  else false end
end

fn valid_name(s: String) -> Bool
  if eq(str_len(s), 0) then false
  else name_bytes_ok(s, 0, str_len(s)) end
end

fn names_ok(names: List[String]) -> Bool
  match names
    case [] -> true
    case [x, ..rest] -> if valid_name(x) then names_ok(rest) else false end
  end
end

fn digits_ok(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_digit(str_byte(s, i)) then digits_ok(s, add(i, 1), n)
  else false end
end

fn parse_qty(s: String) -> Option[Int]
  if eq(str_len(s), 0) then None
  elif digits_ok(s, 0, str_len(s)) then
    match str_to_int(s)
      case Some(k) -> if eq(k, 0) then None else Some(k) end
      case None -> None
    end
  else None end
end

# ---------- stock as a list of entries ----------

fn stock_get(stock: List[Entry], loc: String, item: String) -> Int
  match stock
    case [] -> 0
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then e.qty
      else stock_get(rest, loc, item) end
  end
end

fn has_key(stock: List[Entry], loc: String, item: String) -> Bool
  match stock
    case [] -> false
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then true
      else has_key(rest, loc, item) end
  end
end

fn stock_set(stock: List[Entry], loc: String, item: String, qty: Int) -> List[Entry]
  if has_key(stock, loc, item) then
    list_map(stock, fn(e: Entry)
      if and(eq(e.loc, loc), eq(e.item, item)) then { e with qty: qty } else e end
    end)
  else list_push(stock, Entry { loc: loc, item: item, qty: qty }) end
end

# ---------- step results ----------

fn ok_step(stock: List[Entry]) -> Step
  Step { stock: stock, msg: "", failed: false }
end

fn msg_step(stock: List[Entry], text: String) -> Step
  Step { stock: stock, msg: text, failed: false }
end

fn bad_step(stock: List[Entry], n: Int) -> Step
  Step { stock: stock, msg: str_cat("error: line ", show(n), ": bad command"), failed: true }
end

fn short_step(stock: List[Entry], n: Int, item: String, loc: String) -> Step
  Step { stock: stock, msg: str_cat("error: line ", show(n), ": not enough ", item, " at ", loc), failed: true }
end

# ---------- commands ----------

fn do_add(stock: List[Entry], n: Int, loc: String, item: String, q: String) -> Step
  if names_ok([loc, item]) then
    match parse_qty(q)
      case Some(k) -> ok_step(stock_set(stock, loc, item, add(stock_get(stock, loc, item), k)))
      case None -> bad_step(stock, n)
    end
  else bad_step(stock, n) end
end

fn do_remove(stock: List[Entry], n: Int, loc: String, item: String, q: String) -> Step
  if names_ok([loc, item]) then
    match parse_qty(q)
      case Some(k) ->
        if lt(stock_get(stock, loc, item), k) then short_step(stock, n, item, loc)
        else ok_step(stock_set(stock, loc, item, sub(stock_get(stock, loc, item), k))) end
      case None -> bad_step(stock, n)
    end
  else bad_step(stock, n) end
end

fn move_stock(stock: List[Entry], n: Int, item: String, k: Int, src: String, dst: String) -> Step
  if lt(stock_get(stock, src, item), k) then short_step(stock, n, item, src)
  else
    let left = stock_set(stock, src, item, sub(stock_get(stock, src, item), k))
    ok_step(stock_set(left, dst, item, add(stock_get(left, dst, item), k)))
  end
end

fn do_move(stock: List[Entry], n: Int, item: String, q: String, src: String, dst: String) -> Step
  if and(names_ok([item, src, dst]), not(eq(src, dst))) then
    match parse_qty(q)
      case Some(k) -> move_stock(stock, n, item, k, src, dst)
      case None -> bad_step(stock, n)
    end
  else bad_step(stock, n) end
end

fn entry_before(a: Entry, b: Entry) -> Bool
  if lt(a.loc, b.loc) then true
  elif eq(a.loc, b.loc) then lt(a.item, b.item)
  else false end
end

fn entry_line(e: Entry) -> String
  str_cat(e.loc, " ", e.item, " ", show(e.qty))
end

fn report_step(stock: List[Entry]) -> Step
  let live = list_filter(stock, fn(e: Entry) gt(e.qty, 0) end)
  let sorted = list_sort_by(live, fn(a: Entry, b: Entry) entry_before(a, b) end)
  if eq(list_len(sorted), 0) then msg_step(stock, "(empty)")
  else msg_step(stock, str_join(list_map(sorted, fn(e: Entry) entry_line(e) end), "\n")) end
end

fn total_step(stock: List[Entry], item: String) -> Step
  let sum = list_fold(stock, 0, fn(acc: Int, e: Entry)
    if eq(e.item, item) then add(acc, e.qty) else acc end
  end)
  msg_step(stock, str_cat(item, " ", show(sum)))
end

fn exec_words(stock: List[Entry], n: Int, words: List[String]) -> Step
  match words
    case ["add", loc, item, q] -> do_add(stock, n, loc, item, q)
    case ["remove", loc, item, q] -> do_remove(stock, n, loc, item, q)
    case ["move", item, q, src, dst] -> do_move(stock, n, item, q, src, dst)
    case ["report"] -> report_step(stock)
    case ["total", item] -> if valid_name(item) then total_step(stock, item) else bad_step(stock, n) end
    case _ -> bad_step(stock, n)
  end
end

fn exec_line(stock: List[Entry], n: Int, line: String) -> Step
  if or(eq(line, ""), str_starts(line, "#")) then ok_step(stock)
  else exec_words(stock, n, str_split(line, " ")) end
end

# ---------- driver ----------

fn strip_cr(s: String) -> String
  if gt(str_len(s), 0) then
    if eq(str_byte(s, sub(str_len(s), 1)), 13) then str_slice(s, 0, sub(str_len(s), 1)) else s end
  else s end
end

fn emit(msg: String) -> Unit ! [io]
  if eq(str_len(msg), 0) then Unit else println(msg) end
end

fn run_lines(lines: List[String], n: Int, stock: List[Entry], failed: Bool) -> Bool ! [io]
  match lines
    case [] -> failed
    case [raw, ..rest] ->
      let r = exec_line(stock, n, strip_cr(raw))
      emit(r.msg)
      run_lines(rest, add(n, 1), r.stock, or(failed, r.failed))
  end
end

fn main() -> Unit ! [io]
  let lines = str_split(read_all(), "\n")
  let failed = run_lines(lines, 1, [], false)
  exit(if failed then 1 else 0 end)
end

# ---------- unit tests ----------

test "parse quantities"
  expect_eq(parse_qty("12"), Some(12))
  expect_eq(parse_qty("0"), None)
  expect_eq(parse_qty("-3"), None)
  expect_eq(parse_qty(""), None)
end

test "name validation"
  expect(valid_name("main_2"), "digits and underscore are allowed")
  expect(not(valid_name("Main")), "uppercase is rejected")
  expect(not(valid_name("")), "empty name is rejected")
end

test "move then report"
  let a = exec_line([], 1, "add main apple 5")
  let b = exec_line(a.stock, 2, "move apple 3 main shop")
  expect_eq(b.failed, false)
  expect_eq(stock_get(b.stock, "shop", "apple"), 3)
  expect_eq(stock_get(b.stock, "main", "apple"), 2)
  expect_eq(exec_line(b.stock, 3, "report").msg, "main apple 2\nshop apple 3")
end

test "errors leave stock unchanged"
  let a = exec_line([], 4, "remove shop apple 1")
  expect_eq(a.msg, "error: line 4: not enough apple at shop")
  expect_eq(a.failed, true)
  expect_eq(exec_line([], 5, "frobnicate").msg, "error: line 5: bad command")
  expect_eq(exec_line([], 6, "report").msg, "(empty)")
end
