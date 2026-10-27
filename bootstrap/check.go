package main

import (
	"fmt"
	"sort"
	"strings"
)

// The v0 checker is not a type checker yet. It rejects: unknown names, wrong arity of
// known functions/constructors, wrong record fields, non-exhaustive match, undeclared effects.

type scope struct {
	name   string
	parent *scope
}

func (s *scope) has(n string) bool {
	for x := s; x != nil; x = x.parent {
		if x.name == n {
			return true
		}
	}
	return false
}

func (s *scope) add(n string) *scope { return &scope{n, s} }

type checker struct {
	prog     *Program
	diags    []Diag
	mod      *Module
	fnName   string
	declared map[string]bool
	anyEff   bool // tests may use every effect
	reported map[string]bool
}

func check(prog *Program) []Diag {
	c := &checker{prog: prog}
	for _, m := range prog.Order {
		c.mod = m
		for _, f := range m.Files {
			for _, td := range f.Types {
				c.typeDecl(td)
			}
			for _, fd := range f.Fns {
				c.fn(fd)
			}
			for _, ld := range f.Lets {
				c.begin("let "+ld.Name, nil, false)
				c.expr(ld.X, nil)
			}
			for _, t := range f.Tests {
				c.begin("test", nil, true)
				c.block(t.Body, nil)
			}
		}
	}
	sort.SliceStable(c.diags, func(i, j int) bool {
		a, b := c.diags[i].At, c.diags[j].At
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		return a.Col < b.Col
	})
	return c.diags
}

func (c *checker) err(at Pos, hint, f string, a ...any) {
	c.diags = append(c.diags, Diag{At: at, Msg: fmt.Sprintf(f, a...), Hint: hint})
}

func (c *checker) begin(name string, effs []string, anyEff bool) {
	c.fnName, c.anyEff = name, anyEff
	c.declared = map[string]bool{}
	c.reported = map[string]bool{}
	for _, e := range effs {
		c.declared[e] = true
	}
}

func (c *checker) typeExpr(t TypeExpr, at Pos, tparams map[string]bool) {
	if c.prog.Types[t.Name] == nil && !tparams[t.Name] {
		c.err(at, "", "unknown type %s", t.Name)
	}
	for _, a := range t.Args {
		c.typeExpr(a, at, tparams)
	}
}

func tparamSet(names []string) map[string]bool {
	m := map[string]bool{}
	for _, n := range names {
		m[n] = true
	}
	return m
}

// single uppercase letters are accepted as type variables in signatures
func sigTParams() map[string]bool {
	m := map[string]bool{}
	for c := 'A'; c <= 'Z'; c++ {
		m[string(c)] = true
	}
	return m
}

func (c *checker) typeDecl(td *TypeDecl) {
	tp := tparamSet(td.TParams)
	seen := map[string]bool{}
	for _, f := range td.Fields {
		if seen[f.Name] {
			c.err(td.At, "", "field %s repeated in record %s", f.Name, td.Name)
		}
		seen[f.Name] = true
		c.typeExpr(f.Type, td.At, tp)
	}
	for _, cd := range td.Ctors {
		for _, a := range cd.Args {
			c.typeExpr(a, cd.At, tp)
		}
	}
}

func (c *checker) fn(fd *FnDecl) {
	for _, e := range fd.Effects {
		if _, ok := knownEffects[e]; !ok {
			c.err(fd.At, "known effects: io, net, term, time, fs, proc", "unknown effect %s", e)
		}
	}
	c.begin(fd.Name, fd.Effects, false)
	var sc *scope
	seen := map[string]bool{}
	for _, p := range fd.Params {
		if seen[p.Name] {
			c.err(fd.At, "", "parameter %s repeated", p.Name)
		}
		seen[p.Name] = true
		sc = sc.add(p.Name)
		if p.Type != nil {
			c.typeExpr(*p.Type, fd.At, sigTParams())
		}
	}
	c.typeExpr(fd.Ret, fd.At, sigTParams())
	c.block(fd.Body, sc)
}

func (c *checker) block(b *Block, sc *scope) {
	for _, s := range b.Stmts {
		c.expr(s.X, sc)
		if s.Let != "" {
			sc = sc.add(s.Let)
		}
	}
}

type gref struct {
	found   bool
	fn      *FnDecl
	builtin *Builtin
	mod     *Module
}

func (c *checker) global(m *Module, name string) gref {
	if f := m.Fns[name]; f != nil {
		return gref{found: true, fn: f}
	}
	if m.Lets[name] != nil {
		return gref{found: true}
	}
	if m.Imports[name] != nil {
		return gref{found: true, mod: c.prog.Modules[name]}
	}
	if pre := c.prog.Modules["prelude"]; m != pre {
		if g := c.global(pre, name); g.found {
			return g
		}
	}
	if b := builtins[name]; b != nil {
		return gref{found: true, builtin: b}
	}
	return gref{}
}

func (c *checker) names(m *Module) []string {
	var ns []string
	for n := range m.Fns {
		ns = append(ns, n)
	}
	for n := range m.Lets {
		ns = append(ns, n)
	}
	return ns
}

// suggest returns the closest known name, for "did you mean" hints.
func (c *checker) suggest(name string, sc *scope) string {
	var cands []string
	for x := sc; x != nil; x = x.parent {
		cands = append(cands, x.name)
	}
	cands = append(cands, c.names(c.mod)...)
	cands = append(cands, c.names(c.prog.Modules["prelude"])...)
	for n := range builtins {
		cands = append(cands, n)
	}
	best, bestD := "", 3
	for _, k := range cands {
		if d := editDist(name, k); d < bestD {
			best, bestD = k, d
		}
	}
	if best != "" {
		return "did you mean " + best + "?"
	}
	return ""
}

func editDist(a, b string) int {
	prev := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		cur := make([]int, len(b)+1)
		cur[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
		}
		prev = cur
	}
	return prev[len(b)]
}

func (c *checker) useEffect(eff string, at Pos, callee string) {
	if c.anyEff || c.declared[eff] || c.reported[eff] {
		return
	}
	c.reported[eff] = true
	hint := fmt.Sprintf("add %s to the effect list of %s: ! [%s]", eff, c.fnName, eff)
	if strings.HasPrefix(c.fnName, "let ") {
		hint = "top-level let must be pure; move this into a fn with ! [" + eff + "]"
	}
	c.err(at, hint, "%s calls %s, which has effect %s, but %s does not declare it", c.fnName, callee, eff, c.fnName)
}

func (c *checker) call(x *Call, sc *scope) {
	arity, name := -1, ""
	var fd *FnDecl
	switch t := x.Fn.(type) {
	case *Ident:
		if !sc.has(t.Name) {
			g := c.global(c.mod, t.Name)
			if g.fn != nil {
				fd = g.fn
			} else if g.builtin != nil {
				arity, name = g.builtin.Arity, t.Name
				if g.builtin.Effect != "" {
					c.useEffect(g.builtin.Effect, x.At, t.Name)
				}
			} else if g.mod != nil {
				c.err(x.At, "call a member: "+t.Name+".name(...)", "%s is a module, not a function", t.Name)
			}
		}
	case *Field:
		if id, ok := t.X.(*Ident); ok && !sc.has(id.Name) {
			if g := c.global(c.mod, id.Name); g.mod != nil {
				fd = g.mod.Fns[t.Name]
			}
		}
	case *CtorRef:
		if info := c.prog.Ctors[t.Name]; info != nil {
			arity, name = info.Arity, "constructor "+t.Name
		}
	}
	if fd != nil {
		arity, name = len(fd.Params), fd.Name
		for _, e := range fd.Effects {
			c.useEffect(e, x.At, fd.Name)
		}
	}
	if arity >= 0 && arity != len(x.Args) {
		c.err(x.At, "", "%s expects %d arguments, got %d", name, arity, len(x.Args))
	}
	c.expr(x.Fn, sc)
	for _, a := range x.Args {
		c.expr(a, sc)
	}
}

func (c *checker) expr(e Expr, sc *scope) {
	switch x := e.(type) {
	case *IntLit, *StrLit, *BoolLit:
	case *Ident:
		if !sc.has(x.Name) && !c.global(c.mod, x.Name).found {
			c.err(x.At, c.suggest(x.Name, sc), "unknown name %s", x.Name)
		}
	case *CtorRef:
		if c.prog.Ctors[x.Name] == nil {
			hint := ""
			if c.prog.Records[x.Name] != nil {
				hint = x.Name + " is a record type: build it with " + x.Name + " { field: value }"
			}
			c.err(x.At, hint, "unknown constructor %s", x.Name)
		}
	case *Call:
		c.call(x, sc)
	case *Field:
		if id, ok := x.X.(*Ident); ok && !sc.has(id.Name) {
			if g := c.global(c.mod, id.Name); g.mod != nil {
				if g.mod.Fns[x.Name] == nil && g.mod.Lets[x.Name] == nil {
					c.err(x.At, "", "module %s has no %s", id.Name, x.Name)
				}
				return
			}
		}
		c.expr(x.X, sc)
	case *ListLit:
		for _, it := range x.Items {
			c.expr(it, sc)
		}
	case *RecordLit:
		td := c.prog.Records[x.Type]
		if td == nil {
			c.err(x.At, "", "unknown record type %s", x.Type)
		} else {
			given := map[string]bool{}
			for _, fi := range x.Fields {
				known := false
				for _, fd := range td.Fields {
					known = known || fd.Name == fi.Name
				}
				if !known {
					c.err(fi.At, "fields of "+td.Name+": "+fieldList(td), "record %s has no field %s", td.Name, fi.Name)
				}
				if given[fi.Name] {
					c.err(fi.At, "", "field %s given twice", fi.Name)
				}
				given[fi.Name] = true
			}
			var missing []string
			for _, fd := range td.Fields {
				if !given[fd.Name] {
					missing = append(missing, fd.Name)
				}
			}
			if len(missing) > 0 {
				c.err(x.At, "every field must be given", "record %s is missing field(s) %s", td.Name, strings.Join(missing, ", "))
			}
		}
		for _, fi := range x.Fields {
			c.expr(fi.X, sc)
		}
	case *RecordUpd:
		c.expr(x.X, sc)
		for _, fi := range x.Fields {
			found := false
			for _, td := range c.prog.Records {
				for _, fd := range td.Fields {
					found = found || fd.Name == fi.Name
				}
			}
			if !found {
				c.err(fi.At, "", "no record type has a field %s", fi.Name)
			}
			c.expr(fi.X, sc)
		}
	case *If:
		for i := range x.Conds {
			c.expr(x.Conds[i], sc)
			c.block(x.Bodies[i], sc)
		}
		c.block(x.Else, sc)
	case *Match:
		c.expr(x.X, sc)
		var rows [][]*spat
		for _, arm := range x.Arms {
			sc2 := c.pattern(arm.Pat, sc, map[string]bool{})
			c.block(arm.Body, sc2)
			rows = append(rows, []*spat{c.simplify(arm.Pat)})
		}
		if w := c.witness(rows, 1); w != nil {
			c.err(x.At, "add a case for "+w[0]+" (or a final case _ -> ...)", "match is not exhaustive: %s is not covered", w[0])
		}
	case *Lambda:
		s := sc
		for _, p := range x.Params {
			s = s.add(p.Name)
		}
		c.block(x.Body, s)
	default:
		panic(fmt.Sprintf("check: unhandled %T", e))
	}
}

func fieldList(td *TypeDecl) string {
	var ns []string
	for _, f := range td.Fields {
		ns = append(ns, f.Name)
	}
	return strings.Join(ns, ", ")
}

func (c *checker) pattern(p Pattern, sc *scope, bound map[string]bool) *scope {
	switch q := p.(type) {
	case *PVar:
		if bound[q.Name] {
			c.err(q.At, "", "name %s bound twice in one pattern", q.Name)
		}
		bound[q.Name] = true
		return sc.add(q.Name)
	case *PCtor:
		info := c.prog.Ctors[q.Name]
		if info == nil {
			c.err(q.At, "", "unknown constructor %s in pattern", q.Name)
		} else if info.Arity != len(q.Args) {
			c.err(q.At, "", "constructor %s has %d arguments, pattern gives %d", q.Name, info.Arity, len(q.Args))
		}
		for _, a := range q.Args {
			sc = c.pattern(a, sc, bound)
		}
	case *PList:
		for _, it := range q.Items {
			sc = c.pattern(it, sc, bound)
		}
		if q.Rest != nil {
			sc = c.pattern(q.Rest, sc, bound)
		}
	}
	return sc
}

// --- exhaustiveness (classic pattern-matrix algorithm) ---

type spat struct {
	wild bool
	lit  bool   // literal Int/String: infinite type, never complete
	typ  string // constructor's type ("List" for list patterns, "Bool" for true/false)
	name string
	args []*spat
}

var wildP = &spat{wild: true}

func (c *checker) simplify(p Pattern) *spat {
	switch q := p.(type) {
	case *PWild, *PVar:
		return wildP
	case *PInt, *PStr:
		return &spat{lit: true}
	case *PBool:
		return &spat{typ: "Bool", name: fmt.Sprint(q.V)}
	case *PCtor:
		info := c.prog.Ctors[q.Name]
		if info == nil || info.Arity != len(q.Args) {
			return wildP // already reported
		}
		s := &spat{typ: info.Type, name: q.Name}
		for _, a := range q.Args {
			s.args = append(s.args, c.simplify(a))
		}
		return s
	case *PList:
		tail := &spat{typ: "List", name: "Nil"}
		if q.Rest != nil {
			tail = wildP
		}
		for i := len(q.Items) - 1; i >= 0; i-- {
			tail = &spat{typ: "List", name: "Cons", args: []*spat{c.simplify(q.Items[i]), tail}}
		}
		return tail
	}
	return wildP
}

type sigCtor struct {
	name  string
	arity int
}

func (c *checker) signature(typ string) []sigCtor {
	switch typ {
	case "Bool":
		return []sigCtor{{"true", 0}, {"false", 0}}
	case "List":
		return []sigCtor{{"Nil", 0}, {"Cons", 2}}
	}
	var out []sigCtor
	if td := c.prog.Types[typ]; td != nil {
		for _, cd := range td.Ctors {
			out = append(out, sigCtor{cd.Name, len(cd.Args)})
		}
	}
	return out
}

func fmtCtor(name string, args []string) string {
	switch name {
	case "Nil":
		return "[]"
	case "Cons":
		return "[" + args[0] + ", .." + args[1] + "]"
	}
	if len(args) == 0 {
		return name
	}
	return name + "(" + strings.Join(args, ", ") + ")"
}

// witness returns an example of n values not matched by any row, or nil if rows are exhaustive.
func (c *checker) witness(rows [][]*spat, n int) []string {
	if len(rows) == 0 {
		w := make([]string, n)
		for i := range w {
			w[i] = "_"
		}
		return w
	}
	if n == 0 {
		return nil
	}
	typ, heads := "", map[string]bool{}
	for _, r := range rows {
		if !r[0].wild && !r[0].lit {
			typ = r[0].typ
			heads[r[0].name] = true
		}
	}
	if typ != "" {
		sig := c.signature(typ)
		complete := true
		for _, sc := range sig {
			complete = complete && heads[sc.name]
		}
		if complete {
			for _, sc := range sig {
				var spec [][]*spat
				for _, r := range rows {
					switch {
					case r[0].wild:
						nr := make([]*spat, 0, sc.arity+len(r)-1)
						for i := 0; i < sc.arity; i++ {
							nr = append(nr, wildP)
						}
						spec = append(spec, append(nr, r[1:]...))
					case r[0].name == sc.name:
						spec = append(spec, append(append([]*spat{}, r[0].args...), r[1:]...))
					}
				}
				if w := c.witness(spec, sc.arity+n-1); w != nil {
					return append([]string{fmtCtor(sc.name, w[:sc.arity])}, w[sc.arity:]...)
				}
			}
			return nil
		}
	}
	var def [][]*spat
	for _, r := range rows {
		if r[0].wild {
			def = append(def, r[1:])
		}
	}
	w := c.witness(def, n-1)
	if w == nil {
		return nil
	}
	head := "_"
	if typ != "" {
		for _, sc := range c.signature(typ) {
			if !heads[sc.name] {
				args := make([]string, sc.arity)
				for i := range args {
					args[i] = "_"
				}
				head = fmtCtor(sc.name, args)
				break
			}
		}
	}
	return append([]string{head}, w...)
}
