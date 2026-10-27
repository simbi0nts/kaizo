# AST of GPLM, shared by parser, checker and code generator.

type Pos = { file: String, line: Int, col: Int } end
type Diag = { pos: Pos, msg: String, hint: String } end

type Expr =
  EInt(Pos, Int) | EStr(Pos, String) | EBool(Pos, Bool) | EVar(Pos, String) | ECtor(Pos, String)
  | ECall(Pos, Expr, List[Expr]) | EField(Pos, Expr, String) | EList(Pos, List[Expr])
  | ERec(Pos, String, List[FieldInit]) | EUpd(Pos, Expr, List[FieldInit])
  | EIf(Pos, List[Expr], List[List[Stmt]], List[Stmt]) | EMatch(Pos, Expr, List[Arm])
  | ELam(Pos, List[String], List[Stmt])
end

type FieldInit = { pos: Pos, name: String, x: Expr } end
type Arm = { pat: Pat, body: List[Stmt] } end
# let_name "" means an expression statement
type Stmt = { pos: Pos, let_name: String, x: Expr } end

type Pat =
  PWild(Pos) | PVar(Pos, String) | PInt(Pos, Int) | PStr(Pos, String) | PBool(Pos, Bool)
  | PCtor(Pos, String, List[Pat]) | PList(Pos, List[Pat], Option[Pat])
end

type TypeX = { name: String, args: List[TypeX] } end
type Param = { name: String, ty: Option[TypeX] } end
type FnDecl = { pos: Pos, name: String, params: List[Param], ret: TypeX, effects: List[String], body: List[Stmt] } end
type CtorDecl = { pos: Pos, name: String, args: List[TypeX] } end
type FieldDecl = { name: String, ty: TypeX } end
type TypeDecl = { pos: Pos, name: String, tparams: List[String], is_record: Bool, ctors: List[CtorDecl], fields: List[FieldDecl] } end
type TestDecl = { pos: Pos, name: String, body: List[Stmt] } end
type LetDecl = { pos: Pos, name: String, x: Expr } end
type ImportDecl = { pos: Pos, name: String } end
type SrcFile = { path: String, imports: List[ImportDecl], types: List[TypeDecl], fns: List[FnDecl], tests: List[TestDecl], lets: List[LetDecl] } end

fn expr_pos(e: Expr) -> Pos
  match e
    case EInt(p, _) -> p
    case EStr(p, _) -> p
    case EBool(p, _) -> p
    case EVar(p, _) -> p
    case ECtor(p, _) -> p
    case ECall(p, _, _) -> p
    case EField(p, _, _) -> p
    case EList(p, _) -> p
    case ERec(p, _, _) -> p
    case EUpd(p, _, _) -> p
    case EIf(p, _, _, _) -> p
    case EMatch(p, _, _) -> p
    case ELam(p, _, _) -> p
  end
end

fn pat_pos(p: Pat) -> Pos
  match p
    case PWild(q) -> q
    case PVar(q, _) -> q
    case PInt(q, _) -> q
    case PStr(q, _) -> q
    case PBool(q, _) -> q
    case PCtor(q, _, _) -> q
    case PList(q, _, _) -> q
  end
end

fn pos_str(p: Pos) -> String
  str_join([p.file, ":", show(p.line), ":", show(p.col)], "")
end

fn diag_str(d: Diag) -> String
  let base = str_join([pos_str(d.pos), ": error: ", d.msg], "")
  if eq(d.hint, "") then base else str_join([base, "\n  hint: ", d.hint], "") end
end
