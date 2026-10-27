# Code generator: AST -> x86-64 (stack machine; every expression leaves its value in rax).
#
# Values: Int n = 2n+1. Objects: [header = tag | len << 8][payload]:
#   1 Str [bytes] · 2 List [data ptr] · 3 Record [type id][fields] · 4 Ctor [ctor id][args]
#   5 Bool [0/1] · 6 Closure [code][arity][captures] · 7 Handle [fd]
# Calls: args pushed left to right, closure in r15, callee pops its args (ret imm16).
# Frame: [rbp-8] = closure, slot k at [rbp-8(k+1)], arg i of m at [rbp+16+8(m-1-i)].
# r14 = heap pointer (bump allocation).

let tag_str = 1
let tag_list = 2
let tag_rec = 3
let tag_ctor = 4
let tag_clo = 6

type Loc = LSlot(Int) | LArg(Int) | LCap(Int) end
type Bind = { name: String, loc: Loc } end
type FIdx = { id: Int, idx: Int } end
type Cx = { prog: Program, mod: Module, nargs: Int, fields: Map[List[FIdx]], rec_ids: Map[Int], embeds: Map[String] } end
type G = { code: Code, slot: Int, lab: Int, data: Code, funcs: List[Code], wrappers: List[String], strs: Map[String] } end
type GL = { g: G, l: String } end
type GS = { g: G, s: Int } end
type GE = { g: G, env: List[Bind] } end

let inline_builtins = ["add", "sub", "mul", "div", "mod", "eq", "ne", "lt", "le", "gt", "ge", "not", "and", "or"]
let located_builtins = ["panic", "expect", "expect_eq"]

fn tagged(n: Int) -> Int
  add(mul(n, 2), 1)
end

fn emit(g: G, c: Code) -> G
  { g with code: CCat(g.code, c) }
end

fn eb(g: G, b: List[Int]) -> G
  { g with code: CCat(g.code, CB(b)) }
end

fn new_label(g: G) -> GL
  GL { g: { g with lab: add(g.lab, 1) }, l: str_cat(".L", show(g.lab)) }
end

fn new_global_label(g: G, prefix: String) -> GL
  GL { g: { g with lab: add(g.lab, 1) }, l: str_cat(prefix, show(g.lab)) }
end

fn new_slot(g: G) -> GS
  GS { g: { g with slot: add(g.slot, 1) }, s: g.slot }
end

fn slot_disp(s: Int) -> Int
  mul(-8, add(s, 1))
end

fn fn_label(m: String, name: String) -> String
  str_join(["f:", m, ".", name], "")
end

fn clo_label(l: String) -> String
  str_cat("c:", l)
end

fn ctor_label(name: String) -> String
  str_cat("k:", name)
end

# ---------- data ----------

fn emit_data(g: G, c: Code) -> G
  { g with data: CCat(g.data, c) }
end

fn str_object(s: String) -> Code
  let n = str_len(s)
  let pad = sub(pad_to8(n), n)
  cat([CB(lebytes(add(tag_str, mul(n, 256)), 8)), CS(s), CB(lebytes(0, pad))])
end

# address label of a static string object (deduplicated)
fn str_lit(g: G, s: String) -> GL
  match map.get(g.strs, s)
    case Some(l) -> GL { g: g, l: l }
    case None ->
      let r = new_global_label(g, "s:")
      let g2 = emit_data(r.g, CCat(CLab(r.l), str_object(s)))
      GL { g: { g2 with strs: map.set(g2.strs, s, r.l) }, l: r.l }
  end
end

# ---------- small emitters ----------

fn load_loc(cx: Cx, r: Int, loc: Loc) -> List[Int]
  match loc
    case LSlot(s) -> ldm(r, rbp, slot_disp(s))
    case LArg(i) -> ldm(r, rbp, add(16, mul(8, sub(sub(cx.nargs, 1), i))))
    case LCap(i) -> list_concat(ldm(r, rbp, -8), ldm(r, r, add(24, mul(8, i))))
  end
end

fn tag_rax() -> List[Int]
  list_concat(shift(4, rax, 1), alu_imm(0, rax, 1))
end

fn alloc_fixed(g: G, size: Int) -> G
  eb(g, list_concat(mov_rr(rax, r14), alu_imm(0, r14, size)))
end

# runtime error at pos: push message, call rt fail (never returns)
fn fail_code(g: G, pos: Pos, msg: String) -> G
  let s = str_lit(g, str_join([pos_str(pos), ": runtime error: ", msg], ""))
  emit(s.g, cat([mov_addr(rax, s.l), CB(push_r(rax)), call_l(fn_label(rt_module, "fail"))]))
end

# continue if condition `ok_cc` holds after the preceding flags-setting code, else fail
fn check_cc(g: G, ok_cc: Int, pos: Pos, msg: String) -> G
  let ok = new_label(g)
  let g1 = fail_code(emit(ok.g, jcc(ok_cc, ok.l)), pos, msg)
  emit(g1, CLab(ok.l))
end

# fail unless the value in rax is an object with the given tag
fn check_tag(g: G, tag: Int, pos: Pos, msg: String) -> G
  let bad = new_label(g)
  let ok = new_label(bad.g)
  let g1 = emit(ok.g, cat([CB(test_low(rax, 1)), jcc(cc_ne, bad.l), CB(cmp_byte_mem(rax, 0, tag)), jcc(cc_e, ok.l), CLab(bad.l)]))
  emit(fail_code(g1, pos, msg), CLab(ok.l))
end

# fail unless r (rax/rcx) holds true or false
fn check_bool(g: G, r: Int, pos: Pos, msg: String) -> G
  let ok = new_label(g)
  let g1 = emit(ok.g, cat([mov_addr(rdx, "TRUE"), CB(op_rr(57, r, rdx)), jcc(cc_e, ok.l), mov_addr(rdx, "FALSE"), CB(op_rr(57, r, rdx)), jcc(cc_e, ok.l)]))
  emit(fail_code(g1, pos, msg), CLab(ok.l))
end

# rax = TRUE if condition cc holds, else FALSE
fn set_bool(g: G, c: Int) -> G
  let t = new_label(g)
  let e = new_label(t.g)
  emit(e.g, cat([jcc(c, t.l), mov_addr(rax, "FALSE"), jmp(e.l), CLab(t.l), mov_addr(rax, "TRUE"), CLab(e.l)]))
end

# ---------- name resolution ----------

type Res = RLocal(Loc) | RFn(String, Int) | RLet(String) | RInline(String) | RRt(String, Int) | RLocated(String, Int) | RNone end

fn lookup_env(env: List[Bind], n: String) -> Option[Loc]
  match env
    case [] -> None
    case [b, ..rest] -> if eq(b.name, n) then Some(b.loc) else lookup_env(rest, n) end
  end
end

fn resolve_in(cx: Cx, m: Module, n: String) -> Res
  match map.get(m.fns, n)
    case Some(fd) -> RFn(fn_label(m.name, n), list_len(fd.params))
    case None ->
      if map.has(m.lets, n) then RLet(str_join(["g:", m.name, ".", n], ""))
      elif ne(m.name, prelude_module) then
        match resolve_in(cx, get_module(cx.prog, prelude_module), n)
          case RNone -> resolve_builtin(cx, m, n)
          case r -> r
        end
      else resolve_builtin(cx, m, n)
      end
  end
end

fn resolve_builtin(cx: Cx, m: Module, n: String) -> Res
  if list_contains(inline_builtins, n) then RInline(n)
  elif map.has(prims, n) then if eq(m.name, rt_module) then RInline(n) else RNone end
  else
    match map.get(builtins, n)
      case Some(bi) -> if list_contains(located_builtins, n) then RLocated(fn_label(rt_module, str_cat(n, "_at")), bi.arity) else RRt(fn_label(rt_module, n), bi.arity) end
      case None -> RNone
    end
  end
end

fn resolve(cx: Cx, env: List[Bind], n: String) -> Res
  match lookup_env(env, n)
    case Some(loc) -> RLocal(loc)
    case None -> resolve_in(cx, cx.mod, n)
  end
end

# module member access m.name (m an import, not shadowed)
fn module_member(cx: Cx, env: List[Bind], x: Expr, n: String) -> Option[Res]
  match x
    case EVar(_, mn) ->
      if is_some(lookup_env(env, mn)) then None
      elif map.has(cx.mod.imports, mn) then
        match map.get(cx.prog.modules, mn)
          case Some(m) ->
            match map.get(m.fns, n)
              case Some(fd) -> Some(RFn(fn_label(mn, n), list_len(fd.params)))
              case None -> Some(RLet(str_join(["g:", mn, ".", n], "")))
            end
          case None -> None
        end
      else None
      end
    case _ -> None
  end
end

# value of a resolved name (not a call)
fn cg_res_value(cx: Cx, g: G, r: Res, n: String, pos: Pos) -> G
  match r
    case RLocal(loc) -> eb(g, load_loc(cx, rax, loc))
    case RFn(l, _) -> emit(g, mov_addr(rax, clo_label(l)))
    case RLet(l) -> emit(g, load_abs(rax, l))
    case RRt(l, _) -> emit(g, mov_addr(rax, clo_label(l)))
    case RInline(name) -> need_wrapper(g, str_cat("op:", name))
    case RLocated(_, _) -> need_wrapper(g, str_cat("op:", n))
    case RNone -> fail_code(g, pos, str_cat("unknown name ", n))
  end
end

fn need_wrapper(g: G, w: String) -> G
  let g1 = if list_contains(g.wrappers, w) then g else { g with wrappers: list_push(g.wrappers, w) } end
  emit(g1, mov_addr(rax, clo_label(str_cat("w:", w))))
end

# ---------- expressions ----------

fn cg(cx: Cx, g: G, env: List[Bind], e: Expr, tail: Bool) -> G
  match e
    case EInt(_, n) -> eb(g, mov_imm64(rax, tagged(n)))
    case EStr(_, s) ->
      let r = str_lit(g, s)
      emit(r.g, mov_addr(rax, r.l))
    case EBool(_, v) -> emit(g, mov_addr(rax, if v then "TRUE" else "FALSE" end))
    case EVar(pos, n) -> cg_res_value(cx, g, resolve(cx, env, n), n, pos)
    case ECtor(pos, n) ->
      match map.get(cx.prog.ctors, n)
        case Some(info) -> if eq(info.arity, 0) then emit(g, mov_addr(rax, ctor_label(n))) else need_wrapper(g, str_cat("ctor:", n)) end
        case None -> fail_code(g, pos, str_cat("unknown constructor ", n))
      end
    case ECall(pos, f, args) -> cg_call(cx, g, env, pos, f, args, tail)
    case EField(pos, x, n) ->
      match module_member(cx, env, x, n)
        case Some(r) -> cg_res_value(cx, g, r, n, pos)
        case None -> cg_field(cx, cg(cx, g, env, x, false), pos, n)
      end
    case EList(_, items) -> cg_list(cx, g, env, items)
    case ERec(pos, t, fields) -> cg_record(cx, g, env, pos, t, fields)
    case EUpd(pos, x, fields) -> cg_update(cx, g, env, pos, x, fields)
    case EIf(pos, conds, bodies, els) ->
      let done = new_label(g)
      cg_if(cx, done.g, env, conds, bodies, els, tail, done.l, pos)
    case EMatch(pos, x, arms) -> cg_match(cx, g, env, pos, x, arms, tail)
    case ELam(pos, params, body) -> cg_lambda(cx, g, env, params, body)
  end
end

fn cg_block(cx: Cx, g: G, env: List[Bind], stmts: List[Stmt], tail: Bool) -> G
  match stmts
    case [] -> emit(g, mov_addr(rax, ctor_label("Unit")))
    case [s] -> cg(cx, g, env, s.x, if eq(s.let_name, "") then tail else false end)
    case [s, ..rest] ->
      let g1 = cg(cx, g, env, s.x, false)
      if eq(s.let_name, "") then cg_block(cx, g1, env, rest, tail) else
        let sl = new_slot(g1)
        let g2 = eb(sl.g, store(rbp, slot_disp(sl.s), rax))
        cg_block(cx, g2, list_cons(Bind { name: s.let_name, loc: LSlot(sl.s) }, env), rest, tail)
      end
  end
end

fn cg_if(cx: Cx, g: G, env: List[Bind], conds: List[Expr], bodies: List[List[Stmt]], els: List[Stmt], tail: Bool, done: String, pos: Pos) -> G
  match conds
    case [] -> emit(cg_block(cx, g, env, els, tail), CLab(done))
    case [c, ..crest] ->
      let next = new_label(g)
      let yes = new_label(next.g)
      let g1 = cg(cx, yes.g, env, c, false)
      let g2 = emit(g1, cat([mov_addr(rdx, "TRUE"), CB(op_rr(57, rax, rdx)), jcc(cc_e, yes.l), mov_addr(rdx, "FALSE"), CB(op_rr(57, rax, rdx))]))
      let g3 = emit(check_cc(g2, cc_e, expr_pos(c), "if condition must be Bool"), jmp(next.l))
      let g4 = cg_block(cx, emit(g3, CLab(yes.l)), env, unwrap_or(list_get(bodies, 0), []), tail)
      let g5 = emit(g4, cat([jmp(done), CLab(next.l)]))
      cg_if(cx, g5, env, crest, list_slice(bodies, 1, list_len(bodies)), els, tail, done, pos)
  end
end

fn push_args(cx: Cx, g: G, env: List[Bind], args: List[Expr]) -> G
  list_fold(args, g, fn(acc, a) eb(cg(cx, acc, env, a, false), push_r(rax)) end)
end

# rewrite the current frame so that the n pushed args become the callee's args, then jump
fn tail_move(cx: Cx, n: Int) -> List[Int]
  let m = cx.nargs
  let base = sub(add(16, mul(8, m)), mul(8, n))
  let moves = list_fold(list_reverse(list_range(0, n)), [], fn(acc, j)
    list_concat(acc, list_concat(ldm(rax, rsp, mul(8, j)), store(rbp, add(base, mul(8, j)), rax)))
  end)
  list_concat(list_concat(list_concat(ldm(rcx, rbp, 8), ldm(rdx, rbp, 0)), moves),
    list_concat(list_concat(lea(rsp, rbp, sub(base, 8)), store(rsp, 0, rcx)), mov_rr(rbp, rdx)))
end

fn embed_value(cx: Cx, pos: Pos, args: List[Expr]) -> Option[String]
  match args
    case [EStr(_, p)] -> map.get(cx.embeds, path_join(dirname(pos.file), p))
    case _ -> None
  end
end

fn cg_call(cx: Cx, g: G, env: List[Bind], pos: Pos, f: Expr, args: List[Expr], tail: Bool) -> G
  let n = list_len(args)
  let target = match f
    case EVar(_, name) -> resolve(cx, env, name)
    case EField(_, x, name) -> unwrap_or(module_member(cx, env, x, name), RNone)
    case _ -> RNone
  end
  match f
    case ECtor(_, cname) -> cg_ctor_app(cx, g, env, pos, cname, args)
    case EVar(_, "embed_file") ->
      match embed_value(cx, pos, args)
        case Some(s) ->
          let r = str_lit(g, s)
          emit(r.g, mov_addr(rax, r.l))
        case None -> fail_code(g, pos, "embed_file: file not available at compile time")
      end
    case _ ->
      match target
        case RFn(l, _) -> cg_direct(cx, push_args(cx, g, env, args), l, n, tail)
        case RRt(l, _) -> cg_direct(cx, push_args(cx, g, env, args), l, n, tail)
        case RLocated(l, _) ->
          let s = str_lit(push_args(cx, g, env, args), pos_str(pos))
          cg_direct(cx, eb(emit(s.g, mov_addr(rax, s.l)), push_r(rax)), l, add(n, 1), false)
        case RInline(name) -> cg_inline(cx, g, env, pos, name, args)
        case _ -> cg_indirect(cx, g, env, pos, f, args, tail)
      end
  end
end

fn cg_direct(cx: Cx, g: G, l: String, n: Int, tail: Bool) -> G
  if tail then emit(eb(g, tail_move(cx, n)), jmp(l)) else emit(g, call_l(l)) end
end

fn cg_indirect(cx: Cx, g: G, env: List[Bind], pos: Pos, f: Expr, args: List[Expr], tail: Bool) -> G
  let n = list_len(args)
  let g1 = push_args(cx, eb(cg(cx, g, env, f, false), push_r(rax)), env, args)
  let g2 = eb(g1, list_concat(ldm(r15, rsp, mul(8, n)), mov_rr(rax, r15)))
  let g3 = check_tag(g2, tag_clo, pos, "called value is not a function")
  let g4 = check_cc(eb(g3, cmp_mem_imm(r15, 16, n)), cc_e, pos, str_join(["function called with ", show(n), " argument(s) expects a different number"], ""))
  if tail then eb(g4, list_concat(tail_move(cx, n), jmp_mem(r15, 8)))
  else eb(g4, list_concat(call_mem(r15, 8), alu_imm(0, rsp, 8))) end
end

fn cg_ctor_app(cx: Cx, g: G, env: List[Bind], pos: Pos, cname: String, args: List[Expr]) -> G
  match map.get(cx.prog.ctors, cname)
    case None -> fail_code(g, pos, str_cat("unknown constructor ", cname))
    case Some(info) ->
      let n = list_len(args)
      let g1 = alloc_fixed(g, add(16, mul(8, n)))
      let g2 = eb(g1, list_concat(mov_imm64(rcx, add(tag_ctor, mul(n, 256))), list_concat(store(rax, 0, rcx), list_concat(mov_imm64(rcx, info.id), store(rax, 8, rcx)))))
      fill_slots(cx, g2, env, args, 16)
  end
end

# object in rax; evaluates each expression and stores it at offset base + 8i; leaves the object in rax
fn fill_slots(cx: Cx, g: G, env: List[Bind], xs: List[Expr], base: Int) -> G
  if eq(list_len(xs), 0) then g else
    let sl = new_slot(g)
    let g1 = eb(sl.g, store(rbp, slot_disp(sl.s), rax))
    let r = list_fold(xs, GS { g: g1, s: 0 }, fn(acc, x)
      let a1 = cg(cx, acc.g, env, x, false)
      GS { g: eb(a1, list_concat(ldm(rcx, rbp, slot_disp(sl.s)), store(rcx, add(base, mul(8, acc.s)), rax))), s: add(acc.s, 1) }
    end)
    eb(r.g, ldm(rax, rbp, slot_disp(sl.s)))
  end
end

fn cg_list(cx: Cx, g: G, env: List[Bind], items: List[Expr]) -> G
  let n = list_len(items)
  let g1 = alloc_fixed(g, add(16, mul(8, n)))
  let g2 = eb(g1, list_concat(list_concat(mov_imm64(rcx, add(tag_list, mul(n, 256))), store(rax, 0, rcx)), list_concat(lea(rcx, rax, 16), store(rax, 8, rcx))))
  fill_slots(cx, g2, env, items, 16)
end

fn field_init(fields: List[FieldInit], name: String) -> Option[Expr]
  match fields
    case [] -> None
    case [f, ..rest] -> if eq(f.name, name) then Some(f.x) else field_init(rest, name) end
  end
end

fn cg_record(cx: Cx, g: G, env: List[Bind], pos: Pos, t: String, fields: List[FieldInit]) -> G
  match map.get(cx.prog.records, t)
    case None -> fail_code(g, pos, str_cat("unknown record type ", t))
    case Some(td) ->
      let n = list_len(td.fields)
      let id = unwrap_or(map.get(cx.rec_ids, t), 0)
      let xs = list_map(td.fields, fn(fd) unwrap_or(field_init(fields, fd.name), ECtor(pos, "Unit")) end)
      let g1 = alloc_fixed(g, add(16, mul(8, n)))
      let g2 = eb(g1, list_concat(mov_imm64(rcx, add(tag_rec, mul(n, 256))), list_concat(store(rax, 0, rcx), list_concat(mov_imm64(rcx, id), store(rax, 8, rcx)))))
      fill_slots(cx, g2, env, xs, 16)
  end
end

# record in rax, type id in rcx: jump to the code for the field's index
fn field_dispatch(cx: Cx, g: G, pos: Pos, name: String, on_index: Fn(G, Int) -> G) -> G
  let cands = unwrap_or(map.get(cx.fields, name), [])
  let idxs = list_fold(cands, [], fn(acc, c) if list_contains(acc, c.idx) then acc else list_push(acc, c.idx) end end)
  let done = new_label(g)
  let r = list_fold(idxs, GL { g: done.g, l: "" }, fn(acc, idx)
    let skip = new_label(acc.g)
    let ids = list_filter(cands, fn(c) eq(c.idx, idx) end)
    let hit = new_label(skip.g)
    let g1 = list_fold(ids, hit.g, fn(a2, c) emit(a2, cat([CB(alu_imm(7, rcx, c.id)), jcc(cc_e, hit.l)])) end)
    let g2 = on_index(emit(g1, cat([jmp(skip.l), CLab(hit.l)])), idx)
    GL { g: emit(g2, cat([jmp(done.l), CLab(skip.l)])), l: "" }
  end)
  emit(fail_code(r.g, pos, str_join(["record has no field ", name], "")), CLab(done.l))
end

fn cg_field(cx: Cx, g: G, pos: Pos, name: String) -> G
  let g1 = check_tag(g, tag_rec, pos, str_join(["field access .", name, " on a value that is not a record"], ""))
  field_dispatch(cx, eb(g1, ldm(rcx, rax, 8)), pos, name, fn(ga, idx) eb(ga, ldm(rax, rax, add(16, mul(8, idx)))) end)
end

fn cg_update(cx: Cx, g: G, env: List[Bind], pos: Pos, x: Expr, fields: List[FieldInit]) -> G
  let g1 = check_tag(cg(cx, g, env, x, false), tag_rec, pos, "record update on a value that is not a record")
  let copy = list_concat(list_concat(list_concat(ldm(rcx, rax, 0), shift(5, rcx, 8)), list_concat(alu_imm(0, rcx, 2), mov_rr(rsi, rax))),
    list_concat(list_concat(mov_rr(rdi, r14), list_concat(mov_rr(rdx, rcx), shift(4, rdx, 3))), list_concat(list_concat(op_rr(1, r14, rdx), mov_rr(rax, rdi)), rep_movsq)))
  let sl = new_slot(eb(g1, copy))
  let g2 = eb(sl.g, store(rbp, slot_disp(sl.s), rax))
  let g3 = list_fold(fields, g2, fn(acc, fi)
    let a1 = eb(cg(cx, acc, env, fi.x, false), list_concat(ldm(rdx, rbp, slot_disp(sl.s)), ldm(rcx, rdx, 8)))
    field_dispatch(cx, a1, fi.pos, fi.name, fn(ga, idx) eb(ga, store(rdx, add(16, mul(8, idx)), rax)) end)
  end)
  eb(g3, ldm(rax, rbp, slot_disp(sl.s)))
end

# ---------- match ----------

fn cg_match(cx: Cx, g: G, env: List[Bind], pos: Pos, x: Expr, arms: List[Arm], tail: Bool) -> G
  let g1 = cg(cx, g, env, x, false)
  let sl = new_slot(g1)
  let g2 = eb(sl.g, store(rbp, slot_disp(sl.s), rax))
  let done = new_label(g2)
  let g3 = list_fold(arms, done.g, fn(acc, arm)
    let next = new_label(acc)
    let p = cg_pat(cx, next.g, env, arm.pat, sl.s, next.l)
    let g4 = cg_block(cx, p.g, p.env, arm.body, tail)
    emit(g4, cat([jmp(done.l), CLab(next.l)]))
  end)
  let s = str_lit(g3, str_join([pos_str(pos), ": runtime error: no case matched value "], ""))
  let g5 = emit(s.g, cat([mov_addr(rax, s.l), CB(push_r(rax)), CB(ldm(rax, rbp, slot_disp(sl.s))), CB(push_r(rax)), call_l(fn_label(rt_module, "fail_value"))]))
  emit(g5, CLab(done.l))
end

fn sub_slot(cx: Cx, g: G, env: List[Bind], p: Pat, load_code: List[Int], fail: String) -> GE
  match p
    case PWild(_) -> GE { g: g, env: env }
    case _ ->
      let sl = new_slot(g)
      let g1 = eb(sl.g, list_concat(load_code, store(rbp, slot_disp(sl.s), rax)))
      cg_pat(cx, g1, env, p, sl.s, fail)
  end
end

# test the value in slot src against p; bind variables; jump to fail on mismatch
fn cg_pat(cx: Cx, g: G, env: List[Bind], p: Pat, src: Int, fail: String) -> GE
  let ld = ldm(rax, rbp, slot_disp(src))
  match p
    case PWild(_) -> GE { g: g, env: env }
    case PVar(_, n) -> GE { g: g, env: list_cons(Bind { name: n, loc: LSlot(src) }, env) }
    case PInt(_, n) -> GE { g: emit(g, cat([CB(list_concat(ld, list_concat(mov_imm64(rcx, tagged(n)), op_rr(57, rax, rcx)))), jcc(cc_ne, fail)])), env: env }
    case PBool(_, v) -> GE { g: emit(g, cat([CB(ld), mov_addr(rdx, if v then "TRUE" else "FALSE" end), CB(op_rr(57, rax, rdx)), jcc(cc_ne, fail)])), env: env }
    case PStr(_, s) ->
      let r = str_lit(g, s)
      GE { g: emit(r.g, cat([CB(list_concat(ld, push_r(rax))), mov_addr(rax, r.l), CB(push_r(rax)), call_l(fn_label(rt_module, "equal")),
        mov_addr(rdx, "TRUE"), CB(op_rr(57, rax, rdx)), jcc(cc_ne, fail)])), env: env }
    case PCtor(_, n, args) ->
      let id = match map.get(cx.prog.ctors, n)
        case Some(info) -> info.id
        case None -> -1
      end
      let g1 = emit(g, cat([CB(list_concat(ld, test_low(rax, 1))), jcc(cc_ne, fail), CB(cmp_byte_mem(rax, 0, tag_ctor)), jcc(cc_ne, fail),
        CB(cmp_mem_imm(rax, 8, id)), jcc(cc_ne, fail)]))
      cg_sub_pats(cx, g1, env, args, src, 0, fail, fn(i) list_concat(ldm(rcx, rbp, slot_disp(src)), ldm(rax, rcx, add(16, mul(8, i)))) end)
    case PList(_, items, rest) ->
      let k = list_len(items)
      let g1 = emit(g, cat([CB(list_concat(ld, test_low(rax, 1))), jcc(cc_ne, fail), CB(cmp_byte_mem(rax, 0, tag_list)), jcc(cc_ne, fail),
        CB(list_concat(list_concat(ldm(rcx, rax, 0), shift(5, rcx, 8)), alu_imm(7, rcx, k))), jcc(if is_some(rest) then cc_l else cc_ne end, fail)]))
      let r = cg_sub_pats(cx, g1, env, items, src, 0, fail, fn(i) list_concat(list_concat(ldm(rcx, rbp, slot_disp(src)), ldm(rcx, rcx, 8)), ldm(rax, rcx, mul(8, i))) end)
      match rest
        case None -> r
        case Some(PWild(_)) -> r
        case Some(rp) ->
          let view = list_concat(list_concat(list_concat(mov_rr(rax, r14), alu_imm(0, r14, 16)), list_concat(ldm(rcx, rbp, slot_disp(src)), ldm(rdx, rcx, 0))),
            list_concat(list_concat(list_concat(alu_imm(5, rdx, mul(k, 256)), store(rax, 0, rdx)), list_concat(ldm(rdx, rcx, 8), alu_imm(0, rdx, mul(8, k)))), store(rax, 8, rdx)))
          sub_slot(cx, r.g, r.env, rp, view, fail)
      end
  end
end

fn cg_sub_pats(cx: Cx, g: G, env: List[Bind], ps: List[Pat], src: Int, i: Int, fail: String, loader: Fn(Int) -> List[Int]) -> GE
  match ps
    case [] -> GE { g: g, env: env }
    case [p, ..rest] ->
      let r = sub_slot(cx, g, env, p, loader(i), fail)
      cg_sub_pats(cx, r.g, r.env, rest, src, add(i, 1), fail, loader)
  end
end

# ---------- lambdas ----------

fn fv_block(stmts: List[Stmt], bound: List[String], acc: List[String]) -> List[String]
  match stmts
    case [] -> acc
    case [s, ..rest] ->
      let acc2 = fv(s.x, bound, acc)
      fv_block(rest, if eq(s.let_name, "") then bound else list_cons(s.let_name, bound) end, acc2)
  end
end

fn pat_names(p: Pat, acc: List[String]) -> List[String]
  match p
    case PVar(_, n) -> list_cons(n, acc)
    case PCtor(_, _, args) -> list_fold(args, acc, fn(a, x) pat_names(x, a) end)
    case PList(_, items, rest) ->
      let a1 = list_fold(items, acc, fn(a, x) pat_names(x, a) end)
      match rest
        case Some(r) -> pat_names(r, a1)
        case None -> a1
      end
    case _ -> acc
  end
end

fn add_name(acc: List[String], n: String) -> List[String]
  if list_contains(acc, n) then acc else list_push(acc, n) end
end

# free variable names of e (names not bound inside e), in first-use order
fn fv(e: Expr, bound: List[String], acc: List[String]) -> List[String]
  match e
    case EVar(_, n) -> if list_contains(bound, n) then acc else add_name(acc, n) end
    case ECall(_, f, args) -> list_fold(args, fv(f, bound, acc), fn(a, x) fv(x, bound, a) end)
    case EField(_, x, _) -> fv(x, bound, acc)
    case EList(_, items) -> list_fold(items, acc, fn(a, x) fv(x, bound, a) end)
    case ERec(_, _, fields) -> list_fold(fields, acc, fn(a, f) fv(f.x, bound, a) end)
    case EUpd(_, x, fields) -> list_fold(fields, fv(x, bound, acc), fn(a, f) fv(f.x, bound, a) end)
    case EIf(_, conds, bodies, els) ->
      let a1 = list_fold(conds, acc, fn(a, x) fv(x, bound, a) end)
      fv_block(els, bound, list_fold(bodies, a1, fn(a, b) fv_block(b, bound, a) end))
    case EMatch(_, x, arms) -> list_fold(arms, fv(x, bound, acc), fn(a, arm) fv_block(arm.body, pat_names(arm.pat, bound), a) end)
    case ELam(_, params, body) -> fv_block(body, list_concat(params, bound), acc)
    case _ -> acc
  end
end

fn cg_lambda(cx: Cx, g: G, env: List[Bind], params: List[String], body: List[Stmt]) -> G
  let caps = list_filter(fv_block(body, params, []), fn(n) is_some(lookup_env(env, n)) end)
  let k = list_len(caps)
  let lab = new_global_label(g, "lam:")
  let inner_env = list_concat(
    list_map(list_range(0, list_len(params)), fn(i) Bind { name: unwrap_or(list_get(params, i), ""), loc: LArg(i) } end),
    list_map(list_range(0, k), fn(i) Bind { name: unwrap_or(list_get(caps, i), ""), loc: LCap(i) } end))
  let g1 = cg_function({ cx with nargs: list_len(params) }, lab.g, lab.l, list_len(params), list_reverse(inner_env), body)
  let g2 = alloc_fixed(g1, add(24, mul(8, k)))
  let g3 = emit(g2, cat([CB(list_concat(mov_imm64(rcx, add(tag_clo, mul(k, 256))), store(rax, 0, rcx))), mov_addr(rcx, lab.l),
    CB(list_concat(list_concat(store(rax, 8, rcx), mov_imm64(rcx, list_len(params))), store(rax, 16, rcx)))]))
  list_fold(list_range(0, k), g3, fn(acc, i)
    match lookup_env(env, unwrap_or(list_get(caps, i), ""))
      case Some(loc) -> eb(acc, list_concat(load_loc(cx, rcx, loc), store(rax, add(24, mul(8, i)), rcx)))
      case None -> acc
    end
  end)
end

# generates a complete function into g.funcs, keeping the caller's code and slots
fn cg_function(cx: Cx, g: G, label: String, nparams: Int, env: List[Bind], body: List[Stmt]) -> G
  let g1 = cg_block({ cx with nargs: nparams }, { g with code: CNil, slot: 1 }, env, body, true)
  let frame = mul(8, g1.slot)
  let prologue = list_concat(list_concat(push_r(rbp), mov_rr(rbp, rsp)), list_concat(alu_imm(5, rsp, frame), store(rbp, -8, r15)))
  let epilogue = list_concat(list_concat(mov_rr(rsp, rbp), pop_r(rbp)), ret_n(mul(8, nparams)))
  let f = cat([CLab(label), CB(prologue), g1.code, CB(epilogue)])
  { g1 with funcs: list_push(g1.funcs, f), code: g.code, slot: g.slot }
end

# ---------- inline builtins and intrinsics ----------

fn args2(cx: Cx, g: G, env: List[Bind], args: List[Expr]) -> G
  match args
    case [a, b] -> eb(cg(cx, eb(cg(cx, g, env, a, false), push_r(rax)), env, b, false), pop_r(rcx))
    case _ -> g
  end
end

fn arg1(cx: Cx, g: G, env: List[Bind], args: List[Expr]) -> G
  match args
    case [a] -> cg(cx, g, env, a, false)
    case _ -> g
  end
end

fn check_ints(g: G, pos: Pos, name: String) -> G
  check_cc(eb(g, list_concat(mov_rr(rdx, rcx), list_concat(op_rr(33, rdx, rax), test_low(rdx, 1)))), cc_ne, pos, str_cat(name, ": arguments must be Int"))
end

fn cg_divmod(g: G, pos: Pos, name: String, is_mod: Bool) -> G
  let g1 = check_ints(g, pos, name)
  let g2 = check_cc(eb(g1, list_concat(list_concat(shift(7, rcx, 1), shift(7, rax, 1)), op_rr(133, rax, rax))), cc_ne, pos, str_cat(name, " by zero"))
  let fix = new_label(g2)
  let g3 = eb(fix.g, list_concat(list_concat(mov_rr(r8, rax), mov_rr(rax, rcx)), list_concat(cqo, idiv(r8))))
  let g4 = emit(g3, cat([CB(op_rr(133, rdx, rdx)), jcc(cc_e, fix.l), CB(list_concat(mov_rr(r9, rdx), op_rr(49, r9, r8))), jcc(cc_ns, fix.l),
    CB(list_concat(alu_imm(5, rax, 1), op_rr(1, rdx, r8))), CLab(fix.l)]))
  eb(g4, list_concat(if is_mod then mov_rr(rax, rdx) else [] end, tag_rax()))
end

fn cg_compare(g: G, pos: Pos, c: Int) -> G
  let slow = new_label(g)
  let go = new_label(slow.g)
  let g1 = emit(go.g, cat([CB(list_concat(mov_rr(rdx, rcx), list_concat(op_rr(33, rdx, rax), test_low(rdx, 1)))), jcc(cc_e, slow.l),
    CB(op_rr(57, rcx, rax)), jmp(go.l), CLab(slow.l), CB(list_concat(push_r(rcx), push_r(rax))), call_l(fn_label(rt_module, "compare")),
    CB(alu_imm(7, rax, 1)), CLab(go.l)]))
  set_bool(g1, c)
end

fn cg_equal(g: G, negate: Bool) -> G
  let t = new_label(g)
  let f = new_label(t.g)
  let e = new_label(f.g)
  let yes = if negate then "FALSE" else "TRUE" end
  let no = if negate then "TRUE" else "FALSE" end
  let deep = if negate then
    cat([call_l(fn_label(rt_module, "equal")), mov_addr(rdx, "TRUE"), CB(op_rr(57, rax, rdx)), jcc(cc_e, t.l), jmp(f.l)])
  else
    cat([call_l(fn_label(rt_module, "equal")), jmp(e.l)])
  end
  emit(e.g, cat([CB(op_rr(57, rcx, rax)), jcc(cc_e, t.l), CB(list_concat(mov_rr(rdx, rcx), list_concat(op_rr(9, rdx, rax), test_low(rdx, 1)))), jcc(cc_ne, f.l),
    CB(list_concat(push_r(rcx), push_r(rax))), deep,
    CLab(t.l), mov_addr(rax, yes), jmp(e.l), CLab(f.l), mov_addr(rax, no), CLab(e.l)]))
end

# rcx = object; rcx := address of its first slot (list data, closure captures, record/ctor fields)
fn slot_base(g: G) -> G
  let l = new_label(g)
  let c = new_label(l.g)
  let d = new_label(c.g)
  emit(d.g, cat([CB(cmp_byte_mem(rcx, 0, tag_list)), jcc(cc_e, l.l), CB(cmp_byte_mem(rcx, 0, tag_clo)), jcc(cc_e, c.l),
    CB(lea(rcx, rcx, 16)), jmp(d.l), CLab(l.l), CB(ldm(rcx, rcx, 8)), jmp(d.l), CLab(c.l), CB(lea(rcx, rcx, 24)), CLab(d.l)]))
end

fn unit_rax() -> Code
  mov_addr(rax, ctor_label("Unit"))
end

fn cg_inline(cx: Cx, g: G, env: List[Bind], pos: Pos, name: String, args: List[Expr]) -> G
  if eq(name, "add") then eb(check_ints(args2(cx, g, env, args), pos, name), list_concat(op_rr(1, rax, rcx), alu_imm(5, rax, 1)))
  elif eq(name, "sub") then eb(check_ints(args2(cx, g, env, args), pos, name), list_concat(list_concat(op_rr(41, rcx, rax), alu_imm(0, rcx, 1)), mov_rr(rax, rcx)))
  elif eq(name, "mul") then eb(check_ints(args2(cx, g, env, args), pos, name), list_concat(list_concat(shift(7, rcx, 1), alu_imm(5, rax, 1)), list_concat(imul(rax, rcx), alu_imm(0, rax, 1))))
  elif eq(name, "div") then cg_divmod(args2(cx, g, env, args), pos, name, false)
  elif eq(name, "mod") then cg_divmod(args2(cx, g, env, args), pos, name, true)
  elif eq(name, "lt") then cg_compare(args2(cx, g, env, args), pos, cc_l)
  elif eq(name, "le") then cg_compare(args2(cx, g, env, args), pos, cc_le)
  elif eq(name, "gt") then cg_compare(args2(cx, g, env, args), pos, cc_g)
  elif eq(name, "ge") then cg_compare(args2(cx, g, env, args), pos, cc_ge)
  elif eq(name, "eq") then cg_equal(args2(cx, g, env, args), false)
  elif eq(name, "ne") then cg_equal(args2(cx, g, env, args), true)
  elif eq(name, "not") then
    let g1 = check_bool(arg1(cx, g, env, args), rax, pos, "not: argument must be Bool")
    set_bool(emit(g1, cat([mov_addr(rdx, "FALSE"), CB(op_rr(57, rax, rdx))])), cc_e)
  elif or(eq(name, "and"), eq(name, "or")) then
    let g1 = check_bool(check_bool(args2(cx, g, env, args), rcx, pos, str_cat(name, ": arguments must be Bool")), rax, pos, str_cat(name, ": arguments must be Bool"))
    let keep = new_label(g1)
    emit(keep.g, cat([mov_addr(rdx, if eq(name, "and") then "FALSE" else "TRUE" end), CB(op_rr(57, rcx, rdx)), jcc(cc_ne, keep.l), CB(mov_rr(rax, rdx)), CLab(keep.l)]))
  else cg_prim(cx, g, env, pos, name, args)
  end
end

fn push_all(cx: Cx, g: G, env: List[Bind], args: List[Expr]) -> G
  push_args(cx, g, env, args)
end

fn cg_prim(cx: Cx, g: G, env: List[Bind], pos: Pos, name: String, args: List[Expr]) -> G
  if eq(name, "prim_tag") then
    let p = new_label(g)
    let e = new_label(p.g)
    emit(arg1(cx, e.g, env, args), cat([CB(test_low(rax, 1)), jcc(cc_e, p.l), CB(mov_imm64(rax, 1)), jmp(e.l), CLab(p.l), CB(list_concat(movzx_byte(rax, rax, 0), tag_rax())), CLab(e.l)]))
  elif eq(name, "prim_len") then eb(arg1(cx, g, env, args), list_concat(list_concat(ldm(rax, rax, 0), shift(5, rax, 8)), tag_rax()))
  elif eq(name, "prim_id") then eb(arg1(cx, g, env, args), list_concat(ldm(rax, rax, 8), tag_rax()))
  elif eq(name, "prim_slot") then
    let g1 = slot_base(eb(args2(cx, g, env, args), list_concat(shift(7, rax, 1), shift(4, rax, 3))))
    eb(g1, list_concat(op_rr(1, rcx, rax), ldm(rax, rcx, 0)))
  elif eq(name, "prim_set_slot") then
    let g1 = cg(cx, push_all(cx, g, env, list_slice(args, 0, 2)), env, unwrap_or(list_get(args, 2), EInt(pos, 0)), false)
    let g2 = slot_base(eb(g1, list_concat(list_concat(pop_r(rdx), pop_r(rcx)), list_concat(shift(7, rdx, 1), shift(4, rdx, 3)))))
    emit(eb(g2, list_concat(op_rr(1, rcx, rdx), store(rcx, 0, rax))), unit_rax())
  elif eq(name, "prim_byte") then eb(args2(cx, g, env, args), list_concat(list_concat(shift(7, rax, 1), op_rr(1, rax, rcx)), list_concat(movzx_byte(rax, rax, 8), tag_rax())))
  elif eq(name, "prim_set_byte") then
    let g1 = cg(cx, push_all(cx, g, env, list_slice(args, 0, 2)), env, unwrap_or(list_get(args, 2), EInt(pos, 0)), false)
    emit(eb(g1, list_concat(list_concat(list_concat(pop_r(rdx), pop_r(rcx)), list_concat(shift(7, rdx, 1), op_rr(1, rcx, rdx))), list_concat(shift(7, rax, 1), store_byte(rcx, 8, rax)))), unit_rax())
  elif eq(name, "prim_str_new") then
    eb(arg1(cx, g, env, args), list_concat(list_concat(list_concat(shift(7, rax, 1), mov_rr(rcx, rax)), list_concat(alu_imm(0, rax, 15), alu_imm(4, rax, -8))),
      list_concat(list_concat(list_concat(mov_rr(rdx, r14), op_rr(1, r14, rax)), list_concat(shift(4, rcx, 8), alu_imm(0, rcx, tag_str))), list_concat(store(rdx, 0, rcx), mov_rr(rax, rdx)))))
  elif eq(name, "prim_list_new") then
    eb(arg1(cx, g, env, args), list_concat(list_concat(list_concat(shift(7, rax, 1), mov_rr(rcx, rax)), list_concat(shift(4, rax, 3), alu_imm(0, rax, 16))),
      list_concat(list_concat(list_concat(mov_rr(rdx, r14), op_rr(1, r14, rax)), list_concat(shift(4, rcx, 8), alu_imm(0, rcx, tag_list))),
        list_concat(list_concat(store(rdx, 0, rcx), lea(rcx, rdx, 16)), list_concat(store(rdx, 8, rcx), mov_rr(rax, rdx))))))
  elif eq(name, "prim_list_view") then
    let g1 = cg(cx, push_all(cx, g, env, list_slice(args, 0, 2)), env, unwrap_or(list_get(args, 2), EInt(pos, 0)), false)
    eb(g1, list_concat(list_concat(list_concat(pop_r(rdx), pop_r(rcx)), list_concat(list_concat(shift(7, rax, 1), shift(4, rax, 8)), alu_imm(0, rax, tag_list))),
      list_concat(list_concat(list_concat(mov_rr(rsi, r14), alu_imm(0, r14, 16)), store(rsi, 0, rax)),
        list_concat(list_concat(ldm(rax, rcx, 8), list_concat(shift(7, rdx, 1), shift(4, rdx, 3))), list_concat(list_concat(op_rr(1, rax, rdx), store(rsi, 8, rax)), mov_rr(rax, rsi))))))
  elif eq(name, "prim_record_copy") then
    eb(arg1(cx, g, env, args), list_concat(list_concat(list_concat(ldm(rcx, rax, 0), shift(5, rcx, 8)), list_concat(alu_imm(0, rcx, 2), mov_rr(rsi, rax))),
      list_concat(list_concat(mov_rr(rdi, r14), list_concat(mov_rr(rdx, rcx), shift(4, rdx, 3))), list_concat(list_concat(op_rr(1, r14, rdx), mov_rr(rax, rdi)), rep_movsq))))
  elif eq(name, "prim_addr") then eb(arg1(cx, g, env, args), list_concat(alu_imm(0, rax, 8), tag_rax()))
  elif eq(name, "prim_peek") then eb(arg1(cx, g, env, args), list_concat(list_concat(shift(7, rax, 1), ldm(rax, rax, 0)), tag_rax()))
  elif eq(name, "prim_peek8") then eb(arg1(cx, g, env, args), list_concat(list_concat(shift(7, rax, 1), movzx_byte(rax, rax, 0)), tag_rax()))
  elif eq(name, "prim_syscall") then
    let regs = [r9, r8, r10, rdx, rsi, rdi, rax]
    let g1 = push_all(cx, g, env, args)
    eb(g1, list_concat(list_fold(regs, [], fn(acc, r) list_concat(acc, list_concat(pop_r(r), shift(7, r, 1))) end), list_concat(syscall_op, tag_rax())))
  elif eq(name, "prim_ctor_name") then name_table(arg1(cx, g, env, args), "t:ctor_names")
  elif eq(name, "prim_record_name") then name_table(arg1(cx, g, env, args), "t:rec_names")
  elif eq(name, "prim_field_name") then
    let g1 = args2(cx, g, env, args)
    emit(g1, cat([CB(list_concat(ldm(rcx, rcx, 8), shift(4, rcx, 3))), mov_addr(rdx, "t:rec_fields"),
      CB(list_concat(list_concat(list_concat(op_rr(1, rdx, rcx), ldm(rdx, rdx, 0)), ldm(rdx, rdx, 8)), list_concat(list_concat(shift(7, rax, 1), shift(4, rax, 3)), list_concat(op_rr(1, rdx, rax), ldm(rax, rdx, 0)))))]))
  elif eq(name, "prim_argv") then eb(emit(g, load_abs(rax, "argv_base")), tag_rax())
  elif eq(name, "prim_handle") then
    eb(arg1(cx, g, env, args), list_concat(list_concat(list_concat(shift(7, rax, 1), mov_rr(rcx, r14)), list_concat(alu_imm(0, r14, 16), mov_imm64(rdx, 7))),
      list_concat(list_concat(store(rcx, 0, rdx), store(rcx, 8, rax)), mov_rr(rax, rcx))))
  elif eq(name, "prim_term_save") then
    let p = new_label(g)
    let s = new_label(p.g)
    emit(arg1(cx, s.g, env, args), cat([CB(test_low(rax, 1)), jcc(cc_e, p.l), CB(mov_imm64(rax, 0)), jmp(s.l), CLab(p.l), CB(alu_imm(0, rax, 8)), CLab(s.l),
      store_abs("termios_ptr", rax), unit_rax()]))
  elif eq(name, "prim_copy") then
    let g1 = cg(cx, push_all(cx, g, env, list_slice(args, 0, 4)), env, unwrap_or(list_get(args, 4), EInt(pos, 0)), false)
    emit(eb(g1, list_concat(list_concat(list_concat(mov_rr(rcx, rax), shift(7, rcx, 1)), list_concat(pop_r(rax), shift(7, rax, 1))),
      list_concat(list_concat(list_concat(pop_r(rsi), op_rr(1, rsi, rax)), alu_imm(0, rsi, 8)),
        list_concat(list_concat(list_concat(pop_r(rax), shift(7, rax, 1)), list_concat(pop_r(rdi), op_rr(1, rdi, rax))), list_concat(alu_imm(0, rdi, 8), rep_movsb))))), unit_rax())
  else fail_code(g, pos, str_cat("unknown intrinsic ", name))
  end
end

fn name_table(g: G, table: String) -> G
  emit(g, cat([CB(list_concat(ldm(rcx, rax, 8), shift(4, rcx, 3))), mov_addr(rdx, table), CB(list_concat(op_rr(1, rdx, rcx), ldm(rax, rdx, 0)))]))
end
