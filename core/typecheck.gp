# Static types: inference with unification (Hindley-Milner style, without let-polymorphism for
# locals). Annotations are only the ones GPLM already requires: top-level signatures and type
# declarations. Single capital letters in a signature are type variables: rigid inside the body,
# instantiated fresh at every use. Types flow into lambdas from the call they are passed to.

# TF(params, result, effects): calling it uses those effects
type Ty = TV(Int) | TC(String, List[Ty]) | TF(List[Ty], Ty, List[String]) end
type EffUse = { eff: String, pos: Pos } end
type Scheme = { vars: List[String], ty: Ty } end
type TBind = { name: String, ty: Ty } end
type Pend = { var: Ty, field: String, res: Ty, pos: Pos } end
type TS = { sub: Map[Ty], next: Int, diags: List[Diag], pend: List[Pend], prog: Program, mod: Module, sigs: Map[FnDecl], lets: Map[Ty], used: List[EffUse], lenient: Bool } end
type TR = { ts: TS, ty: Ty } end
type TE = { ts: TS, env: List[TBind] } end

let builtin_types_src = embed_file("rt/types.gp")

fn t_int() -> Ty
  TC("Int", [])
end

fn t_str() -> Ty
  TC("String", [])
end

fn t_bool() -> Ty
  TC("Bool", [])
end

fn t_list(e: Ty) -> Ty
  TC("List", [e])
end

fn fresh(ts: TS) -> TR
  TR { ts: { ts with next: add(ts.next, 1) }, ty: TV(ts.next) }
end

fn fresh_n(ts: TS, n: Int) -> TL
  list_fold(list_range(0, n), TL { ts: ts, tys: [] }, fn(acc, i)
    let r = fresh(acc.ts)
    TL { ts: r.ts, tys: list_push(acc.tys, r.ty) }
  end)
end

type TL = { ts: TS, tys: List[Ty] } end

fn ty_err(ts: TS, pos: Pos, msg: String, hint: String) -> TS
  { ts with diags: list_push(ts.diags, Diag { pos: pos, msg: msg, hint: hint }) }
end

# ---------- substitution ----------

fn tresolve(ts: TS, t: Ty) -> Ty
  match t
    case TV(n) ->
      match map.get(ts.sub, show(n))
        case Some(u) -> tresolve(ts, u)
        case None -> t
      end
    case _ -> t
  end
end

# fully substituted (for messages and field lookup)
fn zonk(ts: TS, t: Ty) -> Ty
  match tresolve(ts, t)
    case TC(n, args) -> TC(n, list_map(args, fn(a) zonk(ts, a) end))
    case TF(ps, r, es) -> TF(list_map(ps, fn(p) zonk(ts, p) end), zonk(ts, r), es)
    case v -> v
  end
end

fn ty_str(t: Ty) -> String
  match t
    case TV(_) -> "?"
    case TC(n, []) -> if str_starts(n, "'") then str_slice(n, 1, str_len(n)) else n end
    case TC(n, args) -> str_join([n, "[", str_join(list_map(args, ty_str), ", "), "]"], "")
    case TF(ps, r, es) ->
      let base = str_join(["Fn(", str_join(list_map(ps, ty_str), ", "), ") -> ", ty_str(r)], "")
      if eq(list_len(es), 0) then base else str_join([base, " ! [", str_join(es, ", "), "]"], "") end
  end
end

fn occurs(ts: TS, n: Int, t: Ty) -> Bool
  match tresolve(ts, t)
    case TV(m) -> eq(m, n)
    case TC(_, args) -> list_fold(args, false, fn(acc, a) or(acc, occurs(ts, n, a)) end)
    case TF(ps, r, _) -> or(occurs(ts, n, r), list_fold(ps, false, fn(acc, a) or(acc, occurs(ts, n, a)) end))
  end
end

type UR = { ts: TS, ok: Bool } end

fn bind_var(ts: TS, n: Int, t: Ty) -> UR
  if occurs(ts, n, t) then UR { ts: ts, ok: false } else UR { ts: { ts with sub: map.set(ts.sub, show(n), t) }, ok: true } end
end

fn unify_raw(ts: TS, a: Ty, b: Ty) -> UR
  let ra = tresolve(ts, a)
  let rb = tresolve(ts, b)
  match ra
    case TV(n) ->
      match rb
        case TV(m) -> if eq(n, m) then UR { ts: ts, ok: true } else bind_var(ts, n, rb) end
        case _ -> bind_var(ts, n, rb)
      end
    case TC(na, aa) ->
      match rb
        case TV(m) -> bind_var(ts, m, ra)
        case TC(nb, ab) -> if and(eq(na, nb), eq(list_len(aa), list_len(ab))) then unify_all(ts, aa, ab) else UR { ts: ts, ok: false } end
        case _ -> UR { ts: ts, ok: false }
      end
    case TF(pa, ra2, ea) ->
      match rb
        case TV(m) -> bind_var(ts, m, ra)
        case TF(pb, rb2, eb) ->
          # a function with effects ea fits where effects eb are allowed only if ea is a subset of eb
          let fits = or(ts.lenient, list_fold(ea, true, fn(acc, e) and(acc, list_contains(eb, e)) end))
          if or(ne(list_len(pa), list_len(pb)), not(fits)) then UR { ts: ts, ok: false } else
            let r = unify_all(ts, pa, pb)
            if r.ok then unify_raw(r.ts, ra2, rb2) else r end
          end
        case _ -> UR { ts: ts, ok: false }
      end
  end
end

fn unify_all(ts: TS, a: List[Ty], b: List[Ty]) -> UR
  list_fold(list_range(0, list_len(a)), UR { ts: ts, ok: true }, fn(acc, i)
    if acc.ok then unify_raw(acc.ts, unwrap_or(list_get(a, i), t_int()), unwrap_or(list_get(b, i), t_int())) else acc end
  end)
end

# unify the type of an expression (got) with what the context wants
fn unify(ts: TS, got: Ty, want: Ty, pos: Pos, what: String) -> TS
  unify_hint(ts, got, want, pos, what, "")
end

fn unify_hint(ts: TS, got: Ty, want: Ty, pos: Pos, what: String, hint: String) -> TS
  let r = unify_raw(ts, got, want)
  if r.ok then r.ts else
    ty_err(ts, pos, str_join(["type mismatch", what, ": expected ", ty_str(zonk(ts, want)), ", got ", ty_str(zonk(ts, got))], ""), hint)
  end
end

let try_hint = "Option has Some/None, Result has Ok/Err; `let x = try e` takes a Result, `let x = try e else v` takes an Option"
let try_block_hint = "try hands the Err on as the value of the enclosing block, so that block (e.g. the fn body) must be a Result; use match to handle the error here"

# ---------- annotations -> types ----------

fn is_tvar_name(n: String) -> Bool
  and(eq(str_len(n), 1), and(ge(str_byte(n, 0), 65), le(str_byte(n, 0), 90)))
end

# vars: a type variable name -> its type
fn tx_ty(t: TypeX, vars: Map[Ty]) -> Ty
  match map.get(vars, t.name)
    case Some(v) -> v
    case None ->
      if eq(t.name, "Fn") then
        let all = list_map(t.args, fn(a) tx_ty(a, vars) end)
        TF(list_slice(all, 0, sub(list_len(all), 1)), unwrap_or(list_get(all, sub(list_len(all), 1)), TC("Unit", [])), t.effects)
      else TC(t.name, list_map(t.args, fn(a) tx_ty(a, vars) end)) end
  end
end

# single capital letters are type variables unless a type of that name is declared (record X)
fn tx_vars(p: Program, t: TypeX, acc: List[String]) -> List[String]
  let a1 = if and(and(is_tvar_name(t.name), not(map.has(p.types, t.name))), not(list_contains(acc, t.name))) then list_push(acc, t.name) else acc end
  list_fold(t.args, a1, fn(a, x) tx_vars(p, x, a) end)
end

fn sig_vars(p: Program, fd: FnDecl) -> List[String]
  let a = list_fold(fd.params, [], fn(acc, prm)
    match prm.ty
      case Some(t) -> tx_vars(p, t, acc)
      case None -> acc
    end
  end)
  tx_vars(p, fd.ret, a)
end

type Sig = { params: List[Ty], ret: Ty } end

fn sig_with(fd: FnDecl, vars: Map[Ty]) -> Sig
  Sig { params: list_map(fd.params, fn(p)
      match p.ty
        case Some(t) -> tx_ty(t, vars)
        case None -> TC("Unit", [])
      end
    end), ret: tx_ty(fd.ret, vars) }
end

# a function used at a call site: its type variables become fresh unification variables
fn instantiate_fn(ts: TS, fd: FnDecl) -> TR
  let names = sig_vars(ts.prog, fd)
  let fr = fresh_n(ts, list_len(names))
  let vars = list_fold(list_range(0, list_len(names)), map.empty(), fn(m, i) map.set(m, unwrap_or(list_get(names, i), ""), unwrap_or(list_get(fr.tys, i), t_int())) end)
  let s = sig_with(fd, vars)
  TR { ts: fr.ts, ty: TF(s.params, s.ret, fd.effects) }
end

fn type_vars_map(ts: TS, names: List[String]) -> TM
  let fr = fresh_n(ts, list_len(names))
  TM { ts: fr.ts, vars: list_fold(list_range(0, list_len(names)), map.empty(), fn(m, i) map.set(m, unwrap_or(list_get(names, i), ""), unwrap_or(list_get(fr.tys, i), t_int())) end), tys: fr.tys }
end

type TM = { ts: TS, vars: Map[Ty], tys: List[Ty] } end

# constructor as a value: Fn(args) -> T[params], or T[params] when it has no arguments
fn instantiate_ctor(ts: TS, name: String) -> TR
  match map.get(ts.prog.ctors, name)
    case None -> fresh(ts)
    case Some(info) ->
      match map.get(ts.prog.types, info.ty)
        case None -> TR { ts: ts, ty: TC(info.ty, []) }
        case Some(td) ->
          let tm = type_vars_map(ts, td.tparams)
          let result = TC(td.name, tm.tys)
          let cd = list_filter(td.ctors, fn(c) eq(c.name, name) end)
          match cd
            case [c, .._] -> if eq(list_len(c.args), 0) then TR { ts: tm.ts, ty: result } else TR { ts: tm.ts, ty: TF(list_map(c.args, fn(a) tx_ty(a, tm.vars) end), result, []) } end
            case [] -> TR { ts: tm.ts, ty: result }
          end
      end
  end
end

# ---------- names ----------

fn lookup_tenv(env: List[TBind], n: String) -> Option[Ty]
  match env
    case [] -> None
    case [b, ..rest] -> if eq(b.name, n) then Some(b.ty) else lookup_tenv(rest, n) end
  end
end

fn let_type(ts: TS, m: Module, n: String) -> Ty
  unwrap_or(map.get(ts.lets, str_join([m.name, ".", n], "")), TV(-1))
end

fn global_type(ts: TS, m: Module, n: String, pos: Pos) -> TR
  match map.get(m.fns, n)
    case Some(fd) -> instantiate_fn(ts, fd)
    case None ->
      if map.has(m.lets, n) then lets_ty(ts, m, n)
      elif ne(m.name, prelude_module) then
        let pm = get_module(ts.prog, prelude_module)
        if or(map.has(pm.fns, n), map.has(pm.lets, n)) then global_type(ts, pm, n, pos) else builtin_ty(ts, n) end
      else builtin_ty(ts, n)
      end
  end
end

fn lets_ty(ts: TS, m: Module, n: String) -> TR
  let t = let_type(ts, m, n)
  match t
    case TV(-1) -> fresh(ts)
    case _ -> TR { ts: ts, ty: t }
  end
end

fn builtin_ty(ts: TS, n: String) -> TR
  match map.get(ts.sigs, n)
    case Some(fd) -> instantiate_fn(ts, fd)
    case None -> fresh(ts)
  end
end

fn module_of(ts: TS, env: List[TBind], x: Expr) -> Option[Module]
  match x
    case EVar(_, mn) ->
      if is_some(lookup_tenv(env, mn)) then None
      elif map.has(ts.mod.imports, mn) then map.get(ts.prog.modules, mn)
      else None
      end
    case _ -> None
  end
end

# ---------- records ----------

fn records_with(ts: TS, field: String) -> List[TypeDecl]
  list_filter(ts.prog.record_list, fn(td) list_contains(list_map(td.fields, fn(f) f.name end), field) end)
end

# type of field f of record type t (t already resolved to TC)
fn field_type(ts: TS, t: Ty, field: String) -> Option[Ty]
  match t
    case TC(name, args) ->
      match map.get(ts.prog.records, name)
        case None -> None
        case Some(td) ->
          let vars = list_fold(list_range(0, list_len(td.tparams)), map.empty(), fn(m, i) map.set(m, unwrap_or(list_get(td.tparams, i), ""), unwrap_or(list_get(args, i), TV(-1))) end)
          match list_filter(td.fields, fn(f) eq(f.name, field) end)
            case [f, .._] -> Some(tx_ty(f.ty, vars))
            case [] -> None
          end
      end
    case _ -> None
  end
end

fn fresh_record(ts: TS, td: TypeDecl) -> TR
  let tm = type_vars_map(ts, td.tparams)
  TR { ts: tm.ts, ty: TC(td.name, tm.tys) }
end

# x.f with x of type t; unknown record types are resolved later (pending) or by a unique field name
fn access(ts: TS, t: Ty, field: String, pos: Pos) -> TR
  let rt = tresolve(ts, t)
  match rt
    case TV(_) ->
      match records_with(ts, field)
        case [td] ->
          let r = fresh_record(ts, td)
          access(unify(r.ts, rt, r.ty, pos, ""), r.ty, field, pos)
        case _ ->
          let res = fresh(ts)
          TR { ts: { res.ts with pend: list_push(res.ts.pend, Pend { var: rt, field: field, res: res.ty, pos: pos }) }, ty: res.ty }
      end
    case _ ->
      match field_type(ts, rt, field)
        case Some(ft) -> TR { ts: ts, ty: ft }
        case None ->
          let r = fresh(ts)
          TR { ts: ty_err(r.ts, pos, str_join(["type ", ty_str(zonk(ts, rt)), " has no field ", field], ""), ""), ty: r.ty }
      end
  end
end

fn solve_pending(ts: TS) -> TS
  let r = list_fold(ts.pend, PS2 { ts: { ts with pend: [] }, progress: false }, fn(acc, p)
    match tresolve(acc.ts, p.var)
      case TV(_) -> PS2 { ts: { acc.ts with pend: list_push(acc.ts.pend, p) }, progress: acc.progress }
      case t ->
        let a = access(acc.ts, t, p.field, p.pos)
        PS2 { ts: unify(a.ts, a.ty, p.res, p.pos, ""), progress: true }
    end
  end)
  if r.progress then solve_pending(r.ts) else r.ts end
end

type PS2 = { ts: TS, progress: Bool } end

fn finish_pending(ts: TS) -> TS
  let ts1 = solve_pending(ts)
  let r = list_fold(ts1.pend, { ts1 with pend: [] }, fn(acc, p)
    ty_err(acc, p.pos, str_join(["cannot tell which record type has field ", p.field, " here"], ""), "several record types have this field; annotate the function's parameter or result")
  end)
  r
end

# ---------- expressions ----------

fn infer_block(ts: TS, env: List[TBind], stmts: List[Stmt], want: Ty) -> TS
  match stmts
    case [] -> unify(ts, TC("Unit", []), want, Pos { file: "", line: 0, col: 0 }, "")
    case [s] ->
      if eq(s.let_name, "") then check(ts, env, s.x, want) else ts end
    case [s, ..rest] ->
      let r = infer(ts, env, s.x)
      let env2 = if eq(s.let_name, "") then env else list_cons(TBind { name: s.let_name, ty: r.ty }, env) end
      infer_block(r.ts, env2, rest, want)
  end
end

fn check(ts: TS, env: List[TBind], e: Expr, want: Ty) -> TS
  match e
    case ELam(pos, params, body) ->
      match tresolve(ts, want)
        case TF(ps, r, weffs) ->
          if eq(list_len(ps), list_len(params)) then
            let env2 = list_fold(list_range(0, list_len(params)), env, fn(acc, i) list_cons(TBind { name: unwrap_or(list_get(params, i), ""), ty: unwrap_or(list_get(ps, i), t_int()) }, acc) end)
            let lam = lambda_body(ts, env2, body, r)
            let missing = list_filter(lam.effs, fn(e) not(list_contains(weffs, e)) end)
            if or(ts.lenient, eq(list_len(missing), 0)) then lam.ts else
              ty_err(lam.ts, pos, str_join(["this function uses ", str_join(missing, ", "), ", but the function type it is passed as allows ",
                if eq(list_len(weffs), 0) then "no effects" else str_join(weffs, ", ") end], ""),
                "declare the effect in the parameter's type, e.g. Fn(A) -> B ! [io], or keep effects out of the callback")
            end
          else
            let got = infer(ts, env, e)
            unify(got.ts, got.ty, want, pos, "")
          end
        case _ ->
          let got = infer(ts, env, e)
          unify(got.ts, got.ty, want, pos, "")
      end
    case EIf(_, conds, bodies, els) ->
      let ts1 = list_fold(conds, ts, fn(acc, c) check(acc, env, c, t_bool()) end)
      let ts2 = list_fold(bodies, ts1, fn(acc, b) infer_block(acc, env, b, want) end)
      infer_block(ts2, env, els, want)
    case EMatch(_, x, arms) ->
      let r = infer(ts, env, x)
      list_fold(arms, r.ts, fn(acc, arm)
        let p = bind_pat(acc, env, arm.pat, r.ty)
        infer_block(p.ts, p.env, arm.body, want)
      end)
    case EList(pos, items) ->
      let el = fresh(ts)
      let ts1 = unify(el.ts, t_list(el.ty), want, pos, "")
      list_fold(items, ts1, fn(acc, it) check(acc, env, it, el.ty) end)
    case ECall(pos, ECtor(_, "Err"), [EVar(_, "try_err")]) ->
      let got = infer(ts, env, e)
      unify_hint(got.ts, got.ty, want, pos, "", try_block_hint)
    case _ ->
      let got = infer(ts, env, e)
      unify(got.ts, got.ty, want, expr_pos(e), "")
  end
end

fn infer(ts: TS, env: List[TBind], e: Expr) -> TR
  match e
    case EInt(_, _) -> TR { ts: ts, ty: t_int() }
    case EStr(_, _) -> TR { ts: ts, ty: t_str() }
    case EBool(_, _) -> TR { ts: ts, ty: t_bool() }
    case EVar(pos, n) ->
      match lookup_tenv(env, n)
        case Some(t) -> TR { ts: ts, ty: t }
        case None -> global_type(ts, ts.mod, n, pos)
      end
    case ECtor(_, n) -> instantiate_ctor(ts, n)
    case ECall(pos, f, args) ->
      let fr = infer(ts, env, f)
      let fty = tresolve(fr.ts, fr.ty)
      let builtin = is_builtin_call(fr.ts, env, f)
      match fty
        case TF(ps, ret, effs) ->
          let ts1 = use_effects(fr.ts, effs, pos)
          if ne(list_len(ps), list_len(args)) then TR { ts: ts1, ty: ret } else
            let ts2 = list_fold(list_range(0, list_len(args)), ts1, fn(acc, i)
              let arg = unwrap_or(list_get(args, i), EInt(pos, 0))
              let want = unwrap_or(list_get(ps, i), t_int())
              if builtin then
                let a1 = check({ acc with lenient: true }, env, arg, want)
                let a2 = { a1 with lenient: acc.lenient }
                # a builtin calls its function arguments: their effects are used here
                match tresolve(a2, want)
                  case TF(_, _, _) -> arg_effects(a2, env, arg, pos)
                  case _ -> a2
                end
              else check_arg(acc, env, arg, want, i) end
            end)
            TR { ts: ts2, ty: ret }
          end
        case _ ->
          let rs = fresh(fr.ts)
          let ps = fresh_n(rs.ts, list_len(args))
          let ts2 = unify(ps.ts, fty, TF(ps.tys, rs.ty, []), pos, " (called value is not a function of this shape)")
          TR { ts: list_fold(list_range(0, list_len(args)), ts2, fn(acc, i) check(acc, env, unwrap_or(list_get(args, i), EInt(pos, 0)), unwrap_or(list_get(ps.tys, i), t_int())) end), ty: rs.ty }
      end
    case EField(pos, x, n) ->
      match module_of(ts, env, x)
        case Some(m) -> global_type(ts, m, n, pos)
        case None ->
          let r = infer(ts, env, x)
          access(r.ts, r.ty, n, pos)
      end
    case EList(pos, items) ->
      let el = fresh(ts)
      TR { ts: list_fold(items, el.ts, fn(acc, it) check(acc, env, it, el.ty) end), ty: t_list(el.ty) }
    case ERec(pos, tname, fields) ->
      match map.get(ts.prog.records, tname)
        case None -> fresh(ts)
        case Some(td) ->
          let r = fresh_record(ts, td)
          TR { ts: list_fold(fields, r.ts, fn(acc, fi)
              match field_type(acc, tresolve(acc, r.ty), fi.name)
                case Some(ft) -> check_field(acc, env, fi, ft)
                case None -> acc
              end
            end), ty: r.ty }
      end
    case EUpd(pos, x, fields) ->
      let r = infer(ts, env, x)
      TR { ts: list_fold(fields, r.ts, fn(acc, fi)
          let a = access(acc, r.ty, fi.name, fi.pos)
          check_field(a.ts, env, fi, a.ty)
        end), ty: r.ty }
    case EIf(_, _, _, _) ->
      let res = fresh(ts)
      TR { ts: check(res.ts, env, e, res.ty), ty: res.ty }
    case EMatch(_, _, _) ->
      let res = fresh(ts)
      TR { ts: check(res.ts, env, e, res.ty), ty: res.ty }
    case ELam(_, params, body) ->
      let ps = fresh_n(ts, list_len(params))
      let res = fresh(ps.ts)
      let env2 = list_fold(list_range(0, list_len(params)), env, fn(acc, i) list_cons(TBind { name: unwrap_or(list_get(params, i), ""), ty: unwrap_or(list_get(ps.tys, i), t_int()) }, acc) end)
      let lam = lambda_body(res.ts, env2, body, res.ty)
      TR { ts: lam.ts, ty: TF(ps.tys, res.ty, lam.effs) }
  end
end

fn use_effects(ts: TS, effs: List[String], pos: Pos) -> TS
  list_fold(effs, ts, fn(acc, e) if list_contains(list_map(acc.used, fn(u) u.eff end), e) then acc else { acc with used: list_push(acc.used, EffUse { eff: e, pos: pos }) } end end)
end

type LamR = { ts: TS, effs: List[String] } end

# a lambda body is checked with its own effect set (the enclosing function's set is restored)
fn lambda_body(ts: TS, env: List[TBind], body: List[Stmt], r: Ty) -> LamR
  let inner = infer_block({ ts with used: [], lenient: false }, env, body, r)
  LamR { ts: { inner with used: ts.used, lenient: ts.lenient }, effs: list_map(inner.used, fn(u) u.eff end) }
end

# the effects of a function value passed to a builtin
fn arg_effects(ts: TS, env: List[TBind], arg: Expr, pos: Pos) -> TS
  let r = infer({ ts with diags: [] }, env, arg)
  match tresolve(r.ts, r.ty)
    case TF(_, _, effs) -> use_effects(ts, effs, pos)
    case _ -> ts
  end
end

fn is_builtin_call(ts: TS, env: List[TBind], f: Expr) -> Bool
  match f
    case EVar(_, n) ->
      if is_some(lookup_tenv(env, n)) then false
      elif or(map.has(ts.mod.fns, n), map.has(ts.mod.lets, n)) then false
      else
        let pm = get_module(ts.prog, prelude_module)
        and(not(or(map.has(pm.fns, n), map.has(pm.lets, n))), map.has(ts.sigs, n))
      end
    case _ -> false
  end
end

fn check_arg(ts: TS, env: List[TBind], arg: Expr, want: Ty, i: Int) -> TS
  let ts1 = check(ts, env, arg, want)
  ts1
end

fn check_field(ts: TS, env: List[TBind], fi: FieldInit, want: Ty) -> TS
  let n = list_len(ts.diags)
  let ts1 = check(ts, env, fi.x, want)
  if eq(list_len(ts1.diags), n) then ts1 else
    # make field mismatches name the field
    let last = unwrap_or(list_get(ts1.diags, sub(list_len(ts1.diags), 1)), Diag { pos: fi.pos, msg: "", hint: "" })
    if eq(last.pos, expr_pos(fi.x)) then { ts1 with diags: list_push(list_slice(ts1.diags, 0, sub(list_len(ts1.diags), 1)), { last with msg: str_join([last.msg, " (field ", fi.name, ")"], "") }) } else ts1 end
  end
end

# ---------- patterns ----------

fn ctor_hint(n: String) -> String
  if list_contains(["Ok", "Err", "Some", "None"], n) then try_hint else "" end
end

fn bind_pat(ts: TS, env: List[TBind], p: Pat, t: Ty) -> TE
  match p
    case PWild(_) -> TE { ts: ts, env: env }
    case PVar(_, n) -> TE { ts: ts, env: list_cons(TBind { name: n, ty: t }, env) }
    case PInt(pos, _) -> TE { ts: unify(ts, t, t_int(), pos, " in pattern"), env: env }
    case PStr(pos, _) -> TE { ts: unify(ts, t, t_str(), pos, " in pattern"), env: env }
    case PBool(pos, _) -> TE { ts: unify(ts, t, t_bool(), pos, " in pattern"), env: env }
    case PCtor(pos, n, args) ->
      let c = instantiate_ctor(ts, n)
      match c.ty
        case TF(ps, res, _) ->
          let ts1 = unify_hint(c.ts, res, t, pos, str_cat(" in pattern ", n), ctor_hint(n))
          list_fold(list_range(0, list_len(args)), TE { ts: ts1, env: env }, fn(acc, i)
            bind_pat(acc.ts, acc.env, unwrap_or(list_get(args, i), PWild(pos)), unwrap_or(list_get(ps, i), t_int()))
          end)
        case res -> TE { ts: unify_hint(c.ts, res, t, pos, str_cat(" in pattern ", n), ctor_hint(n)), env: env }
      end
    case PList(pos, items, rest) ->
      let el = fresh(ts)
      let ts1 = unify(el.ts, t_list(el.ty), t, pos, " in list pattern")
      let r = list_fold(items, TE { ts: ts1, env: env }, fn(acc, it) bind_pat(acc.ts, acc.env, it, el.ty) end)
      match rest
        case Some(rp) -> bind_pat(r.ts, r.env, rp, t_list(el.ty))
        case None -> r
      end
  end
end

# ---------- functions, lets, program ----------

fn check_fn_types(ts: TS, fd: FnDecl) -> TS
  let names = sig_vars(ts.prog, fd)
  let rigid = list_fold(names, map.empty(), fn(m, n) map.set(m, n, TC(str_join(["'", n], ""), [])) end)
  let s = sig_with(fd, rigid)
  let env = list_fold(list_range(0, list_len(fd.params)), [], fn(acc, i)
    match list_get(fd.params, i)
      case Some(p) -> list_cons(TBind { name: p.name, ty: unwrap_or(list_get(s.params, i), t_int()) }, acc)
      case None -> acc
    end
  end)
  let done = finish_pending(infer_block({ ts with pend: [], used: [] }, env, fd.body, s.ret))
  undeclared(done, fd.name, fd.effects)
end

fn undeclared(ts: TS, fname: String, declared: List[String]) -> TS
  list_fold(ts.used, { ts with used: [] }, fn(acc, u)
    if list_contains(declared, u.eff) then acc else
      ty_err(acc, u.pos, str_join([fname, " uses ", u.eff, " (through a function value), but ", fname, " does not declare it"], ""),
        str_join(["add ", u.eff, " to the effect list of ", fname, ": ! [", u.eff, "]"], ""))
    end
  end)
end

fn builtin_sigs() -> Map[FnDecl]
  match parse_file("<builtin types>", builtin_types_src)
    case Ok(f) -> list_fold(f.fns, map.empty(), fn(m, fd) map.set(m, fd.name, fd) end)
    case Err(_) -> map.empty()
  end
end

# type-checks every module except the runtime (which works below the type system)
fn typecheck_program(p: Program) -> List[Diag]
  let ts0 = TS { sub: map.empty(), next: 0, diags: [], pend: [], prog: p, mod: get_module(p, prelude_module), sigs: builtin_sigs(), lets: map.empty(), used: [], lenient: false }
  let ts = list_fold(list_filter(p.order, fn(n) ne(n, rt_module) end), ts0, fn(acc, name)
    let m = get_module(p, name)
    let a0 = { acc with mod: m }
    let a1 = list_fold(m.files, a0, fn(a, f)
      list_fold(f.lets, a, fn(a2, ld)
        let r = infer({ a2 with pend: [], used: [] }, [], ld.x)
        let a3 = undeclared(finish_pending(r.ts), str_cat("let ", ld.name), [])
        { a3 with lets: map.set(a3.lets, str_join([m.name, ".", ld.name], ""), zonk(a3, r.ty)) }
      end)
    end)
    list_fold(m.files, a1, fn(a, f)
      let a2 = list_fold(f.fns, a, check_fn_types)
      list_fold(f.tests, a2, fn(a3, t)
        let res = fresh(a3)
        let done = finish_pending(infer_block({ res.ts with pend: [], used: [] }, [], t.body, res.ty))
        { done with used: [] }
      end)
    end)
  end)
  ts.diags
end
