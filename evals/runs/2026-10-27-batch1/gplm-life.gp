# Conway's Game of Life in GPLM

fn alive_at(s: String, c: Int) -> Int
  if or(lt(c, 0), ge(c, str_len(s))) then 0
  elif eq(str_byte(s, c), 35) then 1
  else 0
  end
end

fn next_byte(a: String, m: String, b: String, c: Int) -> Int
  let top = add(add(alive_at(a, sub(c, 1)), alive_at(a, c)), alive_at(a, add(c, 1)))
  let mid = add(alive_at(m, sub(c, 1)), alive_at(m, add(c, 1)))
  let bot = add(add(alive_at(b, sub(c, 1)), alive_at(b, c)), alive_at(b, add(c, 1)))
  let n = add(top, add(mid, bot))
  let me = alive_at(m, c)
  if or(eq(n, 3), and(eq(me, 1), eq(n, 2))) then 35 else 46 end
end

fn row_at(g: List[String], r: Int) -> String
  if lt(r, 0) then "" else unwrap_or(list_get(g, r), "") end
end

fn next_row(g: List[String], w: Int, r: Int) -> String
  let above = row_at(g, sub(r, 1))
  let cur = row_at(g, r)
  let below = row_at(g, add(r, 1))
  str_from_bytes(list_map(list_range(0, w), fn(c) next_byte(above, cur, below, c) end))
end

fn step(g: List[String]) -> List[String]
  let h = list_len(g)
  if eq(h, 0) then g
  else
    let w = str_len(row_at(g, 0))
    list_map(list_range(0, h), fn(r) next_row(g, w, r) end)
  end
end

fn run_gens(g: List[String], n: Int) -> List[String]
  if le(n, 0) then g else run_gens(step(g), sub(n, 1)) end
end

fn count_row(s: String, i: Int, acc: Int) -> Int
  if ge(i, str_len(s)) then acc
  else count_row(s, add(i, 1), add(acc, alive_at(s, i)))
  end
end

fn count_alive(g: List[String]) -> Int
  list_fold(g, 0, fn(acc, row) add(acc, count_row(row, 0, 0)) end)
end

fn valid_chars(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then true
  else
    let b = str_byte(s, i)
    if or(eq(b, 35), eq(b, 46)) then valid_chars(s, add(i, 1)) else false end
  end
end

fn valid_grid(lines: List[String]) -> Bool
  match lines
    case [] -> true
    case [first, .._] ->
      let w = str_len(first)
      list_fold(lines, true, fn(acc, l) and(acc, and(eq(str_len(l), w), valid_chars(l, 0))) end)
  end
end

fn strip_cr(s: String) -> String
  if str_ends(s, "\r") then str_slice(s, 0, sub(str_len(s), 1)) else s end
end

fn drop_leading_empty(l: List[String]) -> List[String]
  match l
    case [] -> []
    case [first, ..rest] ->
      if eq(first, "") then drop_leading_empty(rest) else l end
  end
end

fn clean_lines(l: List[String]) -> List[String]
  list_reverse(drop_leading_empty(list_reverse(list_map(l, fn(s) strip_cr(s) end))))
end

fn read_all(acc: List[String]) -> List[String] ! [io]
  match read_line()
    case Some(line) -> read_all(list_cons(line, acc))
    case None -> list_reverse(acc)
  end
end

fn print_rows(g: List[String]) -> Unit ! [io]
  match g
    case [] -> Unit
    case [first, ..rest] ->
      println(first)
      print_rows(rest)
  end
end

fn usage() -> Unit ! [io]
  println("usage: life <generations>")
  exit(2)
end

fn bad_grid() -> Unit ! [io]
  println("error: bad grid")
  exit(1)
end

fn run_app(n: Int) -> Unit ! [io]
  let lines = clean_lines(read_all([]))
  if not(valid_grid(lines)) then bad_grid()
  else
    let g = run_gens(lines, n)
    print_rows(g)
    println(str_cat("alive: ", show(count_alive(g))))
    exit(0)
  end
end

fn main() -> Unit ! [io]
  match args()
    case [] -> usage()
    case [s, .._] ->
      match str_to_int(s)
        case Some(n) -> if lt(n, 0) then usage() else run_app(n) end
        case None -> usage()
      end
  end
end

test "blinker rotates"
  let g = [".....", "..#..", "..#..", "..#..", "....."]
  expect_eq(step(g), [".....", ".....", ".###.", ".....", "....."])
end

test "blinker period two and count"
  let g = [".....", "..#..", "..#..", "..#..", "....."]
  expect_eq(run_gens(g, 2), g)
  expect_eq(count_alive(g), 3)
end

test "grid validation"
  expect(valid_grid([".#", "#."]), "valid grid")
  expect(not(valid_grid(["..", "..."])), "ragged grid")
  expect(not(valid_grid([".x"])), "bad char")
  expect(valid_grid([]), "empty grid")
end

test "trailing empty lines dropped"
  expect_eq(clean_lines(["#.", ".#", "", ""]), ["#.", ".#"])
end

test "block is stable"
  let g = ["....", ".##.", ".##.", "...."]
  expect_eq(step(g), g)
end
