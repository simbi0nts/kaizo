# jsonfmt: validate JSON from stdin and pretty-print it

type Json = JNull | JTrue | JFalse | JNum(String) | JStr(String) | JArr(List[Json]) | JObj(List[Member]) end
type Member = { key: String, value: Json } end
type PR = { v: Json, next: Int } end
type SR = { text: String, after: Int } end

fn is_ws(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 10), eq(c, 13))
end

fn skip_ws(s: String, i: Int, n: Int) -> Int
  if ge(i, n) then
    i
  elif is_ws(str_byte(s, i)) then
    skip_ws(s, add(i, 1), n)
  else
    i
  end
end

fn hexval(c: Int) -> Int
  if and(ge(c, 48), le(c, 57)) then
    sub(c, 48)
  elif and(ge(c, 97), le(c, 102)) then
    add(sub(c, 97), 10)
  elif and(ge(c, 65), le(c, 70)) then
    add(sub(c, 65), 10)
  else
    -1
  end
end

fn hex2(c: Int) -> String
  let h = "0123456789abcdef"
  let hi = div(c, 16)
  let lo = mod(c, 16)
  str_cat(str_slice(h, hi, add(hi, 1)), str_slice(h, lo, add(lo, 1)))
end

fn escape_char(c: Int) -> String
  if eq(c, 34) then
    "\\\""
  elif eq(c, 92) then
    "\\\\"
  elif eq(c, 8) then
    "\\b"
  elif eq(c, 12) then
    "\\f"
  elif eq(c, 10) then
    "\\n"
  elif eq(c, 13) then
    "\\r"
  elif eq(c, 9) then
    "\\t"
  elif lt(c, 32) then
    str_cat("\\u00", hex2(c))
  else
    str_from_bytes([c])
  end
end

fn esc_simple(e: Int) -> Option[String]
  if eq(e, 34) then
    Some("\\\"")
  elif eq(e, 92) then
    Some("\\\\")
  elif eq(e, 47) then
    Some("/")
  elif eq(e, 98) then
    Some("\\b")
  elif eq(e, 102) then
    Some("\\f")
  elif eq(e, 110) then
    Some("\\n")
  elif eq(e, 114) then
    Some("\\r")
  elif eq(e, 116) then
    Some("\\t")
  else
    None
  end
end

fn hex4(s: String, p: Int, n: Int, cnt: Int, acc: Int) -> Result[Int, Int]
  if eq(cnt, 4) then
    Ok(acc)
  elif ge(p, n) then
    Err(n)
  else
    let h = hexval(str_byte(s, p))
    if lt(h, 0) then
      Err(p)
    else
      hex4(s, add(p, 1), n, add(cnt, 1), add(mul(acc, 16), h))
    end
  end
end

fn scan_run(s: String, k: Int, n: Int) -> Int
  if ge(k, n) then
    k
  else
    let c = str_byte(s, k)
    if or(eq(c, 34), eq(c, 92), lt(c, 32)) then
      k
    else
      scan_run(s, add(k, 1), n)
    end
  end
end

fn parse_str(s: String, k: Int, n: Int, acc: List[String]) -> Result[SR, Int]
  if ge(k, n) then
    Err(n)
  else
    let c = str_byte(s, k)
    if eq(c, 34) then
      Ok(SR { text: str_join(list_reverse(acc), ""), after: add(k, 1) })
    elif lt(c, 32) then
      Err(k)
    elif eq(c, 92) then
      if ge(add(k, 1), n) then
        Err(n)
      else
        let e = str_byte(s, add(k, 1))
        match esc_simple(e)
          case Some(t) -> parse_str(s, add(k, 2), n, list_cons(t, acc))
          case None ->
            if eq(e, 117) then
              let v = try hex4(s, add(k, 2), n, 0, 0)
              let piece = if lt(v, 128) then escape_char(v) else str_cat("\\u", str_lower(str_slice(s, add(k, 2), add(k, 6)))) end
              parse_str(s, add(k, 6), n, list_cons(piece, acc))
            else
              Err(add(k, 1))
            end
        end
      end
    else
      let e = scan_run(s, k, n)
      parse_str(s, e, n, list_cons(str_slice(s, k, e), acc))
    end
  end
end

fn lit_match(s: String, j: Int, n: Int, lit: String, k: Int) -> Result[Int, Int]
  if eq(k, str_len(lit)) then
    Ok(add(j, k))
  elif ge(add(j, k), n) then
    Err(n)
  elif ne(str_byte(s, add(j, k)), str_byte(lit, k)) then
    Err(add(j, k))
  else
    lit_match(s, j, n, lit, add(k, 1))
  end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn scan_digits(s: String, k: Int, n: Int) -> Int
  if ge(k, n) then
    k
  elif is_digit(str_byte(s, k)) then
    scan_digits(s, add(k, 1), n)
  else
    k
  end
end

fn parse_num(s: String, j: Int, n: Int) -> Result[PR, Int]
  let k = if eq(str_byte(s, j), 45) then add(j, 1) else j end
  if ge(k, n) then
    Err(n)
  else
    let c = str_byte(s, k)
    if eq(c, 48) then
      Ok(PR { v: JNum(str_slice(s, j, add(k, 1))), next: add(k, 1) })
    elif is_digit(c) then
      let e = scan_digits(s, k, n)
      Ok(PR { v: JNum(str_slice(s, j, e)), next: e })
    else
      Err(k)
    end
  end
end

fn parse_lit(s: String, j: Int, n: Int, lit: String, v: Json) -> Result[PR, Int]
  let e = try lit_match(s, j, n, lit, 0)
  Ok(PR { v: v, next: e })
end

fn parse_value(s: String, i: Int, n: Int) -> Result[PR, Int]
  let j = skip_ws(s, i, n)
  if ge(j, n) then
    Err(n)
  else
    let c = str_byte(s, j)
    if eq(c, 123) then
      parse_obj(s, j, n)
    elif eq(c, 91) then
      parse_arr(s, j, n)
    elif eq(c, 34) then
      let r = try parse_str(s, add(j, 1), n, [])
      Ok(PR { v: JStr(r.text), next: r.after })
    elif eq(c, 116) then
      parse_lit(s, j, n, "true", JTrue)
    elif eq(c, 102) then
      parse_lit(s, j, n, "false", JFalse)
    elif eq(c, 110) then
      parse_lit(s, j, n, "null", JNull)
    elif or(eq(c, 45), is_digit(c)) then
      parse_num(s, j, n)
    else
      Err(j)
    end
  end
end

fn parse_arr(s: String, j: Int, n: Int) -> Result[PR, Int]
  let k = skip_ws(s, add(j, 1), n)
  if ge(k, n) then
    Err(n)
  elif eq(str_byte(s, k), 93) then
    Ok(PR { v: JArr([]), next: add(k, 1) })
  else
    parse_elems(s, k, n, [])
  end
end

fn parse_elems(s: String, k: Int, n: Int, acc: List[Json]) -> Result[PR, Int]
  let r = try parse_value(s, k, n)
  let m = skip_ws(s, r.next, n)
  if ge(m, n) then
    Err(n)
  else
    let c = str_byte(s, m)
    if eq(c, 44) then
      parse_elems(s, add(m, 1), n, list_cons(r.v, acc))
    elif eq(c, 93) then
      Ok(PR { v: JArr(list_reverse(list_cons(r.v, acc))), next: add(m, 1) })
    else
      Err(m)
    end
  end
end

fn parse_obj(s: String, j: Int, n: Int) -> Result[PR, Int]
  let k = skip_ws(s, add(j, 1), n)
  if ge(k, n) then
    Err(n)
  elif eq(str_byte(s, k), 125) then
    Ok(PR { v: JObj([]), next: add(k, 1) })
  else
    parse_members(s, k, n, [])
  end
end

fn parse_members(s: String, k: Int, n: Int, acc: List[Member]) -> Result[PR, Int]
  let k2 = skip_ws(s, k, n)
  if ge(k2, n) then
    Err(n)
  elif ne(str_byte(s, k2), 34) then
    Err(k2)
  else
    let sr = try parse_str(s, add(k2, 1), n, [])
    let m = skip_ws(s, sr.after, n)
    if ge(m, n) then
      Err(n)
    elif ne(str_byte(s, m), 58) then
      Err(m)
    else
      let r = try parse_value(s, add(m, 1), n)
      let m2 = skip_ws(s, r.next, n)
      let mem = Member { key: sr.text, value: r.v }
      if ge(m2, n) then
        Err(n)
      else
        let c = str_byte(s, m2)
        if eq(c, 44) then
          parse_members(s, add(m2, 1), n, list_cons(mem, acc))
        elif eq(c, 125) then
          Ok(PR { v: JObj(list_reverse(list_cons(mem, acc))), next: add(m2, 1) })
        else
          Err(m2)
        end
      end
    end
  end
end

fn parse_doc(s: String) -> Result[Json, Int]
  let n = str_len(s)
  let r = try parse_value(s, 0, n)
  let m = skip_ws(s, r.next, n)
  if lt(m, n) then
    Err(m)
  else
    Ok(r.v)
  end
end

fn render(v: Json, ind: Int, acc: List[String]) -> List[String]
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
          let a = render_items(items, add(ind, 1), list_cons("[\n", acc))
          list_cons("]", list_cons(str_repeat("  ", ind), a))
      end
    case JObj(ms) ->
      match ms
        case [] -> list_cons("{}", acc)
        case _ ->
          let a = render_members(ms, add(ind, 1), list_cons("{\n", acc))
          list_cons("}", list_cons(str_repeat("  ", ind), a))
      end
  end
end

fn sep_for(rest_empty: Bool) -> String
  if rest_empty then "\n" else ",\n" end
end

fn render_items(items: List[Json], ind: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [x, ..rest] ->
      let a = render(x, ind, list_cons(str_repeat("  ", ind), acc))
      render_items(rest, ind, list_cons(sep_for(eq(list_len(rest), 0)), a))
  end
end

fn render_members(ms: List[Member], ind: Int, acc: List[String]) -> List[String]
  match ms
    case [] -> acc
    case [m, ..rest] ->
      let pre = list_cons("\": ", list_cons(m.key, list_cons("\"", list_cons(str_repeat("  ", ind), acc))))
      let a = render(m.value, ind, pre)
      render_members(rest, ind, list_cons(sep_for(eq(list_len(rest), 0)), a))
  end
end

fn line_col(s: String, i: Int, p: Int, line: Int, col: Int) -> String
  if ge(i, p) then
    str_cat("line ", show(line), " col ", show(col))
  elif eq(str_byte(s, i), 10) then
    line_col(s, add(i, 1), p, add(line, 1), 1)
  else
    line_col(s, add(i, 1), p, line, add(col, 1))
  end
end

fn format_json(s: String) -> String
  match parse_doc(s)
    case Ok(v) -> str_cat(str_join(list_reverse(render(v, 0, [])), ""), "\n")
    case Err(p) -> str_cat("error: ", line_col(s, 0, p, 1, 1))
  end
end

fn main() -> Unit ! [io]
  let s = read_all()
  match parse_doc(s)
    case Ok(v) -> print(str_cat(str_join(list_reverse(render(v, 0, [])), ""), "\n"))
    case Err(p) ->
      println(str_cat("error: ", line_col(s, 0, p, 1, 1)))
      exit(1)
  end
end

test "example document"
  expect_eq(format_json("{\"a\":[1,2,{}],\"b\":\"x\\u0041\\n\"}"), "{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n")
end

test "scalars and escapes"
  expect_eq(format_json("  -12 "), "-12\n")
  expect_eq(format_json("\"a\\/b\\u00E9\\u001F\""), "\"a/b\\u00e9\\u001f\"\n")
  expect_eq(format_json("[]"), "[]\n")
end

test "errors"
  expect_eq(format_json(""), "error: line 1 col 1")
  expect_eq(format_json("[1,\n 2,]"), "error: line 2 col 4")
  expect_eq(format_json("[1"), "error: line 1 col 3")
  expect_eq(format_json("01"), "error: line 1 col 2")
  expect_eq(format_json("{\"a\" 1}"), "error: line 1 col 6")
end
