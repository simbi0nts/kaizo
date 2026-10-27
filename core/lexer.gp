# Lexer: source text -> linked list of tokens (a linked list keeps appends O(1)).

type TokKind = TkIdent | TkUpper | TkInt | TkStr | TkKw | TkPunct | TkEof end
type Tok = { kind: TokKind, text: String, num: Int, pos: Pos } end
type Toks = TNil | TCons(Tok, Toks) end
type Lexed = { toks: Toks, eof: Tok, err: Option[Diag] } end
type Lx = { src: String, file: String, i: Int, line: Int, col: Int, acc: Toks } end

let keywords = ["fn", "end", "let", "if", "then", "elif", "else", "match", "case", "type", "test", "import", "with", "true", "false"]

fn is_letter(c: Int) -> Bool
  or(and(ge(c, 97), le(c, 122)), and(ge(c, 65), le(c, 90)))
end

fn is_digit(c: Int) -> Bool
  and(ge(c, 48), le(c, 57))
end

fn is_ident_char(c: Int) -> Bool
  or(or(is_letter(c), is_digit(c)), eq(c, 95))
end

fn byte_at(s: String, i: Int) -> Int
  if lt(i, str_len(s)) then str_byte(s, i) else -1 end
end

fn toks_reverse(t: Toks, acc: Toks) -> Toks
  match t
    case TNil -> acc
    case TCons(x, rest) -> toks_reverse(rest, TCons(x, acc))
  end
end

fn lx_pos(x: Lx) -> Pos
  Pos { file: x.file, line: x.line, col: x.col }
end

fn lx_push(x: Lx, kind: TokKind, text: String, num: Int, pos: Pos, len: Int) -> Lx
  { x with i: add(x.i, len), col: add(x.col, len), acc: TCons(Tok { kind: kind, text: text, num: num, pos: pos }, x.acc) }
end

fn scan_while_ident(s: String, j: Int) -> Int
  if is_ident_char(byte_at(s, j)) then scan_while_ident(s, add(j, 1)) else j end
end

fn scan_while_digit(s: String, j: Int) -> Int
  if is_digit(byte_at(s, j)) then scan_while_digit(s, add(j, 1)) else j end
end

fn hex_val(c: Int) -> Int
  if is_digit(c) then sub(c, 48) elif and(ge(c, 97), le(c, 102)) then sub(c, 87) elif and(ge(c, 65), le(c, 70)) then sub(c, 55) else -1 end
end

fn scan_while_hex(s: String, j: Int) -> Int
  if ge(hex_val(byte_at(s, j)), 0) then scan_while_hex(s, add(j, 1)) else j end
end

fn parse_hex(s: String, j: Int, stop: Int, acc: Int) -> Int
  if ge(j, stop) then acc else parse_hex(s, add(j, 1), stop, add(mul(acc, 16), hex_val(str_byte(s, j)))) end
end

# true when the digits starting at d are a hex prefix 0x / 0X
fn is_hex_prefix(s: String, d: Int) -> Bool
  and(eq(byte_at(s, d), 48), or(eq(byte_at(s, add(d, 1)), 120), eq(byte_at(s, add(d, 1)), 88)))
end

fn skip_comment(s: String, j: Int) -> Int
  let c = byte_at(s, j)
  if or(eq(c, -1), eq(c, 10)) then j else skip_comment(s, add(j, 1)) end
end

fn parse_digits(s: String, j: Int, stop: Int, acc: Int) -> Int
  if ge(j, stop) then acc else parse_digits(s, add(j, 1), stop, add(mul(acc, 10), sub(str_byte(s, j), 48))) end
end

fn escape_byte(c: Int) -> Int
  match c
    case 110 -> 10
    case 116 -> 9
    case 114 -> 13
    case 48 -> 0
    case 101 -> 27
    case 92 -> 92
    case 34 -> 34
    case _ -> -1
  end
end

type StrScan = { ok: Bool, end_i: Int, pieces: List[String], err_at: Int, msg: String, hint: String } end

# scans a string literal body starting after the opening quote
fn scan_string(s: String, j: Int, start: Int, pieces: List[String]) -> StrScan
  let c = byte_at(s, j)
  if or(eq(c, -1), eq(c, 10)) then
    StrScan { ok: false, end_i: j, pieces: pieces, err_at: -1, msg: "unterminated string", hint: "strings are one line; write \\n for a newline" }
  elif eq(c, 34) then
    StrScan { ok: true, end_i: add(j, 1), pieces: list_push(pieces, str_slice(s, start, j)), err_at: 0, msg: "", hint: "" }
  elif eq(c, 92) then
    let e = escape_byte(byte_at(s, add(j, 1)))
    if lt(e, 0) then
      StrScan { ok: false, end_i: j, pieces: pieces, err_at: j, msg: str_cat("unknown escape \\", str_slice(s, add(j, 1), add(j, 2))), hint: "known escapes: \\n \\t \\r \\0 \\e (ESC) \\\\ \\\"" }
    else
      scan_string(s, add(j, 2), add(j, 2), list_push(list_push(pieces, str_slice(s, start, j)), str_from_bytes([e])))
    end
  else
    scan_string(s, add(j, 1), start, pieces)
  end
end

fn lex_err(x: Lx, pos: Pos, msg: String, hint: String) -> Lexed
  let eof = Tok { kind: TkEof, text: "end of file", num: 0, pos: pos }
  Lexed { toks: TNil, eof: eof, err: Some(Diag { pos: pos, msg: msg, hint: hint }) }
end

fn lex_loop(x: Lx) -> Lexed
  let s = x.src
  let c = byte_at(s, x.i)
  let pos = lx_pos(x)
  if eq(c, -1) then
    let eof = Tok { kind: TkEof, text: "end of file", num: 0, pos: pos }
    Lexed { toks: toks_reverse(x.acc, TNil), eof: eof, err: None }
  elif eq(c, 10) then
    lex_loop({ x with i: add(x.i, 1), line: add(x.line, 1), col: 1 })
  elif or(or(eq(c, 32), eq(c, 9)), eq(c, 13)) then
    lex_loop({ x with i: add(x.i, 1), col: add(x.col, 1) })
  elif eq(c, 35) then
    let j = skip_comment(s, x.i)
    lex_loop({ x with i: j, col: add(x.col, sub(j, x.i)) })
  elif or(is_letter(c), eq(c, 95)) then
    let j = scan_while_ident(s, x.i)
    let text = str_slice(s, x.i, j)
    let kind = if eq(text, "_") then TkPunct elif list_contains(keywords, text) then TkKw elif and(ge(c, 65), le(c, 90)) then TkUpper else TkIdent end
    lex_loop(lx_push(x, kind, text, 0, pos, sub(j, x.i)))
  elif or(is_digit(c), and(eq(c, 45), is_digit(byte_at(s, add(x.i, 1))))) then
    let neg = eq(c, 45)
    let d = if neg then add(x.i, 1) else x.i end
    if is_hex_prefix(s, d) then
      let j = scan_while_hex(s, add(d, 2))
      if eq(j, add(d, 2)) then
        lex_err(x, pos, str_cat("hex literal has no digits: ", str_slice(s, x.i, j)), "write hex digits after 0x, e.g. 0x1F or -0xff")
      else
        let mag = parse_hex(s, add(d, 2), j, 0)
        let n = if neg then sub(0, mag) else mag end
        lex_loop(lx_push(x, TkInt, str_slice(s, x.i, j), n, pos, sub(j, x.i)))
      end
    else
      let j = scan_while_digit(s, add(x.i, 1))
      let mag = parse_digits(s, d, j, 0)
      let n = if neg then sub(0, mag) else mag end
      lex_loop(lx_push(x, TkInt, str_slice(s, x.i, j), n, pos, sub(j, x.i)))
    end
  elif eq(c, 34) then
    let r = scan_string(s, add(x.i, 1), add(x.i, 1), [])
    if r.ok then
      lex_loop(lx_push(x, TkStr, str_join(r.pieces, ""), 0, pos, sub(r.end_i, x.i)))
    else
      let at = if lt(r.err_at, 0) then pos else { pos with col: add(x.col, sub(r.err_at, x.i)) } end
      lex_err(x, at, r.msg, r.hint)
    end
  else
    let two = str_slice(s, x.i, add(x.i, 2))
    if or(eq(two, "->"), eq(two, "..")) then
      lex_loop(lx_push(x, TkPunct, two, 0, pos, 2))
    else
      let one = str_slice(s, x.i, add(x.i, 1))
      if is_some(str_find("()[]{},:.!=|", one)) then
        lex_loop(lx_push(x, TkPunct, one, 0, pos, 1))
      else
        let hint = if is_some(str_find("+-*/<>&", one)) then "GPLM has no operators; use calls like add(a, b), lt(a, b), and(a, b)" else "" end
        lex_err(x, pos, str_join(["unexpected character ", show_char(one)], ""), hint)
      end
    end
  end
end

fn show_char(c: String) -> String
  str_join(["'", c, "'"], "")
end

fn lex(file: String, src: String) -> Lexed
  lex_loop(Lx { src: src, file: file, i: 0, line: 1, col: 1, acc: TNil })
end

fn lex_first_num(src: String) -> Option[Int]
  let r = lex("t.gp", src)
  match r.toks
    case TCons(t, _) -> if eq(t.kind, TkInt) then Some(t.num) else None end
    case TNil -> None
  end
end

fn lex_err_msg(src: String) -> String
  match lex("t.gp", src).err
    case Some(d) -> str_cat(str_cat(d.msg, " | "), d.hint)
    case None -> ""
  end
end

test "lexer: hex literals"
  expect_eq(lex_first_num("0x1F"), Some(31))
  expect_eq(lex_first_num("0x1f"), Some(31))
  expect_eq(lex_first_num("0XfAdE0cC0"), Some(4208856256))
  expect_eq(lex_first_num("-0x10"), Some(-16))
  expect_eq(lex_first_num("0"), Some(0))
  expect_eq(lex_first_num("-12"), Some(-12))
  expect_eq(lex_err_msg("0x"), "hex literal has no digits: 0x | write hex digits after 0x, e.g. 0x1F or -0xff")
  expect_eq(lex_err_msg("-0xg"), "hex literal has no digits: -0x | write hex digits after 0x, e.g. 0x1F or -0xff")
end
