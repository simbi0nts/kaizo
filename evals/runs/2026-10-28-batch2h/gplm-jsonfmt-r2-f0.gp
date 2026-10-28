# jsonfmt: validate a JSON document from stdin and pretty-print it (2-space indent).
# Errors print "error: line L col C" and exit 1.

type JValue = JNull | JBool(Bool) | JNum(String) | JStr(String) | JArr(List[JValue]) | JObj(List[JValue]) | JPair(String, JValue) end
type Step = Step(JValue, Int) end
type Sv = Sv(String, Int) end

# ---------- scanning helpers (offsets are 0-based bytes) ----------

fn byte_at(s: String, i: Int) -> Int
  if ge(i, str_len(s)) then -1 else str_byte(s, i) end
end

fn is_ws(c: Int) -> Bool
  or(eq(c, 32), eq(c, 9), eq(c, 10), eq(c, 13))
end

fn skip_ws(s: String, i: Int) -> Int
  if is_ws(byte_at(s, i)) then skip_ws(s, add(i, 1)) else i end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_digit_nz(c: Int) -> Bool
  and(ge(c, 49), le(c, 57))
end

fn digits_end(s: String, k: Int) -> Int
  if is_digit(byte_at(s, k)) then digits_end(s, add(k, 1)) else k end
end

fn hex_val(c: Int) -> Int
  if is_digit(c) then sub(c, 48)
  elif and(ge(c, 97), le(c, 102)) then sub(c, 87)
  elif and(ge(c, 65), le(c, 70)) then sub(c, 55)
  else sub(0, 1) end
end

# offset of the first non-hex byte in [p, stop), or -1 if all are hex
fn hex_bad(s: String, p: Int, stop: Int) -> Int
  if ge(p, stop) then -1
  elif lt(hex_val(byte_at(s, p)), 0) then p
  else hex_bad(s, add(p, 1), stop) end
end

# value of 4 hex digits at p (caller checked they are valid)
fn hex_num(s: String, p: Int) -> Int
  let h0 = hex_val(byte_at(s, p))
  let h1 = hex_val(byte_at(s, add(p, 1)))
  let h2 = hex_val(byte_at(s, add(p, 2)))
  let h3 = hex_val(byte_at(s, add(p, 3)))
  add(mul(add(mul(add(mul(h0, 16), h1), 16), h2), 16), h3)
end

# compares w with s at i; -1 when it matches, else the offset of the first mismatch
fn match_word(s: String, i: Int, w: String, k: Int) -> Int
  if ge(k, str_len(w)) then -1
  elif ne(byte_at(s, add(i, k)), str_byte(w, k)) then add(i, k)
  else match_word(s, i, w, add(k, 1)) end
end

fn parse_lit(s: String, i: Int, w: String, v: JValue) -> Result[Step, Int]
  let bad = match_word(s, i, w, 0)
  if lt(bad, 0) then Ok(Step(v, add(i, str_len(w)))) else Err(bad) end
end

# ---------- numbers ----------

fn number_done(s: String, i: Int, e: Int) -> Result[Step, Int]
  Ok(Step(JNum(str_slice(s, i, e)), e))
end

fn parse_number(s: String, i: Int) -> Result[Step, Int]
  let j = if eq(byte_at(s, i), 45) then add(i, 1) else i end
  let c = byte_at(s, j)
  if eq(c, 48) then number_done(s, i, add(j, 1))
  elif is_digit_nz(c) then number_done(s, i, digits_end(s, add(j, 1)))
  else Err(j) end
end

# ---------- strings (body kept in re-escaped output form) ----------

# first offset >= k that is '"', '\', a control byte, or end of input
fn plain_end(s: String, k: Int) -> Int
  let c = byte_at(s, k)
  if or(eq(c, -1), eq(c, 34), eq(c, 92), lt(c, 32)) then k else plain_end(s, add(k, 1)) end
end

fn ctl_esc(v: Int) -> String
  str_cat("\\u00", hexdig(div(v, 16)), hexdig(mod(v, 16)))
end

fn hexdig(n: Int) -> String
  if lt(n, 10) then str_from_bytes([add(48, n)]) else str_from_bytes([add(87, n)]) end
end

fn hex4_esc(v: Int) -> String
  str_cat("\\u", hexdig(div(v, 4096)), hexdig(mod(div(v, 256), 16)), hexdig(mod(div(v, 16), 16)), hexdig(mod(v, 16)))
end

# output form of a decoded character with value v < 0x80
fn esc_char(v: Int) -> String
  if eq(v, 34) then "\\\""
  elif eq(v, 92) then "\\\\"
  elif eq(v, 8) then "\\b"
  elif eq(v, 12) then "\\f"
  elif eq(v, 10) then "\\n"
  elif eq(v, 13) then "\\r"
  elif eq(v, 9) then "\\t"
  elif lt(v, 32) then ctl_esc(v)
  else str_from_bytes([v]) end
end

# output form of a simple escape letter (c is the byte after the backslash); "" if invalid
fn simple_esc(c: Int) -> String
  if eq(c, 34) then "\\\""
  elif eq(c, 92) then "\\\\"
  elif eq(c, 47) then "/"
  elif eq(c, 98) then "\\b"
  elif eq(c, 102) then "\\f"
  elif eq(c, 110) then "\\n"
  elif eq(c, 114) then "\\r"
  elif eq(c, 116) then "\\t"
  else "" end
end

fn str_body(s: String, k: Int, acc: List[String]) -> Result[Sv, Int]
  let c = byte_at(s, k)
  if eq(c, -1) then Err(k)
  elif eq(c, 34) then Ok(Sv(str_join(list_reverse(acc), ""), add(k, 1)))
  elif eq(c, 92) then str_escape(s, k, acc)
  elif lt(c, 32) then Err(k)
  else str_plain(s, k, acc) end
end

fn str_plain(s: String, k: Int, acc: List[String]) -> Result[Sv, Int]
  let e = plain_end(s, k)
  str_body(s, e, list_cons(str_slice(s, k, e), acc))
end

fn str_escape(s: String, k: Int, acc: List[String]) -> Result[Sv, Int]
  let c = byte_at(s, add(k, 1))
  if eq(c, 117) then uni_escape(s, k, acc)
  else str_simple(s, k, acc, simple_esc(c)) end
end

fn str_simple(s: String, k: Int, acc: List[String], out: String) -> Result[Sv, Int]
  if eq(str_len(out), 0) then Err(add(k, 1))
  else str_body(s, add(k, 2), list_cons(out, acc)) end
end

fn uni_escape(s: String, k: Int, acc: List[String]) -> Result[Sv, Int]
  let bad = hex_bad(s, add(k, 2), add(k, 6))
  if ge(bad, 0) then Err(bad)
  else uni_emit(s, k, acc, hex_num(s, add(k, 2))) end
end

fn uni_emit(s: String, k: Int, acc: List[String], v: Int) -> Result[Sv, Int]
  if lt(v, 128) then str_body(s, add(k, 6), list_cons(esc_char(v), acc))
  else str_body(s, add(k, 6), list_cons(hex4_esc(v), acc)) end
end

# i is the offset of the opening quote
fn str_lit(s: String, i: Int) -> Result[Sv, Int]
  str_body(s, add(i, 1), [])
end

# ---------- values ----------

fn parse_value(s: String, i0: Int) -> Result[Step, Int]
  let i = skip_ws(s, i0)
  let c = byte_at(s, i)
  if eq(c, -1) then Err(i)
  elif eq(c, 110) then parse_lit(s, i, "null", JNull)
  elif eq(c, 116) then parse_lit(s, i, "true", JBool(true))
  elif eq(c, 102) then parse_lit(s, i, "false", JBool(false))
  elif eq(c, 34) then parse_string(s, i)
  elif eq(c, 91) then parse_array(s, add(i, 1))
  elif eq(c, 123) then parse_object(s, add(i, 1))
  elif or(eq(c, 45), is_digit(c)) then parse_number(s, i)
  else Err(i) end
end

fn parse_string(s: String, i: Int) -> Result[Step, Int]
  let r = try str_lit(s, i)
  match r
    case Sv(body, j) -> Ok(Step(JStr(body), j))
  end
end

fn parse_array(s: String, i: Int) -> Result[Step, Int]
  let j = skip_ws(s, i)
  if eq(byte_at(s, j), 93) then Ok(Step(JArr([]), add(j, 1)))
  else array_items(s, j, []) end
end

fn array_items(s: String, i: Int, acc: List[JValue]) -> Result[Step, Int]
  let st = try parse_value(s, i)
  match st
    case Step(v, j) -> array_after(s, j, list_cons(v, acc))
  end
end

fn array_after(s: String, i: Int, acc: List[JValue]) -> Result[Step, Int]
  let j = skip_ws(s, i)
  let c = byte_at(s, j)
  if eq(c, 44) then array_items(s, add(j, 1), acc)
  elif eq(c, 93) then Ok(Step(JArr(list_reverse(acc)), add(j, 1)))
  else Err(j) end
end

fn parse_object(s: String, i: Int) -> Result[Step, Int]
  let j = skip_ws(s, i)
  if eq(byte_at(s, j), 125) then Ok(Step(JObj([]), add(j, 1)))
  else member_items(s, j, []) end
end

fn member_items(s: String, i: Int, acc: List[JValue]) -> Result[Step, Int]
  let j = skip_ws(s, i)
  if eq(byte_at(s, j), 34) then member_key(s, j, acc) else Err(j) end
end

fn member_key(s: String, i: Int, acc: List[JValue]) -> Result[Step, Int]
  let kv = try str_lit(s, i)
  match kv
    case Sv(key, k) -> member_colon(s, k, key, acc)
  end
end

fn member_colon(s: String, i: Int, key: String, acc: List[JValue]) -> Result[Step, Int]
  let j = skip_ws(s, i)
  if eq(byte_at(s, j), 58) then member_value(s, add(j, 1), key, acc) else Err(j) end
end

fn member_value(s: String, i: Int, key: String, acc: List[JValue]) -> Result[Step, Int]
  let st = try parse_value(s, i)
  match st
    case Step(v, j) -> member_after(s, j, list_cons(JPair(key, v), acc))
  end
end

fn member_after(s: String, i: Int, acc: List[JValue]) -> Result[Step, Int]
  let j = skip_ws(s, i)
  let c = byte_at(s, j)
  if eq(c, 44) then member_items(s, add(j, 1), acc)
  elif eq(c, 125) then Ok(Step(JObj(list_reverse(acc)), add(j, 1)))
  else Err(j) end
end

fn finish_doc(s: String, v: JValue, j: Int) -> Result[JValue, Int]
  let k = skip_ws(s, j)
  if eq(byte_at(s, k), -1) then Ok(v) else Err(k) end
end

fn parse_document(s: String) -> Result[JValue, Int]
  let st = try parse_value(s, 0)
  match st
    case Step(v, j) -> finish_doc(s, v, j)
  end
end

# ---------- pretty printer (accumulator is reversed) ----------

fn pad(n: Int) -> String
  str_repeat("  ", n)
end

fn bool_text(b: Bool) -> String
  if b then "true" else "false" end
end

fn close_block(close: String, ind: Int, acc: List[String]) -> List[String]
  list_cons(str_cat("\n", pad(ind), close), acc)
end

# items are printed at indentation level ind, separated by ",\n"
fn emit_elems(items: List[JValue], ind: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [x] -> emit(x, ind, list_cons(pad(ind), acc))
    case [x, ..rest] -> emit_elems(rest, ind, list_cons(",\n", emit(x, ind, list_cons(pad(ind), acc))))
  end
end

fn emit_arr(items: List[JValue], ind: Int, acc: List[String]) -> List[String]
  match items
    case [] -> list_cons("[]", acc)
    case _ -> close_block("]", ind, emit_elems(items, add(ind, 1), list_cons("[\n", acc)))
  end
end

fn emit_obj(items: List[JValue], ind: Int, acc: List[String]) -> List[String]
  match items
    case [] -> list_cons("{}", acc)
    case _ -> close_block("}", ind, emit_elems(items, add(ind, 1), list_cons("{\n", acc)))
  end
end

fn emit(v: JValue, ind: Int, acc: List[String]) -> List[String]
  match v
    case JNull -> list_cons("null", acc)
    case JBool(b) -> list_cons(bool_text(b), acc)
    case JNum(t) -> list_cons(t, acc)
    case JStr(b) -> list_cons(str_cat("\"", b, "\""), acc)
    case JArr(items) -> emit_arr(items, ind, acc)
    case JObj(items) -> emit_obj(items, ind, acc)
    case JPair(k, x) -> emit(x, ind, list_cons(str_cat("\"", k, "\": "), acc))
  end
end

fn render(v: JValue) -> String
  str_cat(str_join(list_reverse(emit(v, 0, [])), ""), "\n")
end

# ---------- errors and entry points ----------

# number of newlines in [0, i), plus one
fn count_nl(s: String, i: Int, k: Int, line: Int) -> Int
  if ge(k, i) then line
  elif eq(byte_at(s, k), 10) then count_nl(s, i, add(k, 1), add(line, 1))
  else count_nl(s, i, add(k, 1), line) end
end

# offset of the last newline before i, or -1
fn last_nl(s: String, i: Int, k: Int, last: Int) -> Int
  if ge(k, i) then last
  elif eq(byte_at(s, k), 10) then last_nl(s, i, add(k, 1), k)
  else last_nl(s, i, add(k, 1), last) end
end

fn error_text(s: String, i: Int) -> String
  let line = count_nl(s, i, 0, 1)
  let col = sub(i, last_nl(s, i, 0, -1))
  str_cat("error: line ", show(line), " col ", show(col))
end

fn process_doc(s: String) -> Result[String, Int]
  match parse_document(s)
    case Ok(v) -> Ok(render(v))
    case Err(off) -> Err(off)
  end
end

fn fail_with(src: String, off: Int) -> Unit ! [io]
  println(error_text(src, off))
  exit(1)
end

fn main() -> Unit ! [io]
  let src = read_all()
  match process_doc(src)
    case Ok(out) -> print(out)
    case Err(off) -> fail_with(src, off)
  end
end

test "pretty prints nested document"
  expect_eq(process_doc("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n"))
end

test "reports position of a bad token"
  expect_eq(process_doc("[1,\n x]"), Err(5))
  expect_eq(error_text("[1,\n x]", 5), "error: line 2 col 2")
  expect_eq(process_doc("tru"), Err(3))
end

test "unicode and simple escapes"
  expect_eq(process_doc("\"\\u0041\\u00e9\\/\""), Ok("\"A\\u00e9/\"\n"))
end
