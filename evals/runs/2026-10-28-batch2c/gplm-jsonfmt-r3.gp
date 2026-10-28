# jsonfmt: validate and pretty-print a JSON document from stdin

type Json = JNull | JTrue | JFalse | JNum(String) | JStr(String) | JArr(List[Json]) | JObj(List[Member]) end
type Member = { mk: String, mv: Json } end
type PV = { pv: Json, pp: Int } end
type PS = { ps: String, psp: Int } end

fn at(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then str_byte(s, i) else -1 end
end

fn is_ws(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 10), eq(c, 13))
end

fn skip_ws(s: String, i: Int) -> Int
  if is_ws(at(s, i)) then skip_ws(s, add(i, 1)) else i end
end

fn digits(s: String, i: Int) -> Int
  let c = at(s, i)
  if and(ge(c, 48), le(c, 57)) then digits(s, add(i, 1)) else i end
end

fn hexv(c: Int) -> Int
  if and(ge(c, 48), le(c, 57)) then sub(c, 48)
  elif and(ge(c, 65), le(c, 70)) then sub(c, 55)
  elif and(ge(c, 97), le(c, 102)) then sub(c, 87)
  else -1 end
end

fn hexch(d: Int) -> String
  str_slice("0123456789abcdef", d, add(d, 1))
end

fn esc_byte(v: Int) -> String
  if eq(v, 34) then "\\\""
  elif eq(v, 92) then "\\\\"
  elif eq(v, 8) then "\\b"
  elif eq(v, 12) then "\\f"
  elif eq(v, 10) then "\\n"
  elif eq(v, 13) then "\\r"
  elif eq(v, 9) then "\\t"
  elif lt(v, 32) then str_cat("\\u00", hexch(div(v, 16)), hexch(mod(v, 16)))
  else str_from_bytes([v]) end
end

fn simple_esc(e: Int) -> String
  if eq(e, 34) then "\\\""
  elif eq(e, 92) then "\\\\"
  elif eq(e, 47) then "/"
  elif eq(e, 98) then "\\b"
  elif eq(e, 102) then "\\f"
  elif eq(e, 110) then "\\n"
  elif eq(e, 114) then "\\r"
  elif eq(e, 116) then "\\t"
  else "" end
end

fn hex4(s: String, i: Int, k: Int, acc: Int) -> Result[Int, Int]
  if eq(k, 4) then Ok(acc) else
    let h = hexv(at(s, add(i, k)))
    if lt(h, 0) then Err(add(i, k)) else hex4(s, i, add(k, 1), add(mul(acc, 16), h)) end
  end
end

fn parse_str(s: String, i: Int, run: Int, acc: List[String]) -> Result[PS, Int]
  let c = at(s, i)
  if lt(c, 0) then Err(i)
  elif eq(c, 34) then
    let parts = list_reverse(list_cons(str_slice(s, run, i), acc))
    Ok(PS { ps: str_join(parts, ""), psp: add(i, 1) })
  elif lt(c, 32) then Err(i)
  elif eq(c, 92) then
    let acc1 = list_cons(str_slice(s, run, i), acc)
    let e = at(s, add(i, 1))
    if eq(e, 117) then
      match hex4(s, add(i, 2), 0, 0)
        case Err(p) -> Err(p)
        case Ok(v) ->
          let piece = if lt(v, 128) then esc_byte(v) else str_cat("\\u", str_lower(str_slice(s, add(i, 2), add(i, 6)))) end
          parse_str(s, add(i, 6), add(i, 6), list_cons(piece, acc1))
      end
    else
      let piece = simple_esc(e)
      if eq(piece, "") then Err(add(i, 1)) else parse_str(s, add(i, 2), add(i, 2), list_cons(piece, acc1)) end
    end
  else parse_str(s, add(i, 1), run, acc) end
end

fn lit(s: String, j: Int, word: String, k: Int, v: Json) -> Result[PV, Int]
  if eq(k, str_len(word)) then Ok(PV { pv: v, pp: add(j, k) })
  elif eq(at(s, add(j, k)), str_byte(word, k)) then lit(s, j, word, add(k, 1), v)
  else Err(add(j, k)) end
end

fn parse_num(s: String, j: Int) -> Result[PV, Int]
  let k = if eq(at(s, j), 45) then add(j, 1) else j end
  let c = at(s, k)
  if eq(c, 48) then Ok(PV { pv: JNum(str_slice(s, j, add(k, 1))), pp: add(k, 1) })
  elif and(ge(c, 49), le(c, 57)) then
    let e = digits(s, add(k, 1))
    Ok(PV { pv: JNum(str_slice(s, j, e)), pp: e })
  else Err(k) end
end

fn parse_value(s: String, i: Int) -> Result[PV, Int]
  let j = skip_ws(s, i)
  let c = at(s, j)
  if eq(c, 123) then parse_obj(s, add(j, 1))
  elif eq(c, 91) then parse_arr(s, add(j, 1))
  elif eq(c, 34) then
    match parse_str(s, add(j, 1), add(j, 1), [])
      case Err(p) -> Err(p)
      case Ok(r) -> Ok(PV { pv: JStr(r.ps), pp: r.psp })
    end
  elif eq(c, 116) then lit(s, j, "true", 0, JTrue)
  elif eq(c, 102) then lit(s, j, "false", 0, JFalse)
  elif eq(c, 110) then lit(s, j, "null", 0, JNull)
  elif or(eq(c, 45), and(ge(c, 48), le(c, 57))) then parse_num(s, j)
  else Err(j) end
end

fn parse_arr(s: String, i: Int) -> Result[PV, Int]
  let j = skip_ws(s, i)
  if eq(at(s, j), 93) then Ok(PV { pv: JArr([]), pp: add(j, 1) }) else parse_elems(s, j, []) end
end

fn parse_elems(s: String, j: Int, acc: List[Json]) -> Result[PV, Int]
  let r = try parse_value(s, j)
  let k = skip_ws(s, r.pp)
  let c = at(s, k)
  let acc2 = list_cons(r.pv, acc)
  if eq(c, 44) then parse_elems(s, add(k, 1), acc2)
  elif eq(c, 93) then Ok(PV { pv: JArr(list_reverse(acc2)), pp: add(k, 1) })
  else Err(k) end
end

fn parse_obj(s: String, i: Int) -> Result[PV, Int]
  let j = skip_ws(s, i)
  if eq(at(s, j), 125) then Ok(PV { pv: JObj([]), pp: add(j, 1) }) else parse_members(s, j, []) end
end

fn parse_members(s: String, j0: Int, acc: List[Member]) -> Result[PV, Int]
  let j = skip_ws(s, j0)
  if ne(at(s, j), 34) then Err(j) else
    match parse_str(s, add(j, 1), add(j, 1), [])
      case Err(p) -> Err(p)
      case Ok(ks) ->
        let k = skip_ws(s, ks.psp)
        if ne(at(s, k), 58) then Err(k) else
          let r = try parse_value(s, add(k, 1))
          let m = skip_ws(s, r.pp)
          let c = at(s, m)
          let acc2 = list_cons(Member { mk: ks.ps, mv: r.pv }, acc)
          if eq(c, 44) then parse_members(s, add(m, 1), acc2)
          elif eq(c, 125) then Ok(PV { pv: JObj(list_reverse(acc2)), pp: add(m, 1) })
          else Err(m) end
        end
    end
  end
end

fn parse_doc(s: String) -> Result[Json, Int]
  match parse_value(s, 0)
    case Err(p) -> Err(p)
    case Ok(r) ->
      let e = skip_ws(s, r.pp)
      if lt(e, str_len(s)) then Err(e) else Ok(r.pv) end
  end
end

fn pad(n: Int) -> String
  str_repeat("  ", n)
end

fn emit(v: Json, ind: Int, acc: List[String]) -> List[String]
  match v
    case JNull -> list_cons("null", acc)
    case JTrue -> list_cons("true", acc)
    case JFalse -> list_cons("false", acc)
    case JNum(t) -> list_cons(t, acc)
    case JStr(t) -> list_cons("\"", list_cons(t, list_cons("\"", acc)))
    case JArr(items) ->
      match items
        case [] -> list_cons("[]", acc)
        case _ ->
          let a = emit_items(items, add(ind, 1), list_cons("[\n", acc))
          list_cons("]", list_cons(pad(ind), a))
      end
    case JObj(members) ->
      match members
        case [] -> list_cons("{}", acc)
        case _ ->
          let a = emit_members(members, add(ind, 1), list_cons("{\n", acc))
          list_cons("}", list_cons(pad(ind), a))
      end
  end
end

fn emit_items(items: List[Json], ind: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [x, ..rest] ->
      let a1 = emit(x, ind, list_cons(pad(ind), acc))
      let sep = match rest
        case [] -> "\n"
        case _ -> ",\n"
      end
      emit_items(rest, ind, list_cons(sep, a1))
  end
end

fn emit_members(members: List[Member], ind: Int, acc: List[String]) -> List[String]
  match members
    case [] -> acc
    case [m, ..rest] ->
      let a0 = list_cons("\": ", list_cons(m.mk, list_cons("\"", list_cons(pad(ind), acc))))
      let a1 = emit(m.mv, ind, a0)
      let sep = match rest
        case [] -> "\n"
        case _ -> ",\n"
      end
      emit_members(rest, ind, list_cons(sep, a1))
  end
end

fn render(v: Json) -> String
  str_join(list_reverse(list_cons("\n", emit(v, 0, []))), "")
end

fn lc(s: String, i: Int, target: Int, line: Int, col: Int) -> String
  if ge(i, target) then str_cat("error: line ", show(line), " col ", show(col))
  elif eq(str_byte(s, i), 10) then lc(s, add(i, 1), target, add(line, 1), 1)
  else lc(s, add(i, 1), target, line, add(col, 1)) end
end

fn err_msg(s: String, off: Int) -> String
  lc(s, 0, off, 1, 1)
end

fn format(s: String) -> String
  match parse_doc(s)
    case Ok(v) -> render(v)
    case Err(off) -> err_msg(s, off)
  end
end

fn main() -> Unit ! [io]
  let s = read_all()
  match parse_doc(s)
    case Ok(v) -> print(render(v))
    case Err(off) ->
      println(err_msg(s, off))
      exit(1)
  end
end

test "spec example"
  expect_eq(format("{\"a\":[1,2,{}],\"b\":\"x\\u0041\\n\"}"), "{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n")
end

test "scalars and escapes"
  expect_eq(format(" -0 "), "-0\n")
  expect_eq(format("[]"), "[]\n")
  expect_eq(format("\"\\/\\u00e9\\u001F\\u0022\""), "\"/\\u00e9\\u001f\\\"\"\n")
  expect_eq(esc_byte(1), "\\u0001")
end

test "error positions"
  expect_eq(format(""), "error: line 1 col 1")
  expect_eq(format("[1,]"), "error: line 1 col 4")
  expect_eq(format("{\n  \"a\" 1}"), "error: line 2 col 7")
  expect_eq(format("[tru"), "error: line 1 col 5")
  expect_eq(format("01"), "error: line 1 col 2")
  expect_eq(format("\"\\u12g4\""), "error: line 1 col 6")
end
