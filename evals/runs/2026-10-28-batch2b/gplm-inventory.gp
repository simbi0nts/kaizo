# inventory: stock keeper driven by commands on standard input

type Entry = { loc: String, item: String, qty: Int } end

type Cmd = Add(String, String, Int)
  | Remove(String, String, Int)
  | Move(String, Int, String, String)
  | Report
  | Total(String)
  | Skip
  | Bad
end

type Res = { st: List[Entry], lines: List[String], err: Bool } end

fn name_bytes(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then
    true
  else
    let c = str_byte(s, i)
    if or(and(ge(c, 97), le(c, 122)), and(ge(c, 48), le(c, 57)), eq(c, 95)) then
      name_bytes(s, add(i, 1))
    else
      false
    end
  end
end

fn valid_name(s: String) -> Bool
  if gt(str_len(s), 0) then name_bytes(s, 0) else false end
end

fn digit_bytes(s: String, i: Int) -> Bool
  if ge(i, str_len(s)) then
    true
  else
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then digit_bytes(s, add(i, 1)) else false end
  end
end

fn parse_qty(s: String) -> Option[Int]
  if or(eq(str_len(s), 0), gt(str_len(s), 18)) then
    None
  elif not(digit_bytes(s, 0)) then
    None
  else
    match str_to_int(s)
      case Some(n) -> if gt(n, 0) then Some(n) else None end
      case None -> None
    end
  end
end

fn parse_loc_item_qty(c: String, rest: List[String]) -> Cmd
  match rest
    case [l, i, q] ->
      match parse_qty(q)
        case Some(n) ->
          if and(valid_name(l), valid_name(i)) then
            if eq(c, "add") then Add(l, i, n) else Remove(l, i, n) end
          else
            Bad
          end
        case None -> Bad
      end
    case _ -> Bad
  end
end

fn parse_move(rest: List[String]) -> Cmd
  match rest
    case [i, q, f, t] ->
      match parse_qty(q)
        case Some(n) ->
          if and(valid_name(i), valid_name(f), valid_name(t), ne(f, t)) then
            Move(i, n, f, t)
          else
            Bad
          end
        case None -> Bad
      end
    case _ -> Bad
  end
end

fn by_cmd(c: String, rest: List[String]) -> Cmd
  if or(eq(c, "add"), eq(c, "remove")) then
    parse_loc_item_qty(c, rest)
  elif eq(c, "move") then
    parse_move(rest)
  elif eq(c, "report") then
    match rest
      case [] -> Report
      case _ -> Bad
    end
  elif eq(c, "total") then
    match rest
      case [i] -> if valid_name(i) then Total(i) else Bad end
      case _ -> Bad
    end
  else
    Bad
  end
end

fn parse(line: String) -> Cmd
  if eq(line, "") then
    Skip
  elif str_starts(line, "#") then
    Skip
  else
    match str_split(line, " ")
      case [c, ..rest] -> by_cmd(c, rest)
      case [] -> Bad
    end
  end
end

fn get_qty(st: List[Entry], l: String, i: String) -> Int
  match st
    case [] -> 0
    case [e, ..rest] ->
      if and(eq(e.loc, l), eq(e.item, i)) then e.qty else get_qty(rest, l, i) end
  end
end

fn set_qty(st: List[Entry], l: String, i: String, q: Int) -> List[Entry]
  let rest = list_filter(st, fn(e) not(and(eq(e.loc, l), eq(e.item, i))) end)
  if gt(q, 0) then list_push(rest, Entry { loc: l, item: i, qty: q }) else rest end
end

fn total_of(st: List[Entry], i: String) -> Int
  list_fold(st, 0, fn(acc, e) if eq(e.item, i) then add(acc, e.qty) else acc end end)
end

fn report_lines(st: List[Entry]) -> List[String]
  let sorted = list_sort_by(st, fn(a, b) or(lt(a.loc, b.loc), and(eq(a.loc, b.loc), lt(a.item, b.item))) end)
  let lines = list_map(sorted, fn(e) str_cat(e.loc, " ", e.item, " ", show(e.qty)) end)
  if eq(list_len(lines), 0) then ["(empty)"] else lines end
end

fn not_enough(n: Int, i: String, l: String) -> String
  str_cat("error: line ", show(n), ": not enough ", i, " at ", l)
end

fn exec(st: List[Entry], cmd: Cmd, n: Int) -> Res
  match cmd
    case Add(l, i, q) ->
      Res { st: set_qty(st, l, i, add(get_qty(st, l, i), q)), lines: [], err: false }
    case Remove(l, i, q) ->
      let have = get_qty(st, l, i)
      if lt(have, q) then
        Res { st: st, lines: [not_enough(n, i, l)], err: true }
      else
        Res { st: set_qty(st, l, i, sub(have, q)), lines: [], err: false }
      end
    case Move(i, q, f, t) ->
      let have = get_qty(st, f, i)
      if lt(have, q) then
        Res { st: st, lines: [not_enough(n, i, f)], err: true }
      else
        let st1 = set_qty(st, f, i, sub(have, q))
        Res { st: set_qty(st1, t, i, add(get_qty(st1, t, i), q)), lines: [], err: false }
      end
    case Report -> Res { st: st, lines: report_lines(st), err: false }
    case Total(i) -> Res { st: st, lines: [str_cat(i, " ", show(total_of(st, i)))], err: false }
    case Skip -> Res { st: st, lines: [], err: false }
    case Bad -> Res { st: st, lines: [str_cat("error: line ", show(n), ": bad command")], err: true }
  end
end

fn print_lines(lines: List[String]) -> Unit ! [io]
  match lines
    case [] -> Unit
    case [l, ..rest] ->
      println(l)
      print_lines(rest)
  end
end

fn run_loop(st: List[Entry], n: Int, err: Bool) -> Bool ! [io]
  match read_line()
    case None -> err
    case Some(line) ->
      let r = exec(st, parse(line), n)
      print_lines(r.lines)
      run_loop(r.st, add(n, 1), or(err, r.err))
  end
end

fn main() -> Unit ! [io]
  let e = run_loop([], 1, false)
  if e then exit(1) else exit(0) end
end

test "parse commands"
  expect_eq(parse("add main apple 5"), Add("main", "apple", 5))
  expect_eq(parse("move apple 3 main shop"), Move("apple", 3, "main", "shop"))
  expect_eq(parse("report"), Report)
  expect_eq(parse("# comment"), Skip)
  expect_eq(parse(""), Skip)
end

test "parse bad commands"
  expect_eq(parse("move apple 3 main main"), Bad)
  expect_eq(parse("add main apple 0"), Bad)
  expect_eq(parse("add main apple -1"), Bad)
  expect_eq(parse("add Main apple 1"), Bad)
  expect_eq(parse("add main  apple 1"), Bad)
  expect_eq(parse("report x"), Bad)
  expect_eq(parse("fly away"), Bad)
end

test "example scenario"
  let r1 = exec([], Add("main", "apple", 5), 1)
  let r2 = exec(r1.st, Add("main", "pear", 2), 2)
  let r3 = exec(r2.st, Move("apple", 3, "main", "shop"), 3)
  let r4 = exec(r3.st, Remove("shop", "apple", 4), 4)
  expect_eq(r4.lines, ["error: line 4: not enough apple at shop"])
  expect_eq(r4.err, true)
  let r5 = exec(r4.st, Total("apple"), 5)
  expect_eq(r5.lines, ["apple 5"])
  let r6 = exec(r5.st, Report, 6)
  expect_eq(r6.lines, ["main apple 2", "main pear 2", "shop apple 3"])
  expect_eq(exec([], Report, 1).lines, ["(empty)"])
end
