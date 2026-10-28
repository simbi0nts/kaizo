# jsonfmt: validate a JSON document from stdin and pretty-print it (2-space indent).
# Parsers return Result[Node, Int] where the Int is the byte index of the error.
# Strings are kept in output-escaped form, so the printer only adds quotes.

type Json = JNull | JBool(Bool) | JNum(String) | JStr(String) | JArr(List[Json]) | JObj(List[Member]) end
type Member = { mkey: String, mval: Json } end
type Node = { json: Json, pos: Int } end

# ---------- byte helpers ----------

fn byte_at(s: String, i: Int) -> Int
  if ge(i, str_len(s)) then -1 else str_byte(s, i) end
end

fn is_digit(b: Int) -> Bool
  and(ge(b, 48), le(b, 57))
end

fn hexval(b: Int) -> Int
  if and(ge(b, 48), le(b, 57)) then sub(b, 48)
  elif and(ge(b, 97), le(b, 102)) then sub(b, 87)
  elif and(ge(b, 65), le(b, 70)) then sub(b, 55)
  else -1 end
end

fn skip_ws(s: String, i: Int) -> Int
  let b = byte_at(s, i)
  if or(eq(b, 32), eq(b, 9), eq(b, 10), eq(b, 13)) then skip_ws(s, add(i, 1)) else i end
end

fn expect_char(s: String, q: Int, code: Int) -> Result[Int, Int]
  if eq(byte_at(s, q), code) then Ok(add(q, 1)) else Err(q) end
end

# ---------- escaping for output ----------

fn hexd(n: Int) -> String
  str_slice("0123456789abcdef", n, add(n, 1))
end

fn hex_pair(n: Int) -> String
  str_cat(hexd(div(n, 16)), hexd(mod(n, 16)))
end

fn hex_u(v: Int) -> String
  str_cat("\\u", hex_pair(div(v, 256)), hex_pair(mod(v, 256)))
end

# Output form of one byte value (also used for \u escapes below 0x80).
fn esc_byte(b: Int) -> String
  if eq(b, 34) then "\\\""
  elif eq(b, 92) then "\\\\"
  elif eq(b, 8) then "\\b"
  elif eq(b, 12) then "\\f"
  elif eq(b, 10) then "\\n"
  elif eq(b, 13) then "\\r"
  elif eq(b, 9) then "\\t"
  elif lt(b, 32) then str_cat("\\u00", hex_pair(b))
  else str_from_bytes([b]) end
end

# ---------- string parsing ----------

fn hex4(s: String, p: Int, k: Int, acc: Int) -> Result[Int, Int]
  if eq(k, 4) then Ok(acc)
  elif lt(hexval(byte_at(s, add(p, k))), 0) then Err(add(p, k))
  else hex4(s, p, add(k, 1), add(mul(acc, 16), hexval(byte_at(s, add(p, k))))) end
end

fn unicode_escape(s: String, p: Int, acc: List[String]) -> Result[Node, Int]
  let v = try hex4(s, p, 0, 0)
  let piece = if lt(v, 128) then esc_byte(v) else hex_u(v) end
  str_body(s, add(p, 4), list_cons(piece, acc))
end

# Code of a simple one-character escape, or -1.
fn simple_code(b: Int) -> Int
  if eq(b, 34) then 34
  elif eq(b, 92) then 92
  elif eq(b, 47) then 47
  elif eq(b, 98) then 8
  elif eq(b, 102) then 12
  elif eq(b, 110) then 10
  elif eq(b, 114) then 13
  elif eq(b, 116) then 9
  else -1 end
end

fn str_escape(s: String, p: Int, acc: List[String]) -> Result[Node, Int]
  let b = byte_at(s, p)
  let c = simple_code(b)
  if ge(c, 0) then str_body(s, add(p, 1), list_cons(esc_byte(c), acc))
  elif eq(b, 117) then unicode_escape(s, add(p, 1), acc)
  else Err(p) end
end

# Parses string body starting at p (just after the opening quote).
fn str_body(s: String, p: Int, acc: List[String]) -> Result[Node, Int]
  let b = byte_at(s, p)
  if eq(b, -1) then Err(p)
  elif eq(b, 34) then Ok(Node { json: JStr(str_join(list_reverse(acc), "")), pos: add(p, 1) })
  elif eq(b, 92) then str_escape(s, add(p, 1), acc)
  elif lt(b, 32) then Err(p)
  else str_body(s, add(p, 1), list_cons(esc_byte(b), acc)) end
end

# ---------- literals and numbers ----------

fn match_word(s: String, p: Int, word: String, k: Int) -> Result[Int, Int]
  if eq(k, str_len(word)) then Ok(p)
  elif eq(byte_at(s, p), str_byte(word, k)) then match_word(s, add(p, 1), word, add(k, 1))
  else Err(p) end
end

fn parse_lit(s: String, p: Int, word: String, v: Json) -> Result[Node, Int]
  let e = try match_word(s, p, word, 0)
  Ok(Node { json: v, pos: e })
end

fn digits_end(s: String, q: Int) -> Int
  if is_digit(byte_at(s, q)) then digits_end(s, add(q, 1)) else q end
end

fn int_part(s: String, q: Int) -> Result[Int, Int]
  let b = byte_at(s, q)
  if eq(b, 48) then Ok(add(q, 1))
  elif is_digit(b) then Ok(digits_end(s, add(q, 1)))
  else Err(q) end
end

fn parse_number(s: String, p: Int) -> Result[Node, Int]
  let q = if eq(byte_at(s, p), 45) then add(p, 1) else p end
  let e = try int_part(s, q)
  Ok(Node { json: JNum(str_slice(s, p, e)), pos: e })
end

# ---------- arrays, objects, values ----------

fn str_of(j: Json) -> String
  match j
    case JStr(t) -> t
    case _ -> ""
  end
end

fn parse_key(s: String, q: Int) -> Result[Node, Int]
  if eq(byte_at(s, q), 34) then str_body(s, add(q, 1), []) else Err(q) end
end

fn member_items(s: String, p: Int, acc: List[Member]) -> Result[Node, Int]
  let kn = try parse_key(s, skip_ws(s, p))
  let c = try expect_char(s, skip_ws(s, kn.pos), 58)
  let vn = try parse_value(s, c)
  let items = list_cons(Member { mkey: str_of(kn.json), mval: vn.json }, acc)
  let q = skip_ws(s, vn.pos)
  let b = byte_at(s, q)
  if eq(b, 44) then member_items(s, add(q, 1), items)
  elif eq(b, 125) then Ok(Node { json: JObj(list_reverse(items)), pos: add(q, 1) })
  else Err(q) end
end

fn parse_object(s: String, p: Int) -> Result[Node, Int]
  let q = skip_ws(s, p)
  if eq(byte_at(s, q), 125) then Ok(Node { json: JObj([]), pos: add(q, 1) })
  else member_items(s, q, []) end
end

fn array_items(s: String, p: Int, acc: List[Json]) -> Result[Node, Int]
  let n = try parse_value(s, p)
  let items = list_cons(n.json, acc)
  let q = skip_ws(s, n.pos)
  let b = byte_at(s, q)
  if eq(b, 44) then array_items(s, add(q, 1), items)
  elif eq(b, 93) then Ok(Node { json: JArr(list_reverse(items)), pos: add(q, 1) })
  else Err(q) end
end

fn parse_array(s: String, p: Int) -> Result[Node, Int]
  let q = skip_ws(s, p)
  if eq(byte_at(s, q), 93) then Ok(Node { json: JArr([]), pos: add(q, 1) })
  else array_items(s, q, []) end
end

fn parse_value(s: String, i: Int) -> Result[Node, Int]
  let j = skip_ws(s, i)
  let b = byte_at(s, j)
  if eq(b, 123) then parse_object(s, add(j, 1))
  elif eq(b, 91) then parse_array(s, add(j, 1))
  elif eq(b, 34) then str_body(s, add(j, 1), [])
  elif or(eq(b, 45), is_digit(b)) then parse_number(s, j)
  elif eq(b, 116) then parse_lit(s, j, "true", JBool(true))
  elif eq(b, 102) then parse_lit(s, j, "false", JBool(false))
  elif eq(b, 110) then parse_lit(s, j, "null", JNull)
  else Err(j) end
end

fn parse_doc(s: String) -> Result[Json, Int]
  let n = try parse_value(s, 0)
  let q = skip_ws(s, n.pos)
  if eq(byte_at(s, q), -1) then Ok(n.json) else Err(q) end
end

# ---------- pretty printer ----------
# emit* push chunks onto acc (a reversed list of chunks).

fn indent(d: Int) -> String
  str_repeat("  ", d)
end

fn bool_text(b: Bool) -> String
  if b then "true" else "false" end
end

fn emit_member(m: Member, depth: Int, acc: List[String]) -> List[String]
  emit(m.mval, depth, list_cons(": ", list_cons(str_cat("\"", m.mkey, "\""), acc)))
end

fn emit_members(ms: List[Member], depth: Int, acc: List[String]) -> List[String]
  match ms
    case [] -> acc
    case [m] -> emit_member(m, add(depth, 1), list_cons(indent(add(depth, 1)), list_cons("\n", acc)))
    case [m, ..rest] -> emit_members(rest, depth, list_cons(",", emit_member(m, add(depth, 1), list_cons(indent(add(depth, 1)), list_cons("\n", acc)))))
  end
end

fn emit_elems(items: List[Json], depth: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [x] -> emit(x, add(depth, 1), list_cons(indent(add(depth, 1)), list_cons("\n", acc)))
    case [x, ..rest] -> emit_elems(rest, depth, list_cons(",", emit(x, add(depth, 1), list_cons(indent(add(depth, 1)), list_cons("\n", acc)))))
  end
end

fn emit_array(items: List[Json], depth: Int, acc: List[String]) -> List[String]
  match items
    case [] -> list_cons("[]", acc)
    case _ -> list_cons("]", list_cons(indent(depth), list_cons("\n", emit_elems(items, depth, list_cons("[", acc)))))
  end
end

fn emit_object(ms: List[Member], depth: Int, acc: List[String]) -> List[String]
  match ms
    case [] -> list_cons("{}", acc)
    case _ -> list_cons("}", list_cons(indent(depth), list_cons("\n", emit_members(ms, depth, list_cons("{", acc)))))
  end
end

fn emit(j: Json, depth: Int, acc: List[String]) -> List[String]
  match j
    case JNull -> list_cons("null", acc)
    case JBool(b) -> list_cons(bool_text(b), acc)
    case JNum(t) -> list_cons(t, acc)
    case JStr(t) -> list_cons(str_cat("\"", t, "\""), acc)
    case JArr(items) -> emit_array(items, depth, acc)
    case JObj(ms) -> emit_object(ms, depth, acc)
  end
end

fn format_text(s: String) -> Result[String, Int]
  let j = try parse_doc(s)
  Ok(str_cat(str_join(list_reverse(emit(j, 0, [])), ""), "\n"))
end

# ---------- error position ----------

fn scan_err(s: String, k: Int, p: Int, line: Int, start: Int) -> String
  if ge(k, p) then str_cat("error: line ", show(line), " col ", show(add(sub(p, start), 1)))
  elif eq(byte_at(s, k), 10) then scan_err(s, add(k, 1), p, add(line, 1), add(k, 1))
  else scan_err(s, add(k, 1), p, line, start) end
end

fn error_text(s: String, p: Int) -> String
  scan_err(s, 0, p, 1, 0)
end

# ---------- entry point ----------

fn main() -> Unit ! [io]
  let s = read_all()
  match format_text(s)
    case Ok(out) -> print(out)
    case Err(p) ->
      println(error_text(s, p))
      exit(1)
  end
end

test "pretty prints nested document"
  expect_eq(format_text("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n"))
end

test "error position on trailing comma"
  expect_eq(format_text("[1,]"), Err(3))
end

test "error line and column"
  expect_eq(error_text("x\nyz", 3), "error: line 2 col 2")
end

test "unicode escapes"
  expect_eq(format_text("\"\\u0041\\u00e9\\/\\u0001\""), Ok("\"A\\u00e9/\\u0001\"\n"))
end
