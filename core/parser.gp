# Parser: tokens -> SrcFile. State is threaded through every call. On the first error the
# state records it and drops the remaining tokens, so every loop sees EOF and unwinds.

type PS = { ts: Toks, eof: Tok, err: Option[Diag] } end
type Got[T] = { v: T, st: PS } end

# ---------- token helpers ----------

fn peek(st: PS) -> Tok
  match st.ts
    case TCons(t, _) -> t
    case TNil -> st.eof
  end
end

fn peek_at(ts: Toks, n: Int, eof: Tok) -> Tok
  match ts
    case TCons(t, rest) -> if eq(n, 0) then t else peek_at(rest, sub(n, 1), eof) end
    case TNil -> eof
  end
end

fn adv(st: PS) -> PS
  match st.ts
    case TCons(_, rest) -> { st with ts: rest }
    case TNil -> st
  end
end

fn at_eof(st: PS) -> Bool
  eq(peek(st).kind, TkEof)
end

fn tok_is(t: Tok, s: String) -> Bool
  and(or(eq(t.kind, TkPunct), eq(t.kind, TkKw)), eq(t.text, s))
end

fn is_p(st: PS, s: String) -> Bool
  tok_is(peek(st), s)
end

fn fail_at(st: PS, pos: Pos, msg: String, hint: String) -> PS
  match st.err
    case Some(_) -> { st with ts: TNil }
    case None -> { st with ts: TNil, err: Some(Diag { pos: pos, msg: msg, hint: hint }), eof: { st.eof with pos: pos } }
  end
end

fn fail(st: PS, msg: String, hint: String) -> PS
  fail_at(st, peek(st).pos, msg, hint)
end

fn desc(t: Tok) -> String
  match t.kind
    case TkEof -> "end of file"
    case TkStr -> str_join(["string \"", t.text, "\""], "")
    case _ -> str_join(["\"", t.text, "\""], "")
  end
end

# hint for a token that is a likely slip at this place
fn op_hint(t: Tok) -> String
  if eq(t.text, "=") then "to compare use ==; a single = only appears in let and type" else "" end
end

fn need(st: PS, s: String, ctx: String) -> PS
  if is_p(st, s) then
    adv(st)
  else
    let hint = if eq(s, "end") then "every fn, type, test, if, match and lambda is closed by its own `end`" else op_hint(peek(st)) end
    fail(st, str_join(["expected \"", s, "\" ", ctx, ", found ", desc(peek(st))], ""), hint)
  end
end

fn take_kind(st: PS, kind: TokKind, what: String, ctx: String) -> Got[Tok]
  let t = peek(st)
  if eq(t.kind, kind) then
    Got { v: t, st: adv(st) }
  else
    let hint = if and(eq(kind, TkIdent), eq(t.kind, TkUpper)) then str_cat("values, functions and constants are lower_snake: write ", str_lower(t.text), ", not ", t.text) else op_hint(t) end
    Got { v: t, st: fail(st, str_join(["expected ", what, " ", ctx, ", found ", desc(t)], ""), hint) }
  end
end

fn p_ident(st: PS, ctx: String) -> Got[Tok]
  take_kind(st, TkIdent, "a lowercase name", ctx)
end

fn p_upper(st: PS, ctx: String) -> Got[Tok]
  take_kind(st, TkUpper, "a capitalized name", ctx)
end

# ---------- top level ----------

fn parse_file(path: String, src: String) -> Result[SrcFile, Diag]
  let lx = lex(path, src)
  match lx.err
    case Some(d) -> Err(d)
    case None ->
      let empty = SrcFile { path: path, imports: [], types: [], fns: [], tests: [], lets: [] }
      let r = p_top(PS { ts: lx.toks, eof: lx.eof, err: None }, empty)
      match r.st.err
        case Some(d) -> Err(d)
        case None -> Ok(r.v)
      end
  end
end

fn p_top(st: PS, f: SrcFile) -> Got[SrcFile]
  let t = peek(st)
  if at_eof(st) then
    Got { v: f, st: st }
  elif tok_is(t, "import") then
    let n = p_ident(adv(st), "after import")
    p_top(n.st, { f with imports: list_push(f.imports, ImportDecl { pos: t.pos, name: n.v.text }) })
  elif tok_is(t, "type") then
    let r = p_type_decl(st)
    p_top(r.st, { f with types: list_push(f.types, r.v) })
  elif tok_is(t, "fn") then
    let r = p_fn_decl(st)
    p_top(r.st, { f with fns: list_push(f.fns, r.v) })
  elif tok_is(t, "test") then
    let st1 = adv(st)
    let name = peek(st1)
    if ne(name.kind, TkStr) then
      Got { v: f, st: fail(st1, "expected test name string after test", "test \"name\" ... end") }
    else
      let b = p_block(adv(st1))
      let st2 = need(b.st, "end", "to close test")
      p_top(st2, { f with tests: list_push(f.tests, TestDecl { pos: t.pos, name: name.text, body: b.v }) })
    end
  elif tok_is(t, "let") then
    let n = p_ident(adv(st), "after let")
    let x = p_expr(need(n.st, "=", "in let"))
    p_top(x.st, { f with lets: list_push(f.lets, LetDecl { pos: t.pos, name: n.v.text, x: x.v }) })
  else
    Got { v: f, st: fail(st, str_cat("expected a top-level declaration (import, type, fn, test, let), found ", desc(t)), "") }
  end
end

fn p_comma_uppers(st: PS, acc: List[String]) -> Got[List[String]]
  let u = p_upper(st, "as type parameter")
  let acc2 = list_push(acc, u.v.text)
  if is_p(u.st, ",") then p_comma_uppers(adv(u.st), acc2) else Got { v: acc2, st: u.st } end
end

fn p_type_decl(st0: PS) -> Got[TypeDecl]
  let pos = peek(st0).pos
  let name = p_upper(adv(st0), "after type")
  let tps = if is_p(name.st, "[") then
    let r = p_comma_uppers(adv(name.st), [])
    Got { v: r.v, st: need(r.st, "]", "to close type parameters") }
  else
    Got { v: [], st: name.st }
  end
  let st1 = need(tps.st, "=", "in type declaration")
  let td = TypeDecl { pos: pos, name: name.v.text, tparams: tps.v, is_record: false, ctors: [], fields: [] }
  if is_p(st1, "{") then
    let fs = p_field_decls(adv(st1), [])
    let st2 = need(need(fs.st, "}", "to close record fields"), "end", str_cat("to close type ", td.name))
    Got { v: { td with is_record: true, fields: fs.v }, st: st2 }
  else
    let cs = p_ctor_decls(st1, [])
    Got { v: { td with ctors: cs.v }, st: need(cs.st, "end", str_cat("to close type ", td.name)) }
  end
end

fn p_field_decls(st: PS, acc: List[FieldDecl]) -> Got[List[FieldDecl]]
  if or(is_p(st, "}"), at_eof(st)) then
    Got { v: acc, st: st }
  else
    let n = p_ident(st, "as field name")
    let t = p_type(need(n.st, ":", "after field name"))
    let acc2 = list_push(acc, FieldDecl { name: n.v.text, ty: t.v })
    if is_p(t.st, ",") then p_field_decls(adv(t.st), acc2) else Got { v: acc2, st: t.st } end
  end
end

fn p_ctor_decls(st: PS, acc: List[CtorDecl]) -> Got[List[CtorDecl]]
  let n = p_upper(st, "as constructor name")
  let args = if is_p(n.st, "(") then
    let r = p_types(adv(n.st), [])
    Got { v: r.v, st: need(r.st, ")", "to close constructor arguments") }
  else
    Got { v: [], st: n.st }
  end
  let acc2 = list_push(acc, CtorDecl { pos: n.v.pos, name: n.v.text, args: args.v })
  if is_p(args.st, "|") then p_ctor_decls(adv(args.st), acc2) else Got { v: acc2, st: args.st } end
end

fn p_types(st: PS, acc: List[TypeX]) -> Got[List[TypeX]]
  let t = p_type(st)
  let acc2 = list_push(acc, t.v)
  if is_p(t.st, ",") then p_types(adv(t.st), acc2) else Got { v: acc2, st: t.st } end
end

fn p_type(st: PS) -> Got[TypeX]
  let n = p_upper(st, "as type")
  if and(eq(n.v.text, "Fn"), is_p(n.st, "(")) then
    let ps = if is_p(adv(n.st), ")") then Got { v: [], st: adv(n.st) } else p_types(adv(n.st), []) end
    let st2 = need(need(ps.st, ")", "to close Fn parameter types"), "->", "in Fn type")
    let ret = p_type(st2)
    let effs = p_effects(ret.st)
    Got { v: TypeX { name: "Fn", args: list_push(ps.v, ret.v), effects: effs.v }, st: effs.st }
  elif is_p(n.st, "[") then
    let args = p_types(adv(n.st), [])
    Got { v: TypeX { name: n.v.text, args: args.v, effects: [] }, st: need(args.st, "]", "to close type arguments") }
  else
    Got { v: TypeX { name: n.v.text, args: [], effects: [] }, st: n.st }
  end
end

fn p_params(st: PS, require_types: Bool, acc: List[Param]) -> Got[List[Param]]
  if or(is_p(st, ")"), at_eof(st)) then
    Got { v: acc, st: need(st, ")", "to close parameters") }
  else
    let n = p_ident(st, "as parameter name")
    let ty = if is_p(n.st, ":") then
      let t = p_type(adv(n.st))
      Got { v: Some(t.v), st: t.st }
    elif require_types then
      Got { v: None, st: fail_at(n.st, n.v.pos, str_join(["parameter ", n.v.text, " of a top-level fn needs a type"], ""), str_join(["write ", n.v.text, ": Type"], "")) }
    else
      Got { v: None, st: n.st }
    end
    let acc2 = list_push(acc, Param { name: n.v.text, ty: ty.v })
    if is_p(ty.st, ",") then p_params(adv(ty.st), require_types, acc2) else Got { v: acc2, st: need(ty.st, ")", "to close parameters") } end
  end
end

fn p_effect_names(st: PS, acc: List[String]) -> Got[List[String]]
  if or(is_p(st, "]"), at_eof(st)) then
    Got { v: acc, st: st }
  else
    let n = p_ident(st, "as effect name")
    let acc2 = list_push(acc, n.v.text)
    if is_p(n.st, ",") then p_effect_names(adv(n.st), acc2) else Got { v: acc2, st: n.st } end
  end
end

fn p_effects(st: PS) -> Got[List[String]]
  if is_p(st, "!") then
    let r = p_effect_names(need(adv(st), "[", "after ! (effect list)"), [])
    Got { v: r.v, st: need(r.st, "]", "to close effect list") }
  else
    Got { v: [], st: st }
  end
end

fn p_fn_decl(st0: PS) -> Got[FnDecl]
  let pos = peek(st0).pos
  let name = p_ident(adv(st0), "after fn")
  let ps = p_params(need(name.st, "(", "to open parameters"), true, [])
  let ret = p_type(need(ps.st, "->", "(a top-level fn must declare its return type)"))
  let effs = p_effects(ret.st)
  let body = p_block(effs.st)
  let st = need(body.st, "end", str_cat("to close fn ", name.v.text))
  Got { v: FnDecl { pos: pos, name: name.v.text, params: ps.v, ret: ret.v, effects: effs.v, body: body.v }, st: st }
end

# ---------- blocks and expressions ----------

fn block_end(st: PS) -> Bool
  or(or(is_p(st, "end"), is_p(st, "case")), or(or(is_p(st, "elif"), is_p(st, "else")), at_eof(st)))
end

fn p_block(st: PS) -> Got[List[Stmt]]
  let r = p_stmts(st, [])
  match list_get(r.v, sub(list_len(r.v), 1))
    case None -> Got { v: [], st: fail(r.st, str_cat("empty block: a block needs at least one expression, found ", desc(peek(r.st))), "write Unit for a block that returns nothing") }
    case Some(last) ->
      if ne(last.let_name, "") then
        Got { v: r.v, st: fail_at(r.st, last.pos, "block ends with a let; the last statement must be the value of the block", "add the expression to return after the let") }
      else
        r
      end
  end
end

fn p_stmts(st: PS, acc: List[Stmt]) -> Got[List[Stmt]]
  if block_end(st) then
    Got { v: acc, st: st }
  elif is_p(st, "let") then
    let pos = peek(st).pos
    let n = p_ident(adv(st), "after let")
    let st2 = need(n.st, "=", "in let")
    if is_p(st2, "try") then
      p_try(adv(st2), peek(st2).pos, PVar(n.v.pos, n.v.text), acc)
    else
      let x = p_expr(st2)
      p_stmts(x.st, list_push(acc, Stmt { pos: pos, let_name: n.v.text, x: x.v }))
    end
  elif is_p(st, "try") then
    p_try(adv(st), peek(st).pos, PWild(peek(st).pos), acc)
  elif or(is_p(st, ")"), is_p(st, ","), is_p(st, "]"), is_p(st, "}")) then
    # a block (if/match/fn body) ran into the closer of an enclosing call or list: its `end` is missing
    Got { v: acc, st: fail(st, str_cat("expected end to close the block, found ", desc(peek(st))), "if/match/lambda blocks end with `end`, also inside a call: exit(if c then 1 else 0 end)") }
  else
    let x = p_expr(st)
    p_stmts(x.st, list_push(acc, Stmt { pos: expr_pos(x.v), let_name: "", x: x.v }))
  end
end

# `let x = try e` + rest  ->  match e case Ok(x) -> rest case Err(err) -> Err(err) end
# `let x = try e else alt` + rest  ->  match e case Some(x) -> rest case None -> alt end
# The rest of the block becomes the success arm, so `try` ends the enclosing block early.
fn p_try(st: PS, pos: Pos, bind: Pat, acc: List[Stmt]) -> Got[List[Stmt]]
  let x = p_expr(st)
  let alt = if is_p(x.st, "else") then Some(p_expr(adv(x.st))) else None end
  let st2 = match alt
    case Some(a) -> a.st
    case None -> x.st
  end
  let rest = p_stmts(st2, [])
  # rc.gp keys arms and statements by source position: each generated node needs its own
  let xp = expr_pos(x.v)
  let arms = match alt
    case Some(a) -> [Arm { pat: PCtor(pos, "Some", [bind]), body: rest.v }, Arm { pat: PCtor(xp, "None", []), body: [Stmt { pos: expr_pos(a.v), let_name: "", x: a.v }] }]
    case None -> [Arm { pat: PCtor(pos, "Ok", [bind]), body: rest.v }, Arm { pat: PCtor(xp, "Err", [PVar(xp, "try_err")]), body: [Stmt { pos: xp, let_name: "", x: ECall(xp, ECtor(xp, "Err"), [EVar(xp, "try_err")]) }] }]
  end
  let out = Got { v: list_push(acc, Stmt { pos: pos, let_name: "", x: EMatch(pos, x.v, arms) }), st: rest.st }
  match list_get(rest.v, sub(list_len(rest.v), 1))
    case None -> Got { v: out.v, st: fail_at(rest.st, pos, "try needs more statements after it: the rest of the block runs when it succeeds", "use match for the last value of a block") }
    case Some(last) ->
      if ne(last.let_name, "") then
        Got { v: out.v, st: fail_at(rest.st, last.pos, "block ends with a let; the last statement must be the value of the block", "add the expression to return after the let") }
      else
        out
      end
  end
end

# variadic forms of associative builtins: add(a, b, c) = add(a, add(b, c))
let variadic = ["add", "mul", "str_cat", "and", "or", "bit_and", "bit_or", "bit_xor"]

fn fold_call(pos: Pos, f: Expr, args: List[Expr]) -> Expr
  match args
    case [a, b] -> ECall(pos, f, [a, b])
    case [a, ..rest] -> ECall(pos, f, [a, fold_call(pos, f, rest)])
    case [] -> ECall(pos, f, [])
  end
end

fn make_call(pos: Pos, f: Expr, args: List[Expr]) -> Expr
  match f
    case EVar(_, n) -> if and(gt(list_len(args), 2), list_contains(variadic, n)) then fold_call(pos, f, args) else ECall(pos, f, args) end
    case _ -> ECall(pos, f, args)
  end
end

fn p_expr_list(st: PS, close: String, ctx: String, acc: List[Expr]) -> Got[List[Expr]]
  if or(is_p(st, close), at_eof(st)) then
    Got { v: acc, st: need(st, close, ctx) }
  else
    let e = p_expr(st)
    let acc2 = list_push(acc, e.v)
    if is_p(e.st, ",") then p_expr_list(adv(e.st), close, ctx, acc2) else Got { v: acc2, st: need(e.st, close, ctx) } end
  end
end

fn p_field_inits(st: PS, acc: List[FieldInit]) -> Got[List[FieldInit]]
  if or(is_p(st, "}"), at_eof(st)) then
    Got { v: acc, st: need(st, "}", "to close the record") }
  else
    let n = p_ident(st, "as field name")
    let x = p_expr(need(n.st, ":", "after field name"))
    let acc2 = list_push(acc, FieldInit { pos: n.v.pos, name: n.v.text, x: x.v })
    if is_p(x.st, ",") then p_field_inits(adv(x.st), acc2) else Got { v: acc2, st: need(x.st, "}", "to close the record") } end
  end
end

# Infix operators are sugar for the builtins: a + b == add(a, b). Precedence, low to high:
# || · && · == != < <= > >= · + - · * / % · prefix - !
fn op_level(t: Tok) -> Int
  if ne(t.kind, TkPunct) then 0
  elif eq(t.text, "||") then 1
  elif eq(t.text, "&&") then 2
  elif list_contains(["==", "!=", "<", "<=", ">", ">="], t.text) then 3
  elif or(eq(t.text, "+"), eq(t.text, "-")) then 4
  elif list_contains(["*", "/", "%"], t.text) then 5
  else 0 end
end

fn op_builtin(op: String) -> String
  match op
    case "||" -> "or"
    case "&&" -> "and"
    case "==" -> "eq"
    case "!=" -> "ne"
    case "<" -> "lt"
    case "<=" -> "le"
    case ">" -> "gt"
    case ">=" -> "ge"
    case "+" -> "add"
    case "-" -> "sub"
    case "*" -> "mul"
    case "/" -> "div"
    case _ -> "mod"
  end
end

fn p_expr(st: PS) -> Got[Expr]
  p_binary(st, 1)
end

fn p_binary(st: PS, min: Int) -> Got[Expr]
  p_binary_rest(p_unary(st), min)
end

fn p_binary_rest(left: Got[Expr], min: Int) -> Got[Expr]
  let t = peek(left.st)
  let lv = op_level(t)
  if or(eq(lv, 0), lt(lv, min)) then left
  else
    let right = p_binary(adv(left.st), add(lv, 1))
    let call = ECall(t.pos, EVar(t.pos, op_builtin(t.text)), [left.v, right.v])
    p_binary_rest(Got { v: call, st: right.st }, min)
  end
end

fn p_unary(st: PS) -> Got[Expr]
  let t = peek(st)
  if is_p(st, "-") then
    let x = p_unary(adv(st))
    Got { v: ECall(t.pos, EVar(t.pos, "sub"), [EInt(t.pos, 0), x.v]), st: x.st }
  elif is_p(st, "!") then
    let x = p_unary(adv(st))
    Got { v: ECall(t.pos, EVar(t.pos, "not"), [x.v]), st: x.st }
  else
    p_postfix(p_primary(st))
  end
end

fn p_postfix(r: Got[Expr]) -> Got[Expr]
  if is_p(r.st, "(") then
    let args = p_expr_list(adv(r.st), ")", "to close the call arguments", [])
    p_postfix(Got { v: make_call(expr_pos(r.v), r.v, args.v), st: args.st })
  elif is_p(r.st, ".") then
    let pos = peek(r.st).pos
    let n = p_ident(adv(r.st), "after .")
    p_postfix(Got { v: EField(pos, r.v, n.v.text), st: n.st })
  else
    r
  end
end

fn p_if_chain(st: PS, conds: List[Expr], bodies: List[List[Stmt]]) -> Got[Expr]
  let c = p_expr(st)
  let b = p_block(need(c.st, "then", "after if condition"))
  let conds2 = list_push(conds, c.v)
  let bodies2 = list_push(bodies, b.v)
  if is_p(b.st, "elif") then
    p_if_chain(adv(b.st), conds2, bodies2)
  else
    let e = p_block(need(b.st, "else", "(if is an expression, else is required)"))
    Got { v: EIf(expr_pos(c.v), conds2, bodies2, e.v), st: need(e.st, "end", "to close if") }
  end
end

fn p_arms(st: PS, acc: List[Arm]) -> Got[List[Arm]]
  if is_p(st, "case") then
    let p = p_pattern(adv(st))
    let b = p_block(need(p.st, "->", "after case pattern"))
    p_arms(b.st, list_push(acc, Arm { pat: p.v, body: b.v }))
  else
    Got { v: acc, st: st }
  end
end

fn p_primary(st: PS) -> Got[Expr]
  let t = peek(st)
  let pos = t.pos
  let st1 = adv(st)
  match t.kind
    case TkInt -> Got { v: EInt(pos, t.num), st: st1 }
    case TkStr -> Got { v: EStr(pos, t.text), st: st1 }
    case TkIdent -> Got { v: EVar(pos, t.text), st: st1 }
    case TkUpper ->
      let n1 = peek_at(st1.ts, 1, st1.eof)
      let n2 = peek_at(st1.ts, 2, st1.eof)
      if and(is_p(st1, "{"), or(and(eq(n1.kind, TkIdent), tok_is(n2, ":")), tok_is(n1, "}"))) then
        let fs = p_field_inits(adv(st1), [])
        Got { v: ERec(pos, t.text, fs.v), st: fs.st }
      else
        Got { v: ECtor(pos, t.text), st: st1 }
      end
    case _ ->
      if or(tok_is(t, "true"), tok_is(t, "false")) then
        Got { v: EBool(pos, eq(t.text, "true")), st: st1 }
      elif tok_is(t, "[") then
        let items = p_expr_list(st1, "]", "to close the list", [])
        Got { v: EList(pos, items.v), st: items.st }
      elif tok_is(t, "{") then
        let x = p_expr(st1)
        let fs = p_field_inits(need(x.st, "with", "in record update { value with field: v }"), [])
        Got { v: EUpd(pos, x.v, fs.v), st: fs.st }
      elif tok_is(t, "if") then
        let r = p_if_chain(st1, [], [])
        Got { v: r.v, st: r.st }
      elif tok_is(t, "match") then
        let x = p_expr(st1)
        if not(is_p(x.st, "case")) then
          Got { v: x.v, st: fail(x.st, str_cat("expected case after match value, found ", desc(peek(x.st))), "match x case Pattern -> value ... end") }
        else
          let arms = p_arms(x.st, [])
          Got { v: EMatch(pos, x.v, arms.v), st: need(arms.st, "end", "to close match") }
        end
      elif tok_is(t, "fn") then
        let ps = p_params(need(st1, "(", "to open parameters"), false, [])
        let ret = if is_p(ps.st, "->") then p_type(adv(ps.st)).st else ps.st end
        let effs = p_effects(ret)
        let b = p_block(effs.st)
        Got { v: ELam(pos, list_map(ps.v, fn(p) p.name end), b.v), st: need(b.st, "end", "to close fn (lambda)") }
      elif tok_is(t, "(") then
        let x = p_expr(st1)
        Got { v: x.v, st: need(x.st, ")", "to close the parentheses") }
      else
        Got { v: EInt(pos, 0), st: fail(st, str_cat("expected an expression, found ", desc(t)), "") }
      end
  end
end

# ---------- patterns ----------

fn p_pats(st: PS, close: String, acc: List[Pat]) -> Got[List[Pat]]
  if or(is_p(st, close), at_eof(st)) then
    Got { v: acc, st: st }
  else
    let p = p_pattern(st)
    let acc2 = list_push(acc, p.v)
    if is_p(p.st, ",") then p_pats(adv(p.st), close, acc2) else Got { v: acc2, st: p.st } end
  end
end

fn p_list_pat(st: PS, items: List[Pat]) -> Got[Pat]
  if is_p(st, "..") then
    let r = p_pattern(adv(st))
    let ok_rest = match r.v
      case PVar(_, _) -> true
      case PWild(_) -> true
      case _ -> false
    end
    let st2 = if ok_rest then r.st else fail_at(r.st, pat_pos(r.v), "list rest pattern must be a name or _", "[first, ..rest]") end
    Got { v: PList(peek(st).pos, items, Some(r.v)), st: need(st2, "]", "to close list pattern (..rest must be last)") }
  elif or(is_p(st, "]"), at_eof(st)) then
    Got { v: PList(peek(st).pos, items, None), st: need(st, "]", "to close list pattern (..rest must be last)") }
  else
    let p = p_pattern(st)
    let items2 = list_push(items, p.v)
    if is_p(p.st, ",") then
      p_list_pat(adv(p.st), items2)
    else
      Got { v: PList(pat_pos(p.v), items2, None), st: need(p.st, "]", "to close list pattern (..rest must be last)") }
    end
  end
end

fn p_pattern(st: PS) -> Got[Pat]
  let t = peek(st)
  let pos = t.pos
  let st1 = adv(st)
  match t.kind
    case TkIdent -> Got { v: PVar(pos, t.text), st: st1 }
    case TkInt -> Got { v: PInt(pos, t.num), st: st1 }
    case TkStr -> Got { v: PStr(pos, t.text), st: st1 }
    case TkUpper ->
      if is_p(st1, "(") then
        let args = p_pats(adv(st1), ")", [])
        Got { v: PCtor(pos, t.text, args.v), st: need(args.st, ")", "to close constructor pattern") }
      else
        Got { v: PCtor(pos, t.text, []), st: st1 }
      end
    case _ ->
      if tok_is(t, "_") then
        Got { v: PWild(pos), st: st1 }
      elif or(tok_is(t, "true"), tok_is(t, "false")) then
        Got { v: PBool(pos, eq(t.text, "true")), st: st1 }
      elif tok_is(t, "[") then
        p_list_pat(st1, [])
      else
        Got { v: PWild(pos), st: fail(st, str_cat("expected a pattern, found ", desc(t)), "patterns: _, name, 1, \"s\", true, Ctor(p), [a, ..rest]") }
      end
  end
end
