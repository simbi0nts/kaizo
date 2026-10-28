# jsonfmt: validate a JSON document from stdin and pretty-print it (2-space indent).
# On invalid input prints "error: line L col C" and exits 1.

type Json = JNull | JBool(Bool) | JNum(String) | JStr(String) | JArr(List[Json]) | JObj(List[Json]) | JMember(String, Json) end
type Step = { jv: Json, jat: Int } end
type StrRes = { txt: String, tat: Int } end

# ---------- scanning helpers ----------

fn peek(s: String, i: Int) -> Int
  if ge(i, str_len(s)) then -1 else str_byte(s, i) end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn hex_val(c: Int) -> Int
  if and(ge(c, 48), le(c, 57)) then sub(c, 48)
  elif and(ge(c, 97), le(c, 102)) then sub(c, 87)
  elif and(ge(c, 65), le(c, 70)) then sub(c, 55)
  else -1 end
end

fn skip_ws(s: String, i: Int) -> Int
  let c = peek(s, i)
  if or(eq(c, 32), eq(c, 9), eq(c, 10), eq(c, 13)) then skip_ws(s, add(i, 1)) else i end
end

# -1 when lit matches at i, else the index of the first character that differs
# (or the end of input).
fn lit_check(s: String, i: Int, lit: String, k: Int) -> Int
  if ge(k, str_len(lit)) then -1
  elif ge(add(i, k), str_len(s)) then str_len(s)
  elif eq(str_byte(s, add(i, k)), str_byte(lit, k)) then lit_check(s, i, lit, add(k, 1))
  else add(i, k) end
end

# -1 when the 4 characters at i..i+3 are all hex digits, else the index of the first bad one
fn first_bad_hex(s: String, i: Int, k: Int) -> Int
  if ge(k, 4) then -1
  elif lt(hex_val(peek(s, add(i, k))), 0) then add(i, k)
  else first_bad_hex(s, i, add(k, 1)) end
end

fn hex4(s: String, i: Int, k: Int, acc: Int) -> Int
  if ge(k, 4) then acc
  else hex4(s, i, add(k, 1), add(mul(acc, 16), hex_val(peek(s, add(i, k))))) end
end

fn digits_end(s: String, j: Int) -> Int
  if is_digit(peek(s, j)) then digits_end(s, add(j, 1)) else j end
end

# ---------- string escapes ----------

fn hex_digit(n: Int) -> String
  if lt(n, 10) then str_from_bytes([add(n, 48)]) else str_from_bytes([add(n, 87)]) end
end

fn hex4_text(v: Int) -> String
  str_cat(hex_digit(div(v, 4096)), hex_digit(mod(div(v, 256), 16)), hex_digit(mod(div(v, 16), 16)), hex_digit(mod(v, 16)))
end

# output (escaped) form of one byte value
fn esc_byte(b: Int) -> String
  if eq(b, 34) then "\\\""
  elif eq(b, 92) then "\\\\"
  elif eq(b, 8) then "\\b"
  elif eq(b, 12) then "\\f"
  elif eq(b, 10) then "\\n"
  elif eq(b, 13) then "\\r"
  elif eq(b, 9) then "\\t"
  elif lt(b, 32) then str_cat("\\u00", hex_digit(div(b, 16)), hex_digit(mod(b, 16)))
  else str_from_bytes([b]) end
end

fn simple_byte(e: Int) -> Int
  if eq(e, 34) then 34
  elif eq(e, 92) then 92
  elif eq(e, 98) then 8
  elif eq(e, 102) then 12
  elif eq(e, 110) then 10
  elif eq(e, 114) then 13
  elif eq(e, 116) then 9
  else -1 end
end

# acc holds output chunks in reverse order
fn str_loop(s: String, i: Int, acc: List[String]) -> Result[StrRes, Int]
  let c = peek(s, i)
  if lt(c, 0) then Err(i)
  elif eq(c, 34) then Ok(StrRes { txt: str_join(list_reverse(acc), ""), tat: add(i, 1) })
  elif eq(c, 92) then str_escape(s, i, acc)
  elif lt(c, 32) then Err(i)
  else str_loop(s, add(i, 1), list_cons(str_from_bytes([c]), acc)) end
end

fn str_escape(s: String, i: Int, acc: List[String]) -> Result[StrRes, Int]
  let e = peek(s, add(i, 1))
  if lt(e, 0) then Err(add(i, 1))
  elif eq(e, 117) then unicode_escape(s, i, acc)
  elif eq(e, 47) then str_loop(s, add(i, 2), list_cons("/", acc))
  else simple_escape(s, i, acc, e) end
end

fn simple_escape(s: String, i: Int, acc: List[String], e: Int) -> Result[StrRes, Int]
  let b = simple_byte(e)
  if lt(b, 0) then Err(add(i, 1))
  else str_loop(s, add(i, 2), list_cons(esc_byte(b), acc)) end
end

fn unicode_escape(s: String, i: Int, acc: List[String]) -> Result[StrRes, Int]
  let bad = first_bad_hex(s, add(i, 2), 0)
  if ge(bad, 0) then Err(bad)
  else unicode_push(s, i, acc, hex4(s, add(i, 2), 0, 0)) end
end

fn unicode_push(s: String, i: Int, acc: List[String], v: Int) -> Result[StrRes, Int]
  let piece = if lt(v, 128) then esc_byte(v) else str_cat("\\u", hex4_text(v)) end
  str_loop(s, add(i, 6), list_cons(piece, acc))
end

fn parse_string(s: String, i: Int) -> Result[StrRes, Int]
  str_loop(s, i, [])
end

# ---------- values ----------

fn literal(s: String, i: Int, lit: String, v: Json) -> Result[Step, Int]
  let bad = lit_check(s, i, lit, 0)
  if ge(bad, 0) then Err(bad) else Ok(Step { jv: v, jat: add(i, str_len(lit)) }) end
end

fn number_rest(s: String, i: Int, j: Int) -> Result[Step, Int]
  let e = digits_end(s, j)
  Ok(Step { jv: JNum(str_slice(s, i, e)), jat: e })
end

fn number_value(s: String, i: Int) -> Result[Step, Int]
  let j = if eq(peek(s, i), 45) then add(i, 1) else i end
  let c = peek(s, j)
  if eq(c, 48) then Ok(Step { jv: JNum(str_slice(s, i, add(j, 1))), jat: add(j, 1) })
  elif is_digit(c) then number_rest(s, i, j)
  else Err(j) end
end

fn string_value(s: String, i: Int) -> Result[Step, Int]
  let t = try parse_string(s, add(i, 1))
  Ok(Step { jv: JStr(t.txt), jat: t.tat })
end

fn parse_value(s: String, i0: Int) -> Result[Step, Int]
  let i = skip_ws(s, i0)
  let c = peek(s, i)
  if lt(c, 0) then Err(i)
  elif eq(c, 123) then parse_object(s, add(i, 1))
  elif eq(c, 91) then parse_array(s, add(i, 1))
  elif eq(c, 34) then string_value(s, i)
  elif eq(c, 116) then literal(s, i, "true", JBool(true))
  elif eq(c, 102) then literal(s, i, "false", JBool(false))
  elif eq(c, 110) then literal(s, i, "null", JNull)
  elif or(eq(c, 45), is_digit(c)) then number_value(s, i)
  else Err(i) end
end

# i is just after '['
fn parse_array(s: String, i: Int) -> Result[Step, Int]
  let j = skip_ws(s, i)
  if eq(peek(s, j), 93) then Ok(Step { jv: JArr([]), jat: add(j, 1) })
  else parse_elems(s, j, []) end
end

fn parse_elems(s: String, i: Int, acc: List[Json]) -> Result[Step, Int]
  let st = try parse_value(s, i)
  let k = skip_ws(s, st.jat)
  let c = peek(s, k)
  if eq(c, 44) then parse_elems(s, add(k, 1), list_cons(st.jv, acc))
  elif eq(c, 93) then Ok(Step { jv: JArr(list_reverse(list_cons(st.jv, acc))), jat: add(k, 1) })
  else Err(k) end
end

# i is just after '{'
fn parse_object(s: String, i: Int) -> Result[Step, Int]
  let j = skip_ws(s, i)
  if eq(peek(s, j), 125) then Ok(Step { jv: JObj([]), jat: add(j, 1) })
  else parse_members(s, j, []) end
end

fn member_key(s: String, k: Int) -> Result[StrRes, Int]
  if eq(peek(s, k), 34) then parse_string(s, add(k, 1)) else Err(k) end
end

fn expect_colon(s: String, ci: Int) -> Result[Step, Int]
  if eq(peek(s, ci), 58) then parse_value(s, add(ci, 1)) else Err(ci) end
end

fn parse_member(s: String, i: Int) -> Result[Step, Int]
  let k = skip_ws(s, i)
  let key = try member_key(s, k)
  let ci = skip_ws(s, key.tat)
  let v = try expect_colon(s, ci)
  Ok(Step { jv: JMember(key.txt, v.jv), jat: v.jat })
end

fn parse_members(s: String, i: Int, acc: List[Json]) -> Result[Step, Int]
  let m = try parse_member(s, i)
  let k = skip_ws(s, m.jat)
  let c = peek(s, k)
  if eq(c, 44) then parse_members(s, add(k, 1), list_cons(m.jv, acc))
  elif eq(c, 125) then Ok(Step { jv: JObj(list_reverse(list_cons(m.jv, acc))), jat: add(k, 1) })
  else Err(k) end
end

fn parse_doc(s: String) -> Result[Json, Int]
  let st = try parse_value(s, 0)
  let e = skip_ws(s, st.jat)
  if lt(peek(s, e), 0) then Ok(st.jv) else Err(e) end
end

# ---------- output ----------

fn pad(n: Int) -> String
  str_repeat("  ", n)
end

fn render_items(items: List[Json], d: Int, lo: String, hi: String) -> String
  match items
    case [] -> str_cat(lo, hi)
    case _ -> str_cat(lo, "\n", str_join(list_map(items, fn(x) str_cat(pad(add(d, 1)), render(x, add(d, 1))) end), ",\n"), "\n", pad(d), hi)
  end
end

fn render(v: Json, d: Int) -> String
  match v
    case JNull -> "null"
    case JBool(b) -> if b then "true" else "false" end
    case JNum(t) -> t
    case JStr(t) -> str_cat("\"", t, "\"")
    case JArr(items) -> render_items(items, d, "[", "]")
    case JObj(items) -> render_items(items, d, "{", "}")
    case JMember(k, x) -> str_cat("\"", k, "\": ", render(x, d))
  end
end

# ---------- error position ----------

# line = 1 + number of '\n' before stop; col = stop - (index of last '\n' before stop), or stop + 1
fn scan_pos(s: String, i: Int, stop: Int, line: Int, nl: Int) -> String
  if ge(i, stop) then str_cat("error: line ", show(line), " col ", show(sub(stop, nl)))
  elif eq(str_byte(s, i), 10) then scan_pos(s, add(i, 1), stop, add(line, 1), i)
  else scan_pos(s, add(i, 1), stop, line, nl) end
end

fn error_message(s: String, idx: Int) -> String
  scan_pos(s, 0, idx, 1, -1)
end

# ---------- driver ----------

fn run_doc(s: String) -> Result[String, String]
  match parse_doc(s)
    case Ok(v) -> Ok(str_cat(render(v, 0), "\n"))
    case Err(i) -> Err(error_message(s, i))
  end
end

fn fail_with(msg: String) -> Unit ! [io]
  print(str_cat(msg, "\n"))
  exit(1)
end

fn main() -> Unit ! [io]
  let s = read_all()
  match run_doc(s)
    case Ok(text) -> print(text)
    case Err(msg) -> fail_with(msg)
  end
end

# ---------- tests ----------

test "pretty prints the example"
  expect_eq(run_doc("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n"))
end

test "error line and column"
  expect_eq(run_doc("{\n  \"a\": x\n}"), Err("error: line 2 col 8"))
end

test "unexpected end of input"
  expect_eq(run_doc("[1,"), Err("error: line 1 col 4"))
end

test "unicode escapes"
  expect_eq(run_doc("[\"\\u0041\\u00e9\\u0022\"]"), Ok("[\n  \"A\\u00e9\\\"\"\n]\n"))
end
