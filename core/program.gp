# Program model: modules, types, constructors; loading sources and libraries.

import map

type Module = { name: String, files: List[SrcFile], fns: Map[FnDecl], lets: Map[LetDecl], imports: Map[ImportDecl], tests: List[TestDecl] } end
type CtorInfo = { ty: String, name: String, arity: Int, id: Int } end
type Program = { modules: Map[Module], order: List[String], ctors: Map[CtorInfo], types: Map[TypeDecl], records: Map[TypeDecl], ctor_list: List[CtorInfo], record_list: List[TypeDecl] } end
type Source = { path: String, src: String } end
type ModSrc = { name: String, files: List[Source] } end
type Linked = { prog: Program, diags: List[Diag] } end
type Builtin = { name: String, arity: Int, effect: String } end

let main_module = "main"
let rt_module = "rt"
let prelude_module = "prelude"
let prelude_src = embed_file("rt/prelude.gp")
let rt_src = embed_file("rt/rt.gp")

let effect_names = ["io", "term", "time", "net", "fs", "proc"]

fn b(name: String, arity: Int, effect: String) -> Builtin
  Builtin { name: name, arity: arity, effect: effect }
end

let builtin_list = [
  b("add", 2, ""), b("sub", 2, ""), b("mul", 2, ""), b("div", 2, ""), b("mod", 2, ""),
  b("eq", 2, ""), b("ne", 2, ""), b("lt", 2, ""), b("le", 2, ""), b("gt", 2, ""), b("ge", 2, ""),
  b("not", 1, ""), b("and", 2, ""), b("or", 2, ""),
  b("bit_and", 2, ""), b("bit_or", 2, ""), b("bit_xor", 2, ""), b("bit_shl", 2, ""), b("bit_shr", 2, ""), b("target", 0, ""),
  b("show", 1, ""), b("str_cat", 2, ""), b("str_join", 2, ""), b("str_len", 1, ""), b("str_slice", 3, ""),
  b("str_find", 2, ""), b("str_split", 2, ""), b("str_trim", 1, ""), b("str_starts", 2, ""), b("str_ends", 2, ""),
  b("str_repeat", 2, ""), b("str_lower", 1, ""), b("str_to_int", 1, ""), b("str_byte", 2, ""), b("str_from_bytes", 1, ""),
  b("list_len", 1, ""), b("list_get", 2, ""), b("list_cons", 2, ""), b("list_push", 2, ""), b("list_concat", 2, ""),
  b("list_slice", 3, ""), b("list_reverse", 1, ""), b("list_range", 2, ""), b("list_contains", 2, ""),
  b("list_map", 2, ""), b("list_filter", 2, ""), b("list_fold", 3, ""), b("list_sort", 1, ""),
  b("panic", 1, ""), b("expect", 2, ""), b("expect_eq", 2, ""), b("embed_file", 1, ""),
  b("print", 1, "io"), b("println", 1, "io"), b("read_line", 0, "io"), b("args", 0, "io"), b("exit", 1, "io"), b("env_get", 1, "io"),
  b("term_raw", 0, "term"), b("term_restore", 0, "term"), b("term_key", 0, "term"),
  b("now_ms", 0, "time"), b("sleep_ms", 1, "time"),
  b("tcp_listen", 1, "net"), b("tcp_accept", 1, "net"), b("tcp_read", 3, "net"), b("tcp_write", 2, "net"), b("tcp_close", 1, "net"),
  b("read_file", 1, "fs"), b("write_file", 3, "fs"), b("list_dir", 1, "fs"),
  b("run_image", 2, "proc")
]

# intrinsics, usable only inside the runtime module (see core/rt/rt.gp)
let prim_list = [
  b("prim_tag", 1, ""), b("prim_len", 1, ""), b("prim_id", 1, ""), b("prim_slot", 2, ""), b("prim_set_slot", 3, ""),
  b("prim_byte", 2, ""), b("prim_set_byte", 3, ""), b("prim_str_new", 1, ""), b("prim_list_new", 1, ""),
  b("prim_list_view", 3, ""), b("prim_record_copy", 1, ""), b("prim_addr", 1, ""), b("prim_peek", 1, ""),
  b("prim_syscall", 7, ""), b("prim_ctor_name", 1, ""), b("prim_record_name", 1, ""), b("prim_field_name", 2, ""),
  b("prim_argv", 0, ""), b("prim_handle", 1, ""), b("prim_term_save", 1, ""), b("prim_peek8", 1, ""), b("prim_copy", 5, "")
]

fn table(l: List[Builtin]) -> Map[Builtin]
  list_fold(l, map.empty(), fn(m, x) map.set(m, x.name, x) end)
end

let builtins = table(builtin_list)
let prims = table(prim_list)

# ---------- reading sources ----------

fn dirname(p: String) -> String
  let parts = str_split(p, "/")
  let n = list_len(parts)
  if le(n, 1) then "." else str_join(list_slice(parts, 0, sub(n, 1)), "/") end
end

fn path_join(a: String, b: String) -> String
  if eq(a, ".") then b else str_join([a, "/", b], "") end
end

fn read_sources(paths: List[String], acc: List[Source]) -> Result[List[Source], String] ! [fs]
  match paths
    case [] -> Ok(acc)
    case [p, ..rest] ->
      match read_file(p)
        case Ok(s) -> read_sources(rest, list_push(acc, Source { path: p, src: s }))
        case Err(e) -> Err(str_join([p, ": ", e], ""))
      end
  end
end

# a .gp file, or every .gp file of a directory
fn gp_files(path: String) -> Result[List[Source], String] ! [fs]
  if str_ends(path, ".gp") then
    read_sources([path], [])
  else
    match list_dir(path)
      case Err(e) -> Err(str_join([path, ": ", e], ""))
      case Ok(names) ->
        let gps = list_sort(list_filter(names, fn(n) str_ends(n, ".gp") end))
        if eq(list_len(gps), 0) then Err(str_cat(path, ": no .gp files")) else read_sources(list_map(gps, fn(n) path_join(path, n) end), []) end
    end
  end
end

fn up_dirs(d: String, n: Int, acc: List[String]) -> List[String]
  if eq(n, 0) then acc
  elif eq(d, ".") then up_dirs("..", sub(n, 1), list_push(acc, "."))
  elif or(eq(d, ".."), str_ends(d, "/..")) then up_dirs(str_cat(d, "/.."), sub(n, 1), list_push(acc, d))
  else up_dirs(dirname(d), sub(n, 1), list_push(acc, d))
  end
end

fn exists_dir(d: String) -> Bool ! [fs]
  is_ok(list_dir(d))
end

# $KAIZO_PATH entries, then every `libs/` folder from the app's folder upward
fn lib_dirs(root: String) -> List[String] ! [io, fs]
  let from_env = match env_get("KAIZO_PATH")
    case Some(v) -> list_filter(str_split(v, ":"), fn(x) ne(x, "") end)
    case None -> []
  end
  let start = if str_ends(root, ".gp") then dirname(root) else root end
  let ups = list_map(up_dirs(start, 12, []), fn(d) path_join(d, "libs") end)
  list_concat(from_env, filter_dirs(ups, []))
end

fn filter_dirs(ds: List[String], acc: List[String]) -> List[String] ! [fs]
  match ds
    case [] -> acc
    case [d, ..rest] -> filter_dirs(rest, if exists_dir(d) then list_push(acc, d) else acc end)
  end
end

type Collected = { mods: List[ModSrc], diags: List[Diag] } end

fn find_lib(dirs: List[String], name: String) -> Option[List[Source]] ! [fs]
  match dirs
    case [] -> None
    case [d, ..rest] ->
      match gp_files(path_join(d, name))
        case Ok(fs) -> Some(fs)
        case Err(_) -> find_lib(rest, name)
      end
  end
end

fn has_mod(mods: List[ModSrc], name: String) -> Bool
  list_contains(list_map(mods, fn(m) m.name end), name)
end

fn imports_of(files: List[Source]) -> List[ImportDecl]
  list_fold(files, [], fn(acc, s)
    match parse_file(s.path, s.src)
      case Ok(f) -> list_concat(acc, f.imports)
      case Err(_) -> acc
    end
  end)
end

fn collect_loop(queue: List[ModSrc], c: Collected, dirs: List[String]) -> Collected ! [fs]
  match queue
    case [] -> c
    case [m, ..rest] -> collect_imports(imports_of(m.files), rest, c, dirs)
  end
end

fn collect_imports(imps: List[ImportDecl], queue: List[ModSrc], c: Collected, dirs: List[String]) -> Collected ! [fs]
  match imps
    case [] -> collect_loop(queue, c, dirs)
    case [imp, ..rest] ->
      if has_mod(c.mods, imp.name) then
        collect_imports(rest, queue, c, dirs)
      else
        match find_lib(dirs, imp.name)
          case Some(files) ->
            let m = ModSrc { name: imp.name, files: files }
            collect_imports(rest, list_push(queue, m), { c with mods: list_push(c.mods, m) }, dirs)
          case None ->
            let d = Diag { pos: imp.pos, msg: str_join(["library ", imp.name, " not found"], ""), hint: str_join(["searched: ", str_join(dirs, ", "), " (set KAIZO_PATH to add more)"], "") }
            collect_imports(rest, queue, { c with diags: list_push(c.diags, d) }, dirs)
        end
      end
  end
end

# reads the app at root and every library it imports (transitively)
fn collect(root: String) -> Result[Collected, String] ! [io, fs]
  match gp_files(root)
    case Err(e) -> Err(e)
    case Ok(files) ->
      let main = ModSrc { name: main_module, files: files }
      let rt = ModSrc { name: rt_module, files: [Source { path: "<rt>", src: rt_src }] }
      Ok(collect_loop([main, rt], Collected { mods: [main, rt], diags: [] }, lib_dirs(root)))
  end
end

# ---------- linking ----------

type LinkSt = { prog: Program, diags: List[Diag] } end

fn add_diag(l: LinkSt, pos: Pos, msg: String, hint: String) -> LinkSt
  { l with diags: list_push(l.diags, Diag { pos: pos, msg: msg, hint: hint }) }
end

fn builtin_type(name: String) -> TypeDecl
  TypeDecl { pos: Pos { file: "", line: 0, col: 0 }, name: name, tparams: [], is_record: false, ctors: [], fields: [] }
end

fn defined_in(m: Module, n: String) -> Bool
  or(or(map.has(m.fns, n), map.has(m.lets, n)), map.has(m.imports, n))
end

fn def_check(l: LinkSt, m: Module, n: String, pos: Pos) -> LinkSt
  if defined_in(m, n) then
    add_diag(l, pos, str_cat(n, " is already defined"), "")
  elif and(map.has(builtins, n), ne(m.name, rt_module)) then
    add_diag(l, pos, str_cat(n, " is a builtin and cannot be redefined"), "choose another name")
  elif and(ne(m.name, prelude_module), ne(m.name, rt_module)) then
    match map.get(l.prog.modules, prelude_module)
      case Some(pm) -> if defined_in(pm, n) then add_diag(l, pos, str_cat(n, " is defined in the prelude and cannot be redefined"), "") else l end
      case None -> l
    end
  else
    l
  end
end

type ModLink = { l: LinkSt, m: Module } end

fn link_types(l: LinkSt, tds: List[TypeDecl]) -> LinkSt
  list_fold(tds, l, fn(acc, td)
    if map.has(acc.prog.types, td.name) then
      add_diag(acc, td.pos, str_join(["type ", td.name, " is already defined"], ""), "type and constructor names are global across all modules")
    else
      let p0 = acc.prog
      let p1 = { p0 with types: map.set(p0.types, td.name, td) }
      let p2 = if td.is_record then { p1 with records: map.set(p1.records, td.name, td), record_list: list_push(p1.record_list, td) } else p1 end
      list_fold(td.ctors, { acc with prog: p2 }, fn(a2, cd)
        match map.get(a2.prog.ctors, cd.name)
          case Some(prev) -> add_diag(a2, cd.pos, str_join(["constructor ", cd.name, " is already defined in type ", prev.ty], ""), "type and constructor names are global across all modules")
          case None ->
            let info = CtorInfo { ty: td.name, name: cd.name, arity: list_len(cd.args), id: list_len(a2.prog.ctor_list) }
            let pr = a2.prog
            { a2 with prog: { pr with ctors: map.set(pr.ctors, cd.name, info), ctor_list: list_push(pr.ctor_list, info) } }
        end
      end)
    end
  end)
end

fn link_file(ml: ModLink, src: Source) -> ModLink
  match parse_file(src.path, src.src)
    case Err(d) -> { ml with l: { ml.l with diags: list_push(ml.l.diags, d) } }
    case Ok(f) ->
      let m0 = ml.m
      let s1 = list_fold(f.imports, ml, fn(a, imp)
        if map.has(a.m.imports, imp.name) then a else
          let l2 = def_check(a.l, a.m, imp.name, imp.pos)
          let am = a.m
          ModLink { l: l2, m: { am with imports: map.set(am.imports, imp.name, imp) } }
        end
      end)
      let s2 = list_fold(f.fns, s1, fn(a, fd)
        let l2 = def_check(a.l, a.m, fd.name, fd.pos)
        let am = a.m
        ModLink { l: l2, m: { am with fns: map.set(am.fns, fd.name, fd) } }
      end)
      let s3 = list_fold(f.lets, s2, fn(a, ld)
        let l2 = def_check(a.l, a.m, ld.name, ld.pos)
        let am = a.m
        ModLink { l: l2, m: { am with lets: map.set(am.lets, ld.name, ld) } }
      end)
      let m3 = s3.m
      ModLink { l: link_types(s3.l, f.types), m: { m3 with files: list_push(m3.files, f), tests: list_concat(m3.tests, f.tests) } }
  end
end

fn link_module(l: LinkSt, ms: ModSrc) -> LinkSt
  let m = Module { name: ms.name, files: [], fns: map.empty(), lets: map.empty(), imports: map.empty(), tests: [] }
  let r = list_fold(ms.files, ModLink { l: l, m: m }, link_file)
  let p = r.l.prog
  { r.l with prog: { p with modules: map.set(p.modules, ms.name, r.m) } }
end

fn visit_order(p: Program, n: String, seen: List[String]) -> List[String]
  if list_contains(seen, n) then seen else
    match map.get(p.modules, n)
      case None -> seen
      case Some(m) -> list_push(list_fold(map.keys(m.imports), list_push(seen, n), fn(acc, d) visit_order(p, d, acc) end), n)
    end
  end
end

# dependency order: every module after the modules it imports (a module appears once)
fn dep_order(p: Program) -> List[String]
  let raw = visit_order(p, main_module, visit_order(p, rt_module, visit_order(p, prelude_module, [])))
  dedup_last(raw, [])
end

# visit_order pushes a name when entered and when finished; keep the finished (second) one
fn dedup_last(l: List[String], acc: List[String]) -> List[String]
  match l
    case [] -> acc
    case [x, ..rest] -> if list_contains(rest, x) then dedup_last(rest, acc) else dedup_last(rest, list_push(acc, x)) end
  end
end

fn link(mods: List[ModSrc]) -> Linked
  let p0 = Program { modules: map.empty(), order: [], ctors: map.empty(), types: map.empty(), records: map.empty(), ctor_list: [], record_list: [] }
  let base = list_fold(["Int", "String", "Bool", "List", "Fn", "Unit", "Listener", "Conn"], p0, fn(p, t) { p with types: map.set(p.types, t, builtin_type(t)) } end)
  let unit_td = { builtin_type("Unit") with ctors: [CtorDecl { pos: Pos { file: "", line: 0, col: 0 }, name: "Unit", args: [] }] }
  let unit_info = CtorInfo { ty: "Unit", name: "Unit", arity: 0, id: 0 }
  let p1 = { base with types: map.set(base.types, "Unit", unit_td), ctors: map.set(base.ctors, "Unit", unit_info), ctor_list: [unit_info] }
  let l0 = link_module(LinkSt { prog: p1, diags: [] }, ModSrc { name: prelude_module, files: [Source { path: "<prelude>", src: prelude_src }] })
  let l1 = list_fold(mods, l0, link_module)
  let p = l1.prog
  Linked { prog: { p with order: dep_order(p) }, diags: l1.diags }
end
