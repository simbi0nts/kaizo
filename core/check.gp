# Static checks (v1 = port of the v0 Go checker): unknown names, arity, record fields,
# unknown types, exhaustive match, declared effects.

type Ck = { prog: Program, mod: Module, fn_name: String, declared: List[String], any_eff: Bool, reported: List[String], diags: List[Diag] } end
type GRef = GNone | GFn(FnDecl) | GLet | GMod(Module) | GBuiltin(Builtin) end

fn ck_err(c: Ck, pos: Pos, msg: String, hint: String) -> Ck
  { c with diags: list_push(c.diags, Diag { pos: pos, msg: msg, hint: hint }) }
end

fn ck_begin(c: Ck, name: String, effs: List[String], any_eff: Bool) -> Ck
  { c with fn_name: name, declared: effs, any_eff: any_eff, reported: [] }
end

fn get_module(p: Program, name: String) -> Module
  match map.get(p.modules, name)
    case Some(m) -> m
    case None -> panic(str_cat("no module ", name))
  end
end

fn global(c: Ck, m: Module, name: String) -> GRef
  match map.get(m.fns, name)
    case Some(f) -> GFn(f)
    case None ->
      if map.has(m.lets, name) then GLet
      elif map.has(m.imports, name) then
        match map.get(c.prog.modules, name)
          case Some(dep) -> GMod(dep)
          case None -> GNone
        end
      elif ne(m.name, prelude_module) then
        match global(c, get_module(c.prog, prelude_module), name)
          case GNone -> builtin_ref(m, name)
          case g -> g
        end
      else
        builtin_ref(m, name)
      end
  end
end

fn builtin_ref(m: Module, name: String) -> GRef
  match map.get(builtins, name)
    case Some(bi) -> GBuiltin(bi)
    case None ->
      if eq(m.name, rt_module) then
        match map.get(prims, name)
          case Some(bi) -> GBuiltin(bi)
          case None -> GNone
        end
      else
        GNone
      end
  end
end

fn is_found(g: GRef) -> Bool
  match g
    case GNone -> false
    case _ -> true
  end
end

# ---------- entry ----------

fn check_program(p: Program) -> List[Diag]
  let c0 = Ck { prog: p, mod: get_module(p, prelude_module), fn_name: "", declared: [], any_eff: false, reported: [], diags: [] }
  let c = list_fold(p.order, c0, fn(acc, name) check_module({ acc with mod: get_module(p, name) }) end)
  sort_diags(c.diags)
end

fn check_module(c: Ck) -> Ck
  let trusted = eq(c.mod.name, rt_module)
  list_fold(c.mod.files, c, fn(c1, f)
    let c2 = list_fold(f.types, c1, check_type_decl)
    let c3 = list_fold(f.fns, c2, fn(acc, fd) check_fn(acc, fd, trusted) end)
    let c4 = list_fold(f.lets, c3, fn(acc, ld) check_expr(ck_begin(acc, str_cat("let ", ld.name), [], trusted), ld.x, []) end)
    list_fold(f.tests, c4, fn(acc, t) check_block(ck_begin(acc, "test", [], true), t.body, []) end)
  end)
end

fn is_type_var(name: String) -> Bool
  eq(str_len(name), 1)
end

fn check_typex(c: Ck, t: TypeX, pos: Pos, tparams: List[String]) -> Ck
  let c1 = if or(map.has(c.prog.types, t.name), or(list_contains(tparams, t.name), is_type_var(t.name))) then c else ck_err(c, pos, str_cat("unknown type ", t.name), "") end
  list_fold(t.args, c1, fn(acc, a) check_typex(acc, a, pos, tparams) end)
end

fn check_type_decl(c: Ck, td: TypeDecl) -> Ck
  let r = list_fold(td.fields, Seen { c: c, seen: [] }, fn(acc, f)
    let c1 = if list_contains(acc.seen, f.name) then ck_err(acc.c, td.pos, str_join(["field ", f.name, " repeated in record ", td.name], ""), "") else acc.c end
    Seen { c: check_typex(c1, f.ty, td.pos, td.tparams), seen: list_push(acc.seen, f.name) }
  end)
  list_fold(td.ctors, r.c, fn(acc, cd) list_fold(cd.args, acc, fn(a2, t) check_typex(a2, t, cd.pos, td.tparams) end) end)
end

type Seen = { c: Ck, seen: List[String] } end

fn check_fn(c0: Ck, fd: FnDecl, trusted: Bool) -> Ck
  let c1 = list_fold(fd.effects, c0, fn(acc, e)
    if list_contains(effect_names, e) then acc else ck_err(acc, fd.pos, str_cat("unknown effect ", e), "known effects: io, net, term, time, fs, proc") end
  end)
  let c2 = ck_begin(c1, fd.name, fd.effects, trusted)
  let r = list_fold(fd.params, Seen { c: c2, seen: [] }, fn(acc, p)
    let a1 = if list_contains(acc.seen, p.name) then ck_err(acc.c, fd.pos, str_join(["parameter ", p.name, " repeated"], ""), "") else acc.c end
    let a2 = match p.ty
      case Some(t) -> check_typex(a1, t, fd.pos, [])
      case None -> a1
    end
    Seen { c: a2, seen: list_cons(p.name, acc.seen) }
  end)
  check_block(check_typex(r.c, fd.ret, fd.pos, []), fd.body, r.seen)
end

fn check_block(c: Ck, stmts: List[Stmt], sc: List[String]) -> Ck
  match stmts
    case [] -> c
    case [s, ..rest] ->
      let c1 = check_expr(c, s.x, sc)
      check_block(c1, rest, if eq(s.let_name, "") then sc else list_cons(s.let_name, sc) end)
  end
end

fn use_effect(c: Ck, eff: String, pos: Pos, callee: String) -> Ck
  if or(or(c.any_eff, list_contains(c.declared, eff)), list_contains(c.reported, eff)) then c else
    let hint = if str_starts(c.fn_name, "let ") then str_join(["top-level let must be pure; move this into a fn with ! [", eff, "]"], "")
      else str_join(["add ", eff, " to the effect list of ", c.fn_name, ": ! [", eff, "]"], "") end
    let c1 = ck_err(c, pos, str_join([c.fn_name, " calls ", callee, ", which has effect ", eff, ", but ", c.fn_name, " does not declare it"], ""), hint)
    { c1 with reported: list_push(c1.reported, eff) }
  end
end

type Target = { arity: Int, name: String, effects: List[String] } end

fn call_target(c: Ck, f: Expr, sc: List[String]) -> Target
  let none_t = Target { arity: -1, name: "", effects: [] }
  match f
    case EVar(_, n) ->
      if list_contains(sc, n) then none_t else
        match global(c, c.mod, n)
          case GFn(fd) -> Target { arity: list_len(fd.params), name: fd.name, effects: fd.effects }
          case GBuiltin(bi) -> Target { arity: bi.arity, name: n, effects: if eq(bi.effect, "") then [] else [bi.effect] end }
          case _ -> none_t
        end
      end
    case EField(_, EVar(_, mn), n) ->
      if list_contains(sc, mn) then none_t else
        match global(c, c.mod, mn)
          case GMod(m) ->
            match map.get(m.fns, n)
              case Some(fd) -> Target { arity: list_len(fd.params), name: fd.name, effects: fd.effects }
              case None -> none_t
            end
          case _ -> none_t
        end
      end
    case ECtor(_, n) ->
      match map.get(c.prog.ctors, n)
        case Some(info) -> Target { arity: info.arity, name: str_cat("constructor ", n), effects: [] }
        case None -> none_t
      end
    case _ -> none_t
  end
end

fn check_call(c: Ck, pos: Pos, f: Expr, args: List[Expr], sc: List[String]) -> Ck
  let t = call_target(c, f, sc)
  let c1 = list_fold(t.effects, c, fn(acc, e) use_effect(acc, e, pos, t.name) end)
  let c2 = if and(ge(t.arity, 0), ne(t.arity, list_len(args))) then
    ck_err(c1, pos, str_join([t.name, " expects ", show(t.arity), " arguments, got ", show(list_len(args))], ""), "")
  else c1 end
  let c3 = match f
    case EVar(vp, n) ->
      match global(c2, c2.mod, n)
        case GMod(_) -> if list_contains(sc, n) then c2 else ck_err(c2, vp, str_cat(n, " is a module, not a function"), str_join(["call a member: ", n, ".name(...)"], "")) end
        case _ -> check_expr(c2, f, sc)
      end
    case _ -> check_expr(c2, f, sc)
  end
  list_fold(args, c3, fn(acc, a) check_expr(acc, a, sc) end)
end

fn field_names(td: TypeDecl) -> List[String]
  list_map(td.fields, fn(f) f.name end)
end

fn check_record_lit(c: Ck, pos: Pos, tname: String, fields: List[FieldInit], sc: List[String]) -> Ck
  let c1 = match map.get(c.prog.records, tname)
    case None -> ck_err(c, pos, str_cat("unknown record type ", tname), "")
    case Some(td) ->
      let known = field_names(td)
      let r = list_fold(fields, Seen { c: c, seen: [] }, fn(acc, fi)
        let a1 = if list_contains(known, fi.name) then acc.c else ck_err(acc.c, fi.pos, str_join(["record ", td.name, " has no field ", fi.name], ""), str_join(["fields of ", td.name, ": ", str_join(known, ", ")], "")) end
        let a2 = if list_contains(acc.seen, fi.name) then ck_err(a1, fi.pos, str_join(["field ", fi.name, " given twice"], ""), "") else a1 end
        Seen { c: a2, seen: list_push(acc.seen, fi.name) }
      end)
      let missing = list_filter(known, fn(k) not(list_contains(r.seen, k)) end)
      if eq(list_len(missing), 0) then r.c else ck_err(r.c, pos, str_join(["record ", td.name, " is missing field(s) ", str_join(missing, ", ")], ""), "every field must be given") end
  end
  list_fold(fields, c1, fn(acc, fi) check_expr(acc, fi.x, sc) end)
end

fn any_record_has(c: Ck, name: String) -> Bool
  list_fold(c.prog.record_list, false, fn(acc, td) or(acc, list_contains(field_names(td), name)) end)
end

fn check_expr(c: Ck, e: Expr, sc: List[String]) -> Ck
  match e
    case EInt(_, _) -> c
    case EStr(_, _) -> c
    case EBool(_, _) -> c
    case EVar(pos, n) ->
      if or(list_contains(sc, n), is_found(global(c, c.mod, n))) then c else ck_err(c, pos, str_cat("unknown name ", n), suggest(c, n, sc)) end
    case ECtor(pos, n) ->
      if map.has(c.prog.ctors, n) then c else
        let hint = if map.has(c.prog.records, n) then str_join([n, " is a record type: build it with ", n, " { field: value }"], "") else "" end
        ck_err(c, pos, str_cat("unknown constructor ", n), hint)
      end
    case ECall(pos, f, args) -> check_call(c, pos, f, args, sc)
    case EField(pos, x, n) ->
      match x
        case EVar(_, mn) ->
          match if list_contains(sc, mn) then GNone else global(c, c.mod, mn) end
            case GMod(m) -> if or(map.has(m.fns, n), map.has(m.lets, n)) then c else ck_err(c, pos, str_join(["module ", mn, " has no ", n], ""), "") end
            case _ -> check_expr(c, x, sc)
          end
        case _ -> check_expr(c, x, sc)
      end
    case EList(_, items) -> list_fold(items, c, fn(acc, it) check_expr(acc, it, sc) end)
    case ERec(pos, t, fields) -> check_record_lit(c, pos, t, fields, sc)
    case EUpd(_, x, fields) ->
      list_fold(fields, check_expr(c, x, sc), fn(acc, fi)
        let a1 = if any_record_has(acc, fi.name) then acc else ck_err(acc, fi.pos, str_cat("no record type has a field ", fi.name), "") end
        check_expr(a1, fi.x, sc)
      end)
    case EIf(_, conds, bodies, els) ->
      let c1 = list_fold(conds, c, fn(acc, x) check_expr(acc, x, sc) end)
      let c2 = list_fold(bodies, c1, fn(acc, bd) check_block(acc, bd, sc) end)
      check_block(c2, els, sc)
    case EMatch(pos, x, arms) ->
      let c1 = check_expr(c, x, sc)
      let c2 = list_fold(arms, c1, fn(acc, arm)
        let r = check_pat(Seen { c: acc, seen: [] }, arm.pat)
        check_block(r.c, arm.body, list_concat(r.seen, sc))
      end)
      match witness(c2.prog, list_map(arms, fn(a) [simplify(c2.prog, a.pat)] end), 1)
        case Some(w) ->
          let s = unwrap_or(list_get(w, 0), "_")
          ck_err(c2, pos, str_join(["match is not exhaustive: ", s, " is not covered"], ""), str_join(["add a case for ", s, " (or a final case _ -> ...)"], ""))
        case None -> c2
      end
    case ELam(_, params, body) -> check_block(c, body, list_concat(params, sc))
  end
end

# Seen.seen collects the names a pattern binds
fn check_pat(s: Seen, p: Pat) -> Seen
  match p
    case PVar(pos, n) ->
      let c1 = if list_contains(s.seen, n) then ck_err(s.c, pos, str_join(["name ", n, " bound twice in one pattern"], ""), "") else s.c end
      Seen { c: c1, seen: list_push(s.seen, n) }
    case PCtor(pos, n, args) ->
      let c1 = match map.get(s.c.prog.ctors, n)
        case None -> ck_err(s.c, pos, str_join(["unknown constructor ", n, " in pattern"], ""), "")
        case Some(info) ->
          if eq(info.arity, list_len(args)) then s.c else
            ck_err(s.c, pos, str_join(["constructor ", n, " has ", show(info.arity), " arguments, pattern gives ", show(list_len(args))], ""), "")
          end
      end
      list_fold(args, { s with c: c1 }, check_pat)
    case PList(_, items, rest) ->
      let s1 = list_fold(items, s, check_pat)
      match rest
        case Some(r) -> check_pat(s1, r)
        case None -> s1
      end
    case _ -> s
  end
end

fn suggest(c: Ck, name: String, sc: List[String]) -> String
  let cands = list_concat(list_concat(sc, list_concat(map.keys(c.mod.fns), map.keys(c.mod.lets))), map.keys(builtins))
  let best = list_fold(cands, Best { name: "", d: 3 }, fn(acc, k)
    let d = edit_dist(name, k)
    if lt(d, acc.d) then Best { name: k, d: d } else acc end
  end)
  if eq(best.name, "") then "" else str_join(["did you mean ", best.name, "?"], "") end
end

type Best = { name: String, d: Int } end

fn edit_dist(a: String, b: String) -> Int
  if gt(sub(str_len(a), str_len(b)), 3) then 9 elif gt(sub(str_len(b), str_len(a)), 3) then 9 else
    let first = list_range(0, add(str_len(b), 1))
    let last = list_fold(list_range(1, add(str_len(a), 1)), first, fn(prev, i)
      edit_row(a, b, i, prev, 1, [i])
    end)
    unwrap_or(list_get(last, str_len(b)), 9)
  end
end

fn edit_row(a: String, b: String, i: Int, prev: List[Int], j: Int, cur: List[Int]) -> List[Int]
  if gt(j, str_len(b)) then cur else
    let cost = if eq(str_byte(a, sub(i, 1)), str_byte(b, sub(j, 1))) then 0 else 1 end
    let up = add(unwrap_or(list_get(prev, j), 0), 1)
    let left = add(unwrap_or(list_get(cur, sub(j, 1)), 0), 1)
    let diag = add(unwrap_or(list_get(prev, sub(j, 1)), 0), cost)
    edit_row(a, b, i, prev, add(j, 1), list_push(cur, min(min(up, left), diag)))
  end
end

# ---------- exhaustiveness (pattern-matrix algorithm) ----------

type SP = SWild | SLit | SCon(String, String, List[SP]) end
type SigCtor = { name: String, arity: Int } end

fn simplify(p: Program, pat: Pat) -> SP
  match pat
    case PWild(_) -> SWild
    case PVar(_, _) -> SWild
    case PInt(_, _) -> SLit
    case PStr(_, _) -> SLit
    case PBool(_, v) -> SCon("Bool", show(v), [])
    case PCtor(_, n, args) ->
      match map.get(p.ctors, n)
        case Some(info) -> if eq(info.arity, list_len(args)) then SCon(info.ty, n, list_map(args, fn(a) simplify(p, a) end)) else SWild end
        case None -> SWild
      end
    case PList(_, items, rest) ->
      let tail = match rest
        case Some(_) -> SWild
        case None -> SCon("List", "Nil", [])
      end
      list_fold(list_reverse(items), tail, fn(acc, it) SCon("List", "Cons", [simplify(p, it), acc]) end)
  end
end

fn signature(p: Program, ty: String) -> List[SigCtor]
  if eq(ty, "Bool") then [SigCtor { name: "true", arity: 0 }, SigCtor { name: "false", arity: 0 }]
  elif eq(ty, "List") then [SigCtor { name: "Nil", arity: 0 }, SigCtor { name: "Cons", arity: 2 }]
  else
    match map.get(p.types, ty)
      case Some(td) -> list_map(td.ctors, fn(cd) SigCtor { name: cd.name, arity: list_len(cd.args) } end)
      case None -> []
    end
  end
end

fn fmt_ctor(name: String, args: List[String]) -> String
  if eq(name, "Nil") then "[]"
  elif eq(name, "Cons") then str_join(["[", unwrap_or(list_get(args, 0), "_"), ", ..", unwrap_or(list_get(args, 1), "_"), "]"], "")
  elif eq(list_len(args), 0) then name
  else str_join([name, "(", str_join(args, ", "), ")"], "")
  end
end

fn wilds(n: Int) -> List[String]
  list_map(list_range(0, n), fn(i) "_" end)
end

fn sp_wilds(n: Int) -> List[SP]
  list_map(list_range(0, n), fn(i) SWild end)
end

type Heads = { ty: String, names: List[String] } end

fn heads_of(rows: List[List[SP]]) -> Heads
  list_fold(rows, Heads { ty: "", names: [] }, fn(acc, r)
    match r
      case [SCon(ty, n, _), .._] -> Heads { ty: ty, names: list_push(acc.names, n) }
      case _ -> acc
    end
  end)
end

fn specialize(rows: List[List[SP]], s: SigCtor) -> List[List[SP]]
  list_fold(rows, [], fn(acc, r)
    match r
      case [SWild, ..rest] -> list_push(acc, list_concat(sp_wilds(s.arity), rest))
      case [SCon(_, n, args), ..rest] -> if eq(n, s.name) then list_push(acc, list_concat(args, rest)) else acc end
      case _ -> acc
    end
  end)
end

fn default_rows(rows: List[List[SP]]) -> List[List[SP]]
  list_fold(rows, [], fn(acc, r)
    match r
      case [SWild, ..rest] -> list_push(acc, rest)
      case _ -> acc
    end
  end)
end

# an example of n values matched by no row, or None when the rows are exhaustive
fn witness(p: Program, rows: List[List[SP]], n: Int) -> Option[List[String]]
  if eq(list_len(rows), 0) then Some(wilds(n))
  elif eq(n, 0) then None
  else
    let h = heads_of(rows)
    let sig = signature(p, h.ty)
    let complete = and(ne(h.ty, ""), list_fold(sig, true, fn(acc, s) and(acc, list_contains(h.names, s.name)) end))
    if complete then
      witness_sig(p, rows, n, sig)
    else
      match witness(p, default_rows(rows), sub(n, 1))
        case None -> None
        case Some(w) ->
          let missing = list_filter(sig, fn(s) not(list_contains(h.names, s.name)) end)
          let head = match missing
            case [s, .._] -> if eq(h.ty, "") then "_" else fmt_ctor(s.name, wilds(s.arity)) end
            case [] -> "_"
          end
          Some(list_cons(head, w))
      end
    end
  end
end

fn witness_sig(p: Program, rows: List[List[SP]], n: Int, sig: List[SigCtor]) -> Option[List[String]]
  match sig
    case [] -> None
    case [s, ..rest] ->
      match witness(p, specialize(rows, s), sub(add(s.arity, n), 1))
        case Some(w) -> Some(list_cons(fmt_ctor(s.name, list_slice(w, 0, s.arity)), list_slice(w, s.arity, list_len(w))))
        case None -> witness_sig(p, rows, n, rest)
      end
  end
end

# ---------- ordering ----------

fn pos_before(a: Pos, b: Pos) -> Bool
  if ne(a.file, b.file) then lt(a.file, b.file)
  elif ne(a.line, b.line) then lt(a.line, b.line)
  else lt(a.col, b.col)
  end
end

fn insert_diag(sorted: List[Diag], d: Diag) -> List[Diag]
  match sorted
    case [] -> [d]
    case [x, ..rest] -> if pos_before(d.pos, x.pos) then list_cons(d, sorted) else list_cons(x, insert_diag(rest, d)) end
  end
end

fn sort_diags(ds: List[Diag]) -> List[Diag]
  list_fold(ds, [], insert_diag)
end
