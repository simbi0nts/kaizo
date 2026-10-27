# Whole-program generation: every function, static data, descriptor tables, entry point.

type Mode = AppMode | TestMode(String) end

fn param_env(params: List[String]) -> List[Bind]
  list_map(list_range(0, list_len(params)), fn(i) Bind { name: unwrap_or(list_get(params, i), ""), loc: LArg(i) } end)
end

fn static_closure(label: String, arity: Int) -> Code
  cat([CLab(clo_label(label)), CB(lebytes(tag_clo, 8)), CA64(label), CB(lebytes(arity, 8))])
end

fn field_table(p: Program) -> Map[List[FIdx]]
  let r = list_fold(p.record_list, FT { m: map.empty(), id: 0 }, fn(acc, td)
    let m2 = list_fold(list_range(0, list_len(td.fields)), acc.m, fn(m, j)
      let name = match list_get(td.fields, j)
        case Some(f) -> f.name
        case None -> ""
      end
      map.set(m, name, list_push(unwrap_or(map.get(m, name), []), FIdx { id: acc.id, idx: j }))
    end)
    FT { m: m2, id: add(acc.id, 1) }
  end)
  r.m
end

type FT = { m: Map[List[FIdx]], id: Int } end

fn record_ids(p: Program) -> Map[Int]
  let r = list_fold(p.record_list, RI { m: map.empty(), id: 0 }, fn(acc, td) RI { m: map.set(acc.m, td.name, acc.id), id: add(acc.id, 1) } end)
  r.m
end

type RI = { m: Map[Int], id: Int } end

fn gen_fns(cx: Cx, g: G, m: Module) -> G
  list_fold(m.files, g, fn(acc, f)
    list_fold(f.fns, acc, fn(a2, fd)
      let l = fn_label(m.name, fd.name)
      let ps = list_map(fd.params, fn(p) p.name end)
      let a3 = cg_function({ cx with mod: m }, a2, l, list_len(ps), param_env(ps), fd.body)
      emit_data(a3, static_closure(l, list_len(ps)))
    end)
  end)
end

fn gen_init(cx: Cx, g: G) -> G
  let body = list_fold(cx.prog.order, { g with code: CNil, slot: 1 }, fn(acc, name)
    let m = get_module(cx.prog, name)
    list_fold(m.files, acc, fn(a2, f)
      list_fold(f.lets, a2, fn(a3, ld)
        let gl = str_join(["g:", m.name, ".", ld.name], "")
        let a4 = cg({ cx with mod: m, nargs: 0 }, a3, [], ld.x, false)
        emit_data(emit(a4, store_abs(gl, rax)), cat([CLab(gl), CB(lebytes(0, 8))]))
      end)
    end)
  end)
  let prologue = list_concat(list_concat(push_r(rbp), mov_rr(rbp, rsp)), alu_imm(5, rsp, mul(8, body.slot)))
  let f = cat([CLab("init"), CB(prologue), body.code, CB(list_concat(list_concat(mov_rr(rsp, rbp), pop_r(rbp)), ret_n(0)))])
  { body with funcs: list_push(body.funcs, f), code: g.code, slot: g.slot }
end

fn gen_wrapper(cx: Cx, g: G, w: String) -> G
  let rt = get_module(cx.prog, rt_module)
  let pos = Pos { file: "<wrapper>", line: 0, col: 0 }
  let is_ctor = str_starts(w, "ctor:")
  let name = str_slice(w, if is_ctor then 5 else 3 end, str_len(w))
  let arity = if is_ctor then
    match map.get(cx.prog.ctors, name)
      case Some(info) -> info.arity
      case None -> 0
    end
  else
    match map.get(builtins, name)
      case Some(bi) -> bi.arity
      case None -> unwrap_or(map.get(table_arity(prims), name), 0)
    end
  end
  let params = list_map(list_range(0, arity), fn(i) str_cat("a", show(i)) end)
  let callee = if is_ctor then ECtor(pos, name) else EVar(pos, name) end
  let body = [Stmt { pos: pos, let_name: "", x: ECall(pos, callee, list_map(params, fn(p) EVar(pos, p) end)) }]
  let l = str_cat("w:", w)
  emit_data(cg_function({ cx with mod: rt }, g, l, arity, param_env(params), body), static_closure(l, arity))
end

fn table_arity(t: Map[Builtin]) -> Map[Int]
  list_fold(map.entries(t), map.empty(), fn(m, e) map.set(m, e.key, e.value.arity) end)
end

fn gen_wrappers(cx: Cx, g: G, done: List[String]) -> G
  match list_filter(g.wrappers, fn(w) not(list_contains(done, w)) end)
    case [] -> g
    case [w, .._] -> gen_wrappers(cx, gen_wrapper(cx, g, w), list_push(done, w))
  end
end

# static list object holding the given words
fn static_list(label: String, words: List[Code]) -> Code
  let n = list_len(words)
  cat(list_concat([CLab(label), CB(lebytes(add(tag_list, mul(n, 256)), 8)), CA64(str_cat(label, ".d")), CLab(str_cat(label, ".d"))], words))
end

fn gen_tables(g: G, p: Program) -> G
  let r1 = list_fold(p.ctor_list, GW { g: g, words: [] }, fn(acc, c)
    let s = str_lit(acc.g, c.name)
    GW { g: s.g, words: list_push(acc.words, CA64(s.l)) }
  end)
  let objs = list_fold(p.ctor_list, CNil, fn(acc, c)
    if eq(c.arity, 0) then CCat(acc, cat([CLab(ctor_label(c.name)), CB(list_concat(lebytes(tag_ctor, 8), lebytes(c.id, 8)))])) else acc end
  end)
  let g1 = emit_data(r1.g, CCat(cat(list_concat([CLab("t:ctor_names")], r1.words)), objs))
  let r2 = list_fold(p.record_list, GW { g: g1, words: [] }, fn(acc, td)
    let s = str_lit(acc.g, td.name)
    GW { g: s.g, words: list_push(acc.words, CA64(s.l)) }
  end)
  let g2 = emit_data(r2.g, cat(list_concat([CLab("t:rec_names")], r2.words)))
  let r3 = list_fold(list_range(0, list_len(p.record_list)), GW { g: g2, words: [] }, fn(acc, i)
    let td = unwrap_or(list_get(p.record_list, i), builtin_type("?"))
    let fr = list_fold(td.fields, GW { g: acc.g, words: [] }, fn(a2, f)
      let s = str_lit(a2.g, f.name)
      GW { g: s.g, words: list_push(a2.words, CA64(s.l)) }
    end)
    let lab = str_cat("t:fields:", show(i))
    GW { g: emit_data(fr.g, static_list(lab, fr.words)), words: list_push(acc.words, CA64(lab)) }
  end)
  emit_data(r3.g, cat(list_concat([CLab("t:rec_fields")], r3.words)))
end

type GW = { g: G, words: List[Code] } end

let sa_restorer = 67108864

fn gen_runtime_data(g: G) -> G
  emit_data(g, cat([
    CLab("TRUE"), CB(list_concat(lebytes(5, 8), lebytes(1, 8))),
    CLab("FALSE"), CB(list_concat(lebytes(5, 8), lebytes(0, 8))),
    CLab("argv_base"), CB(lebytes(0, 8)),
    CLab("termios_ptr"), CB(lebytes(0, 8)),
    CLab("sigact"), CA64("sighandler"), CB(lebytes(sa_restorer, 8)), CA64("sighandler"), CB(lebytes(0, 8)),
    CLab("sigign"), CB(list_concat(list_concat(lebytes(1, 8), lebytes(0, 8)), list_concat(lebytes(0, 8), lebytes(0, 8)))),
    CLab("cursor_on"), CB([27, 91, 63, 50, 53, 104, 0, 0])
  ]))
end

fn sys_mmap(size: Int) -> List[Int]
  list_concat(list_concat(list_concat(mov_imm32(rax, 9), mov_imm32(rdi, 0)), list_concat(mov_imm64(rsi, size), mov_imm32(rdx, 3))),
    list_concat(list_concat(mov_imm32(r10, 16418), mov_imm64(r8, -1)), list_concat(mov_imm32(r9, 0), syscall_op)))
end

fn sigaction_code(sig: Int, act: String) -> Code
  cat([CB(list_concat(mov_imm32(rax, 13), mov_imm32(rdi, sig))), mov_addr(rsi, act), CB(list_concat(list_concat(mov_imm32(rdx, 0), mov_imm32(r10, 8)), syscall_op))])
end

let heap_size = 68719476736
let stack_size = 1073741824

fn gen_start(g: G, mode: Mode) -> G
  let call_main = match mode
    case AppMode -> call_l(fn_label(main_module, "main"))
    case TestMode(path) -> cat([mov_addr(rax, "t:test_path"), CB(push_r(rax)), mov_addr(rax, "t:test_names"), CB(push_r(rax)), mov_addr(rax, "t:test_fns"), CB(push_r(rax)), call_l(fn_label(rt_module, "run_tests"))])
  end
  let start = cat([CLab("_start"), store_abs("argv_base", rsp),
    CB(list_concat(sys_mmap(heap_size), mov_rr(r14, rax))),
    CB(list_concat(list_concat(sys_mmap(stack_size), alu_imm(0, rax, stack_size)), mov_rr(rsp, rax))),
    sigaction_code(2, "sigact"), sigaction_code(15, "sigact"), sigaction_code(13, "sigign"),
    call_l("init"), call_main,
    CB(list_concat(list_concat(mov_imm32(rax, 231), mov_imm32(rdi, 0)), syscall_op))])
  let skip = ".sigskip"
  let handler = cat([CLab("sighandler"), CB(mov_rr(12, rdi)), load_abs(rdx, "termios_ptr"), CB(op_rr(133, rdx, rdx)), jcc(cc_e, skip),
    CB(list_concat(list_concat(mov_imm32(rax, 16), mov_imm32(rdi, 0)), list_concat(mov_imm32(rsi, 21506), syscall_op))),
    CB(list_concat(mov_imm32(rax, 1), mov_imm32(rdi, 1))), mov_addr(rsi, "cursor_on"), CB(list_concat(mov_imm32(rdx, 6), syscall_op)),
    CLab(skip), CB(list_concat(list_concat(mov_rr(rdi, 12), alu_imm(0, rdi, 128)), list_concat(mov_imm32(rax, 231), syscall_op)))])
  { g with funcs: list_push(list_push(g.funcs, start), handler) }
end

fn gen_tests(cx: Cx, g: G, path: String) -> G
  let m = get_module(cx.prog, main_module)
  let r = list_fold(m.tests, TG { g: g, k: 0, names: [], fns: [] }, fn(acc, t)
    let l = str_cat("test:", show(acc.k))
    let g1 = emit_data(cg_function({ cx with mod: m }, acc.g, l, 0, [], t.body), static_closure(l, 0))
    let s = str_lit(g1, t.name)
    TG { g: s.g, k: add(acc.k, 1), names: list_push(acc.names, CA64(s.l)), fns: list_push(acc.fns, CA64(clo_label(l))) }
  end)
  emit_data(r.g, cat([static_list("t:test_names", r.names), static_list("t:test_fns", r.fns), CLab("t:test_path"), str_object(path)]))
end

type TG = { g: G, k: Int, names: List[Code], fns: List[Code] } end

fn gen_program(p: Program, embeds: Map[String], mode: Mode) -> Image
  let cx = Cx { prog: p, mod: get_module(p, main_module), nargs: 0, fields: field_table(p), rec_ids: record_ids(p), embeds: embeds }
  let g0 = G { code: CNil, slot: 1, lab: 0, data: CNil, funcs: [], wrappers: [], strs: map.empty() }
  let g1 = list_fold(p.order, g0, fn(acc, name) gen_fns(cx, acc, get_module(p, name)) end)
  let g2 = gen_init(cx, g1)
  let g3 = match mode
    case TestMode(path) -> gen_tests(cx, g2, path)
    case AppMode -> g2
  end
  let g4 = gen_start(gen_runtime_data(gen_tables(gen_wrappers(cx, g3, []), p)), mode)
  let blobs = list_push(list_map(g4.funcs, assemble), assemble(g4.data))
  link_image(blobs, "_start")
end
