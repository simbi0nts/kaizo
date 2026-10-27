package main

import (
	"fmt"
	"net"
	"strconv"
	"strings"
)

// Value is one of: int64, string, bool, List, *Record, *CtorV, *Closure,
// *Builtin, *CtorFn, *ModuleV, *Handle.
type Value interface{}

type List []Value

type Record struct {
	Type   string
	Fields []string
	Vals   []Value
}

type CtorV struct {
	Type, Name string
	Args       []Value
}

type Closure struct {
	Name   string
	Params []string
	Body   *Block
	Env    *Env
}

type Builtin struct {
	Name   string
	Arity  int
	Effect string // "" = pure
	Fn     func(in *Interp, a []Value, at Pos) Value
}

type CtorFn struct{ Info *CtorInfo }

type ModuleV struct{ M *Module }

type Handle struct {
	Kind string // "listener" | "conn"
	L    net.Listener
	C    net.Conn
}

var unitV = &CtorV{Type: "Unit", Name: "Unit"}

func mkCtor(typ, name string, args ...Value) *CtorV { return &CtorV{Type: typ, Name: name, Args: args} }
func some(v Value) Value                            { return mkCtor("Option", "Some", v) }
func none() Value                                   { return mkCtor("Option", "None") }
func ok(v Value) Value                              { return mkCtor("Result", "Ok", v) }
func errV(msg string) Value                         { return mkCtor("Result", "Err", msg) }

// Globals hold top-level names of one module; parent chain: module -> prelude -> builtins.
type Globals struct {
	vars   map[string]Value
	parent *Globals
}

// Env is a persistent linked list of local bindings ending at a module's globals.
type Env struct {
	name   string
	val    Value
	parent *Env
	g      *Globals
}

func (e *Env) bind(name string, v Value) *Env { return &Env{name: name, val: v, parent: e, g: e.g} }

func (e *Env) lookup(name string) (Value, bool) {
	for x := e; x != nil; x = x.parent {
		if x.parent == nil {
			break
		}
		if x.name == name {
			return x.val, true
		}
	}
	for g := e.g; g != nil; g = g.parent {
		if v, ok := g.vars[name]; ok {
			return v, true
		}
	}
	return nil, false
}

type RuntimeError struct {
	At    Pos
	Msg   string
	Trace []frame
}

func (r *RuntimeError) Error() string {
	var sb strings.Builder
	fmt.Fprintf(&sb, "%s: runtime error: %s", r.At, r.Msg)
	for i := len(r.Trace) - 1; i >= 0 && i >= len(r.Trace)-10; i-- {
		fmt.Fprintf(&sb, "\n  in %s, called at %s", r.Trace[i].fn, r.Trace[i].at)
	}
	return sb.String()
}

func rtE(at Pos, f string, a ...any) *RuntimeError {
	return &RuntimeError{At: at, Msg: fmt.Sprintf(f, a...)}
}

type frame struct {
	fn string
	at Pos
}

type tailCall struct {
	fn   *Closure
	args []Value
	at   Pos
}

const maxDepth = 100000

type Interp struct {
	prog  *Program
	args  []string
	stack []frame
}

func (in *Interp) eval(e Expr, env *Env, tail bool) Value {
	switch x := e.(type) {
	case *IntLit:
		return x.V
	case *StrLit:
		return x.V
	case *BoolLit:
		return x.V
	case *Ident:
		v, ok := env.lookup(x.Name)
		if !ok {
			panic(rtE(x.At, "unknown name %s", x.Name))
		}
		return v
	case *CtorRef:
		info := in.prog.Ctors[x.Name]
		if info == nil {
			panic(rtE(x.At, "unknown constructor %s", x.Name))
		}
		if info.Arity == 0 {
			if x.Name == "Unit" {
				return unitV
			}
			return &CtorV{Type: info.Type, Name: x.Name}
		}
		return &CtorFn{info}
	case *Call:
		fn := in.eval(x.Fn, env, false)
		args := make([]Value, len(x.Args))
		for i, a := range x.Args {
			args[i] = in.eval(a, env, false)
		}
		if c, ok := fn.(*Closure); ok && tail {
			return &tailCall{c, args, x.At}
		}
		return in.apply(fn, args, x.At)
	case *Field:
		v := in.eval(x.X, env, false)
		switch r := v.(type) {
		case *Record:
			for i, f := range r.Fields {
				if f == x.Name {
					return r.Vals[i]
				}
			}
			panic(rtE(x.At, "record %s has no field %s", r.Type, x.Name))
		case *ModuleV:
			if mv, ok := r.M.Globals.vars[x.Name]; ok {
				return mv
			}
			panic(rtE(x.At, "module %s has no %s", r.M.Name, x.Name))
		}
		panic(rtE(x.At, "field access .%s on %s, which is not a record", x.Name, typeName(v)))
	case *ListLit:
		l := make(List, len(x.Items))
		for i, it := range x.Items {
			l[i] = in.eval(it, env, false)
		}
		return l
	case *RecordLit:
		td := in.prog.Records[x.Type]
		if td == nil {
			panic(rtE(x.At, "unknown record type %s", x.Type))
		}
		r := &Record{Type: td.Name, Fields: make([]string, len(td.Fields)), Vals: make([]Value, len(td.Fields))}
		for i, fd := range td.Fields {
			r.Fields[i] = fd.Name
			found := false
			for _, fi := range x.Fields {
				if fi.Name == fd.Name {
					r.Vals[i] = in.eval(fi.X, env, false)
					found = true
				}
			}
			if !found {
				panic(rtE(x.At, "record %s is missing field %s", td.Name, fd.Name))
			}
		}
		return r
	case *RecordUpd:
		v := in.eval(x.X, env, false)
		old, ok := v.(*Record)
		if !ok {
			panic(rtE(x.At, "record update on %s, which is not a record", typeName(v)))
		}
		r := &Record{Type: old.Type, Fields: old.Fields, Vals: append([]Value(nil), old.Vals...)}
		for _, fi := range x.Fields {
			idx := -1
			for i, f := range r.Fields {
				if f == fi.Name {
					idx = i
				}
			}
			if idx < 0 {
				panic(rtE(fi.At, "record %s has no field %s", r.Type, fi.Name))
			}
			r.Vals[idx] = in.eval(fi.X, env, false)
		}
		return r
	case *If:
		for i, c := range x.Conds {
			cv := in.eval(c, env, false)
			b, ok := cv.(bool)
			if !ok {
				panic(rtE(c.P(), "if condition must be Bool, got %s", typeName(cv)))
			}
			if b {
				return in.evalBlock(x.Bodies[i], env, tail)
			}
		}
		return in.evalBlock(x.Else, env, tail)
	case *Match:
		v := in.eval(x.X, env, false)
		for _, arm := range x.Arms {
			if env2, ok := in.matchPat(arm.Pat, v, env); ok {
				return in.evalBlock(arm.Body, env2, tail)
			}
		}
		panic(rtE(x.At, "no case matched value %s", show(v, false)))
	case *Lambda:
		names := make([]string, len(x.Params))
		for i, p := range x.Params {
			names[i] = p.Name
		}
		return &Closure{Name: "lambda at " + x.At.String(), Params: names, Body: x.Body, Env: env}
	}
	panic(fmt.Sprintf("eval: unhandled %T", e))
}

func (in *Interp) evalBlock(b *Block, env *Env, tail bool) Value {
	last := len(b.Stmts) - 1
	for i, s := range b.Stmts {
		if s.Let != "" {
			env = env.bind(s.Let, in.eval(s.X, env, false))
			continue
		}
		if i == last {
			return in.eval(s.X, env, tail)
		}
		in.eval(s.X, env, false)
	}
	panic("evalBlock: block without final expression")
}

func (in *Interp) matchPat(p Pattern, v Value, env *Env) (*Env, bool) {
	switch q := p.(type) {
	case *PWild:
		return env, true
	case *PVar:
		return env.bind(q.Name, v), true
	case *PInt:
		n, ok := v.(int64)
		return env, ok && n == q.V
	case *PStr:
		s, ok := v.(string)
		return env, ok && s == q.V
	case *PBool:
		b, ok := v.(bool)
		return env, ok && b == q.V
	case *PCtor:
		c, ok := v.(*CtorV)
		if !ok || c.Name != q.Name || len(c.Args) != len(q.Args) {
			return env, false
		}
		for i, sp := range q.Args {
			if env, ok = in.matchPat(sp, c.Args[i], env); !ok {
				return env, false
			}
		}
		return env, true
	case *PList:
		l, ok := v.(List)
		if !ok || len(l) < len(q.Items) || (q.Rest == nil && len(l) != len(q.Items)) {
			return env, false
		}
		for i, sp := range q.Items {
			if env, ok = in.matchPat(sp, l[i], env); !ok {
				return env, false
			}
		}
		if q.Rest != nil {
			return in.matchPat(q.Rest, l[len(q.Items):], env)
		}
		return env, true
	}
	panic(fmt.Sprintf("matchPat: unhandled %T", p))
}

// apply calls fn and resolves tail calls in a loop, so tail recursion runs in constant stack.
func (in *Interp) apply(fn Value, args []Value, at Pos) Value {
	base := len(in.stack)
	for {
		switch f := fn.(type) {
		case *Closure:
			if len(args) != len(f.Params) {
				panic(rtE(at, "%s expects %d arguments, got %d", f.Name, len(f.Params), len(args)))
			}
			env := f.Env
			for i, p := range f.Params {
				env = env.bind(p, args[i])
			}
			fr := frame{f.Name, at}
			if len(in.stack) > base {
				in.stack[len(in.stack)-1] = fr
			} else {
				in.stack = append(in.stack, fr)
			}
			if len(in.stack) > maxDepth {
				panic(rtE(at, "stack overflow: recursion deeper than %d; make the recursive call the last expression so it becomes a tail call", maxDepth))
			}
			r := in.evalBlock(f.Body, env, true)
			if tc, ok := r.(*tailCall); ok {
				fn, args, at = tc.fn, tc.args, tc.at
				continue
			}
			in.stack = in.stack[:base]
			return r
		case *Builtin:
			if len(args) != f.Arity {
				panic(rtE(at, "%s expects %d arguments, got %d", f.Name, f.Arity, len(args)))
			}
			r := f.Fn(in, args, at)
			in.stack = in.stack[:base]
			return r
		case *CtorFn:
			if len(args) != f.Info.Arity {
				panic(rtE(at, "constructor %s expects %d arguments, got %d", f.Info.Name, f.Info.Arity, len(args)))
			}
			in.stack = in.stack[:base]
			return &CtorV{Type: f.Info.Type, Name: f.Info.Name, Args: args}
		}
		panic(rtE(at, "cannot call %s: it is not a function", typeName(fn)))
	}
}

// protect runs f and converts a GPLM runtime panic into an error.
func (in *Interp) protect(f func() Value) (v Value, err error) {
	defer func() {
		if r := recover(); r != nil {
			re, ok := r.(*RuntimeError)
			if !ok {
				panic(r)
			}
			re.Trace = append([]frame(nil), in.stack...)
			in.stack = in.stack[:0]
			err = re
		}
	}()
	return f(), nil
}

func typeName(v Value) string {
	switch x := v.(type) {
	case int64:
		return "Int"
	case string:
		return "String"
	case bool:
		return "Bool"
	case List:
		return "List"
	case *Record:
		return x.Type
	case *CtorV:
		return x.Type
	case *Closure, *Builtin, *CtorFn:
		return "Fn"
	case *ModuleV:
		return "module " + x.M.Name
	case *Handle:
		if x.Kind == "listener" {
			return "Listener"
		}
		return "Conn"
	}
	return fmt.Sprintf("%T", v)
}

func show(v Value, top bool) string {
	switch x := v.(type) {
	case int64:
		return strconv.FormatInt(x, 10)
	case string:
		if top {
			return x
		}
		return strconv.Quote(x)
	case bool:
		return strconv.FormatBool(x)
	case List:
		parts := make([]string, len(x))
		for i, e := range x {
			parts[i] = show(e, false)
		}
		return "[" + strings.Join(parts, ", ") + "]"
	case *Record:
		parts := make([]string, len(x.Fields))
		for i, f := range x.Fields {
			parts[i] = f + ": " + show(x.Vals[i], false)
		}
		return x.Type + " { " + strings.Join(parts, ", ") + " }"
	case *CtorV:
		if len(x.Args) == 0 {
			return x.Name
		}
		parts := make([]string, len(x.Args))
		for i, e := range x.Args {
			parts[i] = show(e, false)
		}
		return x.Name + "(" + strings.Join(parts, ", ") + ")"
	case *Closure:
		return "<fn " + x.Name + ">"
	case *Builtin:
		return "<builtin " + x.Name + ">"
	case *CtorFn:
		return "<constructor " + x.Info.Name + ">"
	}
	return "<" + typeName(v) + ">"
}

func equal(a, b Value) bool {
	switch x := a.(type) {
	case int64, string, bool:
		return a == b
	case List:
		y, ok := b.(List)
		if !ok || len(x) != len(y) {
			return false
		}
		for i := range x {
			if !equal(x[i], y[i]) {
				return false
			}
		}
		return true
	case *Record:
		y, ok := b.(*Record)
		if !ok || x.Type != y.Type {
			return false
		}
		for i := range x.Vals {
			if !equal(x.Vals[i], y.Vals[i]) {
				return false
			}
		}
		return true
	case *CtorV:
		y, ok := b.(*CtorV)
		if !ok || x.Name != y.Name || len(x.Args) != len(y.Args) {
			return false
		}
		for i := range x.Args {
			if !equal(x.Args[i], y.Args[i]) {
				return false
			}
		}
		return true
	}
	return a == b
}
