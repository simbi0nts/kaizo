package main

import "fmt"

type parser struct {
	toks []Token
	i    int
}

func parseFile(path, src string) (f *File, err error) {
	toks, err := lex(path, src)
	if err != nil {
		return nil, err
	}
	p := &parser{toks: toks}
	defer func() {
		if r := recover(); r != nil {
			d, ok := r.(Diag)
			if !ok {
				panic(r)
			}
			f, err = nil, d
		}
	}()
	return p.file(path), nil
}

func (p *parser) peek() Token { return p.toks[p.i] }
func (p *parser) peekN(n int) Token {
	if p.i+n < len(p.toks) {
		return p.toks[p.i+n]
	}
	return p.toks[len(p.toks)-1]
}
func (p *parser) next() Token {
	t := p.toks[p.i]
	if t.Kind != TEOF {
		p.i++
	}
	return t
}
func (p *parser) isP(s string) bool {
	t := p.peek()
	return (t.Kind == TPunct || t.Kind == TKw) && t.Text == s
}
func (p *parser) accept(s string) bool {
	if p.isP(s) {
		p.next()
		return true
	}
	return false
}
func (p *parser) fail(msg, hint string) { panic(Diag{At: p.peek().At, Msg: msg, Hint: hint}) }

func desc(t Token) string {
	switch t.Kind {
	case TEOF:
		return "end of file"
	case TStr:
		return fmt.Sprintf("string %q", t.Text)
	}
	return fmt.Sprintf("%q", t.Text)
}

func (p *parser) expect(s, ctx string) Token {
	if !p.isP(s) {
		hint := ""
		if s == "end" {
			hint = "every fn, type, test, if, match and lambda is closed by its own `end`"
		}
		p.fail(fmt.Sprintf("expected %q %s, found %s", s, ctx, desc(p.peek())), hint)
	}
	return p.next()
}

func (p *parser) ident(ctx string) Token {
	if p.peek().Kind != TIdent {
		p.fail(fmt.Sprintf("expected a lowercase name %s, found %s", ctx, desc(p.peek())), "")
	}
	return p.next()
}

func (p *parser) upper(ctx string) Token {
	if p.peek().Kind != TUpper {
		p.fail(fmt.Sprintf("expected a capitalized name %s, found %s", ctx, desc(p.peek())), "")
	}
	return p.next()
}

func (p *parser) file(path string) *File {
	f := &File{Path: path}
	for p.peek().Kind != TEOF {
		t := p.peek()
		switch {
		case p.isP("import"):
			p.next()
			f.Imports = append(f.Imports, &Import{Node{t.At}, p.ident("after import").Text})
		case p.isP("type"):
			f.Types = append(f.Types, p.typeDecl())
		case p.isP("fn"):
			f.Fns = append(f.Fns, p.fnDecl())
		case p.isP("test"):
			p.next()
			if p.peek().Kind != TStr {
				p.fail("expected test name string after test", `test "name" ... end`)
			}
			name := p.next().Text
			body := p.block()
			p.expect("end", "to close test")
			f.Tests = append(f.Tests, &TestDecl{Node{t.At}, name, body})
		case p.isP("let"):
			p.next()
			name := p.ident("after let").Text
			p.expect("=", "in let")
			f.Lets = append(f.Lets, &LetDecl{Node{t.At}, name, p.expr()})
		default:
			p.fail("expected a top-level declaration (import, type, fn, test, let), found "+desc(t), "")
		}
	}
	return f
}

func (p *parser) typeDecl() *TypeDecl {
	at := p.next().At
	td := &TypeDecl{Node: Node{at}, Name: p.upper("after type").Text}
	if p.accept("[") {
		for {
			td.TParams = append(td.TParams, p.upper("as type parameter").Text)
			if !p.accept(",") {
				break
			}
		}
		p.expect("]", "to close type parameters")
	}
	p.expect("=", "in type declaration")
	if p.accept("{") {
		td.IsRecord = true
		for !p.isP("}") {
			name := p.ident("as field name").Text
			p.expect(":", "after field name")
			td.Fields = append(td.Fields, FieldDecl{name, p.typeExpr()})
			if !p.accept(",") {
				break
			}
		}
		p.expect("}", "to close record fields")
	} else {
		for {
			t := p.upper("as constructor name")
			cd := CtorDecl{At: t.At, Name: t.Text}
			if p.accept("(") {
				for {
					cd.Args = append(cd.Args, p.typeExpr())
					if !p.accept(",") {
						break
					}
				}
				p.expect(")", "to close constructor arguments")
			}
			td.Ctors = append(td.Ctors, cd)
			if !p.accept("|") {
				break
			}
		}
	}
	p.expect("end", "to close type "+td.Name)
	return td
}

func (p *parser) typeExpr() TypeExpr {
	t := p.upper("as type")
	if t.Text == "Fn" && p.accept("(") {
		var args []TypeExpr
		for !p.isP(")") {
			args = append(args, p.typeExpr())
			if !p.accept(",") {
				break
			}
		}
		p.expect(")", "to close Fn parameter types")
		p.expect("->", "in Fn type")
		return TypeExpr{Name: "Fn", Args: append(args, p.typeExpr())}
	}
	te := TypeExpr{Name: t.Text}
	if p.accept("[") {
		for {
			te.Args = append(te.Args, p.typeExpr())
			if !p.accept(",") {
				break
			}
		}
		p.expect("]", "to close type arguments")
	}
	return te
}

func (p *parser) params(requireTypes bool) []Param {
	p.expect("(", "to open parameters")
	var ps []Param
	for !p.isP(")") {
		name := p.ident("as parameter name")
		prm := Param{Name: name.Text}
		if p.accept(":") {
			te := p.typeExpr()
			prm.Type = &te
		} else if requireTypes {
			panic(Diag{At: name.At, Msg: "parameter " + name.Text + " of a top-level fn needs a type",
				Hint: "write " + name.Text + ": Type"})
		}
		ps = append(ps, prm)
		if !p.accept(",") {
			break
		}
	}
	p.expect(")", "to close parameters")
	return ps
}

func (p *parser) effects() []string {
	var effs []string
	if p.accept("!") {
		p.expect("[", "after ! (effect list)")
		for !p.isP("]") {
			effs = append(effs, p.ident("as effect name").Text)
			if !p.accept(",") {
				break
			}
		}
		p.expect("]", "to close effect list")
	}
	return effs
}

func (p *parser) fnDecl() *FnDecl {
	at := p.next().At
	fd := &FnDecl{Node: Node{at}}
	fd.Name = p.ident("after fn").Text
	fd.Params = p.params(true)
	p.expect("->", "(a top-level fn must declare its return type)")
	fd.Ret = p.typeExpr()
	fd.Effects = p.effects()
	fd.Body = p.block()
	p.expect("end", "to close fn "+fd.Name)
	return fd
}

func (p *parser) blockEnd() bool {
	return p.isP("end") || p.isP("case") || p.isP("elif") || p.isP("else") || p.peek().Kind == TEOF
}

func (p *parser) block() *Block {
	b := &Block{}
	for !p.blockEnd() {
		if p.isP("let") {
			at := p.next().At
			name := p.ident("after let").Text
			p.expect("=", "in let")
			b.Stmts = append(b.Stmts, Stmt{At: at, Let: name, X: p.expr()})
			continue
		}
		x := p.expr()
		b.Stmts = append(b.Stmts, Stmt{At: x.P(), X: x})
	}
	if len(b.Stmts) == 0 {
		p.fail("empty block: a block needs at least one expression, found "+desc(p.peek()), "write Unit for a block that returns nothing")
	}
	if last := b.Stmts[len(b.Stmts)-1]; last.Let != "" {
		panic(Diag{At: last.At, Msg: "block ends with a let; the last statement must be the value of the block",
			Hint: "add the expression to return after the let"})
	}
	return b
}

func (p *parser) exprList(close, ctx string) []Expr {
	var xs []Expr
	for !p.isP(close) {
		xs = append(xs, p.expr())
		if !p.accept(",") {
			break
		}
	}
	p.expect(close, ctx)
	return xs
}

func (p *parser) fieldInits() []FieldInit {
	var fs []FieldInit
	for !p.isP("}") {
		t := p.ident("as field name")
		p.expect(":", "after field name")
		fs = append(fs, FieldInit{t.At, t.Text, p.expr()})
		if !p.accept(",") {
			break
		}
	}
	p.expect("}", "to close the record")
	return fs
}

func (p *parser) expr() Expr {
	x := p.primary()
	for {
		switch {
		case p.isP("("):
			p.next()
			x = &Call{Node{x.P()}, x, p.exprList(")", "to close the call arguments")}
		case p.isP("."):
			at := p.next().At
			x = &Field{Node{at}, x, p.ident("after .").Text}
		default:
			return x
		}
	}
}

func (p *parser) primary() Expr {
	t := p.peek()
	switch {
	case t.Kind == TInt:
		p.next()
		return &IntLit{Node{t.At}, t.Int}
	case t.Kind == TStr:
		p.next()
		return &StrLit{Node{t.At}, t.Text}
	case p.isP("true"), p.isP("false"):
		p.next()
		return &BoolLit{Node{t.At}, t.Text == "true"}
	case t.Kind == TIdent:
		p.next()
		return &Ident{Node{t.At}, t.Text}
	case t.Kind == TUpper:
		p.next()
		if p.isP("{") && ((p.peekN(1).Kind == TIdent && p.peekN(2).Text == ":") || p.peekN(1).Text == "}") {
			p.next()
			return &RecordLit{Node{t.At}, t.Text, p.fieldInits()}
		}
		return &CtorRef{Node{t.At}, t.Text}
	case p.isP("["):
		p.next()
		return &ListLit{Node{t.At}, p.exprList("]", "to close the list")}
	case p.isP("{"):
		p.next()
		x := p.expr()
		p.expect("with", "in record update { value with field: v }")
		return &RecordUpd{Node{t.At}, x, p.fieldInits()}
	case p.isP("if"):
		p.next()
		n := &If{Node: Node{t.At}}
		for {
			n.Conds = append(n.Conds, p.expr())
			p.expect("then", "after if condition")
			n.Bodies = append(n.Bodies, p.block())
			if !p.accept("elif") {
				break
			}
		}
		p.expect("else", "(if is an expression, else is required)")
		n.Else = p.block()
		p.expect("end", "to close if")
		return n
	case p.isP("match"):
		p.next()
		m := &Match{Node: Node{t.At}, X: p.expr()}
		if !p.isP("case") {
			p.fail("expected case after match value, found "+desc(p.peek()), "match x case Pattern -> value ... end")
		}
		for p.accept("case") {
			pat := p.pattern()
			p.expect("->", "after case pattern")
			m.Arms = append(m.Arms, Arm{pat, p.block()})
		}
		p.expect("end", "to close match")
		return m
	case p.isP("fn"):
		p.next()
		l := &Lambda{Node: Node{t.At}, Params: p.params(false)}
		if p.accept("->") {
			p.typeExpr()
		}
		p.effects()
		l.Body = p.block()
		p.expect("end", "to close fn (lambda)")
		return l
	}
	hint := ""
	if t.Text == "(" {
		hint = "there is no grouping with parentheses; nest calls instead: add(a, mul(b, c))"
	}
	p.fail("expected an expression, found "+desc(t), hint)
	return nil
}

func (p *parser) pattern() Pattern {
	t := p.peek()
	switch {
	case p.isP("_"):
		p.next()
		return &PWild{Node{t.At}}
	case t.Kind == TIdent:
		p.next()
		return &PVar{Node{t.At}, t.Text}
	case t.Kind == TInt:
		p.next()
		return &PInt{Node{t.At}, t.Int}
	case t.Kind == TStr:
		p.next()
		return &PStr{Node{t.At}, t.Text}
	case p.isP("true"), p.isP("false"):
		p.next()
		return &PBool{Node{t.At}, t.Text == "true"}
	case t.Kind == TUpper:
		p.next()
		pc := &PCtor{Node: Node{t.At}, Name: t.Text}
		if p.accept("(") {
			for !p.isP(")") {
				pc.Args = append(pc.Args, p.pattern())
				if !p.accept(",") {
					break
				}
			}
			p.expect(")", "to close constructor pattern")
		}
		return pc
	case p.isP("["):
		p.next()
		pl := &PList{Node: Node{t.At}}
		for !p.isP("]") {
			if p.accept("..") {
				r := p.pattern()
				switch r.(type) {
				case *PVar, *PWild:
				default:
					panic(Diag{At: r.P(), Msg: "list rest pattern must be a name or _", Hint: "[first, ..rest]"})
				}
				pl.Rest = r
				break
			}
			pl.Items = append(pl.Items, p.pattern())
			if !p.accept(",") {
				break
			}
		}
		p.expect("]", "to close list pattern (..rest must be last)")
		return pl
	}
	p.fail("expected a pattern, found "+desc(t), "patterns: _, name, 1, \"s\", true, Ctor(p), [a, ..rest]")
	return nil
}
