# Runtime of native GPLM programs, written in GPLM. Embedded into the kaizo binary and compiled
# into every program as module `rt`. It implements every non-inline builtin on top of the
# prim_* intrinsics (see codegen.gp) and raw Linux syscalls. No libc.

# ---------- low level ----------

fn sys(n: Int, a: Int, b: Int, c: Int) -> Int
  prim_syscall(n, a, b, c, 0, 0, 0)
end

fn sys5(n: Int, a: Int, b: Int, c: Int, d: Int, e: Int) -> Int
  prim_syscall(n, a, b, c, d, e, 0)
end

fn holder(n: Int) -> List[Unit]
  let h = prim_list_new(n)
  list_fold_i(h, 0, n)
end

fn list_fold_i(h: List[Unit], i: Int, n: Int) -> List[Unit]
  if ge(i, n) then h else
    prim_set_slot(h, i, Unit)
    list_fold_i(h, add(i, 1), n)
  end
end

# slot 0: saved termios (String) or Unit · slot 1: pending key bytes (String) · slot 2: stdin buffer
let state = holder(3)

fn cstr(s: String) -> String
  str_cat(s, str_from_bytes([0]))
end

fn write_all(fd: Int, s: String, off: Int) -> Int
  let n = prim_len(s)
  if ge(off, n) then 0 else
    let w = sys(1, fd, add(prim_addr(s), off), sub(n, off))
    if lt(w, 0) then w else write_all(fd, s, add(off, w)) end
  end
end

fn u_le(s: String, off: Int, k: Int) -> Int
  if eq(k, 0) then 0 else add(prim_byte(s, off), mul(256, u_le(s, add(off, 1), sub(k, 1)))) end
end

fn put_le(s: String, off: Int, v: Int, k: Int) -> Unit
  if eq(k, 0) then Unit else
    prim_set_byte(s, off, mod(v, 256))
    put_le(s, add(off, 1), div(v, 256), sub(k, 1))
  end
end

fn zeros(n: Int) -> String
  let s = prim_str_new(n)
  fill_zero(s, 0, n)
end

fn fill_zero(s: String, i: Int, n: Int) -> String
  if ge(i, n) then s else
    prim_set_byte(s, i, 0)
    fill_zero(s, add(i, 1), n)
  end
end

fn errno_msg(r: Int) -> String
  match sub(0, r)
    case 2 -> "no such file or directory"
    case 9 -> "bad file descriptor"
    case 11 -> "resource temporarily unavailable"
    case 13 -> "permission denied"
    case 17 -> "file exists"
    case 20 -> "not a directory"
    case 21 -> "is a directory"
    case 32 -> "broken pipe"
    case 98 -> "address already in use"
    case 99 -> "cannot assign requested address"
    case 104 -> "connection reset by peer"
    case 110 -> "i/o timeout"
    case e -> str_cat("errno ", show(e))
  end
end

# ---------- failure ----------

fn restore_quiet() -> Unit
  match prim_slot(state, 0)
    case Unit -> Unit
    case saved ->
      sys(16, 0, 21506, prim_addr(saved))
      prim_slot_set_unit(0)
      prim_term_save(0)
      write_all(1, "\e[?25h", 0)
      Unit
  end
end

fn prim_slot_set_unit(i: Int) -> Unit
  prim_set_slot(state, i, Unit)
end

fn fail(msg: String) -> Unit
  restore_quiet()
  write_all(2, str_cat(msg, "\n"), 0)
  sys(231, 1, 0, 0)
  Unit
end

fn fail_value(prefix: String, v: Int) -> Unit
  fail(str_cat(prefix, show_inner(v)))
end

fn panic_at(msg: String, pos: String) -> Unit
  fail(str_join([pos, ": runtime error: panic: ", show(msg)], ""))
end

fn expect_at(c: Bool, msg: String, pos: String) -> Unit
  if c then Unit else fail(str_join([pos, ": runtime error: expectation failed: ", show(msg)], "")) end
end

fn expect_eq_at(a: Int, b: Int, pos: String) -> Unit
  if equal(a, b) then Unit else
    fail(str_join([pos, ": runtime error: expect_eq failed\n    got:      ", show_inner(a), "\n    expected: ", show_inner(b)], ""))
  end
end

fn embed_file(p: String) -> String
  fail("embed_file is only available at compile time")
  ""
end

fn type_fail(name: String, want: String) -> Unit
  fail(str_join(["runtime error: ", name, ": argument must be ", want], ""))
end

fn need(v: Int, tag: Int, name: String, want: String) -> Unit
  if eq(prim_tag(v), tag) then Unit else type_fail(name, want) end
end

# ---------- equality, ordering, show ----------

fn same(a: Int, b: Int) -> Bool
  eq(prim_addr(a), prim_addr(b))
end

fn equal(a: Int, b: Int) -> Bool
  let ta = prim_tag(a)
  if ne(ta, prim_tag(b)) then false
  elif eq(ta, 0) then eq(a, b)
  elif same(a, b) then true
  elif eq(ta, 1) then str_eq(a, b, 0, prim_len(a))
  elif eq(ta, 2) then and(eq(prim_len(a), prim_len(b)), slots_eq(a, b, 0, prim_len(a)))
  elif or(eq(ta, 3), eq(ta, 4)) then and(eq(prim_id(a), prim_id(b)), slots_eq(a, b, 0, prim_len(a)))
  elif eq(ta, 7) then eq(prim_id(a), prim_id(b))
  else false
  end
end

fn str_eq(a: String, b: String, i: Int, n: Int) -> Bool
  if ne(n, prim_len(b)) then false
  elif ge(i, n) then true
  elif ne(prim_byte(a, i), prim_byte(b, i)) then false
  else str_eq(a, b, add(i, 1), n)
  end
end

fn slots_eq(a: Int, b: Int, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif equal(prim_slot(a, i), prim_slot(b, i)) then slots_eq(a, b, add(i, 1), n)
  else false
  end
end

fn compare(a: Int, b: Int) -> Int
  if and(eq(prim_tag(a), 1), eq(prim_tag(b), 1)) then str_cmp(a, b, 0)
  elif and(eq(prim_tag(a), 0), eq(prim_tag(b), 0)) then if lt(a, b) then -1 elif eq(a, b) then 0 else 1 end
  else
    type_fail("lt/le/gt/ge", "Int or String (both the same type)")
    0
  end
end

fn str_cmp(a: String, b: String, i: Int) -> Int
  let la = prim_len(a)
  let lb = prim_len(b)
  if and(ge(i, la), ge(i, lb)) then 0
  elif ge(i, la) then -1
  elif ge(i, lb) then 1
  else
    let x = prim_byte(a, i)
    let y = prim_byte(b, i)
    if lt(x, y) then -1 elif gt(x, y) then 1 else str_cmp(a, b, add(i, 1)) end
  end
end

fn digits(n: Int, acc: List[Int]) -> List[Int]
  if lt(n, 10) then list_cons(add(48, n), acc) else digits(div(n, 10), list_cons(add(48, mod(n, 10)), acc)) end
end

fn int_str(n: Int) -> String
  if lt(n, 0) then str_cat("-", str_from_bytes(digits(sub(0, n), []))) else str_from_bytes(digits(n, [])) end
end

fn hex_digit(d: Int) -> Int
  if lt(d, 10) then add(48, d) else add(87, d) end
end

fn quote_bytes(s: String, i: Int, acc: List[String]) -> List[String]
  if ge(i, prim_len(s)) then acc else
    let c = prim_byte(s, i)
    let piece = if eq(c, 34) then "\\\""
      elif eq(c, 92) then "\\\\"
      elif eq(c, 10) then "\\n"
      elif eq(c, 9) then "\\t"
      elif eq(c, 13) then "\\r"
      elif or(lt(c, 32), eq(c, 127)) then str_from_bytes([92, 120, hex_digit(div(c, 16)), hex_digit(mod(c, 16))])
      else str_from_bytes([c])
      end
    quote_bytes(s, add(i, 1), list_push(acc, piece))
  end
end

fn quote(s: String) -> String
  str_join(list_concat(list_push(quote_bytes(s, 0, ["\""]), "\""), []), "")
end

fn show(v: Int) -> String
  if eq(prim_tag(v), 1) then v else show_inner(v) end
end

fn show_slots(v: Int, i: Int, n: Int, acc: List[String]) -> List[String]
  if ge(i, n) then acc else show_slots(v, add(i, 1), n, list_push(acc, show_inner(prim_slot(v, i)))) end
end

fn show_fields(v: Int, i: Int, n: Int, acc: List[String]) -> List[String]
  if ge(i, n) then acc else show_fields(v, add(i, 1), n, list_push(acc, str_join([prim_field_name(v, i), ": ", show_inner(prim_slot(v, i))], ""))) end
end

fn show_inner(v: Int) -> String
  let t = prim_tag(v)
  if eq(t, 0) then int_str(v)
  elif eq(t, 1) then quote(v)
  elif eq(t, 2) then str_join(["[", str_join(show_slots(v, 0, prim_len(v), []), ", "), "]"], "")
  elif eq(t, 3) then str_join([prim_record_name(v), " { ", str_join(show_fields(v, 0, prim_len(v), []), ", "), " }"], "")
  elif eq(t, 4) then
    if eq(prim_len(v), 0) then prim_ctor_name(v) else str_join([prim_ctor_name(v), "(", str_join(show_slots(v, 0, prim_len(v), []), ", "), ")"], "") end
  elif eq(t, 5) then if eq(prim_id(v), 1) then "true" else "false" end
  elif eq(t, 6) then "<fn>"
  else "<handle>"
  end
end

# ---------- strings (byte strings) ----------

fn str_len(s: String) -> Int
  need(s, 1, "str_len", "String")
  prim_len(s)
end

fn str_cat(a: String, b: String) -> String
  need(a, 1, "str_cat", "String")
  need(b, 1, "str_cat", "String")
  let la = prim_len(a)
  let lb = prim_len(b)
  let s = prim_str_new(add(la, lb))
  prim_copy(s, 0, a, 0, la)
  prim_copy(s, la, b, 0, lb)
  s
end

fn join_len(l: List[String], i: Int, n: Int, acc: Int) -> Int
  if ge(i, n) then acc else
    let x = prim_slot(l, i)
    need(x, 1, "str_join", "a List of String")
    join_len(l, add(i, 1), n, add(acc, prim_len(x)))
  end
end

fn join_fill(s: String, l: List[String], sep: String, i: Int, n: Int, off: Int) -> String
  if ge(i, n) then s else
    let x = prim_slot(l, i)
    prim_copy(s, off, x, 0, prim_len(x))
    let off2 = add(off, prim_len(x))
    if lt(add(i, 1), n) then
      prim_copy(s, off2, sep, 0, prim_len(sep))
      join_fill(s, l, sep, add(i, 1), n, add(off2, prim_len(sep)))
    else s end
  end
end

fn str_join(l: List[String], sep: String) -> String
  need(l, 2, "str_join", "List")
  let n = prim_len(l)
  let total = add(join_len(l, 0, n, 0), mul(prim_len(sep), max(0, sub(n, 1))))
  join_fill(prim_str_new(total), l, sep, 0, n, 0)
end

fn clamp(i: Int, lo: Int, hi: Int) -> Int
  if lt(i, lo) then lo elif gt(i, hi) then hi else i end
end

fn str_slice(s: String, from: Int, to: Int) -> String
  need(s, 1, "str_slice", "String")
  let n = prim_len(s)
  let f = clamp(from, 0, n)
  let t = clamp(to, f, n)
  let r = prim_str_new(sub(t, f))
  prim_copy(r, 0, s, f, sub(t, f))
  r
end

fn match_at(s: String, sub_s: String, i: Int, j: Int, m: Int) -> Bool
  if ge(j, m) then true
  elif ne(prim_byte(s, add(i, j)), prim_byte(sub_s, j)) then false
  else match_at(s, sub_s, i, add(j, 1), m)
  end
end

fn find_from(s: String, sub_s: String, i: Int) -> Int
  let n = prim_len(s)
  let m = prim_len(sub_s)
  if gt(add(i, m), n) then -1
  elif match_at(s, sub_s, i, 0, m) then i
  else find_from(s, sub_s, add(i, 1))
  end
end

fn str_find(s: String, sub_s: String) -> Option[Int]
  need(s, 1, "str_find", "String")
  let i = find_from(s, sub_s, 0)
  if lt(i, 0) then None else Some(i) end
end

fn split_loop(s: String, sep: String, start: Int, acc: List[String]) -> List[String]
  let i = find_from(s, sep, start)
  if lt(i, 0) then list_push(acc, str_slice(s, start, prim_len(s)))
  else split_loop(s, sep, add(i, prim_len(sep)), list_push(acc, str_slice(s, start, i)))
  end
end

fn str_split(s: String, sep: String) -> List[String]
  need(s, 1, "str_split", "String")
  if eq(prim_len(sep), 0) then
    fail("runtime error: str_split: separator must not be empty")
    []
  else split_loop(s, sep, 0, []) end
end

fn is_space(c: Int) -> Bool
  or(eq(c, 32), and(ge(c, 9), le(c, 13)))
end

fn trim_start(s: String, i: Int) -> Int
  if and(lt(i, prim_len(s)), is_space(prim_byte(s, i))) then trim_start(s, add(i, 1)) else i end
end

fn trim_end(s: String, j: Int, lo: Int) -> Int
  if and(gt(j, lo), is_space(prim_byte(s, sub(j, 1)))) then trim_end(s, sub(j, 1), lo) else j end
end

fn str_trim(s: String) -> String
  need(s, 1, "str_trim", "String")
  let i = trim_start(s, 0)
  str_slice(s, i, trim_end(s, prim_len(s), i))
end

fn str_starts(s: String, p: String) -> Bool
  and(le(prim_len(p), prim_len(s)), match_at(s, p, 0, 0, prim_len(p)))
end

fn str_ends(s: String, p: String) -> Bool
  and(le(prim_len(p), prim_len(s)), match_at(s, p, sub(prim_len(s), prim_len(p)), 0, prim_len(p)))
end

fn repeat_fill(r: String, s: String, i: Int, n: Int) -> String
  if ge(i, n) then r else
    prim_copy(r, mul(i, prim_len(s)), s, 0, prim_len(s))
    repeat_fill(r, s, add(i, 1), n)
  end
end

fn str_repeat(s: String, n: Int) -> String
  let k = max(0, n)
  repeat_fill(prim_str_new(mul(k, prim_len(s))), s, 0, k)
end

fn lower_fill(r: String, s: String, i: Int) -> String
  if ge(i, prim_len(s)) then r else
    let c = prim_byte(s, i)
    prim_set_byte(r, i, if and(ge(c, 65), le(c, 90)) then add(c, 32) else c end)
    lower_fill(r, s, add(i, 1))
  end
end

fn str_lower(s: String) -> String
  lower_fill(prim_str_new(prim_len(s)), s, 0)
end

fn parse_uint(s: String, i: Int, acc: Int) -> Int
  if ge(i, prim_len(s)) then acc else
    let c = prim_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then parse_uint(s, add(i, 1), add(mul(acc, 10), sub(c, 48))) else -1 end
  end
end

fn str_to_int(s0: String) -> Option[Int]
  let s = str_trim(s0)
  let n = prim_len(s)
  if eq(n, 0) then None else
    let c = prim_byte(s, 0)
    let signed = or(eq(c, 45), eq(c, 43))
    let start = if signed then 1 else 0 end
    if ge(start, n) then None else
      let v = parse_uint(s, start, 0)
      if lt(v, 0) then None elif eq(c, 45) then Some(sub(0, v)) else Some(v) end
    end
  end
end

fn str_byte(s: String, i: Int) -> Int
  if or(lt(i, 0), ge(i, prim_len(s))) then
    fail(str_join(["runtime error: str_byte: index ", show(i), " out of range (length ", show(prim_len(s)), ")"], ""))
    0
  else prim_byte(s, i) end
end

fn bytes_fill(s: String, l: List[Int], i: Int, n: Int) -> String
  if ge(i, n) then s else
    prim_set_byte(s, i, prim_slot(l, i))
    bytes_fill(s, l, add(i, 1), n)
  end
end

fn str_from_bytes(l: List[Int]) -> String
  need(l, 2, "str_from_bytes", "List")
  bytes_fill(prim_str_new(prim_len(l)), l, 0, prim_len(l))
end

# ---------- lists (immutable arrays) ----------

fn list_len(l: List[Int]) -> Int
  need(l, 2, "list_len", "List")
  prim_len(l)
end

fn list_get(l: List[Int], i: Int) -> Option[Int]
  need(l, 2, "list_get", "List")
  if or(lt(i, 0), ge(i, prim_len(l))) then None else Some(prim_slot(l, i)) end
end

fn copy_into(dst: List[Int], doff: Int, src: List[Int], i: Int, n: Int) -> List[Int]
  if ge(i, n) then dst else
    prim_set_slot(dst, add(doff, i), prim_slot(src, i))
    copy_into(dst, doff, src, add(i, 1), n)
  end
end

fn list_cons(x: Int, l: List[Int]) -> List[Int]
  need(l, 2, "list_cons", "List")
  let r = prim_list_new(add(prim_len(l), 1))
  prim_set_slot(r, 0, x)
  copy_into(r, 1, l, 0, prim_len(l))
end

fn list_push(l: List[Int], x: Int) -> List[Int]
  need(l, 2, "list_push", "List")
  let n = prim_len(l)
  let r = copy_into(prim_list_new(add(n, 1)), 0, l, 0, n)
  prim_set_slot(r, n, x)
  r
end

fn list_concat(a: List[Int], b: List[Int]) -> List[Int]
  need(a, 2, "list_concat", "List")
  need(b, 2, "list_concat", "List")
  let r = copy_into(prim_list_new(add(prim_len(a), prim_len(b))), 0, a, 0, prim_len(a))
  copy_into(r, prim_len(a), b, 0, prim_len(b))
end

fn list_slice(l: List[Int], from: Int, to: Int) -> List[Int]
  need(l, 2, "list_slice", "List")
  let n = prim_len(l)
  let f = clamp(from, 0, n)
  let t = clamp(to, f, n)
  copy_into(prim_list_new(sub(t, f)), 0, prim_list_view(l, f, sub(t, f)), 0, sub(t, f))
end

fn rev_fill(r: List[Int], l: List[Int], i: Int, n: Int) -> List[Int]
  if ge(i, n) then r else
    prim_set_slot(r, sub(sub(n, 1), i), prim_slot(l, i))
    rev_fill(r, l, add(i, 1), n)
  end
end

fn list_reverse(l: List[Int]) -> List[Int]
  rev_fill(prim_list_new(prim_len(l)), l, 0, prim_len(l))
end

fn range_fill(r: List[Int], from: Int, i: Int, n: Int) -> List[Int]
  if ge(i, n) then r else
    prim_set_slot(r, i, add(from, i))
    range_fill(r, from, add(i, 1), n)
  end
end

fn list_range(from: Int, to: Int) -> List[Int]
  let n = max(0, sub(to, from))
  range_fill(prim_list_new(n), from, 0, n)
end

fn contains_loop(l: List[Int], x: Int, i: Int, n: Int) -> Bool
  if ge(i, n) then false elif equal(prim_slot(l, i), x) then true else contains_loop(l, x, add(i, 1), n) end
end

fn list_contains(l: List[Int], x: Int) -> Bool
  need(l, 2, "list_contains", "List")
  contains_loop(l, x, 0, prim_len(l))
end

fn map_fill(r: List[Int], l: List[Int], f: Fn(Int) -> Int, i: Int, n: Int) -> List[Int]
  if ge(i, n) then r else
    prim_set_slot(r, i, f(prim_slot(l, i)))
    map_fill(r, l, f, add(i, 1), n)
  end
end

fn list_map(l: List[Int], f: Fn(Int) -> Int) -> List[Int]
  need(l, 2, "list_map", "List")
  map_fill(prim_list_new(prim_len(l)), l, f, 0, prim_len(l))
end

fn filter_fill(r: List[Int], l: List[Int], f: Fn(Int) -> Bool, i: Int, n: Int, k: Int) -> List[Int]
  if ge(i, n) then prim_list_view(r, 0, k) else
    let x = prim_slot(l, i)
    let keep = f(x)
    if eq(prim_tag(keep), 5) then Unit else type_fail("list_filter", "a predicate returning Bool") end
    if keep then
      prim_set_slot(r, k, x)
      filter_fill(r, l, f, add(i, 1), n, add(k, 1))
    else filter_fill(r, l, f, add(i, 1), n, k) end
  end
end

fn list_filter(l: List[Int], f: Fn(Int) -> Bool) -> List[Int]
  need(l, 2, "list_filter", "List")
  filter_fill(prim_list_new(prim_len(l)), l, f, 0, prim_len(l), 0)
end

fn fold_loop(l: List[Int], acc: Int, f: Fn(Int, Int) -> Int, i: Int, n: Int) -> Int
  if ge(i, n) then acc else fold_loop(l, f(acc, prim_slot(l, i)), f, add(i, 1), n) end
end

fn list_fold(l: List[Int], init: Int, f: Fn(Int, Int) -> Int) -> Int
  need(l, 2, "list_fold", "List")
  fold_loop(l, init, f, 0, prim_len(l))
end

fn merge(a: List[Int], b: List[Int], i: Int, j: Int, r: List[Int]) -> List[Int]
  let na = prim_len(a)
  let nb = prim_len(b)
  if and(ge(i, na), ge(j, nb)) then r
  elif ge(i, na) then
    prim_set_slot(r, add(i, j), prim_slot(b, j))
    merge(a, b, i, add(j, 1), r)
  elif ge(j, nb) then
    prim_set_slot(r, add(i, j), prim_slot(a, i))
    merge(a, b, add(i, 1), j, r)
  elif le(compare(prim_slot(a, i), prim_slot(b, j)), 0) then
    prim_set_slot(r, add(i, j), prim_slot(a, i))
    merge(a, b, add(i, 1), j, r)
  else
    prim_set_slot(r, add(i, j), prim_slot(b, j))
    merge(a, b, i, add(j, 1), r)
  end
end

fn list_sort(l: List[Int]) -> List[Int]
  let n = prim_len(l)
  if le(n, 1) then l else
    let h = div(n, 2)
    let a = list_sort(prim_list_view(l, 0, h))
    let b = list_sort(prim_list_view(l, h, sub(n, h)))
    merge(a, b, 0, 0, prim_list_new(n))
  end
end

# ---------- io ----------

fn print(s: String) -> Unit
  need(s, 1, "print", "String")
  write_all(1, s, 0)
  Unit
end

fn println(s: String) -> Unit
  need(s, 1, "println", "String")
  write_all(1, str_cat(s, "\n"), 0)
  Unit
end

fn read_line_loop(buf: String, acc: List[Int]) -> Option[String]
  let n = sys(0, 0, prim_addr(buf), 1)
  if le(n, 0) then
    if eq(list_len(acc), 0) then None else Some(str_from_bytes(acc)) end
  else
    let c = prim_byte(buf, 0)
    if eq(c, 10) then Some(str_from_bytes(trim_cr(acc))) else read_line_loop(buf, list_push(acc, c)) end
  end
end

fn trim_cr(acc: List[Int]) -> List[Int]
  match list_get(acc, sub(prim_len(acc), 1))
    case Some(13) -> list_slice(acc, 0, sub(prim_len(acc), 1))
    case _ -> acc
  end
end

fn read_line() -> Option[String]
  read_line_loop(zeros(1), [])
end

fn cstring_len(addr: Int, i: Int) -> Int
  if eq(prim_peek8(add(addr, i)), 0) then i else cstring_len(addr, add(i, 1)) end
end

fn cstring_fill(s: String, addr: Int, i: Int, n: Int) -> String
  if ge(i, n) then s else
    prim_set_byte(s, i, prim_peek8(add(addr, i)))
    cstring_fill(s, addr, add(i, 1), n)
  end
end

fn cstring_at(addr: Int) -> String
  let n = cstring_len(addr, 0)
  cstring_fill(prim_str_new(n), addr, 0, n)
end

fn argc() -> Int
  prim_peek(prim_argv())
end

fn args_loop(i: Int, n: Int, acc: List[String]) -> List[String]
  if ge(i, n) then acc else args_loop(add(i, 1), n, list_push(acc, cstring_at(prim_peek(add(prim_argv(), mul(8, add(i, 1))))))) end
end

fn args() -> List[String]
  args_loop(1, argc(), [])
end

fn envp() -> Int
  add(prim_argv(), mul(8, add(argc(), 2)))
end

fn env_loop(prefix: String, i: Int) -> Option[String]
  let p = prim_peek(add(envp(), mul(8, i)))
  if eq(p, 0) then None else
    let s = cstring_at(p)
    if str_starts(s, prefix) then Some(str_slice(s, prim_len(prefix), prim_len(s))) else env_loop(prefix, add(i, 1)) end
  end
end

fn env_get(name: String) -> Option[String]
  env_loop(str_cat(name, "="), 0)
end

fn exit(code: Int) -> Unit
  restore_quiet()
  sys(231, code, 0, 0)
  Unit
end

# ---------- terminal ----------

fn has_bit(b: Int, m: Int) -> Bool
  eq(mod(div(b, m), 2), 1)
end

fn term_raw() -> Result[Unit, String]
  let t = zeros(64)
  let r = sys(16, 0, 21505, prim_addr(t))
  if lt(r, 0) then Err(str_cat("stdin is not a terminal: ", errno_msg(r))) else
    let saved = str_slice(t, 0, 64)
    match prim_slot(state, 0)
      case Unit ->
        prim_set_slot(state, 0, saved)
        prim_term_save(saved)
      case _ -> Unit
    end
    let lf = prim_byte(t, 12)
    let lf2 = sub(sub(lf, if has_bit(lf, 2) then 2 else 0 end), if has_bit(lf, 8) then 8 else 0 end)
    prim_set_byte(t, 12, lf2)
    prim_set_byte(t, 22, 0)
    prim_set_byte(t, 23, 0)
    let r2 = sys(16, 0, 21506, prim_addr(t))
    if lt(r2, 0) then Err(errno_msg(r2)) else
      write_all(1, "\e[?25l", 0)
      Ok(Unit)
    end
  end
end

fn term_restore() -> Unit
  restore_quiet()
end

fn pending() -> String
  match prim_slot(state, 1)
    case Unit -> ""
    case s -> s
  end
end

fn term_key() -> String
  let buf = zeros(64)
  let n = match prim_slot(state, 0)
    case Unit -> 0
    case _ -> sys(0, 0, prim_addr(buf), 64)
  end
  let p = if gt(n, 0) then str_cat(pending(), str_slice(buf, 0, n)) else pending() end
  let np = prim_len(p)
  if eq(np, 0) then "" else
    let c = prim_byte(p, 0)
    if eq(c, 27) then
      if and(ge(np, 3), eq(prim_byte(p, 1), 91)) then
        prim_set_slot(state, 1, str_slice(p, 3, np))
        match prim_byte(p, 2)
          case 65 -> "up"
          case 66 -> "down"
          case 67 -> "right"
          case 68 -> "left"
          case _ -> term_key()
        end
      else
        prim_set_slot(state, 1, str_slice(p, 1, np))
        "esc"
      end
    else
      prim_set_slot(state, 1, str_slice(p, 1, np))
      str_slice(p, 0, 1)
    end
  end
end

# ---------- time ----------

fn now_ms() -> Int
  let ts = zeros(16)
  sys(228, 0, prim_addr(ts), 0)
  add(mul(u_le(ts, 0, 8), 1000), div(u_le(ts, 8, 8), 1000000))
end

fn sleep_ms(n: Int) -> Unit
  let ts = zeros(16)
  put_le(ts, 0, div(max(0, n), 1000), 8)
  put_le(ts, 8, mul(mod(max(0, n), 1000), 1000000), 8)
  sys(35, prim_addr(ts), 0, 0)
  Unit
end

# ---------- net ----------

fn parse_ip(parts: List[String], acc: List[Int]) -> Option[List[Int]]
  match parts
    case [] -> if eq(list_len(acc), 4) then Some(acc) else None end
    case [p, ..rest] ->
      match str_to_int(p)
        case Some(v) -> if and(ge(v, 0), le(v, 255)) then parse_ip(rest, list_push(acc, v)) else None end
        case None -> None
      end
  end
end

fn sockaddr(addr: String) -> Option[String]
  match str_split(addr, ":")
    case [host, port] ->
      match str_to_int(port)
        case None -> None
        case Some(pn) ->
          match parse_ip(str_split(if eq(host, "") then "0.0.0.0" else host end, "."), [])
            case None -> None
            case Some(ip) -> Some(str_from_bytes(list_concat(list_concat([2, 0, div(pn, 256), mod(pn, 256)], ip), [0, 0, 0, 0, 0, 0, 0, 0])))
          end
      end
    case _ -> None
  end
end

fn tcp_listen(addr: String) -> Result[Int, String]
  match sockaddr(addr)
    case None -> Err(str_cat("bad address (want ip:port): ", addr))
    case Some(sa) ->
      let fd = sys(41, 2, 524289, 0)
      if lt(fd, 0) then Err(errno_msg(fd)) else
        let one = str_from_bytes([1, 0, 0, 0])
        sys5(54, fd, 1, 2, prim_addr(one), 4)
        let r = sys(49, fd, prim_addr(sa), 16)
        if lt(r, 0) then
          sys(3, fd, 0, 0)
          Err(str_join(["listen tcp ", addr, ": bind: ", errno_msg(r)], ""))
        else
          let r2 = sys(50, fd, 128, 0)
          if lt(r2, 0) then Err(errno_msg(r2)) else Ok(prim_handle(fd)) end
        end
      end
  end
end

fn tcp_accept(l: Int) -> Result[Int, String]
  let fd = sys(43, prim_id(l), 0, 0)
  if lt(fd, 0) then Err(errno_msg(fd)) else Ok(prim_handle(fd)) end
end

fn tcp_read(c: Int, max_bytes: Int, timeout: Int) -> Result[String, String]
  let fd = prim_id(c)
  let pfd = zeros(8)
  put_le(pfd, 0, fd, 4)
  put_le(pfd, 4, 1, 2)
  let pr = sys(7, prim_addr(pfd), 1, timeout)
  if lt(pr, 0) then Err(errno_msg(pr))
  elif eq(pr, 0) then Err("i/o timeout")
  else
    let n = clamp(max_bytes, 1, 1048576)
    let buf = prim_str_new(n)
    let r = sys(0, fd, prim_addr(buf), n)
    if lt(r, 0) then Err(errno_msg(r)) else Ok(str_slice(buf, 0, r)) end
  end
end

fn tcp_write(c: Int, s: String) -> Result[Unit, String]
  let r = write_all(prim_id(c), s, 0)
  if lt(r, 0) then Err(errno_msg(r)) else Ok(Unit) end
end

fn tcp_close(c: Int) -> Unit
  sys(3, prim_id(c), 0, 0)
  Unit
end

# ---------- files ----------

fn read_chunks(fd: Int, acc: List[String]) -> Result[String, String]
  let buf = prim_str_new(65536)
  let n = sys(0, fd, prim_addr(buf), 65536)
  if lt(n, 0) then Err(errno_msg(n))
  elif eq(n, 0) then Ok(str_join(acc, ""))
  else read_chunks(fd, list_push(acc, str_slice(buf, 0, n)))
  end
end

fn read_file(path: String) -> Result[String, String]
  let fd = sys(2, prim_addr(cstr(path)), 0, 0)
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", errno_msg(fd)], "")) else
    let r = read_chunks(fd, [])
    sys(3, fd, 0, 0)
    r
  end
end

fn write_file(path: String, content: String, mode_bits: Int) -> Result[Unit, String]
  let fd = sys(2, prim_addr(cstr(path)), 577, mode_bits)
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", errno_msg(fd)], "")) else
    let w = write_all(fd, content, 0)
    sys(91, fd, mode_bits, 0)
    sys(3, fd, 0, 0)
    if lt(w, 0) then Err(errno_msg(w)) else Ok(Unit) end
  end
end

fn dirents(buf: String, off: Int, n: Int, acc: List[String]) -> List[String]
  if ge(off, n) then acc else
    let reclen = u_le(buf, add(off, 16), 2)
    let name = cstring_at(add(prim_addr(buf), add(off, 19)))
    let acc2 = if or(eq(name, "."), eq(name, "..")) then acc else list_push(acc, name) end
    dirents(buf, add(off, reclen), n, acc2)
  end
end

fn read_dir(fd: Int, acc: List[String]) -> Result[List[String], String]
  let buf = prim_str_new(32768)
  let n = sys(217, fd, prim_addr(buf), 32768)
  if lt(n, 0) then Err(errno_msg(n))
  elif eq(n, 0) then Ok(acc)
  else read_dir(fd, dirents(buf, 0, n, acc))
  end
end

fn list_dir(path: String) -> Result[List[String], String]
  let fd = sys(2, prim_addr(cstr(path)), 65536, 0)
  if lt(fd, 0) then Err(str_join(["open ", path, ": ", errno_msg(fd)], "")) else
    let r = read_dir(fd, [])
    sys(3, fd, 0, 0)
    match r
      case Ok(names) -> Ok(list_sort(names))
      case e -> e
    end
  end
end

# ---------- processes ----------

fn ptr_array(cs: List[String]) -> String
  let n = prim_len(cs)
  let buf = zeros(mul(8, add(n, 1)))
  list_fold(list_range(0, n), buf, fn(b, i)
    put_le(b, mul(8, i), prim_addr(prim_slot(cs, i)), 8)
    b
  end)
end

fn run_image(bin: String, argv: List[String]) -> Result[Unit, String]
  let fd = sys(319, prim_addr(cstr("kaizo-app")), 0, 0)
  if lt(fd, 0) then Err(str_cat("memfd_create: ", errno_msg(fd))) else
    write_all(fd, bin, 0)
    let cs = list_map(list_cons("app", argv), cstr)
    let av = ptr_array(cs)
    restore_quiet()
    let r = prim_syscall(322, fd, prim_addr(cstr("")), prim_addr(av), envp(), 4096, 0)
    Err(str_cat("execveat: ", errno_msg(r)))
  end
end

# ---------- tests: one forked child per test ----------

fn run_tests(path: String, names: List[String], fns: List[Fn() -> Unit]) -> Unit
  let n = prim_len(names)
  let failed = run_test_loop(names, fns, 0, n, 0)
  println(str_join([path, ": ", show(sub(n, failed)), " passed, ", show(failed), " failed"], ""))
  exit(if gt(failed, 0) then 1 else 0 end)
end

fn run_test_loop(names: List[String], fns: List[Fn() -> Unit], i: Int, n: Int, failed: Int) -> Int
  if ge(i, n) then failed else
    let name = prim_slot(names, i)
    let pid = sys(57, 0, 0, 0)
    if eq(pid, 0) then
      let f = prim_slot(fns, i)
      f()
      sys(231, 0, 0, 0)
      0
    else
      let st = zeros(8)
      sys5(61, pid, prim_addr(st), 0, 0, 0)
      let sig = mod(prim_byte(st, 0), 128)
      let code = prim_byte(st, 1)
      if and(eq(sig, 0), eq(code, 0)) then
        println(str_cat("PASS ", name))
        run_test_loop(names, fns, add(i, 1), n, failed)
      else
        let why = if ne(sig, 0) then str_join(["  (crashed with signal ", show(sig), ")"], "") else "" end
        println(str_join(["FAIL ", name, why], ""))
        run_test_loop(names, fns, add(i, 1), n, add(failed, 1))
      end
    end
  end
end
