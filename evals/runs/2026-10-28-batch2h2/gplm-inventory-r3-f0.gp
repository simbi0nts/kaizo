# Inventory: a stock keeper driven by commands on standard input.

type Entry = { loc: String, item: String, qty: Int } end
type Step = { stock: List[Entry], failed: Bool } end

fn char_name_ok(c: Int) -> Bool
  or(or(and(ge(c, 97), le(c, 122)), and(ge(c, 48), le(c, 57))), eq(c, 95))
end

fn name_chars_ok(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then
    true
  else
    if char_name_ok(str_byte(s, i)) then name_chars_ok(s, add(i, 1)) else false end
  end
end

fn is_name(s: String) -> Bool
  and(gt(str_len(s), 0), name_chars_ok(s, 0))
end

fn digit_chars_ok(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then
    true
  else
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then digit_chars_ok(s, add(i, 1)) else false end
  end
end

fn to_qty(s: String) -> Int
  match str_to_int(s)
    case Some(n) -> n
    case None -> 0
  end
end

fn is_qty(s: String) -> Bool
  if and(gt(str_len(s), 0), le(str_len(s), 15)) then
    and(digit_chars_ok(s, 0), gt(to_qty(s), 0))
  else
    false
  end
end

fn has_entry(stock: List[Entry], loc: String, item: String) -> Bool
  match stock
    case [] -> false
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then true else has_entry(rest, loc, item) end
  end
end

fn qty_of(stock: List[Entry], loc: String, item: String) -> Int
  match stock
    case [] -> 0
    case [e, ..rest] ->
      if and(eq(e.loc, loc), eq(e.item, item)) then e.qty else qty_of(rest, loc, item) end
  end
end

fn set_qty(stock: List[Entry], loc: String, item: String, n: Int) -> List[Entry]
  if has_entry(stock, loc, item) then
    list_map(stock, fn(e: Entry)
      if and(eq(e.loc, loc), eq(e.item, item)) then
        Entry { loc: loc, item: item, qty: n }
      else
        e
      end
    end)
  else
    list_push(stock, Entry { loc: loc, item: item, qty: n })
  end
end

fn total_of(stock: List[Entry], item: String) -> Int
  list_fold(stock, 0, fn(acc: Int, e: Entry)
    if eq(e.item, item) then add(acc, e.qty) else acc end
  end)
end

fn before(a: Entry, b: Entry) -> Bool
  or(lt(a.loc, b.loc), and(eq(a.loc, b.loc), lt(a.item, b.item)))
end

fn print_entries(items: List[Entry]) -> Unit ! [io]
  match items
    case [] -> Unit
    case [e, ..rest] ->
      println(str_cat(e.loc, " ", e.item, " ", show(e.qty)))
      print_entries(rest)
  end
end

fn print_report(stock: List[Entry]) -> Unit ! [io]
  let shown = list_sort_by(list_filter(stock, fn(e: Entry) gt(e.qty, 0) end), fn(a: Entry, b: Entry) before(a, b) end)
  if eq(list_len(shown), 0) then
    println("(empty)")
  else
    print_entries(shown)
  end
end

fn good_step(stock: List[Entry]) -> Step
  Step { stock: stock, failed: false }
end

fn bad_command(n: Int, stock: List[Entry]) -> Step ! [io]
  println(str_cat("error: line ", show(n), ": bad command"))
  Step { stock: stock, failed: true }
end

fn not_enough(n: Int, item: String, loc: String, stock: List[Entry]) -> Step ! [io]
  println(str_cat("error: line ", show(n), ": not enough ", item, " at ", loc))
  Step { stock: stock, failed: true }
end

fn strip_cr(line: String) -> String
  if str_ends(line, "\r") then str_slice(line, 0, sub(str_len(line), 1)) else line end
end

fn step(line: String, n: Int, stock: List[Entry]) -> Step ! [io]
  if or(eq(line, ""), str_starts(line, "#")) then
    good_step(stock)
  else
    match str_split(line, " ")
      case ["add", loc, item, qs] ->
        if and(is_name(loc), and(is_name(item), is_qty(qs))) then
          good_step(set_qty(stock, loc, item, add(qty_of(stock, loc, item), to_qty(qs))))
        else
          bad_command(n, stock)
        end
      case ["remove", loc, item, qs] ->
        if and(is_name(loc), and(is_name(item), is_qty(qs))) then
          let have = qty_of(stock, loc, item)
          let q = to_qty(qs)
          if lt(have, q) then
            not_enough(n, item, loc, stock)
          else
            good_step(set_qty(stock, loc, item, sub(have, q)))
          end
        else
          bad_command(n, stock)
        end
      case ["move", item, qs, src, dst] ->
        if and(and(is_name(item), is_qty(qs)), and(and(is_name(src), is_name(dst)), ne(src, dst))) then
          let have = qty_of(stock, src, item)
          let q = to_qty(qs)
          if lt(have, q) then
            not_enough(n, item, src, stock)
          else
            good_step(set_qty(set_qty(stock, src, item, sub(have, q)), dst, item, add(qty_of(stock, dst, item), q)))
          end
        else
          bad_command(n, stock)
        end
      case ["report"] ->
        print_report(stock)
        good_step(stock)
      case ["total", item] ->
        if is_name(item) then
          println(str_cat(item, " ", show(total_of(stock, item))))
          good_step(stock)
        else
          bad_command(n, stock)
        end
      case _ -> bad_command(n, stock)
    end
  end
end

fn run_lines(lines: List[String], n: Int, stock: List[Entry], failed: Bool) -> Bool ! [io]
  match lines
    case [] -> failed
    case [line, ..rest] ->
      let r = step(strip_cr(line), n, stock)
      run_lines(rest, add(n, 1), r.stock, or(failed, r.failed))
  end
end

fn main() -> Unit ! [io]
  let failed = run_lines(str_split(read_all(), "\n"), 1, [], false)
  exit(if failed then 1 else 0 end)
end

test "qty_of sums stock per location and item"
  let s = set_qty(set_qty([], "main", "apple", 5), "shop", "apple", 2)
  expect_eq(qty_of(s, "main", "apple"), 5)
  expect_eq(qty_of(s, "shop", "apple"), 2)
  expect_eq(qty_of(s, "shop", "pear"), 0)
end

test "names and quantities are validated"
  expect(is_name("main_2"), "name with digit and underscore")
  expect(not(is_name("Main")), "uppercase is rejected")
  expect(not(is_name("")), "empty name is rejected")
  expect(is_qty("12"), "12 is a quantity")
  expect(not(is_qty("0")), "zero is not a quantity")
  expect(not(is_qty("-3")), "sign is rejected")
  expect(not(is_qty("1x")), "letters are rejected")
end

test "a move that is too large fails and changes nothing"
  let s = set_qty([], "main", "apple", 3)
  let r = step("move apple 5 main shop", 1, s)
  expect(r.failed, "short move fails")
  expect_eq(qty_of(r.stock, "main", "apple"), 3)
  expect_eq(qty_of(r.stock, "shop", "apple"), 0)
end
