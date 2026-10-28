# jsonfmt: validate a JSON document from standard input and pretty-print it.

type Node = NullV | BoolV(Bool) | IntV(String) | StrV(String) | ArrV(List[Node]) | ObjV(List[Node]) | MemV(String, Node) end
type PR = Parsed(Node, Int) | Fail(Int) end
type HX = HexOk(Int, Int) | HexErr(Int) end

# Byte at position i, or -1 at end of input.
fn at(s: String, i: Int) -> Int
  if ge(i, str_len(s)) then -1 else str_byte(s, i) end
end

fn skip_ws(s: String, i: Int) -> Int
  let c = at(s, i)
  if or(eq(c, 32), eq(c, 9), eq(c, 10), eq(c, 13)) then skip_ws(s, add(i, 1)) else i end
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn skip_digits(s: String, i: Int) -> Int
  if is_digit(at(s, i)) then skip_digits(s, add(i, 1)) else i end
end

fn parse_value(s: String, i0: Int) -> PR
  let i = skip_ws(s, i0)
  let c = at(s, i)
  if eq(c, 123) then parse_object(s, add(i, 1))
  elif eq(c, 91) then parse_array(s, add(i, 1))
  elif eq(c, 34) then str_body(s, add(i, 1), [])
  elif eq(c, 116) then parse_lit(s, i, "true", 0, BoolV(true))
  elif eq(c, 102) then parse_lit(s, i, "false", 0, BoolV(false))
  elif eq(c, 110) then parse_lit(s, i, "null", 0, NullV)
  elif or(eq(c, 45), is_digit(c)) then parse_number(s, i)
  else Fail(i)
  end
end

fn parse_lit(s: String, j: Int, w: String, k: Int, v: Node) -> PR
  if ge(k, str_len(w)) then Parsed(v, j)
  elif eq(at(s, j), str_byte(w, k)) then parse_lit(s, add(j, 1), w, add(k, 1), v)
  else Fail(j)
  end
end

fn num_done(s: String, i: Int, e: Int) -> PR
  Parsed(IntV(str_slice(s, i, e)), e)
end

fn parse_number(s: String, i: Int) -> PR
  let j = if eq(at(s, i), 45) then add(i, 1) else i end
  let c = at(s, j)
  if eq(c, 48) then num_done(s, i, add(j, 1))
  elif and(ge(c, 49), le(c, 57)) then num_done(s, i, skip_digits(s, add(j, 1)))
  else Fail(j)
  end
end

fn parse_array(s: String, j: Int) -> PR
  let k = skip_ws(s, j)
  if eq(at(s, k), 93) then Parsed(ArrV([]), add(k, 1))
  else arr_items(s, k, [])
  end
end

fn arr_items(s: String, j: Int, acc: List[Node]) -> PR
  match parse_value(s, j)
    case Fail(p) -> Fail(p)
    case Parsed(v, k) -> arr_after(s, skip_ws(s, k), list_cons(v, acc))
  end
end

fn arr_after(s: String, k: Int, acc: List[Node]) -> PR
  if eq(at(s, k), 44) then arr_items(s, add(k, 1), acc)
  elif eq(at(s, k), 93) then Parsed(ArrV(list_reverse(acc)), add(k, 1))
  else Fail(k)
  end
end

fn parse_object(s: String, j: Int) -> PR
  let k = skip_ws(s, j)
  if eq(at(s, k), 125) then Parsed(ObjV([]), add(k, 1))
  else obj_items(s, k, [])
  end
end

fn obj_items(s: String, j: Int, acc: List[Node]) -> PR
  let k = skip_ws(s, j)
  if eq(at(s, k), 34) then obj_key(s, k, acc)
  else Fail(k)
  end
end

fn obj_key(s: String, k: Int, acc: List[Node]) -> PR
  match str_body(s, add(k, 1), [])
    case Parsed(StrV(key), k2) -> obj_colon(s, skip_ws(s, k2), key, acc)
    case Fail(p) -> Fail(p)
    case _ -> Fail(k)
  end
end

fn obj_colon(s: String, k: Int, key: String, acc: List[Node]) -> PR
  if eq(at(s, k), 58) then obj_value(s, add(k, 1), key, acc)
  else Fail(k)
  end
end

fn obj_value(s: String, k: Int, key: String, acc: List[Node]) -> PR
  match parse_value(s, k)
    case Fail(p) -> Fail(p)
    case Parsed(v, k2) -> obj_after(s, skip_ws(s, k2), list_cons(MemV(key, v), acc))
  end
end

fn obj_after(s: String, k: Int, acc: List[Node]) -> PR
  if eq(at(s, k), 44) then obj_items(s, add(k, 1), acc)
  elif eq(at(s, k), 125) then Parsed(ObjV(list_reverse(acc)), add(k, 1))
  else Fail(k)
  end
end

# Scans the body of a string (j is just after the opening quote).
# acc holds the already re-escaped pieces in reverse order.
fn str_body(s: String, j: Int, acc: List[String]) -> PR
  let c = at(s, j)
  if eq(c, 34) then Parsed(StrV(str_join(list_reverse(acc), "")), add(j, 1))
  elif eq(c, 92) then str_escape(s, j, acc)
  elif lt(c, 32) then Fail(j)
  else
    let e = raw_end(s, j)
    str_body(s, e, list_cons(str_slice(s, j, e), acc))
  end
end

fn raw_end(s: String, j: Int) -> Int
  let c = at(s, j)
  if or(eq(c, 34), eq(c, 92), lt(c, 32)) then j else raw_end(s, add(j, 1)) end
end

# j is at the backslash.
fn str_escape(s: String, j: Int, acc: List[String]) -> PR
  let c = at(s, add(j, 1))
  if eq(c, 34) then str_body(s, add(j, 2), list_cons("\\\"", acc))
  elif eq(c, 92) then str_body(s, add(j, 2), list_cons("\\\\", acc))
  elif eq(c, 47) then str_body(s, add(j, 2), list_cons("/", acc))
  elif eq(c, 98) then str_body(s, add(j, 2), list_cons("\\b", acc))
  elif eq(c, 102) then str_body(s, add(j, 2), list_cons("\\f", acc))
  elif eq(c, 110) then str_body(s, add(j, 2), list_cons("\\n", acc))
  elif eq(c, 114) then str_body(s, add(j, 2), list_cons("\\r", acc))
  elif eq(c, 116) then str_body(s, add(j, 2), list_cons("\\t", acc))
  elif eq(c, 117) then uescape(s, add(j, 2), acc)
  else Fail(add(j, 1))
  end
end

fn uescape(s: String, k: Int, acc: List[String]) -> PR
  match uhex(s, k, 0, 0)
    case HexErr(p) -> Fail(p)
    case HexOk(v, k2) -> str_body(s, k2, list_cons(uesc(v), acc))
  end
end

fn uhex(s: String, k: Int, n: Int, v: Int) -> HX
  if eq(n, 4) then HexOk(v, k)
  else
    let d = hexv(at(s, k))
    if lt(d, 0) then HexErr(k) else uhex(s, add(k, 1), add(n, 1), add(mul(v, 16), d)) end
  end
end

fn hexv(c: Int) -> Int
  if and(ge(c, 48), le(c, 57)) then sub(c, 48)
  elif and(ge(c, 97), le(c, 102)) then sub(c, 87)
  elif and(ge(c, 65), le(c, 70)) then sub(c, 55)
  else -1
  end
end

fn hexd(n: Int) -> String
  str_slice("0123456789abcdef", n, add(n, 1))
end

# Output text for a \uXXXX escape value.
fn uesc(v: Int) -> String
  if lt(v, 128) then esc_code(v)
  else str_cat("\\u", hexd(div(v, 4096)), hexd(mod(div(v, 256), 16)), hexd(mod(div(v, 16), 16)), hexd(mod(v, 16)))
  end
end

# Output text for one character code below 0x80, re-escaped as the spec requires.
fn esc_code(c: Int) -> String
  if eq(c, 34) then "\\\""
  elif eq(c, 92) then "\\\\"
  elif eq(c, 8) then "\\b"
  elif eq(c, 12) then "\\f"
  elif eq(c, 10) then "\\n"
  elif eq(c, 13) then "\\r"
  elif eq(c, 9) then "\\t"
  elif lt(c, 32) then str_cat("\\u00", hexd(div(c, 16)), hexd(mod(c, 16)))
  else str_from_bytes([c])
  end
end

fn parse_doc(s: String) -> PR
  match parse_value(s, 0)
    case Fail(p) -> Fail(p)
    case Parsed(v, k) -> trailing(s, k, v)
  end
end

fn trailing(s: String, k: Int, v: Node) -> PR
  let j = skip_ws(s, k)
  if eq(at(s, j), -1) then Parsed(v, j) else Fail(j) end
end

fn ind(d: Int) -> String
  str_repeat("  ", d)
end

# Renders v (at indentation depth d); pieces are prepended to acc (reverse order).
fn render(v: Node, d: Int, acc: List[String]) -> List[String]
  match v
    case NullV -> list_cons("null", acc)
    case BoolV(b) -> list_cons(if b then "true" else "false" end, acc)
    case IntV(t) -> list_cons(t, acc)
    case StrV(t) -> list_cons(str_cat("\"", t, "\""), acc)
    case ArrV(items) -> block(items, d, "[", "]", acc)
    case ObjV(items) -> block(items, d, "{", "}", acc)
    case MemV(k, x) -> render(x, d, list_cons(": ", list_cons(str_cat("\"", k, "\""), acc)))
  end
end

fn block(items: List[Node], d: Int, open: String, close: String, acc: List[String]) -> List[String]
  match items
    case [] -> list_cons(str_cat(open, close), acc)
    case _ -> list_cons(str_cat("\n", ind(d), close), elems(items, add(d, 1), list_cons(str_cat(open, "\n"), acc)))
  end
end

fn elems(items: List[Node], d: Int, acc: List[String]) -> List[String]
  match items
    case [] -> acc
    case [x] -> render(x, d, list_cons(ind(d), acc))
    case [x, ..rest] -> elems(rest, d, list_cons(",\n", render(x, d, list_cons(ind(d), acc))))
  end
end

# Converts a byte offset into "line L col C" (1-based, col counts bytes).
fn locate(s: String, target: Int, i: Int, line: Int, col: Int) -> String
  if eq(i, target) then str_cat("line ", show(line), " col ", show(col))
  elif eq(at(s, i), 10) then locate(s, target, add(i, 1), add(line, 1), 1)
  else locate(s, target, add(i, 1), line, add(col, 1))
  end
end

fn format_doc(s: String) -> Result[String, String]
  match parse_doc(s)
    case Parsed(v, _) -> Ok(str_join(list_reverse(list_cons("\n", render(v, 0, []))), ""))
    case Fail(p) -> Err(locate(s, p, 0, 1, 1))
  end
end

fn run_json(s: String) -> Int ! [io]
  match format_doc(s)
    case Ok(t) ->
      print(t)
      0
    case Err(m) ->
      println(str_cat("error: ", m))
      1
  end
end

fn main() -> Unit ! [io]
  exit(run_json(read_all()))
end

test "pretty prints nested document"
  expect_eq(format_doc("{\"a\":[1,2,{}],\"b\":\"xA\\n\"}"), Ok("{\n  \"a\": [\n    1,\n    2,\n    {}\n  ],\n  \"b\": \"xA\\n\"\n}\n"))
end

test "error position across lines"
  expect_eq(format_doc("[1,\n x]"), Err("line 2 col 2"))
end

test "unicode and simple escapes"
  expect_eq(format_doc("\"\\u0041\\u00e9\\/\""), Ok("\"A\\u00e9/\"\n"))
end

test "unexpected end of input"
  expect_eq(format_doc("[1"), Err("line 1 col 3"))
end
