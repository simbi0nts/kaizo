# jsonfmt: validate a JSON document from stdin and pretty-print it.

type Json = JNull | JBool(Bool) | JNum(String) | JStr(String) | JArr(List[Json]) | JObj(List[Member]) end
type Member = Mem(String, Json) end
type Parsed = Got(Json, Int) end

fn peek(s: String, p: Int) -> Int
  if ge(p, str_len(s)) then -1 else str_byte(s, p) end
end

fn skip_ws(s: String, p: Int) -> Int
  let c = peek(s, p)
  if or(eq(c, 32), eq(c, 9), eq(c, 10), eq(c, 13)) then skip_ws(s, add(p, 1)) else p end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn skip_digits(s: String, p: Int) -> Int
  if is_digit(peek(s, p)) then skip_digits(s, add(p, 1)) else p end
end

fn hex_val(c: Int) -> Int
  if is_digit(c) then sub(c, 48)
  elif and(ge(c, 97), le(c, 102)) then sub(c, 87)
  elif and(ge(c, 65), le(c, 70)) then sub(c, 55)
  else
    -1
  end
end

fn hex_char(n: Int) -> String
  if lt(n, 10) then str_from_bytes([add(n, 48)]) else str_from_bytes([add(n, 87)]) end
end

fn encode_byte(c: Int) -> String
  if eq(c, 34) then "\\\""
  elif eq(c, 92) then "\\\\"
  elif eq(c, 8) then "\\b"
  elif eq(c, 12) then "\\f"
  elif eq(c, 10) then "\\n"
  elif eq(c, 13) then "\\r"
  elif eq(c, 9) then "\\t"
  elif lt(c, 32) then str_cat("\\u00", hex_char(div(c, 16)), hex_char(mod(c, 16)))
  else str_from_bytes([c])
  end
end

fn unicode_piece(v: Int, hex: String) -> String
  if lt(v, 128) then encode_byte(v) else str_cat("\\u", hex) end
end

fn simple_escape(e: Int) -> Option[String]
  if eq(e, 34) then Some("\\\"")
  elif eq(e, 92) then Some("\\\\")
  elif eq(e, 47) then Some("/")
  elif eq(e, 98) then Some("\\b")
  elif eq(e, 102) then Some("\\f")
  elif eq(e, 110) then Some("\\n")
  elif eq(e, 114) then Some("\\r")
  elif eq(e, 116) then Some("\\t")
  else None
  end
end

fn hex4(s: String, q: Int, left: Int, v: Int) -> Result[Int, Int]
  if eq(left, 0) then Ok(v)
  else hex_step(s, q, left, v, hex_val(peek(s, q)))
  end
end

fn hex_step(s: String, q: Int, left: Int, v: Int, d: Int) -> Result[Int, Int]
  if lt(d, 0) then Err(q) else hex4(s, add(q, 1), sub(left, 1), add(mul(v, 16), d)) end
end

fn scan_unicode(s: String, p: Int, acc: List[String]) -> Result[Parsed, Int]
  let v = try hex4(s, add(p, 2), 4, 0)
  scan_str(s, add(p, 6), list_cons(unicode_piece(v, str_lower(str_slice(s, add(p, 2), add(p, 6)))), acc))
end

fn scan_escape(s: String, p: Int, acc: List[String]) -> Result[Parsed, Int]
  let e = peek(s, add(p, 1))
  if eq(e, 117) then scan_unicode(s, p, acc)
  elif eq(e, -1) then Err(add(p, 1))
  else
    match simple_escape(e)
      case Some(t) -> scan_str(s, add(p, 2), list_cons(t, acc))
      case None -> Err(add(p, 1))
    end
  end
end

fn scan_str(s: String, p: Int, acc: List[String]) -> Result[Parsed, Int]
  let c = peek(s, p)
  if eq(c, -1) then Err(p)
  elif eq(c, 34) then Ok(Got(JStr(str_cat("\"", str_join(list_reverse(acc), ""), "\"")), add(p, 1)))
  elif eq(c, 92) then scan_escape(s, p, acc)
  elif lt(c, 32) then Err(p)
  else scan_str(s, add(p, 1), list_cons(str_slice(s, p, add(p, 1)), acc))
  end
end

fn json_text(j: Json) -> String
  match j
    case JStr(t) -> t
    case _ -> ""
  end
end

fn parse_number(s: String, p: Int) -> Result[Parsed, Int]
  let q = if eq(peek(s, p), 45) then add(p, 1) else p end
  let d = peek(s, q)
  if not(is_digit(d)) then Err(q)
  elif eq(d, 48) then num_result(s, p, add(q, 1))
  else num_result(s, p, skip_digits(s, add(q, 1)))
  end
end

fn num_result(s: String, p: Int, e: Int) -> Result[Parsed, Int]
  Ok(Got(JNum(str_slice(s, p, e)), e))
end

fn match_lit(s: String, p: Int, word: String, i: Int) -> Result[Int, Int]
  if eq(i, str_len(word)) then Ok(p)
  elif eq(peek(s, p), str_byte(word, i)) then match_lit(s, add(p, 1), word, add(i, 1))
  else Err(p)
  end
end

fn lit_at(s: String, p: Int, word: String, value: Json) -> Result[Parsed, Int]
  let q = try match_lit(s, p, word, 0)
  Ok(Got(value, q))
end

fn parse_value(s: String, p0: Int) -> Result[Parsed, Int]
  let p = skip_ws(s, p0)
  let c = peek(s, p)
  if eq(c, -1) then Err(p)
  elif eq(c, 123) then parse_object(s, add(p, 1))
  elif eq(c, 91) then parse_array(s, add(p, 1))
  elif eq(c, 34) then scan_str(s, add(p, 1), [])
  elif eq(c, 116) then lit_at(s, p, "true", JBool(true))
  elif eq(c, 102) then lit_at(s, p, "false", JBool(false))
  elif eq(c, 110) then lit_at(s, p, "null", JNull)
  elif or(eq(c, 45), is_digit(c)) then parse_number(s, p)
  else Err(p)
  end
end

fn parse_array(s: String, p: Int) -> Result[Parsed, Int]
  let q = skip_ws(s, p)
  if eq(peek(s, q), 93) then Ok(Got(JArr([]), add(q, 1)))
  else parse_elems(s, q, [])
  end
end

fn parse_elems(s: String, p: Int, acc: List[Json]) -> Result[Parsed, Int]
  let st = try parse_value(s, p)
  match st
    case Got(v, q) ->
      let r = skip_ws(s, q)
      if eq(peek(s, r), 44) then parse_elems(s, add(r, 1), list_cons(v, acc))
      elif eq(peek(s, r), 93) then Ok(Got(JArr(list_reverse(list_cons(v, acc))), add(r, 1)))
      else Err(r)
      end
  end
end

fn parse_object(s: String, p: Int) -> Result[Parsed, Int]
  let q = skip_ws(s, p)
  if eq(peek(s, q), 125) then Ok(Got(JObj([]), add(q, 1)))
  else parse_members(s, q, [])
  end
end

fn parse_members(s: String, p: Int, acc: List[Member]) -> Result[Parsed, Int]
  let q = skip_ws(s, p)
  if eq(peek(s, q), 34) then parse_member(s, add(q, 1), acc)
  else Err(q)
  end
end

fn parse_member(s: String, p: Int, acc: List[Member]) -> Result[Parsed, Int]
  let kst = try scan_str(s, p, [])
  match kst
    case Got(kj, q) ->
      let r = skip_ws(s, q)
      if eq(peek(s, r), 58) then parse_member_value(s, add(r, 1), json_text(kj), acc)
      else Err(r)
      end
  end
end

fn parse_member_value(s: String, p: Int, key: String, acc: List[Member]) -> Result[Parsed, Int]
  let st = try parse_value(s, p)
  match st
    case Got(v, q) ->
      let r = skip_ws(s, q)
      let acc2 = list_cons(Mem(key, v), acc)
      if eq(peek(s, r), 44) then parse_members(s, add(r, 1), acc2)
      elif eq(peek(s, r), 125) then Ok(Got(JObj(list_reverse(acc2)), add(r, 1)))
      else Err(r)
      end
  end
end

fn parse_doc(s: String) -> Result[Json, Int]
  let st = try parse_value(s, 0)
  match st
    case Got(v, q) ->
      let r = skip_ws(s, q)
      if eq(peek(s, r), -1) then Ok(v) else Err(r) end
  end
end

fn pad(n: Int) -> String
  str_repeat(" ", n)
end

fn render_member(m: Member, ind: Int) -> String
  match m
    case Mem(k, x) -> str_cat(pad(ind), k, ": ", render_val(x, ind))
  end
end

fn render_val(v: Json, ind: Int) -> String
  match v
    case JNull -> "null"
    case JBool(b) -> if b then "true" else "false" end
    case JNum(t) -> t
    case JStr(t) -> t
    case JArr(items) ->
      if eq(list_len(items), 0) then "[]"
      else str_cat("[\n", str_join(list_map(items, fn(x) str_cat(pad(add(ind, 2)), render_val(x, add(ind, 2))) end), ",\n"), "\n", pad(ind), "]")
      end
    case JObj(ms) ->
      if eq(list_len(ms), 0) then "{}"
      else str_cat("{\n", str_join(list_map(ms, fn(m) render_member(m, add(ind, 2)) end), ",\n"), "\n", pad(ind), "}")
      end
  end
end

fn format_doc(text: String) -> Result[String, Int]
  let v = try parse_doc(text)
  Ok(render_val(v, 0))
end

fn err_text(s: String, i: Int, pos: Int, line: Int, last: Int) -> String
  if ge(i, pos) then str_cat("error: line ", show(line), " col ", show(sub(pos, last)))
  elif eq(str_byte(s, i), 10) then err_text(s, add(i, 1), pos, add(line, 1), i)
  else err_text(s, add(i, 1), pos, line, last)
  end
end

fn error_text(text: String) -> String
  match format_doc(text)
    case Ok(out) -> out
    case Err(p) -> err_text(text, 0, p, 1, -1)
  end
end

fn main() -> Unit ! [io]
  let text = read_all()
  match format_doc(text)
    case Ok(out) -> println(out)
    case Err(p) ->
      println(err_text(text, 0, p, 1, -1))
      exit(1)
  end
end

test "nested object pretty print"
  expect_eq(format_doc("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}"))
end

test "scalars and escapes"
  expect_eq(format_doc("[null,true,-0,\"a\\u0041\\/\"]"), Ok("[\n  null,\n  true,\n  -0,\n  \"aA/\"\n]"))
end

test "control character escape"
  expect_eq(format_doc("\"\\u0001\""), Ok("\"\\u0001\""))
end

test "error on line 2"
  expect_eq(error_text("[1,\n]"), "error: line 2 col 1")
end

test "error at unexpected end"
  expect_eq(error_text("[1,2"), "error: line 1 col 5")
end

test "error on missing colon"
  expect_eq(error_text("{\"a\" 1}"), "error: line 1 col 6")
end
