# jsonfmt: validate a JSON document from stdin and pretty-print it.
# Strings are kept in their output (re-escaped) form while parsing, so the
# printer only has to join pieces. Positions are byte offsets, converted to
# line/col only when an error is reported.

type Json = JNull | JBool(Bool) | JNum(String) | JStr(String) | JArr(List[Json]) | JPair(Json, Json) | JObj(List[Json]) end
type Parsed = MkParsed(Json, Int) end
type PErr = MkErr(Int) end
type Where = MkWhere(Int, Int) end

# ---------- whitespace and small scanners ----------

fn skip_ws(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then
    let b = str_byte(s, i)
    if or(eq(b, 32), eq(b, 9), eq(b, 10), eq(b, 13)) then skip_ws(s, add(i, 1)) else i end
  else
    i
  end
end

fn is_digit(b: Int) -> Bool
  and(ge(b, 48), le(b, 57))
end

fn skip_digits(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then
    if is_digit(str_byte(s, i)) then skip_digits(s, add(i, 1)) else i end
  else
    i
  end
end

# index of the first byte at or after i that is a plain string byte (>= 32, not quote, not backslash)
fn plain_end(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then
    let b = str_byte(s, i)
    if and(ge(b, 32), ne(b, 34), ne(b, 92)) then plain_end(s, add(i, 1)) else i end
  else
    i
  end
end

fn hex_val(b: Int) -> Int
  if and(ge(b, 48), le(b, 57)) then sub(b, 48)
  elif and(ge(b, 97), le(b, 102)) then sub(b, 87)
  elif and(ge(b, 65), le(b, 70)) then sub(b, 55)
  else -1
  end
end

# value of exactly k hex digits starting at i
fn hex4(s: String, i: Int, k: Int, v: Int) -> Result[Int, PErr]
  if eq(k, 0) then Ok(v)
  elif ge(i, str_len(s)) then Err(MkErr(i))
  else
    let d = hex_val(str_byte(s, i))
    if lt(d, 0) then Err(MkErr(i))
    else hex4(s, add(i, 1), sub(k, 1), add(mul(v, 16), d))
    end
  end
end

# matches the literal word w starting at i; the error is at the first mismatching byte
fn expect_word(s: String, i: Int, w: String, k: Int) -> Result[Int, PErr]
  if ge(k, str_len(w)) then Ok(i)
  elif ge(i, str_len(s)) then Err(MkErr(i))
  elif eq(str_byte(s, i), str_byte(w, k)) then expect_word(s, add(i, 1), w, add(k, 1))
  else Err(MkErr(i))
  end
end

# ---------- escaped output of strings ----------

fn hexc(d: Int) -> Int
  if lt(d, 10) then add(48, d) else add(87, d) end
end

# output form of a \u escape whose value is v
fn unicode_out(v: Int) -> String
  if lt(v, 128) then char_esc(v)
  else str_from_bytes([92, 117, hexc(div(v, 4096)), hexc(mod(div(v, 256), 16)), hexc(mod(div(v, 16), 16)), hexc(mod(v, 16))])
  end
end

# output form of a character with code v < 128
fn char_esc(v: Int) -> String
  if eq(v, 34) then str_from_bytes([92, 34])
  elif eq(v, 92) then str_from_bytes([92, 92])
  elif eq(v, 8) then str_from_bytes([92, 98])
  elif eq(v, 12) then str_from_bytes([92, 102])
  elif eq(v, 10) then str_from_bytes([92, 110])
  elif eq(v, 13) then str_from_bytes([92, 114])
  elif eq(v, 9) then str_from_bytes([92, 116])
  elif lt(v, 32) then str_from_bytes([92, 117, 48, 48, hexc(div(v, 16)), hexc(mod(v, 16))])
  else str_from_bytes([v])
  end
end

# ---------- strings ----------

# acc holds output pieces in reverse order; it starts with the opening quote
fn finish(acc: List[String]) -> String
  str_join(list_reverse(list_cons("\"", acc)), "")
end

fn str_body(s: String, i: Int, acc: List[String]) -> Result[Parsed, PErr]
  if ge(i, str_len(s)) then Err(MkErr(i))
  else
    let b = str_byte(s, i)
    match b
      case 34 -> Ok(MkParsed(JStr(finish(acc)), add(i, 1)))
      case 92 -> str_escape(s, add(i, 1), acc)
      case _ ->
        if lt(b, 32) then Err(MkErr(i))
        else
          let e = plain_end(s, i)
          str_body(s, e, list_cons(str_slice(s, i, e), acc))
        end
    end
  end
end

# i is the index just after the backslash
fn str_escape(s: String, i: Int, acc: List[String]) -> Result[Parsed, PErr]
  if ge(i, str_len(s)) then Err(MkErr(i))
  else
    let b = str_byte(s, i)
    if or(eq(b, 34), eq(b, 92), eq(b, 98), eq(b, 102), eq(b, 110), eq(b, 114), eq(b, 116)) then
      str_body(s, add(i, 1), list_cons(str_from_bytes([92, b]), acc))
    elif eq(b, 47) then
      str_body(s, add(i, 1), list_cons("/", acc))
    elif eq(b, 117) then
      str_unicode(s, add(i, 1), acc)
    else
      Err(MkErr(i))
    end
  end
end

# i is the index just after the 'u'
fn str_unicode(s: String, i: Int, acc: List[String]) -> Result[Parsed, PErr]
  let v = try hex4(s, i, 4, 0)
  str_body(s, add(i, 4), list_cons(unicode_out(v), acc))
end

fn parse_string(s: String, i: Int) -> Result[Parsed, PErr]
  str_body(s, i, ["\""])
end

# ---------- numbers and literals ----------

fn parse_number(s: String, i: Int) -> Result[Parsed, PErr]
  let neg = eq(str_byte(s, i), 45)
  let d = if neg then add(i, 1) else i end
  if ge(d, str_len(s)) then Err(MkErr(d))
  else
    let b = str_byte(s, d)
    if eq(b, 48) then
      Ok(MkParsed(JNum(str_slice(s, i, add(d, 1))), add(d, 1)))
    elif and(ge(b, 49), le(b, 57)) then
      let e = skip_digits(s, add(d, 1))
      Ok(MkParsed(JNum(str_slice(s, i, e)), e))
    else
      Err(MkErr(d))
    end
  end
end

fn literal(s: String, i: Int, word: String, v: Json) -> Result[Parsed, PErr]
  let j = try expect_word(s, i, word, 0)
  Ok(MkParsed(v, j))
end

# ---------- arrays and objects ----------

fn array_items(s: String, i: Int, acc: List[Json]) -> Result[Parsed, PErr]
  let p = try parse_value(s, i)
  match p
    case MkParsed(v, j) ->
      let k = skip_ws(s, j)
      if ge(k, str_len(s)) then Err(MkErr(k))
      else
        let b = str_byte(s, k)
        if eq(b, 44) then array_items(s, add(k, 1), list_cons(v, acc))
        elif eq(b, 93) then Ok(MkParsed(JArr(list_reverse(list_cons(v, acc))), add(k, 1)))
        else Err(MkErr(k))
        end
      end
  end
end

fn parse_array(s: String, i: Int) -> Result[Parsed, PErr]
  let j = skip_ws(s, i)
  if ge(j, str_len(s)) then Err(MkErr(j))
  elif eq(str_byte(s, j), 93) then Ok(MkParsed(JArr([]), add(j, 1)))
  else array_items(s, j, [])
  end
end

# after ':' and the key
fn member_colon(s: String, j: Int, key: Json, acc: List[Json]) -> Result[Parsed, PErr]
  let k = skip_ws(s, j)
  if ge(k, str_len(s)) then Err(MkErr(k))
  elif ne(str_byte(s, k), 58) then Err(MkErr(k))
  else
    let vp = try parse_value(s, add(k, 1))
    match vp
      case MkParsed(v, m) -> member_end(s, m, list_cons(JPair(key, v), acc))
    end
  end
end

fn member_end(s: String, m: Int, acc: List[Json]) -> Result[Parsed, PErr]
  let n = skip_ws(s, m)
  if ge(n, str_len(s)) then Err(MkErr(n))
  else
    let b = str_byte(s, n)
    if eq(b, 44) then object_members(s, add(n, 1), acc)
    elif eq(b, 125) then Ok(MkParsed(JObj(list_reverse(acc)), add(n, 1)))
    else Err(MkErr(n))
    end
  end
end

fn object_members(s: String, i0: Int, acc: List[Json]) -> Result[Parsed, PErr]
  let i = skip_ws(s, i0)
  if ge(i, str_len(s)) then Err(MkErr(i))
  elif ne(str_byte(s, i), 34) then Err(MkErr(i))
  else
    let kp = try parse_string(s, add(i, 1))
    match kp
      case MkParsed(key, j) -> member_colon(s, j, key, acc)
    end
  end
end

fn parse_object(s: String, i: Int) -> Result[Parsed, PErr]
  let j = skip_ws(s, i)
  if ge(j, str_len(s)) then Err(MkErr(j))
  elif eq(str_byte(s, j), 125) then Ok(MkParsed(JObj([]), add(j, 1)))
  else object_members(s, j, [])
  end
end

# ---------- values and document ----------

fn parse_value(s: String, i0: Int) -> Result[Parsed, PErr]
  let i = skip_ws(s, i0)
  if ge(i, str_len(s)) then Err(MkErr(i))
  else
    let b = str_byte(s, i)
    match b
      case 123 -> parse_object(s, add(i, 1))
      case 91 -> parse_array(s, add(i, 1))
      case 34 -> parse_string(s, add(i, 1))
      case 116 -> literal(s, i, "true", JBool(true))
      case 102 -> literal(s, i, "false", JBool(false))
      case 110 -> literal(s, i, "null", JNull)
      case _ -> parse_number(s, i)
    end
  end
end

fn parse_document(s: String) -> Result[Json, PErr]
  let p = try parse_value(s, 0)
  match p
    case MkParsed(v, i) ->
      let j = skip_ws(s, i)
      if eq(j, str_len(s)) then Ok(v) else Err(MkErr(j)) end
  end
end

# ---------- output ----------

fn ind(n: Int) -> String
  str_repeat("  ", n)
end

# items of a container whose own line is at depth d
fn join_items(items: List[Json], d: Int) -> String
  str_join(list_map(items, fn(x) str_cat(ind(add(d, 1)), pretty(x, add(d, 1))) end), ",\n")
end

fn pretty(v: Json, d: Int) -> String
  match v
    case JNull -> "null"
    case JBool(b) -> if b then "true" else "false" end
    case JNum(t) -> t
    case JStr(t) -> t
    case JPair(k, x) -> str_cat(pretty(k, d), ": ", pretty(x, d))
    case JArr(items) ->
      if eq(list_len(items), 0) then "[]"
      else str_cat("[\n", join_items(items, d), "\n", ind(d), "]")
      end
    case JObj(items) ->
      if eq(list_len(items), 0) then "{}"
      else str_cat("{\n", join_items(items, d), "\n", ind(d), "}")
      end
  end
end

# line and column (1-based, bytes) of byte offset pos
fn scan_pos(s: String, i: Int, pos: Int, line: Int, ls: Int) -> Where
  if lt(i, pos) then
    if eq(str_byte(s, i), 10) then scan_pos(s, add(i, 1), pos, add(line, 1), add(i, 1))
    else scan_pos(s, add(i, 1), pos, line, ls)
    end
  else
    MkWhere(line, add(sub(pos, ls), 1))
  end
end

fn locate(text: String, pos: Int) -> Where
  scan_pos(text, 0, pos, 1, 0)
end

fn error_text(text: String, e: PErr) -> String
  match e
    case MkErr(pos) ->
      match locate(text, pos)
        case MkWhere(line, col) -> str_cat("error: line ", show(line), " col ", show(col), "\n")
      end
  end
end

# full stdout text on success, or the error text on failure
fn outcome(text: String) -> Result[String, String]
  match parse_document(text)
    case Ok(v) -> Ok(str_cat(pretty(v, 0), "\n"))
    case Err(e) -> Err(error_text(text, e))
  end
end

fn main() -> Unit ! [io]
  let text = read_all()
  match outcome(text)
    case Ok(out) -> print(out)
    case Err(msg) ->
      print(msg)
      exit(1)
  end
end

test "nested object and array pretty print"
  expect_eq(outcome("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n"))
end

test "string escapes are normalized"
  expect_eq(outcome("\"\\u0041\\u00e9\\/\""), Ok("\"A\\u00e9/\"\n"))
end

test "error position on a single line"
  expect_eq(outcome("[1,]"), Err("error: line 1 col 4\n"))
end

test "error position after a newline"
  expect_eq(outcome("{\n  \"a\" 1}"), Err("error: line 2 col 7\n"))
end

test "unexpected end of input"
  expect_eq(outcome("[1"), Err("error: line 1 col 3\n"))
end
