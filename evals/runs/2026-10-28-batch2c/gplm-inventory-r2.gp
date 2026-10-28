type Cmd = Add(String, String, Int) | Remove(String, String, Int) | Move(String, Int, String, String) | Report | Total(String) | Skip | Bad end

type Tree = Leaf | Node(Tree, String, String, Int, Tree, Int) end

type Outcome = { tree: Tree, out: List[String], failed: Bool } end

# ---------- parsing ----------

fn is_name_char(b: Int) -> Bool
  or(and(ge(b, 97), le(b, 122)), and(ge(b, 48), le(b, 57)), eq(b, 95))
end

fn valid_name_from(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif is_name_char(str_byte(s, i)) then valid_name_from(s, add(i, 1), n)
  else false end
end

fn valid_name(s: String) -> Bool
  if gt(str_len(s), 0) then valid_name_from(s, 0, str_len(s)) else false end
end

fn all_digits(s: String, i: Int, n: Int) -> Bool
  if ge(i, n) then true
  elif and(ge(str_byte(s, i), 48), le(str_byte(s, i), 57)) then all_digits(s, add(i, 1), n)
  else false end
end

fn parse_qty(s: String) -> Option[Int]
  if and(gt(str_len(s), 0), le(str_len(s), 18)) then
    if all_digits(s, 0, str_len(s)) then
      match str_to_int(s)
        case Some(v) -> if gt(v, 0) then Some(v) else None end
        case None -> None
      end
    else None end
  else None end
end

fn mk_lq(l: String, i: String, q: String, is_add: Bool) -> Cmd
  if and(valid_name(l), valid_name(i)) then
    match parse_qty(q)
      case Some(n) -> if is_add then Add(l, i, n) else Remove(l, i, n) end
      case None -> Bad
    end
  else Bad end
end

fn mk_move(i: String, q: String, f: String, t: String) -> Cmd
  if and(valid_name(i), valid_name(f), valid_name(t), ne(f, t)) then
    match parse_qty(q)
      case Some(n) -> Move(i, n, f, t)
      case None -> Bad
    end
  else Bad end
end

fn parse_words(w: List[String]) -> Cmd
  match w
    case ["add", l, i, q] -> mk_lq(l, i, q, true)
    case ["remove", l, i, q] -> mk_lq(l, i, q, false)
    case ["move", i, q, f, t] -> mk_move(i, q, f, t)
    case ["report"] -> Report
    case ["total", i] -> if valid_name(i) then Total(i) else Bad end
    case _ -> Bad
  end
end

fn parse(line: String) -> Cmd
  if eq(line, "") then Skip
  elif str_starts(line, "#") then Skip
  else parse_words(str_split(line, " ")) end
end

# ---------- AVL tree keyed by (loc, item) ----------

fn cmp_key(l1: String, i1: String, l2: String, i2: String) -> Int
  if lt(l1, l2) then -1
  elif gt(l1, l2) then 1
  elif lt(i1, i2) then -1
  elif gt(i1, i2) then 1
  else 0 end
end

fn height(t: Tree) -> Int
  match t
    case Leaf -> 0
    case Node(_, _, _, _, _, h) -> h
  end
end

fn left_of(t: Tree) -> Tree
  match t
    case Leaf -> Leaf
    case Node(l, _, _, _, _, _) -> l
  end
end

fn right_of(t: Tree) -> Tree
  match t
    case Leaf -> Leaf
    case Node(_, _, _, _, r, _) -> r
  end
end

fn node(l: Tree, a: String, b: String, q: Int, r: Tree) -> Tree
  Node(l, a, b, q, r, add(max(height(l), height(r)), 1))
end

fn rot_right(t: Tree) -> Tree
  match t
    case Node(Node(ll, la, lb, lq, lr, _), a, b, q, r, _) -> node(ll, la, lb, lq, node(lr, a, b, q, r))
    case _ -> t
  end
end

fn rot_left(t: Tree) -> Tree
  match t
    case Node(l, a, b, q, Node(rl, ra, rb, rq, rr, _), _) -> node(node(l, a, b, q, rl), ra, rb, rq, rr)
    case _ -> t
  end
end

fn balance(l: Tree, a: String, b: String, q: Int, r: Tree) -> Tree
  let hl = height(l)
  let hr = height(r)
  if gt(hl, add(hr, 1)) then
    let l2 = if lt(height(left_of(l)), height(right_of(l))) then rot_left(l) else l end
    rot_right(node(l2, a, b, q, r))
  elif gt(hr, add(hl, 1)) then
    let r2 = if lt(height(right_of(r)), height(left_of(r))) then rot_right(r) else r end
    rot_left(node(l, a, b, q, r2))
  else node(l, a, b, q, r) end
end

fn get_qty(t: Tree, loc: String, item: String) -> Int
  match t
    case Leaf -> 0
    case Node(l, k1, k2, q, r, _) ->
      let c = cmp_key(loc, item, k1, k2)
      if lt(c, 0) then get_qty(l, loc, item)
      elif gt(c, 0) then get_qty(r, loc, item)
      else q end
  end
end

fn set_qty(t: Tree, loc: String, item: String, v: Int) -> Tree
  match t
    case Leaf -> Node(Leaf, loc, item, v, Leaf, 1)
    case Node(l, k1, k2, q, r, h) ->
      let c = cmp_key(loc, item, k1, k2)
      if lt(c, 0) then balance(set_qty(l, loc, item, v), k1, k2, q, r)
      elif gt(c, 0) then balance(l, k1, k2, q, set_qty(r, loc, item, v))
      else Node(l, k1, k2, v, r, h) end
  end
end

fn sum_item(t: Tree, item: String) -> Int
  match t
    case Leaf -> 0
    case Node(l, _, k2, q, r, _) ->
      let here = if eq(k2, item) then q else 0 end
      add(sum_item(l, item), here, sum_item(r, item))
  end
end

fn report_lines(t: Tree, acc: List[String]) -> List[String]
  match t
    case Leaf -> acc
    case Node(l, k1, k2, q, r, _) ->
      let a1 = report_lines(l, acc)
      let a2 = if ne(q, 0) then list_push(a1, str_cat(k1, " ", k2, " ", show(q))) else a1 end
      report_lines(r, a2)
  end
end

# ---------- applying commands ----------

fn ok_out(t: Tree) -> Outcome
  Outcome { tree: t, out: [], failed: false }
end

fn not_enough(t: Tree, n: Int, item: String, loc: String) -> Outcome
  Outcome { tree: t, out: [str_cat("error: line ", show(n), ": not enough ", item, " at ", loc)], failed: true }
end

fn step(t: Tree, cmd: Cmd, n: Int) -> Outcome
  match cmd
    case Skip -> ok_out(t)
    case Bad -> Outcome { tree: t, out: [str_cat("error: line ", show(n), ": bad command")], failed: true }
    case Add(l, i, q) -> ok_out(set_qty(t, l, i, add(get_qty(t, l, i), q)))
    case Remove(l, i, q) ->
      let have = get_qty(t, l, i)
      if lt(have, q) then not_enough(t, n, i, l) else ok_out(set_qty(t, l, i, sub(have, q))) end
    case Move(i, q, f, to) ->
      let have = get_qty(t, f, i)
      if lt(have, q) then not_enough(t, n, i, f)
      else
        let t1 = set_qty(t, f, i, sub(have, q))
        ok_out(set_qty(t1, to, i, add(get_qty(t1, to, i), q)))
      end
    case Report ->
      let ls = report_lines(t, [])
      let out = if eq(list_len(ls), 0) then ["(empty)"] else ls end
      Outcome { tree: t, out: out, failed: false }
    case Total(i) -> Outcome { tree: t, out: [str_cat(i, " ", show(sum_item(t, i)))], failed: false }
  end
end

fn strip_cr(s: String) -> String
  if str_ends(s, "\r") then str_slice(s, 0, sub(str_len(s), 1)) else s end
end

fn run(lines: List[String], i: Int, n: Int, t: Tree, failed: Bool) -> Bool ! [io]
  if ge(i, n) then failed
  else
    let line = strip_cr(unwrap_or(list_get(lines, i), ""))
    let o = step(t, parse(line), add(i, 1))
    if gt(list_len(o.out), 0) then println(str_join(o.out, "\n")) else Unit end
    run(lines, add(i, 1), n, o.tree, or(failed, o.failed))
  end
end

fn main() -> Unit ! [io]
  let lines = str_split(read_all(), "\n")
  let failed = run(lines, 0, list_len(lines), Leaf, false)
  if failed then exit(1) else exit(0) end
end

# ---------- tests ----------

test "parse valid and invalid commands"
  expect_eq(parse("add main apple 5"), Add("main", "apple", 5))
  expect_eq(parse("move apple 3 main shop"), Move("apple", 3, "main", "shop"))
  expect_eq(parse("move apple 3 main main"), Bad)
  expect_eq(parse("add main apple 0"), Bad)
  expect_eq(parse("add Main apple 1"), Bad)
  expect_eq(parse("add main  apple 1"), Bad)
  expect_eq(parse("report x"), Bad)
  expect_eq(parse("# comment"), Skip)
  expect_eq(parse(""), Skip)
end

test "remove with too little stock fails and changes nothing"
  let o1 = step(Leaf, Add("main", "apple", 2), 1)
  let o2 = step(o1.tree, Remove("main", "apple", 3), 2)
  expect_eq(o2.failed, true)
  expect_eq(o2.out, ["error: line 2: not enough apple at main"])
  expect_eq(get_qty(o2.tree, "main", "apple"), 2)
end

test "example script report and total"
  let o1 = step(Leaf, Add("main", "apple", 5), 1)
  let o2 = step(o1.tree, Add("main", "pear", 2), 2)
  let o3 = step(o2.tree, Move("apple", 3, "main", "shop"), 3)
  let o4 = step(o3.tree, Total("apple"), 4)
  expect_eq(o4.out, ["apple 5"])
  let o5 = step(o3.tree, Report, 5)
  expect_eq(o5.out, ["main apple 2", "main pear 2", "shop apple 3"])
  let o6 = step(Leaf, Report, 1)
  expect_eq(o6.out, ["(empty)"])
end

test "many inserts stay balanced"
  let t = list_fold(list_range(0, 1000), Leaf, fn(acc, k) set_qty(acc, str_cat("l", show(add(10000, k))), "x", 1) end)
  expect(le(height(t), 20), "tree too deep")
  expect_eq(sum_item(t, "x"), 1000)
end
