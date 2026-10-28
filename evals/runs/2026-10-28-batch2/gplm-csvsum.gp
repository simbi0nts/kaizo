  # csvsum: group and sum a CSV file read from standard input
  
  type Rec = { fields: List[String], nxt: Int, good: Bool } end
  type Pair = { g: String, v: Int } end
  
  fn byte_at(s: String, n: Int, i: Int) -> Int
    if lt(i, n) then str_byte(s, i) else -1 end
  end
  
  fn done(acc: List[String], nxt: Int) -> Rec
    Rec { fields: list_reverse(acc), nxt: nxt, good: true }
  end
  
  fn bad_rec() -> Rec
    Rec { fields: [], nxt: 0, good: false }
  end
  
  # Parse one field starting at pos, then the rest of the record.
  fn parse_field(s: String, n: Int, pos: Int, acc: List[String]) -> Rec
    if eq(byte_at(s, n, pos), 34) then
      scan_quoted(s, n, add(pos, 1), add(pos, 1), [], acc)
    else
      scan_unquoted(s, n, pos, pos, acc)
    end
  end
  
  fn scan_unquoted(s: String, n: Int, start: Int, i: Int, acc: List[String]) -> Rec
    if ge(i, n) then
      done(list_cons(str_slice(s, start, i), acc), i)
    else
      let b = str_byte(s, i)
      if eq(b, 44) then
        parse_field(s, n, add(i, 1), list_cons(str_slice(s, start, i), acc))
      elif eq(b, 10) then
        done(list_cons(str_slice(s, start, i), acc), add(i, 1))
      elif eq(b, 34) then
        bad_rec()
      else
        scan_unquoted(s, n, start, add(i, 1), acc)
      end
    end
  end
  
  fn scan_quoted(s: String, n: Int, start: Int, i: Int, pieces: List[String], acc: List[String]) -> Rec
    if ge(i, n) then
      bad_rec()
    else
      let b = str_byte(s, i)
      if eq(b, 34) then
        if eq(byte_at(s, n, add(i, 1)), 34) then
          scan_quoted(s, n, add(i, 2), add(i, 2), list_cons(str_slice(s, start, add(i, 1)), pieces), acc)
        else
          let field = str_join(list_reverse(list_cons(str_slice(s, start, i), pieces)), "")
          let c = byte_at(s, n, add(i, 1))
          if eq(c, 44) then
            parse_field(s, n, add(i, 2), list_cons(field, acc))
          elif eq(c, 10) then
            done(list_cons(field, acc), add(i, 2))
          elif eq(c, -1) then
            done(list_cons(field, acc), add(i, 1))
          else
            bad_rec()
          end
        end
      else
        scan_quoted(s, n, start, add(i, 1), pieces, acc)
      end
    end
  end
  
  fn all_digits(s: String, i: Int, n: Int) -> Bool
    if ge(i, n) then
      true
    else
      let b = str_byte(s, i)
      if and(ge(b, 48), le(b, 57)) then all_digits(s, add(i, 1), n) else false end
    end
  end
  
  fn parse_int(s: String) -> Option[Int]
    let len = str_len(s)
    let start = if eq(len, 0) then 0 elif eq(str_byte(s, 0), 45) then 1 else 0 end
    if ge(start, len) then
      None
    elif all_digits(s, start, len) then
      str_to_int(s)
    else
      None
    end
  end
  
  fn index_of(l: List[String], x: String, i: Int) -> Option[Int]
    match l
      case [] -> None
      case [h, ..rest] -> if eq(h, x) then Some(i) else index_of(rest, x, add(i, 1)) end
    end
  end
  
  fn process(s: String, n: Int, pos: Int, recno: Int, ncols: Int, gi: Int, si: Int, acc: List[Pair]) -> Result[List[Pair], Int]
    if ge(pos, n) then
      Ok(acc)
    else
      let r = parse_field(s, n, pos, [])
      if not(r.good) then
        Err(recno)
      elif ne(list_len(r.fields), ncols) then
        Err(recno)
      else
        match parse_int(unwrap_or(list_get(r.fields, si), "x"))
          case None -> Err(recno)
          case Some(v) ->
            let p = Pair { g: unwrap_or(list_get(r.fields, gi), ""), v: v }
            process(s, n, r.nxt, add(recno, 1), ncols, gi, si, list_cons(p, acc))
        end
      end
    end
  end
  
  fn quote_group(g: String) -> String
    if or(is_some(str_find(g, ",")), or(is_some(str_find(g, "\"")), is_some(str_find(g, "\n")))) then
      str_cat("\"", str_cat(str_join(str_split(g, "\""), "\"\""), "\""))
    else
      g
    end
  end
  
  fn fmt_line(g: String, t: Int) -> String
    str_cat(quote_group(g), str_cat(",", show(t)))
  end
  
  fn emit(ps: List[Pair], cur: String, total: Int, out: List[String]) -> List[String]
    match ps
      case [] -> list_reverse(list_cons(fmt_line(cur, total), out))
      case [p, ..rest] ->
        if eq(p.g, cur) then
          emit(rest, cur, add(total, p.v), out)
        else
          emit(rest, p.g, p.v, list_cons(fmt_line(cur, total), out))
        end
    end
  end
  
  fn summarize(ps: List[Pair]) -> List[String]
    let sorted = list_sort_by(ps, fn(a, b) lt(a.g, b.g) end)
    match sorted
      case [] -> []
      case [p, ..rest] -> emit(rest, p.g, p.v, [])
    end
  end
  
  # text: the whole input, each line followed by "\n"
  fn compute(text: String, gname: String, sname: String) -> Result[List[String], String]
    let n = str_len(text)
    let h = parse_field(text, n, 0, [])
    if not(h.good) then
      Err("error: record 1")
    else
      match index_of(h.fields, gname, 0)
        case None -> Err(str_cat("error: no column ", gname))
        case Some(gi) ->
          match index_of(h.fields, sname, 0)
            case None -> Err(str_cat("error: no column ", sname))
            case Some(si) ->
              match process(text, n, h.nxt, 2, list_len(h.fields), gi, si, [])
                case Err(k) -> Err(str_cat("error: record ", show(k)))
                case Ok(ps) -> Ok(summarize(ps))
              end
          end
      end
    end
  end
  
  fn read_all(acc: List[String]) -> List[String] ! [io]
    match read_line()
      case None -> list_reverse(acc)
      case Some(l) -> read_all(list_cons(l, acc))
    end
  end
  
  fn main() -> Unit ! [io]
    let a = args()
    if ne(list_len(a), 2) then
      println("usage: csvsum <group-column> <sum-column>")
      exit(2)
    else
      let lines = read_all([])
      if eq(list_len(lines), 0) then
        println("error: no header")
        exit(1)
      else
        let text = str_cat(str_join(lines, "\n"), "\n")
        match compute(text, unwrap_or(list_get(a, 0), ""), unwrap_or(list_get(a, 1), ""))
          case Err(msg) ->
            println(msg)
            exit(1)
          case Ok(out) ->
            if eq(list_len(out), 0) then Unit else print(str_cat(str_join(out, "\n"), "\n")) end
        end
      end
    end
  end
  
  test "example from spec"
    let input = "city,amount,note\nOslo,10,first\n\"Rome, IT\",5,\"says \"\"hi\"\"\"\nOslo,-3,\n"
    expect_eq(compute(input, "city", "amount"), Ok(["Oslo,7", "\"Rome, IT\",5"]))
  end
  
  test "bad integer is a bad record"
    expect_eq(compute("a,b\nx,1\ny,1.5\n", "a", "b"), Err("error: record 3"))
  end
  
  test "unclosed quote is a bad record"
    expect_eq(compute("a,b\nx,1\ny,\"1\n", "a", "b"), Err("error: record 3"))
  end
  
  test "missing column, group checked first"
    expect_eq(compute("a,b\n", "zz", "yy"), Err("error: no column zz"))
  end
  
  test "wrong field count"
    expect_eq(compute("a,b\nx,1,2\n", "a", "b"), Err("error: record 2"))
  end
  
  test "header only prints nothing"
    expect_eq(compute("a,b\n", "a", "b"), Ok([]))
  end
  
  test "quoting of group values"
    expect_eq(quote_group("a\"b"), "\"a\"\"b\"")
    expect_eq(quote_group("x\ny"), "\"x\ny\"")
    expect_eq(quote_group("plain"), "plain")
  end
  
  test "parse_int"
    expect_eq(parse_int("-12"), Some(-12))
    expect_eq(parse_int("-"), None)
    expect_eq(parse_int("+3"), None)
    expect_eq(parse_int(""), None)
  end
  