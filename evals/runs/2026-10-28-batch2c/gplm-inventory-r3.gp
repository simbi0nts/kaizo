# inventory: stock keeper driven by commands on stdin

type Tree = Leaf | Node(Tree, String, Int, Tree, Int) end
type Inv = { stock: Tree, totals: Tree } end
type Outcome = Done(Inv, List[String]) | Failed(String) end
type Final = { out: List[String], err: Bool } end

# ---------- AVL map String -> Int ----------

fn height(t: Tree) -> Int
  match t
    case Leaf -> 0
    case Node(_, _, _, _, h) -> h
  end
end

fn mk(l: Tree, k: String, v: Int, r: Tree) -> Tree
  Node(l, k, v, r, add(max(height(l), height(r)), 1))
end

fn bal(l: Tree, k: String, v: Int, r: Tree) -> Tree
  let hl = height(l)
  let hr = height(r)
  if gt(hl, add(hr, 1)) then
    match l
      case Node(ll, lk, lv, lr, _) ->
        if ge(height(ll), height(lr)) then mk(ll, lk, lv, mk(lr, k, v, r))
        else
          match lr
            case Node(lrl, lrk, lrv, lrr, _) -> mk(mk(ll, lk, lv, lrl), lrk, lrv, mk(lrr, k, v, r))
            case Leaf -> mk(l, k, v, r)
          end
        end
      case Leaf -> mk(l, k, v, r)
    end
  elif gt(hr, add(hl, 1)) then
    match r
      case Node(rl, rk, rv, rr, _) ->
        if ge(height(rr), height(rl)) then mk(mk(l, k, v, rl), rk, rv, rr)
        else
          match rl
            case Node(rll, rlk, rlv, rlr, _) -> mk(mk(l, k, v, rll), rlk, rlv, mk(rlr, rk, rv, rr))
            case Leaf -> mk(l, k, v, r)
          end
        end
      case Leaf -> mk(l, k, v, r)
    end
  else mk(l, k, v, r) end
end

fn tree_set(t: Tree, k: String, v: Int) -> Tree
  match t
    case Leaf -> Node(Leaf, k, v, Leaf, 1)
    case Node(l, nk, nv, r, h) ->
      if lt(k, nk) then bal(tree_set(l, k, v), nk, nv, r)
      elif gt(k, nk) then bal(l, nk, nv, tree_set(r, k, v))
      else Node(l, k, v, r, h) end
  end
end

fn tree_get(t: Tree, k: String) -> Int
  match t
    case Leaf -> 0
    case Node(l, nk, nv, r, _) ->
      if lt(k, nk) then tree_get(l, k)
      elif gt(k, nk) then tree_get(r, k)
      else nv end
  end
end

fn to_lines(t: Tree, acc: List[String]) -> List[String]
  match t
    case Leaf -> acc
    case Node(l, k, v, r, _) ->
      let acc2 = to_lines(r, acc)
      let acc3 = if eq(v, 0) then acc2 else list_cons(str_cat(k, " ", show(v)), acc2) end
      to_lines(l, acc3)
  end
end

# ---------- validation ----------

fn name_chars_ok(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  else
    let c = str_byte(s, i)
    if or(and(ge(c, 97), le(c, 122)), and(ge(c, 48), le(c, 57)), eq(c, 95)) then
      name_chars_ok(s, add(i, 1), n)
    else false end
  end
end

fn valid_name(s: String) -> Bool
  let n = str_len(s)
  if gt(n, 0) then name_chars_ok(s, 0, n) else false end
end

fn digits_ok(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  else
    let c = str_byte(s, i)
    if and(ge(c, 48), le(c, 57)) then digits_ok(s, add(i, 1), n) else false end
  end
end

fn parse_qty(s: String) -> Option[Int]
  let n = str_len(s)
  if and(gt(n, 0), le(n, 18), digits_ok(s, 0, n)) then
    match str_to_int(s)
      case Some(v) -> if gt(v, 0) then Some(v) else None end
      case None -> None
    end
  else None end
end

# ---------- commands ----------

fn key(loc: String, item: String) -> String
  str_cat(loc, " ", item)
end

fn bad(n: Int) -> Outcome
  Failed(str_cat("error: line ", show(n), ": bad command"))
end

fn not_enough(n: Int, item: String, loc: String) -> Outcome
  Failed(str_cat("error: line ", show(n), ": not enough ", item, " at ", loc))
end

fn adjust(inv: Inv, loc: String, item: String, d: Int) -> Inv
  let k = key(loc, item)
  Inv {
    stock: tree_set(inv.stock, k, add(tree_get(inv.stock, k), d)),
    totals: tree_set(inv.totals, item, add(tree_get(inv.totals, item), d))
  }
end

fn exec(inv: Inv, words: List[String], n: Int) -> Outcome
  match words
    case ["add", loc, item, q] ->
      let qty = try parse_qty(q) else bad(n)
      if and(valid_name(loc), valid_name(item)) then Done(adjust(inv, loc, item, qty), [])
      else bad(n) end
    case ["remove", loc, item, q] ->
      let qty = try parse_qty(q) else bad(n)
      if and(valid_name(loc), valid_name(item)) then
        let cur = tree_get(inv.stock, key(loc, item))
        if lt(cur, qty) then not_enough(n, item, loc)
        else Done(adjust(inv, loc, item, sub(0, qty)), []) end
      else bad(n) end
    case ["move", item, q, src, dst] ->
      let qty = try parse_qty(q) else bad(n)
      if not(and(valid_name(item), valid_name(src), valid_name(dst))) then bad(n)
      elif eq(src, dst) then bad(n)
      else
        let cur = tree_get(inv.stock, key(src, item))
        if lt(cur, qty) then not_enough(n, item, src)
        else Done(adjust(adjust(inv, src, item, sub(0, qty)), dst, item, qty), []) end
      end
    case ["report"] ->
      let ls = to_lines(inv.stock, [])
      if eq(list_len(ls), 0) then Done(inv, ["(empty)"]) else Done(inv, ls) end
    case ["total", item] ->
      if valid_name(item) then Done(inv, [str_cat(item, " ", show(tree_get(inv.totals, item)))])
      else bad(n) end
    case _ -> bad(n)
  end
end

fn strip_cr(s: String) -> String
  if str_ends(s, "\r") then str_slice(s, 0, sub(str_len(s), 1)) else s end
end

fn process(lines: List[String], n: Int, inv: Inv, out: List[String], err: Bool) -> Final
  match lines
    case [] -> Final { out: list_reverse(out), err: err }
    case [raw, ..rest] ->
      let line = strip_cr(raw)
      if or(eq(line, ""), str_starts(line, "#")) then process(rest, add(n, 1), inv, out, err)
      else
        match exec(inv, str_split(line, " "), n)
          case Done(inv2, ls) ->
            let out2 = list_fold(ls, out, fn(acc, x) list_cons(x, acc) end)
            process(rest, add(n, 1), inv2, out2, err)
          case Failed(msg) -> process(rest, add(n, 1), inv, list_cons(msg, out), true)
        end
      end
  end
end

fn run_text(text: String) -> Final
  process(str_split(text, "\n"), 1, Inv { stock: Leaf, totals: Leaf }, [], false)
end

fn main() -> Unit ! [io]
  let f = run_text(read_all())
  if gt(list_len(f.out), 0) then println(str_join(f.out, "\n")) else Unit end
  if f.err then exit(1) else exit(0) end
end

# ---------- tests ----------

test "example script"
  let f = run_text("add main apple 5\nadd main pear 2\nmove apple 3 main shop\nremove shop apple 4\ntotal apple\nreport\n")
  expect_eq(f.out, ["error: line 4: not enough apple at shop", "apple 5", "main apple 2", "main pear 2", "shop apple 3"])
  expect_eq(f.err, true)
end

test "validation"
  expect_eq(valid_name("a_1"), true)
  expect_eq(valid_name("A"), false)
  expect_eq(valid_name(""), false)
  expect_eq(parse_qty("12"), Some(12))
  expect_eq(parse_qty("0"), None)
  expect_eq(parse_qty("-3"), None)
  expect_eq(parse_qty("+3"), None)
end

test "bad commands and empty report"
  let f = run_text("# comment\n\nmove x 1 a a\nadd a b 0\nadd a  b 1\nfoo\nreport\nadd z q 1\nremove z q 1\nreport")
  expect_eq(f.out, ["error: line 3: bad command", "error: line 4: bad command", "error: line 5: bad command", "error: line 6: bad command", "(empty)", "(empty)"])
  expect_eq(f.err, true)
end

test "no errors and sorting"
  let f = run_text("add b x 1\nadd a y 2\nadd a x 3\nadd ab x 4\nreport\ntotal x\ntotal none")
  expect_eq(f.out, ["a x 3", "a y 2", "ab x 4", "b x 1", "x 8", "none 0"])
  expect_eq(f.err, false)
end
