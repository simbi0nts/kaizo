type Entry = { loc: String, item: String, qty: Int } end
type Step = { stock: List[Entry], failed: Bool } end

fn mk(stock: List[Entry], failed: Bool) -> Step
  Step { stock: stock, failed: failed }
end

fn is_name_byte(b: Int) -> Bool
  or(and(ge(b, 97), le(b, 122)), and(ge(b, 48), le(b, 57)), eq(b, 95))
end

fn name_chars_ok(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_name_byte(str_byte(s, i)) then name_chars_ok(s, add(i, 1), n)
  else false end
end

fn name_ok(s: String) -> Bool
  let n = str_len(s)
  and(gt(n, 0), name_chars_ok(s, 0, n))
end

fn all_digits(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif and(ge(str_byte(s, i), 48), le(str_byte(s, i), 57)) then all_digits(s, add(i, 1), n)
  else false end
end

fn digits_value(s: String, i: Int, n: Int, acc: Int) -> Int
  if ge(i, n) then acc
  else digits_value(s, add(i, 1), n, add(mul(acc, 10), sub(str_byte(s, i), 48))) end
end

# Returns the quantity, 0 for "0", or -1 when the text is not a valid number.
fn parse_qty(s: String) -> Int
  let n = str_len(s)
  if and(gt(n, 0), le(n, 15)) then
    if all_digits(s, 0, n) then digits_value(s, 0, n, 0) else -1 end
  else -1 end
end

fn find_qty(stock: List[Entry], loc: String, item: String) -> Int
  match stock
    case [] -> 0
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then e.qty
      else find_qty(rest, loc, item) end
  end
end

fn put(stock: List[Entry], loc: String, item: String, q: Int) -> List[Entry]
  match stock
    case [] -> [Entry { loc: loc, item: item, qty: q }]
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then
        list_cons(Entry { loc: loc, item: item, qty: q }, rest)
      else
        list_cons(e, put(rest, loc, item, q))
      end
  end
end

fn total_of(stock: List[Entry], item: String) -> Int
  match stock
    case [] -> 0
    case [e, ..rest] ->
      if eq(e.item, item) then add(e.qty, total_of(rest, item))
      else total_of(rest, item) end
  end
end

fn nonzero(e: Entry) -> Bool
  gt(e.qty, 0)
end

fn entry_before(a: Entry, b: Entry) -> Bool
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

fn word(words: List[String], i: Int) -> String
  unwrap_or(list_get(words, i), "")
end

fn bad(stock: List[Entry], n: Int) -> Step ! [io]
  println(str_cat("error: line ", show(n), ": bad command"))
  mk(stock, true)
end

fn not_enough(stock: List[Entry], n: Int, item: String, loc: String) -> Step ! [io]
  println(str_cat("error: line ", show(n), ": not enough ", item, " at ", loc))
  mk(stock, true)
end

fn do_add(stock: List[Entry], n: Int, words: List[String]) -> Step ! [io]
  let loc = word(words, 1)
  let item = word(words, 2)
  let q = parse_qty(word(words, 3))
  if and(name_ok(loc), name_ok(item), gt(q, 0)) then
    mk(put(stock, loc, item, add(find_qty(stock, loc, item), q)), false)
  else bad(stock, n) end
end

fn do_remove(stock: List[Entry], n: Int, words: List[String]) -> Step ! [io]
  let loc = word(words, 1)
  let item = word(words, 2)
  let q = parse_qty(word(words, 3))
  if and(name_ok(loc), name_ok(item), gt(q, 0)) then
    let have = find_qty(stock, loc, item)
    if lt(have, q) then not_enough(stock, n, item, loc)
    else mk(put(stock, loc, item, sub(have, q)), false) end
  else bad(stock, n) end
end

fn do_move(stock: List[Entry], n: Int, words: List[String]) -> Step ! [io]
  let item = word(words, 1)
  let q = parse_qty(word(words, 2))
  let src = word(words, 3)
  let dst = word(words, 4)
  if and(name_ok(item), gt(q, 0), name_ok(src), name_ok(dst), not(eq(src, dst))) then
    let have = find_qty(stock, src, item)
    if lt(have, q) then not_enough(stock, n, item, src)
    else
      let taken = put(stock, src, item, sub(have, q))
      mk(put(taken, dst, item, add(find_qty(taken, dst, item), q)), false)
    end
  else bad(stock, n) end
end

fn do_total(stock: List[Entry], n: Int, words: List[String]) -> Step ! [io]
  let item = word(words, 1)
  if name_ok(item) then
    println(str_cat(item, " ", show(total_of(stock, item))))
    mk(stock, false)
  else bad(stock, n) end
end

fn do_report(stock: List[Entry]) -> Step ! [io]
  let rows = list_sort_by(list_filter(stock, fn(e) nonzero(e) end), fn(a, b) entry_before(a, b) end)
  if eq(list_len(rows), 0) then println("(empty)")
  else print_rows(rows) end
  mk(stock, false)
end

fn exec(stock: List[Entry], n: Int, words: List[String]) -> Step ! [io]
  let cmd = word(words, 0)
  let k = list_len(words)
  if and(eq(cmd, "add"), eq(k, 4)) then do_add(stock, n, words)
  elif and(eq(cmd, "remove"), eq(k, 4)) then do_remove(stock, n, words)
  elif and(eq(cmd, "move"), eq(k, 5)) then do_move(stock, n, words)
  elif and(eq(cmd, "total"), eq(k, 2)) then do_total(stock, n, words)
  elif and(eq(cmd, "report"), eq(k, 1)) then do_report(stock)
  else bad(stock, n) end
end

fn is_skip(line: String) -> Bool
  if eq(str_len(line), 0) then true
  else eq(str_byte(line, 0), 35) end
end

fn handle_line(stock: List[Entry], n: Int, line: String) -> Step ! [io]
  if is_skip(line) then mk(stock, false)
  else exec(stock, n, str_split(line, " ")) end
end

fn run(stock: List[Entry], n: Int, failed: Bool) -> Bool ! [io]
  match read_line()
    case None -> failed
    case Some(line) ->
      let s = handle_line(stock, n, line)
      run(s.stock, add(n, 1), or(failed, s.failed))
  end
end

fn main() -> Unit ! [io]
  let failed = run([], 1, false)
  exit(if failed then 1 else 0 end)
end

test "parse_qty"
  expect_eq(parse_qty("12"), 12)
  expect_eq(parse_qty("0"), 0)
  expect_eq(parse_qty("-3"), -1)
  expect_eq(parse_qty("1x"), -1)
  expect_eq(parse_qty(""), -1)
end

test "stock put and find"
  let s = put(put([], "main", "apple", 5), "main", "apple", 2)
  expect_eq(find_qty(s, "main", "apple"), 2)
  expect_eq(find_qty(s, "shop", "apple"), 0)
  expect_eq(list_len(s), 1)
end

test "name validation"
  expect(name_ok("main_2"), "valid name")
  expect(not(name_ok("Main")), "uppercase rejected")
  expect(not(name_ok("")), "empty rejected")
end

test "report order"
  expect(entry_before(Entry { loc: "a", item: "z", qty: 1 }, Entry { loc: "b", item: "a", qty: 1 }), "location first")
end
