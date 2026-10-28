# Reference counting, decided at compile time (Perceus-style, invisible to the programmer).
#
# Every owned variable (parameter, let, pattern variable) holds one reference. A backward
# liveness pass decides, for every use, whether it is the last one (the reference moves) or
# not (dup: count + 1), and where values that are no longer needed are dropped:
#   - parameters never used: at function entry
#   - lets never used: right after the let
#   - variables used on only some branches: at the entry of the other branches
#   - pattern variables: dup on a successful match only if the arm uses them
#   - "borrowed" uses (field access, match on a variable, read-only intrinsics): no count
#     traffic; if that was the last use, the variable is dropped at the end of the statement.
# GPLM values are immutable and closures cannot refer to themselves, so the heap is acyclic and
# counting alone reclaims everything.

type RcAnn = { dups: Map[Bool], stmt_drops: Map[List[String]], entry: Map[List[String]], let_drop: Map[Bool], arm_live: Map[List[String]] } end
type Lv = { live: List[String], a: RcAnn } end

fn rc_empty() -> RcAnn
  RcAnn { dups: map.empty(), stmt_drops: map.empty(), entry: map.empty(), let_drop: map.empty(), arm_live: map.empty() }
end

fn dup_key(p: Pos, x: String) -> String
  str_join(["d:", pos_str(p), ":", x], "")
end

fn cap_key(p: Pos, x: String) -> String
  str_join(["c:", pos_str(p), ":", x], "")
end

fn stmt_key(s: Stmt) -> String
  str_join(["s:", pos_str(s.pos), ":", s.let_name], "")
end

fn arm_key(p: Pat) -> String
  str_cat("a:", pos_str(pat_pos(p)))
end

fn set_add(s: List[String], x: String) -> List[String]
  if list_contains(s, x) then s else list_push(s, x) end
end

fn set_union(a: List[String], b: List[String]) -> List[String]
  list_fold(b, a, set_add)
end

fn set_minus(a: List[String], b: List[String]) -> List[String]
  list_filter(a, fn(x) not(list_contains(b, x)) end)
end

fn set_inter(a: List[String], b: List[String]) -> List[String]
  list_filter(a, fn(x) list_contains(b, x) end)
end

# argument positions in which intrinsics only read (borrow) their argument
fn borrow_positions(name: String) -> List[Int]
  if eq(name, "prim_copy") then [0, 2]
  elif list_contains(["prim_slot_cmp", "prim_eq_flat", "prim_find_flat"], name) then [0, 1]
  elif eq(name, "prim_copy_slots") then [0, 2]
  elif list_contains(["prim_tag", "prim_len", "prim_id", "prim_slot", "prim_set_slot", "prim_byte", "prim_set_byte", "prim_list_view",
    "prim_record_copy", "prim_addr", "prim_ctor_name", "prim_record_name", "prim_field_name", "prim_term_save"], name) then [0]
  else []
  end
end

fn call_name(f: Expr) -> String
  match f
    case EVar(_, n) -> n
    case _ -> ""
  end
end

fn owned_var(e: Expr, owned: List[String]) -> Option[String]
  match e
    case EVar(_, x) -> if list_contains(owned, x) then Some(x) else None end
    case _ -> None
  end
end

fn is_borrowed_arg(f: Expr, i: Int) -> Bool
  list_contains(borrow_positions(call_name(f)), i)
end

# owned variables used in borrowed positions at this statement level (not inside nested blocks)
fn borrows(e: Expr, owned: List[String], acc: List[String]) -> List[String]
  match e
    case ECall(_, f, args) ->
      let r = list_fold(list_range(0, list_len(args)), acc, fn(a, i)
        let arg = unwrap_or(list_get(args, i), EInt(expr_pos(e), 0))
        let a2 = if is_borrowed_arg(f, i) then
          match owned_var(arg, owned)
            case Some(x) -> set_add(a, x)
            case None -> a
          end
        else a end
        borrows(arg, owned, a2)
      end)
      borrows(f, owned, r)
    case EField(_, x, _) ->
      match owned_var(x, owned)
        case Some(v) -> set_add(acc, v)
        case None -> borrows(x, owned, acc)
      end
    case EMatch(_, x, _) ->
      match owned_var(x, owned)
        case Some(v) -> set_add(acc, v)
        case None -> borrows(x, owned, acc)
      end
    case EIf(_, conds, _, _) -> list_fold(conds, acc, fn(a, c) borrows(c, owned, a) end)
    case EList(_, items) -> list_fold(items, acc, fn(a, x) borrows(x, owned, a) end)
    case ERec(_, _, fs) -> list_fold(fs, acc, fn(a, fi) borrows(fi.x, owned, a) end)
    case EUpd(_, x, fs) -> list_fold(fs, borrows(x, owned, acc), fn(a, fi) borrows(fi.x, owned, a) end)
    case _ -> acc
  end
end

fn mark_dup(a: RcAnn, k: String) -> RcAnn
  { a with dups: map.set(a.dups, k, true) }
end

# a consuming use of variable x at p
fn lv_use(a: RcAnn, p: Pos, x: String, after: List[String], owned: List[String]) -> Lv
  if not(list_contains(owned, x)) then Lv { live: after, a: a }
  elif list_contains(after, x) then Lv { live: after, a: mark_dup(a, dup_key(p, x)) }
  else Lv { live: list_push(after, x), a: a }
  end
end

# a borrowed use: keeps x alive, no ownership change
fn lv_borrow(a: RcAnn, x: String, after: List[String], owned: List[String]) -> Lv
  Lv { live: if list_contains(owned, x) then set_add(after, x) else after end, a: a }
end

# expressions evaluated in order xs: process them right to left
fn lv_seq(a: RcAnn, xs: List[Expr], after: List[String], owned: List[String]) -> Lv
  list_fold(list_reverse(xs), Lv { live: after, a: a }, fn(acc, x) lv_expr(acc.a, x, acc.live, owned) end)
end

fn lv_expr(a: RcAnn, e: Expr, after: List[String], owned: List[String]) -> Lv
  match e
    case EVar(p, x) -> lv_use(a, p, x, after, owned)
    case ECall(_, f, args) ->
      let r = list_fold(list_reverse(list_range(0, list_len(args))), Lv { live: after, a: a }, fn(acc, i)
        let arg = unwrap_or(list_get(args, i), EInt(expr_pos(e), 0))
        match if is_borrowed_arg(f, i) then owned_var(arg, owned) else None end
          case Some(x) -> lv_borrow(acc.a, x, acc.live, owned)
          case None -> lv_expr(acc.a, arg, acc.live, owned)
        end
      end)
      match f
        case EVar(_, _) -> if is_some(owned_var(f, owned)) then lv_expr(r.a, f, r.live, owned) else r end
        case _ -> lv_expr(r.a, f, r.live, owned)
      end
    case EField(_, x, _) ->
      match owned_var(x, owned)
        case Some(v) -> lv_borrow(a, v, after, owned)
        case None -> lv_expr(a, x, after, owned)
      end
    case EList(_, items) -> lv_seq(a, items, after, owned)
    case ERec(_, _, fs) -> lv_seq(a, list_map(fs, fn(fi) fi.x end), after, owned)
    case EUpd(_, x, fs) ->
      # field values are evaluated first and the record last, so the record's use can be its last one
      lv_seq(a, list_push(list_map(fs, fn(fi) fi.x end), x), after, owned)
    case EIf(_, conds, bodies, els) -> lv_if(a, conds, bodies, els, after, owned)
    case EMatch(_, x, arms) ->
      let r = list_fold(arms, MA { a: a, lives: [] }, fn(acc, arm)
        let bound = pat_names(arm.pat, [])
        let b = lv_block(acc.a, arm.body, after, set_union(owned, bound))
        let a2 = { b.a with arm_live: map.set(b.a.arm_live, arm_key(arm.pat), set_inter(b.live, bound)) }
        MA { a: a2, lives: list_push(acc.lives, set_minus(b.live, bound)) }
      end)
      let u = list_fold(r.lives, [], set_union)
      let a3 = list_fold(list_range(0, list_len(arms)), r.a, fn(acc, j)
        match list_get(arms, j)
          case Some(arm) -> { acc with entry: map.set(acc.entry, arm_key(arm.pat), set_minus(u, unwrap_or(list_get(r.lives, j), []))) }
          case None -> acc
        end
      end)
      match owned_var(x, owned)
        case Some(v) -> lv_borrow(a3, v, u, owned)
        case None -> lv_expr(a3, x, u, owned)
      end
    case ELam(p, params, body) ->
      let caps = set_inter(fv_block(body, params, []), owned)
      list_fold(list_reverse(caps), Lv { live: after, a: a }, fn(acc, c)
        if list_contains(acc.live, c) then Lv { live: acc.live, a: mark_dup(acc.a, cap_key(p, c)) } else Lv { live: list_push(acc.live, c), a: acc.a } end
      end)
    case _ -> Lv { live: after, a: a }
  end
end

type MA = { a: RcAnn, lives: List[List[String]] } end

fn cond_key(prefix: String, c: Expr) -> String
  str_cat(prefix, pos_str(expr_pos(c)))
end

fn lv_if(a: RcAnn, conds: List[Expr], bodies: List[List[Stmt]], els: List[Stmt], after: List[String], owned: List[String]) -> Lv
  match conds
    case [] -> lv_block(a, els, after, owned)
    case [c, ..rest] ->
      let t = lv_block(a, unwrap_or(list_get(bodies, 0), []), after, owned)
      let f = lv_if(t.a, rest, list_slice(bodies, 1, list_len(bodies)), els, after, owned)
      let u = set_union(t.live, f.live)
      let a2 = { f.a with entry: map.set(map.set(f.a.entry, cond_key("t:", c), set_minus(u, t.live)), cond_key("f:", c), set_minus(u, f.live)) }
      lv_expr(a2, c, u, owned)
  end
end

# owned names introduced by the lets of a block, in order
fn block_owned(stmts: List[Stmt], owned: List[String]) -> List[List[String]]
  list_fold(stmts, [], fn(acc, s)
    let cur = unwrap_or(list_get(acc, sub(list_len(acc), 1)), owned)
    let before = if eq(list_len(acc), 0) then owned else cur end
    list_push(acc, before)
  end)
end

fn lv_block(a: RcAnn, stmts: List[Stmt], after: List[String], owned: List[String]) -> Lv
  let owneds = prefix_owned(stmts, owned, [])
  list_fold(list_reverse(list_range(0, list_len(stmts))), Lv { live: after, a: a }, fn(acc, i)
    match list_get(stmts, i)
      case None -> acc
      case Some(s) ->
        let ow = unwrap_or(list_get(owneds, i), owned)
        let cur = if eq(s.let_name, "") then acc.live else set_minus(acc.live, [s.let_name]) end
        let a1 = if and(ne(s.let_name, ""), not(list_contains(acc.live, s.let_name))) then { acc.a with let_drop: map.set(acc.a.let_drop, stmt_key(s), true) } else acc.a end
        let bs = borrows(s.x, ow, [])
        let r = lv_expr(a1, s.x, set_union(cur, bs), ow)
        let drops = set_minus(bs, cur)
        Lv { live: r.live, a: if eq(list_len(drops), 0) then r.a else { r.a with stmt_drops: map.set(r.a.stmt_drops, stmt_key(s), drops) } end }
    end
  end)
end

# owned set in effect at each statement
fn prefix_owned(stmts: List[Stmt], owned: List[String], acc: List[List[String]]) -> List[List[String]]
  match stmts
    case [] -> acc
    case [s, ..rest] -> prefix_owned(rest, if eq(s.let_name, "") then owned else set_add(owned, s.let_name) end, list_push(acc, owned))
  end
end

type FnRc = { ann: RcAnn, param_drops: List[String] } end

fn rc_function(params: List[String], body: List[Stmt]) -> FnRc
  let r = lv_block(rc_empty(), body, [], params)
  FnRc { ann: r.a, param_drops: set_minus(params, r.live) }
end
