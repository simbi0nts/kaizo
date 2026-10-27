# kaizo — the GPLM core: checker and native x86-64 compiler, written in GPLM.

let version = "1.0.0-dev"

let usage = "kaizo 1.0.0-dev - GPLM core (native, self-hosted)\n\nusage:\n  kaizo run   <file.gp|dir> [args...]   check, compile, run fn main\n  kaizo check <file.gp|dir> [--json]    static checks only\n  kaizo test  <file.gp|dir>             compile and run test blocks\n  kaizo build <file.gp|dir> -o <out>    native executable\n  kaizo version\n"

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
fn load(path: String, json: Bool) -> Option[Program] ! [io, fs]
  match collect(path)
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
    case [a, ..rest] -> if str_starts(a, "--") then positional(rest) else list_cons(a, positional(rest)) end
  end
end

fn cmd_check(rest: List[String]) -> Unit ! [io, fs]
  let json = list_contains(rest, "--json")
  match positional(rest)
    case [path] ->
      match load(path, json)
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

fn main() -> Unit ! [io, fs, proc]
  match args()
    case ["check", ..rest] -> cmd_check(rest)
    case ["version", .._] -> println(version)
    case _ -> fail_usage()
  end
end
