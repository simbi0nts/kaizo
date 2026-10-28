  type Entry = { loc: String, item: String, qty: Int } end
  type Outcome = { entries: List[Entry], out: List[String], err: Bool } end
  type Cmd = Add(String, String, Int) | Remove(String, String, Int) | Move(String, Int, String, String) | Report | Total(String) | Skip | Bad end
  
  fn is_name_byte(b: Int) -> Bool
    or(or(and(ge(b, 97), le(b, 122)), and(ge(b, 48), le(b, 57))), eq(b, 95))
  end
  
  fn name_ok_from(s: String, i: Int, n: Int) -> Bool
    if ge(i, n) then true
    elif is_name_byte(str_byte(s, i)) then name_ok_from(s, add(i, 1), n)
    else false end
  end
  
  fn valid_name(s: String) -> Bool
    let n = str_len(s)
    if eq(n, 0) then false else name_ok_from(s, 0, n) end
  end
  
  fn digits_from(s: String, i: Int, n: Int) -> Bool
    if ge(i, n) then true
    else
      let b = str_byte(s, i)
      if and(ge(b, 48), le(b, 57)) then digits_from(s, add(i, 1), n) else false end
    end
  end
  
  fn parse_qty(s: String) -> Option[Int]
    let n = str_len(s)
    if or(eq(n, 0), gt(n, 18)) then None
    elif not(digits_from(s, 0, n)) then None
    else
      match str_to_int(s)
        case Some(v) -> if gt(v, 0) then Some(v) else None end
        case None -> None
      end
    end
  end
  
  fn parse_add(l: String, i: String, q: String) -> Cmd
    match parse_qty(q)
      case Some(n) -> if and(valid_name(l), valid_name(i)) then Add(l, i, n) else Bad end
      case None -> Bad
    end
  end
  
  fn parse_remove(l: String, i: String, q: String) -> Cmd
    match parse_qty(q)
      case Some(n) -> if and(valid_name(l), valid_name(i)) then Remove(l, i, n) else Bad end
      case None -> Bad
    end
  end
  
  fn parse_move(i: String, q: String, f: String, t: String) -> Cmd
    match parse_qty(q)
      case Some(n) ->
        if and(and(valid_name(i), valid_name(f)), and(valid_name(t), ne(f, t))) then Move(i, n, f, t) else Bad end
      case None -> Bad
    end
  end
  
  fn parse_words(ws: List[String]) -> Cmd
    match ws
      case ["add", l, i, q] -> parse_add(l, i, q)
      case ["remove", l, i, q] -> parse_remove(l, i, q)
      case ["move", i, q, f, t] -> parse_move(i, q, f, t)
      case ["report"] -> Report
      case ["total", i] -> if valid_name(i) then Total(i) else Bad end
      case _ -> Bad
    end
  end
  
  fn parse(line: String) -> Cmd
    if eq(line, "") then Skip
    elif str_starts(line, "#") then Skip
    else parse_words(str_split(line, " ")) end
  end
  
  fn get_qty(es: List[Entry], loc: String, item: String) -> Int
    match es
      case [] -> 0
      case [e, ..rest] ->
        if and(eq(e.loc, loc), eq(e.item, item)) then e.qty else get_qty(rest, loc, item) end
    end
  end
  
  fn set_qty(es: List[Entry], loc: String, item: String, q: Int) -> List[Entry]
    let others = list_filter(es, fn(e) not(and(eq(e.loc, loc), eq(e.item, item))) end)
    if gt(q, 0) then list_cons(Entry { loc: loc, item: item, qty: q }, others) else others end
  end
  
  fn not_enough(n: Int, item: String, loc: String) -> String
    str_join(["error: line ", show(n), ": not enough ", item, " at ", loc], "")
  end
  
  fn bad_line(n: Int) -> String
    str_join(["error: line ", show(n), ": bad command"], "")
  end
  
  fn entry_before(a: Entry, b: Entry) -> Bool
    if lt(a.loc, b.loc) then true
    elif eq(a.loc, b.loc) then lt(a.item, b.item)
    else false end
  end
  
  fn entry_line(e: Entry) -> String
    str_join([e.loc, e.item, show(e.qty)], " ")
  end
  
  fn report_lines(es: List[Entry]) -> List[String]
    let nz = list_filter(es, fn(e) gt(e.qty, 0) end)
    if eq(list_len(nz), 0) then ["(empty)"]
    else list_map(list_sort_by(nz, fn(a, b) entry_before(a, b) end), fn(e) entry_line(e) end) end
  end
  
  fn total_of(es: List[Entry], item: String) -> Int
    list_fold(es, 0, fn(acc, e) if eq(e.item, item) then add(acc, e.qty) else acc end end)
  end
  
  fn apply(es: List[Entry], cmd: Cmd, n: Int) -> Outcome
    match cmd
      case Skip -> Outcome { entries: es, out: [], err: false }
      case Bad -> Outcome { entries: es, out: [bad_line(n)], err: true }
      case Add(l, i, q) ->
        Outcome { entries: set_qty(es, l, i, add(get_qty(es, l, i), q)), out: [], err: false }
      case Remove(l, i, q) ->
        let have = get_qty(es, l, i)
        if lt(have, q) then Outcome { entries: es, out: [not_enough(n, i, l)], err: true }
        else Outcome { entries: set_qty(es, l, i, sub(have, q)), out: [], err: false } end
      case Move(i, q, f, t) ->
        let have = get_qty(es, f, i)
        if lt(have, q) then Outcome { entries: es, out: [not_enough(n, i, f)], err: true }
        else
          let es1 = set_qty(es, f, i, sub(have, q))
          let es2 = set_qty(es1, t, i, add(get_qty(es1, t, i), q))
          Outcome { entries: es2, out: [], err: false }
        end
      case Report -> Outcome { entries: es, out: report_lines(es), err: false }
      case Total(i) -> Outcome { entries: es, out: [str_join([i, show(total_of(es, i))], " ")], err: false }
    end
  end
  
  fn print_all(ls: List[String]) -> Unit ! [io]
    match ls
      case [] -> Unit
      case [l, ..rest] ->
        println(l)
        print_all(rest)
    end
  end
  
  fn run(es: List[Entry], n: Int, failed: Bool) -> Bool ! [io]
    match read_line()
      case None -> failed
      case Some(line) ->
        let o = apply(es, parse(line), n)
        print_all(o.out)
        run(o.entries, add(n, 1), or(failed, o.err))
    end
  end
  
  fn main() -> Unit ! [io]
    let failed = run([], 1, false)
    if failed then exit(1) else exit(0) end
  end
  
  test "parse valid and invalid commands"
    expect_eq(parse("add main apple 5"), Add("main", "apple", 5))
    expect_eq(parse("add main apple 0"), Bad)
    expect_eq(parse("add Main apple 5"), Bad)
    expect_eq(parse("add main apple -5"), Bad)
    expect_eq(parse("move apple 3 main main"), Bad)
    expect_eq(parse("move apple 3 main shop"), Move("apple", 3, "main", "shop"))
    expect_eq(parse("# comment"), Skip)
    expect_eq(parse(""), Skip)
    expect_eq(parse("add  main apple 5"), Bad)
    expect_eq(parse("report x"), Bad)
  end
  
  test "remove with too little stock changes nothing"
    let o1 = apply([], Add("main", "apple", 2), 1)
    let o2 = apply(o1.entries, Remove("main", "apple", 3), 2)
    expect_eq(o2.err, true)
    expect_eq(o2.out, ["error: line 2: not enough apple at main"])
    expect_eq(get_qty(o2.entries, "main", "apple"), 2)
  end
  
  test "example script report and total"
    let o1 = apply([], parse("add main apple 5"), 1)
    let o2 = apply(o1.entries, parse("add main pear 2"), 2)
    let o3 = apply(o2.entries, parse("move apple 3 main shop"), 3)
    expect_eq(apply(o3.entries, parse("total apple"), 4).out, ["apple 5"])
    expect_eq(report_lines(o3.entries), ["main apple 2", "main pear 2", "shop apple 3"])
    expect_eq(report_lines([]), ["(empty)"])
  end
  