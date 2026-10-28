type Json = JNull | JBool(Bool) | JInt(String) | JStr(String) | JArr(List[Json]) | JObj(List[Member]) end
type Member = { key: String, val: Json } end
type Parsed = { v: Json, pos: Int } end
type StrP = { text: String, next: Int } end

fn ws(s: String, n: Int, i: Int) -> Int
  if ge(i, n) then i
  else
    let b = str_byte(s, i)
    if or(eq(b, 32), eq(b, 9), eq(b, 10), eq(b, 13)) then ws(s, n, add(i, 1)) else i end
  end
end

fn hexval(b: Int) -> Int
  if and(ge(b, 48), le(b, 57)) then sub(b, 48)
  elif and(ge(b, 97), le(b, 102)) then sub(b, 87)
  elif and(ge(b, 65), le(b, 70)) then sub(b, 55)
  else -1 end
end

fn hexn(s: String, n: Int, i: Int, k: Int, acc: Int) -> Result[Int, Int]
  if eq(k, 4) then Ok(acc)
  elif ge(i, n) then Err(n)
  else
    let v = hexval(str_byte(s, i))
    if lt(v, 0) then Err(i) else hexn(s, n, add(i, 1), add(k, 1), add(mul(acc, 16), v)) end
  end
end

fn hex_digit(d: Int) -> String
  if lt(d, 10) then str_from_bytes([add(48, d)]) else str_from_bytes([add(87, d)]) end
end

fn esc_char(c: Int) -> String
  match c
    case 34 -> "\\\""
    case 92 -> "\\\\"
    case 8 -> "\\b"
    case 12 -> "\\f"
    case 10 -> "\\n"
    case 13 -> "\\r"
    case 9 -> "\\t"
    case _ ->
      if lt(c, 32) then str_cat("\\u00", hex_digit(div(c, 16)), hex_digit(mod(c, 16)))
      else str_from_bytes([c]) end
  end
end

fn simple_esc(c: Int) -> String
  match c
    case 34 -> "\\\""
    case 92 -> "\\\\"
    case 47 -> "/"
    case 98 -> "\\b"
    case 102 -> "\\f"
    case 110 -> "\\n"
    case 114 -> "\\r"
    case 116 -> "\\t"
    case _ -> ""
  end
end

fn pstr(s: String, n: Int, start: Int, j: Int, acc: List[String]) -> Result[StrP, Int]
  if ge(j, n) then Err(n)
  else
    let b = str_byte(s, j)
    if eq(b, 34) then
      Ok(StrP { text: str_join(list_reverse(list_cons(str_slice(s, start, j), acc)), ""), next: add(j, 1) })
    elif and(ge(b, 0), lt(b, 32)) then Err(j)
    elif eq(b, 92) then
      let acc2 = list_cons(str_slice(s, start, j), acc)
      if ge(add(j, 1), n) then Err(n)
      else
        let c = str_byte(s, add(j, 1))
        if eq(c, 117) then
          let h = try hexn(s, n, add(j, 2), 0, 0)
          let piece = if lt(h, 128) then esc_char(h) else str_cat("\\u", str_lower(str_slice(s, add(j, 2), add(j, 6)))) end
          pstr(s, n, add(j, 6), add(j, 6), list_cons(piece, acc2))
        else
          let piece = simple_esc(c)
          if eq(piece, "") then Err(add(j, 1))
          else pstr(s, n, add(j, 2), add(j, 2), list_cons(piece, acc2)) end
        end
      end
    else pstr(s, n, start, add(j, 1), acc) end
  end
end

fn plit(s: String, n: Int, i: Int, lit: String, k: Int, v: Json) -> Result[Parsed, Int]
  if eq(k, str_len(lit)) then Ok(Parsed { v: v, pos: add(i, k) })
  elif ge(add(i, k), n) then Err(n)
  elif ne(str_byte(s, add(i, k)), str_byte(lit, k)) then Err(add(i, k))
  else plit(s, n, i, lit, add(k, 1), v) end
end

fn digits(s: String, n: Int, i: Int) -> Int
  if ge(i, n) then i
  else
    let b = str_byte(s, i)
    if and(ge(b, 48), le(b, 57)) then digits(s, n, add(i, 1)) else i end
  end
end

fn pnum(s: String, n: Int, i: Int) -> Result[Parsed, Int]
  let j = if eq(str_byte(s, i), 45) then add(i, 1) else i end
  if ge(j, n) then Err(n)
  else
    let b = str_byte(s, j)
    if eq(b, 48) then Ok(Parsed { v: JInt(str_slice(s, i, add(j, 1))), pos: add(j, 1) })
    elif and(ge(b, 49), le(b, 57)) then
      let k = digits(s, n, add(j, 1))
      Ok(Parsed { v: JInt(str_slice(s, i, k)), pos: k })
    else Err(j) end
  end
end

fn pval(s: String, n: Int, i0: Int) -> Result[Parsed, Int]
  let i = ws(s, n, i0)
  if ge(i, n) then Err(n)
  else
    let b = str_byte(s, i)
    if eq(b, 123) then pobj(s, n, add(i, 1))
    elif eq(b, 91) then parr(s, n, add(i, 1))
    elif eq(b, 34) then
      let r = try pstr(s, n, add(i, 1), add(i, 1), [])
      Ok(Parsed { v: JStr(r.text), pos: r.next })
    elif eq(b, 116) then plit(s, n, i, "true", 0, JBool(true))
    elif eq(b, 102) then plit(s, n, i, "false", 0, JBool(false))
    elif eq(b, 110) then plit(s, n, i, "null", 0, JNull)
    elif or(eq(b, 45), and(ge(b, 48), le(b, 57))) then pnum(s, n, i)
    else Err(i) end
  end
end

fn parr(s: String, n: Int, i: Int) -> Result[Parsed, Int]
  let j = ws(s, n, i)
  if and(lt(j, n), eq(str_byte(s, j), 93)) then Ok(Parsed { v: JArr([]), pos: add(j, 1) })
  else items(s, n, j, []) end
end

fn items(s: String, n: Int, i: Int, acc: List[Json]) -> Result[Parsed, Int]
  let p = try pval(s, n, i)
  let k = ws(s, n, p.pos)
  if ge(k, n) then Err(n)
  else
    let b = str_byte(s, k)
    if eq(b, 44) then items(s, n, add(k, 1), list_cons(p.v, acc))
    elif eq(b, 93) then Ok(Parsed { v: JArr(list_reverse(list_cons(p.v, acc))), pos: add(k, 1) })
    else Err(k) end
  end
end

fn pobj(s: String, n: Int, i: Int) -> Result[Parsed, Int]
  let j = ws(s, n, i)
  if and(lt(j, n), eq(str_byte(s, j), 125)) then Ok(Parsed { v: JObj([]), pos: add(j, 1) })
  else members(s, n, j, []) end
end

fn members(s: String, n: Int, i: Int, acc: List[Member]) -> Result[Parsed, Int]
  let j = ws(s, n, i)
  if ge(j, n) then Err(n)
  elif ne(str_byte(s, j), 34) then Err(j)
  else
    let kr = try pstr(s, n, add(j, 1), add(j, 1), [])
    let c = ws(s, n, kr.next)
    if ge(c, n) then Err(n)
    elif ne(str_byte(s, c), 58) then Err(c)
    else
      let p = try pval(s, n, add(c, 1))
      let k = ws(s, n, p.pos)
      let m = Member { key: kr.text, val: p.v }
      if ge(k, n) then Err(n)
      else
        let b = str_byte(s, k)
        if eq(b, 44) then members(s, n, add(k, 1), list_cons(m, acc))
        elif eq(b, 125) then Ok(Parsed { v: JObj(list_reverse(list_cons(m, acc))), pos: add(k, 1) })
        else Err(k) end
      end
    end
  end
end

fn emit(v: Json, d: Int, acc: List[String]) -> List[String]
  match v
    case JNull -> list_cons("null", acc)
    case JBool(b) -> list_cons(if b then "true" else "false" end, acc)
    case JInt(t) -> list_cons(t, acc)
    case JStr(t) -> list_cons("\"", list_cons(t, list_cons("\"", acc)))
    case JArr(xs) ->
      match xs
        case [] -> list_cons("[]", acc)
        case _ ->
          let a = emit_items(xs, add(d, 1), list_cons("[\n", acc))
          list_cons("]", list_cons(str_repeat("  ", d), a))
      end
    case JObj(ms) ->
      match ms
        case [] -> list_cons("{}", acc)
        case _ ->
          let a = emit_members(ms, add(d, 1), list_cons("{\n", acc))
          list_cons("}", list_cons(str_repeat("  ", d), a))
      end
  end
end

fn emit_items(xs: List[Json], d: Int, acc: List[String]) -> List[String]
  match xs
    case [] -> acc
    case [x, ..rest] ->
      let a = emit(x, d, list_cons(str_repeat("  ", d), acc))
      let sep = match rest
        case [] -> "\n"
        case _ -> ",\n"
      end
      emit_items(rest, d, list_cons(sep, a))
  end
end

fn emit_members(ms: List[Member], d: Int, acc: List[String]) -> List[String]
  match ms
    case [] -> acc
    case [m, ..rest] ->
      let pre = list_cons("\": ", list_cons(m.key, list_cons("\"", list_cons(str_repeat("  ", d), acc))))
      let a = emit(m.val, d, pre)
      let sep = match rest
        case [] -> "\n"
        case _ -> ",\n"
      end
      emit_members(rest, d, list_cons(sep, a))
  end
end

fn format(s: String) -> Result[String, Int]
  let n = str_len(s)
  let p = try pval(s, n, 0)
  let k = ws(s, n, p.pos)
  if lt(k, n) then Err(k) else Ok(str_join(list_reverse(emit(p.v, 0, [])), "")) end
end

fn lc(s: String, idx: Int, i: Int, line: Int, ls: Int) -> String
  if ge(i, idx) then str_cat("error: line ", show(line), " col ", show(add(sub(idx, ls), 1)))
  elif eq(str_byte(s, i), 10) then lc(s, idx, add(i, 1), add(line, 1), add(i, 1))
  else lc(s, idx, add(i, 1), line, ls) end
end

fn error_msg(s: String, idx: Int) -> String
  lc(s, idx, 0, 1, 0)
end

fn main() -> Unit ! [io]
  let s = read_all()
  match format(s)
    case Ok(out) -> println(out)
    case Err(idx) ->
      println(error_msg(s, idx))
      exit(1)
  end
end

test "pretty prints example"
  expect_eq(format("{\"a\":[1,2,{}],\"b\":\"x\\u0041\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}"))
end

test "trailing comma error position"
  expect_eq(format("[1,]"), Err(3))
  expect_eq(format("[1"), Err(2))
  expect_eq(format(""), Err(0))
  expect_eq(format("01"), Err(1))
end

test "escapes"
  expect_eq(format("\"\\u00E9\\/\\u001f\""), Ok("\"\\u00e9/\\u001f\""))
  expect_eq(format("\"\\x\""), Err(2))
end

test "error message line and col"
  expect_eq(error_msg("a\nbc", 3), "error: line 2 col 2")
  expect_eq(error_msg("ab", 2), "error: line 1 col 3")
end
