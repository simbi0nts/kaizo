# jsonfmt: validate a JSON document from stdin and pretty-print it

type Json = JRaw(String) | JStr(String) | JArr(List[Json]) | JObj(List[Member]) end
type Member = { key: String, value: Json } end
type PR = { v: Json, pos: Int } end
type SR = { text: String, next: Int } end

fn at(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then str_byte(s, i) else -1 end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn ws(s: String, i: Int) -> Int
  let c = at(s, i)
  if or(or(eq(c, 32), eq(c, 9)), or(eq(c, 10), eq(c, 13))) then ws(s, add(i, 1)) else i end
end

fn hexd(c: Int) -> Int
  if is_digit(c) then sub(c, 48)
  elif and(ge(c, 97), le(c, 102)) then sub(c, 87)
  elif and(ge(c, 65), le(c, 70)) then sub(c, 55)
  else -1
  end
end

fn hex4(s: String, i: Int, k: Int, v: Int) -> Result[Int, Int]
  if eq(k, 4) then Ok(v)
  else
    let d = hexd(at(s, i))
    if lt(d, 0) then Err(i) else hex4(s, add(i, 1), add(k, 1), add(mul(v, 16), d)) end
  end
end

fn hexdigit(d: Int) -> String
  str_slice("0123456789abcdef", d, add(d, 1))
end

fn esc_char(v: Int) -> String
  match v
    case 34 -> "\\\""
    case 92 -> "\\\\"
    case 8 -> "\\b"
    case 12 -> "\\f"
    case 10 -> "\\n"
    case 13 -> "\\r"
    case 9 -> "\\t"
    case _ ->
      if lt(v, 32) then str_cat("\\u00", str_cat(hexdigit(div(v, 16)), hexdigit(mod(v, 16))))
      else str_from_bytes([v])
      end
  end
end

fn uesc(s: String, i: Int, v: Int) -> String
  if lt(v, 128) then esc_char(v) else str_cat("\\u", str_lower(str_slice(s, i, add(i, 4)))) end
end

fn simple_esc(e: Int) -> Option[String]
  match e
    case 34 -> Some("\\\"")
    case 92 -> Some("\\\\")
    case 47 -> Some("/")
    case 98 -> Some("\\b")
    case 102 -> Some("\\f")
    case 110 -> Some("\\n")
    case 114 -> Some("\\r")
    case 116 -> Some("\\t")
    case _ -> None
  end
end

fn pstr(s: String, i: Int, start: Int, acc: List[String]) -> Result[SR, Int]
  let c = at(s, i)
  if lt(c, 0) then Err(i)
  elif eq(c, 34) then
    let parts = list_reverse(list_cons(str_slice(s, start, i), acc))
    Ok(SR { text: str_join(parts, ""), next: add(i, 1) })
  elif eq(c, 92) then
    let acc2 = list_cons(str_slice(s, start, i), acc)
    let e = at(s, add(i, 1))
    if eq(e, 117) then
      match hex4(s, add(i, 2), 0, 0)
        case Err(p) -> Err(p)
        case Ok(v) -> pstr(s, add(i, 6), add(i, 6), list_cons(uesc(s, add(i, 2), v), acc2))
      end
    else
      match simple_esc(e)
        case None -> Err(add(i, 1))
        case Some(t) -> pstr(s, add(i, 2), add(i, 2), list_cons(t, acc2))
      end
    end
  elif lt(c, 32) then Err(i)
  else pstr(s, add(i, 1), start, acc)
  end
end

fn lit_loop(s: String, i: Int, word: String, k: Int) -> Result[Int, Int]
  if eq(k, str_len(word)) then Ok(add(i, k))
  elif eq(at(s, add(i, k)), str_byte(word, k)) then lit_loop(s, i, word, add(k, 1))
  else Err(add(i, k))
  end
end

fn plit(s: String, i: Int, word: String) -> Result[PR, Int]
  match lit_loop(s, i, word, 0)
    case Err(p) -> Err(p)
    case Ok(e) -> Ok(PR { v: JRaw(word), pos: e })
  end
end

fn digits(s: String, i: Int) -> Int
  if is_digit(at(s, i)) then digits(s, add(i, 1)) else i end
end

fn pnum(s: String, i: Int) -> Result[PR, Int]
  let j = if eq(at(s, i), 45) then add(i, 1) else i end
  let c = at(s, j)
  if eq(c, 48) then Ok(PR { v: JRaw(str_slice(s, i, add(j, 1))), pos: add(j, 1) })
  elif is_digit(c) then
    let e = digits(s, add(j, 1))
    Ok(PR { v: JRaw(str_slice(s, i, e)), pos: e })
  else Err(j)
  end
end

fn parr(s: String, i: Int) -> Result[PR, Int]
  let j = ws(s, i)
  if eq(at(s, j), 93) then Ok(PR { v: JArr([]), pos: add(j, 1) })
  else parr_items(s, j, [])
  end
end

fn parr_items(s: String, i: Int, acc: List[Json]) -> Result[PR, Int]
  match pval(s, i)
    case Err(p) -> Err(p)
    case Ok(r) ->
      let j = ws(s, r.pos)
      let c = at(s, j)
      if eq(c, 44) then parr_items(s, ws(s, add(j, 1)), list_cons(r.v, acc))
      elif eq(c, 93) then Ok(PR { v: JArr(list_reverse(list_cons(r.v, acc))), pos: add(j, 1) })
      else Err(j)
      end
  end
end

fn pobj(s: String, i: Int) -> Result[PR, Int]
  let j = ws(s, i)
  if eq(at(s, j), 125) then Ok(PR { v: JObj([]), pos: add(j, 1) })
  else pmembers(s, j, [])
  end
end

fn pmembers(s: String, i: Int, acc: List[Member]) -> Result[PR, Int]
  if ne(at(s, i), 34) then Err(i)
  else
    match pstr(s, add(i, 1), add(i, 1), [])
      case Err(p) -> Err(p)
      case Ok(k) ->
        let j = ws(s, k.next)
        if ne(at(s, j), 58) then Err(j)
        else
          match pval(s, ws(s, add(j, 1)))
            case Err(p) -> Err(p)
            case Ok(r) ->
              let m = Member { key: k.text, value: r.v }
              let q = ws(s, r.pos)
              let c = at(s, q)
              if eq(c, 44) then pmembers(s, ws(s, add(q, 1)), list_cons(m, acc))
              elif eq(c, 125) then Ok(PR { v: JObj(list_reverse(list_cons(m, acc))), pos: add(q, 1) })
              else Err(q)
              end
          end
        end
    end
  end
end

fn pval(s: String, i: Int) -> Result[PR, Int]
  let c = at(s, i)
  if eq(c, 123) then pobj(s, add(i, 1))
  elif eq(c, 91) then parr(s, add(i, 1))
  elif eq(c, 34) then
    match pstr(s, add(i, 1), add(i, 1), [])
      case Err(p) -> Err(p)
      case Ok(r) -> Ok(PR { v: JStr(r.text), pos: r.next })
    end
  elif eq(c, 116) then plit(s, i, "true")
  elif eq(c, 102) then plit(s, i, "false")
  elif eq(c, 110) then plit(s, i, "null")
  elif or(eq(c, 45), is_digit(c)) then pnum(s, i)
  else Err(i)
  end
end

fn pad(n: Int) -> String
  str_repeat(" ", n)
end

fn emit(v: Json, ind: Int, acc: List[String]) -> List[String]
  match v
    case JRaw(t) -> list_cons(t, acc)
    case JStr(t) -> list_cons("\"", list_cons(t, list_cons("\"", acc)))
    case JArr(items) ->
      match items
        case [] -> list_cons("[]", acc)
        case _ ->
          let a = emit_items(items, add(ind, 2), list_cons("[\n", acc))
          list_cons("]", list_cons(pad(ind), a))
      end
    case JObj(ms) ->
      match ms
        case [] -> list_cons("{}", acc)
        case _ ->
          let a = emit_members(ms, add(ind, 2), list_cons("{\n", acc))
          list_cons("}", list_cons(pad(ind), a))
      end
  end
end

fn emit_items(items: List[Json], ind: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [x, ..rest] ->
      let a = emit(x, ind, list_cons(pad(ind), acc))
      match rest
        case [] -> list_cons("\n", a)
        case _ -> emit_items(rest, ind, list_cons(",\n", a))
      end
  end
end

fn emit_members(ms: List[Member], ind: Int, acc: List[String]) -> List[String]
  match ms
    case [] -> acc
    case [m, ..rest] ->
      let pre = list_cons("\": ", list_cons(m.key, list_cons("\"", list_cons(pad(ind), acc))))
      let a = emit(m.value, ind, pre)
      match rest
        case [] -> list_cons("\n", a)
        case _ -> emit_members(rest, ind, list_cons(",\n", a))
      end
  end
end

fn parse_doc(s: String) -> Result[String, Int]
  let i = ws(s, 0)
  match pval(s, i)
    case Err(p) -> Err(p)
    case Ok(r) ->
      let j = ws(s, r.pos)
      if lt(j, str_len(s)) then Err(j)
      else Ok(str_join(list_reverse(list_cons("\n", emit(r.v, 0, []))), ""))
      end
  end
end

fn lc(s: String, i: Int, pos: Int, line: Int, col: Int) -> String
  if ge(i, pos) then str_cat("line ", str_cat(show(line), str_cat(" col ", show(col))))
  elif eq(str_byte(s, i), 10) then lc(s, add(i, 1), pos, add(line, 1), 1)
  else lc(s, add(i, 1), pos, line, add(col, 1))
  end
end

fn line_col(s: String, pos: Int) -> String
  lc(s, 0, pos, 1, 1)
end

fn read_all(acc: List[String]) -> String ! [io]
  match read_line()
    case None -> str_join(list_reverse(acc), "")
    case Some(l) ->
      let line = if str_ends(l, "\n") then l else str_cat(l, "\n") end
      read_all(list_cons(line, acc))
  end
end

fn main() -> Unit ! [io]
  let src = read_all([])
  match parse_doc(src)
    case Ok(out) -> print(out)
    case Err(p) ->
      println(str_cat("error: ", line_col(src, p)))
      exit(1)
  end
end

test "example pretty print"
  expect_eq(parse_doc("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n"))
end

test "error positions"
  expect_eq(parse_doc("[1,]"), Err(3))
  expect_eq(parse_doc("[1,2"), Err(4))
  expect_eq(parse_doc("01"), Err(1))
  expect_eq(parse_doc("\"\\x\""), Err(2))
  expect_eq(line_col("a\nbc", 3), "line 2 col 2")
end

test "string escapes"
  expect_eq(esc_char(31), "\\u001f")
  expect_eq(esc_char(65), "A")
  expect_eq(parse_doc("\"\\u0041\\u00E9\\/\""), Ok("\"A\\u00e9/\"\n"))
end
