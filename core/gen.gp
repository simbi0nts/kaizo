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
  let f = cat([CLab("init"), CI([IEnter, IAluI(5, rsp, mul(8, body.slot))]), body.code, CI([ILeave(0)])])
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

# ---------- runtime data and entry points ----------

fn gen_runtime_data(g: G, t: Target) -> G
  let sig = if eq(t.os, "linux") then
    cat([CLab("sigact"), CA64("sighandler"), CB(lebytes(67108864, 8)), CA64("sighandler"), CB(lebytes(0, 8)), CLab("sigign"), CB(lebytes(1, 32))])
  else CNil end
  emit_data(g, cat([sig,
    CLab("TRUE"), CB(list_concat(lebytes(5, 8), lebytes(1, 8))),
    CLab("FALSE"), CB(list_concat(lebytes(5, 8), lebytes(0, 8))),
    CLab("g_argc"), CB(lebytes(0, 8)), CLab("g_argv"), CB(lebytes(0, 8)), CLab("g_envp"), CB(lebytes(0, 8)),
    CLab("termios_ptr"), CB(lebytes(0, 8)), CLab("sig_num"), CB(lebytes(0, 8)),
    CLab("heap_base"), CB(lebytes(0, 8)), CLab("heap_end"), CB(lebytes(0, 8)), CLab("ctrl_tmp"), CB(lebytes(0, 16)),
    CLab("cursor_on"), CB([27, 91, 63, 50, 53, 104, 0, 0])
  ]))
end

let heap_size = 68719476736
let stack_size = 1073741824

# argument registers of the platform C ABI, as IR registers
fn abi_args(t: Target) -> List[Int]
  if eq(t.arch, "arm64") then [rax, rcx, rdx, rsi, rdi, r8, r9, r10]
  elif eq(t.os, "windows") then [rcx, rdx, r8, r9]
  else [rdi, rsi, rdx, rcx, r8, r9]
  end
end

fn arg_reg(t: Target, i: Int) -> Int
  unwrap_or(list_get(abi_args(t), i), rax)
end

# raw C call with immediate arguments
fn craw(t: Target, sym: String, args: List[Int]) -> List[Ins]
  list_push(list_map(list_range(0, list_len(args)), fn(i) IMovI(arg_reg(t, i), unwrap_or(list_get(args, i), 0)) end), ICRaw(sym))
end

# data pointers (CA64) were linked for the preferred address; add the load slide (macOS ASLR)
fn self_reloc() -> Code
  cat([CI([IAddr(rax, "data_start"), ILdG(rcx, "data_start_link"), IAlu(41, rax, rcx), IAluI(7, rax, 0)]), jcc(cc_e, ".rel_done"),
    CI([IAddr(rdx, "reloc_table"), ILd(rcx, rdx, 0), IAddr(rsi, "data_start")]),
    CLab(".rel_loop"), CI([IAluI(7, rcx, 0)]), jcc(cc_e, ".rel_done"),
    CI([IAluI(0, rdx, 8), ILd(rdi, rdx, 0), IAlu(1, rdi, rsi), ILd(r8, rdi, 0), IAlu(1, r8, rax), ISt(rdi, 0, r8), IAluI(5, rcx, 1)]),
    jmp(".rel_loop"), CLab(".rel_done")])
end

fn call_main(mode: Mode) -> Code
  match mode
    case AppMode -> call_l(fn_label(main_module, "main"))
    case TestMode(_) -> cat([mov_addr(rax, "t:test_path"), CI(push_r(rax)), mov_addr(rax, "t:test_names"), CI(push_r(rax)),
      mov_addr(rax, "t:test_fns"), CI(push_r(rax)), call_l(fn_label(rt_module, "run_tests"))])
  end
end

fn sys_mmap(size: Int) -> List[Ins]
  [IMovI(rax, 9), IMovI(rdi, 0), IMovI(rsi, size), IMovI(rdx, 3), IMovI(r10, 16418), IMovI(r8, -1), IMovI(r9, 0), ISys]
end

fn start_linux(mode: Mode) -> List[Code]
  let start = cat([CLab("_start"),
    CI([IMov(rax, rsp), ILd(rcx, rax, 0), IStG("g_argc", rcx), ILea(rdx, rax, 8), IStG("g_argv", rdx),
      IMov(rdx, rcx), IShI(4, rdx, 3), IAlu(1, rdx, rax), IAluI(0, rdx, 16), IStG("g_envp", rdx)]),
    self_reloc(),
    CI(list_push(sys_mmap(heap_size), IMov(r14, rax))),
    CI(list_concat(sys_mmap(stack_size), [IAluI(0, rax, stack_size), IMov(rsp, rax)])),
    linux_sigaction(2, "sigact"), linux_sigaction(15, "sigact"), linux_sigaction(13, "sigign"),
    call_l("init"), call_main(mode), CI([IMovI(rax, 231), IMovI(rdi, 0), ISys])])
  let handler = cat([CLab("sighandler"), CI([IStG("sig_num", rdi), ILdG(rdx, "termios_ptr"), IAlu(133, rdx, rdx)]), jcc(cc_e, ".sigskip"),
    CI([IMovI(rax, 16), IMovI(rdi, 0), IMovI(rsi, 21506), ISys, IMovI(rax, 1), IMovI(rdi, 1), IAddr(rsi, "cursor_on"), IMovI(rdx, 6), ISys]),
    CLab(".sigskip"), CI([ILdG(rdi, "sig_num"), IAluI(0, rdi, 128), IMovI(rax, 231), ISys])])
  [start, handler]
end

fn linux_sigaction(sig: Int, act: String) -> Code
  CI([IMovI(rax, 13), IMovI(rdi, sig), IAddr(rsi, act), IMovI(rdx, 0), IMovI(r10, 8), ISys])
end

fn entry_code(t: Target, mode: Mode) -> List[Code]
  if eq(t.os, "linux") then start_linux(mode)
  elif eq(t.os, "windows") then start_windows(t, mode)
  else start_macos(t, mode)
  end
end

# symbols the entry code imports (besides the ones the runtime uses)
fn entry_imports(t: Target) -> List[String]
  if eq(t.os, "windows") then ["VirtualAlloc", "AddVectoredExceptionHandler", "SetConsoleCtrlHandler", "SetConsoleOutputCP", "ExitProcess", "GetStdHandle", "SetConsoleMode", "WriteFile"]
  elif eq(t.os, "macos") then ["mmap", "signal", "tcsetattr", "write", "_exit", "exit"]
  else []
  end
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

type Out = { text: List[Blob], data: List[Blob], imports: List[String] } end

fn gen_program(p: Program, embeds: Map[String], mode: Mode, t: Target) -> Out
  let cx = Cx { prog: p, mod: get_module(p, main_module), nargs: 0, fields: field_table(p), rec_ids: record_ids(p), embeds: embeds, target: t }
  let g0 = G { code: CNil, slot: 1, lab: 0, data: CLab("data_start"), funcs: [], wrappers: [], strs: map.empty(), imports: entry_imports(t) }
  let g1 = list_fold(p.order, g0, fn(acc, name) gen_fns(cx, acc, get_module(p, name)) end)
  let g2 = gen_init(cx, g1)
  let g3 = match mode
    case TestMode(path) -> gen_tests(cx, g2, path)
    case AppMode -> g2
  end
  let g4 = gen_runtime_data(gen_tables(gen_wrappers(cx, g3, []), p), t)
  let text = list_map(list_concat(g4.funcs, entry_code(t, mode)), fn(c) assemble(t, c) end)
  let data = assemble(t, g4.data)
  let rel = list_filter(data.fixups, fn(f) eq(f.kind, 2) end)
  let reloc = assemble(t, cat(list_concat([CLab("data_start_link"), CA64("data_start"), CLab("reloc_table"), CB(lebytes(list_len(rel), 8))],
    list_map(rel, fn(f) CB(lebytes(f.off, 8)) end))))
  Out { text: text, data: [data, reloc], imports: g4.imports }
end

fn start_windows(t: Target, mode: Mode) -> List[Code]
  let start = cat([CLab("_start"), self_reloc(),
    CI(craw(t, "VirtualAlloc", [0, heap_size, 8192, 4])),
    CI([IMov(r14, rax), IStG("heap_base", rax), IMovI(rcx, heap_size), IAlu(1, rcx, rax), IStG("heap_end", rcx),
      IMovI(rcx, 1), IAddr(rdx, "veh"), ICRaw("AddVectoredExceptionHandler"),
      IAddr(rcx, "ctrlhandler"), IMovI(rdx, 1), ICRaw("SetConsoleCtrlHandler")]),
    CI(craw(t, "SetConsoleOutputCP", [65001])),
    call_l("init"), call_main(mode), CI(craw(t, "ExitProcess", [0]))])
  # heap pages are reserved up front and committed on first touch (access violation inside the heap)
  let veh = cat([CLab("veh"), CI([IPush(rbx), ILd(rax, rcx, 0), ILd(rdx, rax, 0), IMovI(r8, 4294967295), IAlu(33, rdx, r8), IMovI(r8, 3221225477), IAlu(57, rdx, r8)]),
    jcc(cc_ne, ".veh_no"), CI([ILd(rdx, rax, 40), ILdG(r8, "heap_base"), IAlu(57, rdx, r8)]), jcc(cc_l, ".veh_no"),
    CI([ILdG(r8, "heap_end"), IAlu(57, rdx, r8)]), jcc(cc_ge, ".veh_no"),
    CI([IMov(rcx, rdx), IAluI(4, rcx, -4096), IAlu(41, r8, rcx), IMovI(rdx, 67108864), IAlu(57, r8, rdx)]), jcc(cc_ge, ".veh_size"),
    CI([IMov(rdx, r8)]), CLab(".veh_size"),
    CI([IMovI(r8, 4096), IMovI(r9, 4), ICRaw("VirtualAlloc"), IMovI(rax, -1), IPop(rbx)]), CB([195]),
    CLab(".veh_no"), CI([IMovI(rax, 0), IPop(rbx)]), CB([195])])
  # Ctrl+C: restore the console modes saved by term_raw, show the cursor, exit 130
  let ctrl = cat([CLab("ctrlhandler"), CI([ILdG(rdx, "termios_ptr"), IAlu(133, rdx, rdx)]), jcc(cc_e, ".ctrl_exit"),
    CI([IStG("ctrl_tmp", rdx), IMovI(rcx, -11), ICRaw("GetStdHandle"), IPush(rax), IAddr(rax, "cursor_on"), IPush(rax), IMovI(rax, 6), IPush(rax),
      IAddr(rax, "sig_num"), IPush(rax), IMovI(rax, 0), IPush(rax), ICCall("WriteFile", 5, true),
      IMovI(rcx, -10), ICRaw("GetStdHandle"), IMov(rcx, rax), ILdG(rdx, "ctrl_tmp"), ILd(rdx, rdx, 0), ICRaw("SetConsoleMode"),
      IMovI(rcx, -11), ICRaw("GetStdHandle"), IMov(rcx, rax), ILdG(rdx, "ctrl_tmp"), ILd(rdx, rdx, 4), ICRaw("SetConsoleMode")]),
    CLab(".ctrl_exit"), CI(craw(t, "ExitProcess", [130]))])
  [start, veh, ctrl]
end

fn start_macos(t: Target, mode: Mode) -> List[Code]
  []
end
