# kaizo — the GPLM core: checker and native x86-64 compiler, written in GPLM.

let version = "1.1.0-dev"
let host_target = target()

let usage = "kaizo 1.0.0-dev - GPLM core (native, self-hosted)\n\nusage:\n  kaizo run   <file.gp|dir> [args...]   check, compile, run fn main\n  kaizo check <file.gp|dir> [--json]    static checks only\n  kaizo test  <file.gp|dir>             compile and run test blocks\n  kaizo build <file.gp|dir> -o <out>    native executable\n\noptions:\n  --target linux-x64|windows-x64|macos-x64|macos-arm64   (default: the host)\n  kaizo version\n"

fn json_str(s: String) -> String
  let b = str_from_bytes([92])
  let q = str_from_bytes([34])
  let e1 = str_join(str_split(s, b), str_cat(b, b))
  let e2 = str_join(str_split(e1, q), str_cat(b, q))
  let e3 = str_join(str_split(e2, "\n"), str_cat(b, "n"))
  let e4 = str_join(str_split(e3, "\t"), str_cat(b, "t"))
  str_join([q, str_join(str_split(e4, "\r"), str_cat(b, "r")), q], "")
end

fn diag_json(d: Diag) -> String
  let base = ["{\"file\": ", json_str(d.pos.file), ", \"line\": ", show(d.pos.line), ", \"col\": ", show(d.pos.col), ", \"message\": ", json_str(d.msg)]
  let hint = if eq(d.hint, "") then [] else [", \"hint\": ", json_str(d.hint)] end
  str_join(list_concat(list_concat(base, hint), ["}"]), "")
end

fn print_diags(ds: List[Diag], json: Bool) -> Unit ! [io]
  if json then
    println(str_join(["[", str_join(list_map(ds, diag_json), ",\n "), "]"], ""))
  else
    println(str_cat(str_join(list_map(ds, diag_str), "\n"), str_join(["\n", show(list_len(ds)), " error(s)"], "")))
  end
end

# collect + link + check; prints diagnostics on failure
fn load(path: String, json: Bool, t: Target) -> Option[Program] ! [io, fs]
  match collect(path, t)
    case Err(e) ->
      println(str_cat("error: ", e))
      None
    case Ok(c) ->
      let l = if eq(list_len(c.diags), 0) then link(c.mods) else Linked { prog: link([]).prog, diags: c.diags } end
      let ds = if eq(list_len(l.diags), 0) then check_program(l.prog) else l.diags end
      if eq(list_len(ds), 0) then Some(l.prog) else
        print_diags(ds, json)
        None
      end
  end
end

fn flag_value(args: List[String], flag: String) -> Option[String]
  match args
    case [f, v, ..rest] -> if eq(f, flag) then Some(v) else flag_value(list_cons(v, rest), flag) end
    case _ -> None
  end
end

fn positional(args: List[String]) -> List[String]
  match args
    case [] -> []
    case ["-o", _, ..rest] -> positional(rest)
    case ["--target", _, ..rest] -> positional(rest)
    case [a, ..rest] -> if str_starts(a, "--") then positional(rest) else list_cons(a, positional(rest)) end
  end
end

fn host() -> Target
  unwrap_or(find_target(host_target), Target { name: "linux-x64", os: "linux", arch: "x64" })
end

# --target NAME, or the host; an unknown name is reported and kaizo exits
fn target_arg(args: List[String]) -> Target
  match flag_value(args, "--target")
    case None -> host()
    case Some(name) -> unwrap_or(find_target(name), host())
  end
end

fn write_image(t: Target, o: Out) -> Image
  if eq(t.os, "windows") then write_pe(o)
  elif eq(t.os, "macos") then write_macho(t, o)
  else write_elf(o)
  end
end

fn cmd_check(rest: List[String]) -> Unit ! [io, fs]
  let json = list_contains(rest, "--json")
  match positional(rest)
    case [path] ->
      match load(path, json, target_arg(rest))
        case Some(_) -> println(if json then "[]" else "ok" end)
        case None -> exit(1)
      end
    case _ -> fail_usage()
  end
end

fn fail_usage() -> Unit ! [io]
  print(usage)
  exit(2)
end

# ---------- compile-time embed_file ----------

fn embeds_block(stmts: List[Stmt], file: String, acc: List[String]) -> List[String]
  list_fold(stmts, acc, fn(a, st) embeds_expr(st.x, file, a) end)
end

fn embeds_expr(e: Expr, file: String, acc: List[String]) -> List[String]
  match e
    case ECall(_, EVar(_, "embed_file"), [EStr(_, p)]) -> list_push(acc, path_join(dirname(file), p))
    case ECall(_, f, args) -> list_fold(args, embeds_expr(f, file, acc), fn(a, x) embeds_expr(x, file, a) end)
    case EField(_, x, _) -> embeds_expr(x, file, acc)
    case EList(_, items) -> list_fold(items, acc, fn(a, x) embeds_expr(x, file, a) end)
    case ERec(_, _, fs) -> list_fold(fs, acc, fn(a, f) embeds_expr(f.x, file, a) end)
    case EUpd(_, x, fs) -> list_fold(fs, embeds_expr(x, file, acc), fn(a, f) embeds_expr(f.x, file, a) end)
    case EIf(_, cs, bs, el) -> embeds_block(el, file, list_fold(bs, list_fold(cs, acc, fn(a, x) embeds_expr(x, file, a) end), fn(a, b) embeds_block(b, file, a) end))
    case EMatch(_, x, arms) -> list_fold(arms, embeds_expr(x, file, acc), fn(a, arm) embeds_block(arm.body, file, a) end)
    case ELam(_, _, body) -> embeds_block(body, file, acc)
    case _ -> acc
  end
end

fn embed_paths(p: Program) -> List[String]
  list_fold(p.order, [], fn(acc, name)
    list_fold(get_module(p, name).files, acc, fn(a, f)
      let a1 = list_fold(f.fns, a, fn(a2, fd) embeds_block(fd.body, f.path, a2) end)
      let a2 = list_fold(f.lets, a1, fn(a3, ld) embeds_expr(ld.x, f.path, a3) end)
      list_fold(f.tests, a2, fn(a3, t) embeds_block(t.body, f.path, a3) end)
    end)
  end)
end

fn read_embeds(paths: List[String], m: Map[String]) -> Result[Map[String], String] ! [fs]
  match paths
    case [] -> Ok(m)
    case [p, ..rest] ->
      match read_file(p)
        case Ok(s) -> read_embeds(rest, map.set(m, p, s))
        case Err(e) -> Err(str_cat("embed_file: ", e))
      end
  end
end

# check + generate; None after printing errors
fn compile(path: String, mode: Mode, t: Target) -> Option[String] ! [io, fs]
  match load(path, false, t)
    case None -> None
    case Some(prog) ->
      match read_embeds(embed_paths(prog), map.empty())
        case Err(e) ->
          println(str_cat("error: ", e))
          None
        case Ok(embeds) ->
          let img = write_image(t, gen_program(prog, embeds, mode, t))
          if gt(list_len(img.missing), 0) then
            println(str_cat("internal error: unresolved symbols: ", str_join(list_slice(img.missing, 0, 10), ", ")))
            None
          else Some(img.bytes) end
      end
  end
end

fn cmd_build(rest: List[String]) -> Unit ! [io, fs]
  match positional(rest)
    case [path] ->
      match flag_value(rest, "-o")
        case None -> fail_usage()
        case Some(out) ->
          match compile(path, AppMode, target_arg(rest))
            case None -> exit(1)
            case Some(bin) ->
              match write_file(out, bin, 493)
                case Ok(_) -> println(str_join(["built ", out, " (", show(str_len(bin)), " bytes)"], ""))
                case Err(e) ->
                  println(str_cat("error: ", e))
                  exit(1)
              end
          end
      end
    case _ -> fail_usage()
  end
end

fn cmd_run(rest: List[String]) -> Unit ! [io, fs, proc]
  match rest
    case [path, ..app_args] ->
      match compile(path, AppMode, host())
        case None -> exit(1)
        case Some(bin) ->
          match run_image(bin, app_args)
            case Ok(_) -> Unit
            case Err(e) ->
              println(str_cat("error: ", e))
              exit(1)
          end
      end
    case [] -> fail_usage()
  end
end

fn cmd_test(rest: List[String]) -> Unit ! [io, fs, proc]
  match positional(rest)
    case [path] ->
      match compile(path, TestMode(path), host())
        case None -> exit(1)
        case Some(bin) ->
          match run_image(bin, [])
            case Ok(_) -> Unit
            case Err(e) ->
              println(str_cat("error: ", e))
              exit(1)
          end
      end
    case _ -> fail_usage()
  end
end

fn main() -> Unit ! [io, fs, proc]
  match args()
    case ["check", ..rest] -> cmd_check(rest)
    case ["build", ..rest] -> cmd_build(rest)
    case ["run", ..rest] -> cmd_run(rest)
    case ["test", ..rest] -> cmd_test(rest)
    case ["version", .._] -> println(version)
    case _ -> fail_usage()
  end
end
