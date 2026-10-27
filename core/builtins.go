package main

import (
	"bufio"
	"io"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

var builtins = map[string]*Builtin{}

// Known effects. A fn may call an effectful builtin only if it declares the effect.
var knownEffects = map[string]string{
	"io":   "stdout/stdin, program arguments",
	"term": "terminal raw mode and key input",
	"time": "clock and sleep",
	"net":  "TCP sockets",
}

func def(name string, arity int, eff string, f func(in *Interp, a []Value, at Pos) Value) {
	builtins[name] = &Builtin{Name: name, Arity: arity, Effect: eff, Fn: f}
}

func argInt(name string, a []Value, i int, at Pos) int64 {
	n, ok := a[i].(int64)
	if !ok {
		panic(rtE(at, "%s: argument %d must be Int, got %s", name, i+1, typeName(a[i])))
	}
	return n
}

func argStr(name string, a []Value, i int, at Pos) string {
	s, ok := a[i].(string)
	if !ok {
		panic(rtE(at, "%s: argument %d must be String, got %s", name, i+1, typeName(a[i])))
	}
	return s
}

func argBool(name string, a []Value, i int, at Pos) bool {
	b, ok := a[i].(bool)
	if !ok {
		panic(rtE(at, "%s: argument %d must be Bool, got %s", name, i+1, typeName(a[i])))
	}
	return b
}

func argList(name string, a []Value, i int, at Pos) List {
	l, ok := a[i].(List)
	if !ok {
		panic(rtE(at, "%s: argument %d must be List, got %s", name, i+1, typeName(a[i])))
	}
	return l
}

func argHandle(name, kind string, a []Value, i int, at Pos) *Handle {
	h, ok := a[i].(*Handle)
	if !ok || h.Kind != kind {
		panic(rtE(at, "%s: argument %d must be a %s handle, got %s", name, i+1, kind, typeName(a[i])))
	}
	return h
}

func intOp(name string, f func(x, y int64, at Pos) int64) {
	def(name, 2, "", func(in *Interp, a []Value, at Pos) Value {
		return f(argInt(name, a, 0, at), argInt(name, a, 1, at), at)
	})
}

func cmpOp(name string, f func(c int) bool) {
	def(name, 2, "", func(in *Interp, a []Value, at Pos) Value {
		switch x := a[0].(type) {
		case int64:
			return f(cmpInt(x, argInt(name, a, 1, at)))
		case string:
			return f(strings.Compare(x, argStr(name, a, 1, at)))
		}
		panic(rtE(at, "%s compares Int or String, got %s", name, typeName(a[0])))
	})
}

func cmpInt(x, y int64) int {
	switch {
	case x < y:
		return -1
	case x > y:
		return 1
	}
	return 0
}

func clamp(i, lo, hi int64) int64 {
	if i < lo {
		return lo
	}
	if i > hi {
		return hi
	}
	return i
}

var stdin = bufio.NewReader(os.Stdin)

func init() {
	// --- Int
	intOp("add", func(x, y int64, at Pos) int64 { return x + y })
	intOp("sub", func(x, y int64, at Pos) int64 { return x - y })
	intOp("mul", func(x, y int64, at Pos) int64 { return x * y })
	intOp("div", func(x, y int64, at Pos) int64 {
		if y == 0 {
			panic(rtE(at, "div by zero"))
		}
		q := x / y
		if (x%y != 0) && ((x < 0) != (y < 0)) {
			q--
		}
		return q
	})
	intOp("mod", func(x, y int64, at Pos) int64 {
		if y == 0 {
			panic(rtE(at, "mod by zero"))
		}
		r := x % y
		if r != 0 && ((r < 0) != (y < 0)) {
			r += y
		}
		return r
	})
	// --- comparison and logic
	def("eq", 2, "", func(in *Interp, a []Value, at Pos) Value { return equal(a[0], a[1]) })
	def("ne", 2, "", func(in *Interp, a []Value, at Pos) Value { return !equal(a[0], a[1]) })
	cmpOp("lt", func(c int) bool { return c < 0 })
	cmpOp("le", func(c int) bool { return c <= 0 })
	cmpOp("gt", func(c int) bool { return c > 0 })
	cmpOp("ge", func(c int) bool { return c >= 0 })
	def("not", 1, "", func(in *Interp, a []Value, at Pos) Value { return !argBool("not", a, 0, at) })
	def("and", 2, "", func(in *Interp, a []Value, at Pos) Value {
		return argBool("and", a, 0, at) && argBool("and", a, 1, at)
	})
	def("or", 2, "", func(in *Interp, a []Value, at Pos) Value {
		return argBool("or", a, 0, at) || argBool("or", a, 1, at)
	})

	// --- String (byte-based)
	def("show", 1, "", func(in *Interp, a []Value, at Pos) Value { return show(a[0], true) })
	def("str_cat", 2, "", func(in *Interp, a []Value, at Pos) Value {
		return argStr("str_cat", a, 0, at) + argStr("str_cat", a, 1, at)
	})
	def("str_join", 2, "", func(in *Interp, a []Value, at Pos) Value {
		l := argList("str_join", a, 0, at)
		parts := make([]string, len(l))
		for i, v := range l {
			s, ok := v.(string)
			if !ok {
				panic(rtE(at, "str_join: item %d is %s, not String", i, typeName(v)))
			}
			parts[i] = s
		}
		return strings.Join(parts, argStr("str_join", a, 1, at))
	})
	def("str_len", 1, "", func(in *Interp, a []Value, at Pos) Value { return int64(len(argStr("str_len", a, 0, at))) })
	def("str_slice", 3, "", func(in *Interp, a []Value, at Pos) Value {
		s := argStr("str_slice", a, 0, at)
		n := int64(len(s))
		from := clamp(argInt("str_slice", a, 1, at), 0, n)
		to := clamp(argInt("str_slice", a, 2, at), from, n)
		return s[from:to]
	})
	def("str_find", 2, "", func(in *Interp, a []Value, at Pos) Value {
		i := strings.Index(argStr("str_find", a, 0, at), argStr("str_find", a, 1, at))
		if i < 0 {
			return none()
		}
		return some(int64(i))
	})
	def("str_split", 2, "", func(in *Interp, a []Value, at Pos) Value {
		sep := argStr("str_split", a, 1, at)
		if sep == "" {
			panic(rtE(at, "str_split: separator must not be empty"))
		}
		parts := strings.Split(argStr("str_split", a, 0, at), sep)
		l := make(List, len(parts))
		for i, p := range parts {
			l[i] = p
		}
		return l
	})
	def("str_trim", 1, "", func(in *Interp, a []Value, at Pos) Value { return strings.TrimSpace(argStr("str_trim", a, 0, at)) })
	def("str_starts", 2, "", func(in *Interp, a []Value, at Pos) Value {
		return strings.HasPrefix(argStr("str_starts", a, 0, at), argStr("str_starts", a, 1, at))
	})
	def("str_ends", 2, "", func(in *Interp, a []Value, at Pos) Value {
		return strings.HasSuffix(argStr("str_ends", a, 0, at), argStr("str_ends", a, 1, at))
	})
	def("str_repeat", 2, "", func(in *Interp, a []Value, at Pos) Value {
		n := argInt("str_repeat", a, 1, at)
		if n < 0 {
			n = 0
		}
		return strings.Repeat(argStr("str_repeat", a, 0, at), int(n))
	})
	def("str_lower", 1, "", func(in *Interp, a []Value, at Pos) Value { return strings.ToLower(argStr("str_lower", a, 0, at)) })
	def("str_to_int", 1, "", func(in *Interp, a []Value, at Pos) Value {
		n, err := strconv.ParseInt(strings.TrimSpace(argStr("str_to_int", a, 0, at)), 10, 64)
		if err != nil {
			return none()
		}
		return some(n)
	})

	// --- List (immutable; every op returns a new list)
	def("list_len", 1, "", func(in *Interp, a []Value, at Pos) Value { return int64(len(argList("list_len", a, 0, at))) })
	def("list_get", 2, "", func(in *Interp, a []Value, at Pos) Value {
		l, i := argList("list_get", a, 0, at), argInt("list_get", a, 1, at)
		if i < 0 || i >= int64(len(l)) {
			return none()
		}
		return some(l[i])
	})
	def("list_cons", 2, "", func(in *Interp, a []Value, at Pos) Value {
		l := argList("list_cons", a, 1, at)
		return append(List{a[0]}, l...)
	})
	def("list_push", 2, "", func(in *Interp, a []Value, at Pos) Value {
		l := argList("list_push", a, 0, at)
		return append(append(make(List, 0, len(l)+1), l...), a[1])
	})
	def("list_concat", 2, "", func(in *Interp, a []Value, at Pos) Value {
		x, y := argList("list_concat", a, 0, at), argList("list_concat", a, 1, at)
		return append(append(make(List, 0, len(x)+len(y)), x...), y...)
	})
	def("list_slice", 3, "", func(in *Interp, a []Value, at Pos) Value {
		l := argList("list_slice", a, 0, at)
		n := int64(len(l))
		from := clamp(argInt("list_slice", a, 1, at), 0, n)
		to := clamp(argInt("list_slice", a, 2, at), from, n)
		return append(List(nil), l[from:to]...)
	})
	def("list_reverse", 1, "", func(in *Interp, a []Value, at Pos) Value {
		l := argList("list_reverse", a, 0, at)
		r := make(List, len(l))
		for i, v := range l {
			r[len(l)-1-i] = v
		}
		return r
	})
	def("list_range", 2, "", func(in *Interp, a []Value, at Pos) Value {
		from, to := argInt("list_range", a, 0, at), argInt("list_range", a, 1, at)
		var l List
		for i := from; i < to; i++ {
			l = append(l, i)
		}
		if l == nil {
			l = List{}
		}
		return l
	})
	def("list_contains", 2, "", func(in *Interp, a []Value, at Pos) Value {
		for _, v := range argList("list_contains", a, 0, at) {
			if equal(v, a[1]) {
				return true
			}
		}
		return false
	})
	def("list_map", 2, "", func(in *Interp, a []Value, at Pos) Value {
		l := argList("list_map", a, 0, at)
		r := make(List, len(l))
		for i, v := range l {
			r[i] = in.apply(a[1], []Value{v}, at)
		}
		return r
	})
	def("list_filter", 2, "", func(in *Interp, a []Value, at Pos) Value {
		r := List{}
		for _, v := range argList("list_filter", a, 0, at) {
			keep, ok := in.apply(a[1], []Value{v}, at).(bool)
			if !ok {
				panic(rtE(at, "list_filter: predicate must return Bool"))
			}
			if keep {
				r = append(r, v)
			}
		}
		return r
	})
	def("list_fold", 3, "", func(in *Interp, a []Value, at Pos) Value {
		acc := a[1]
		for _, v := range argList("list_fold", a, 0, at) {
			acc = in.apply(a[2], []Value{acc, v}, at)
		}
		return acc
	})
	def("list_sort", 1, "", func(in *Interp, a []Value, at Pos) Value {
		r := append(List(nil), argList("list_sort", a, 0, at)...)
		sort.SliceStable(r, func(i, j int) bool {
			switch x := r[i].(type) {
			case int64:
				y, _ := r[j].(int64)
				return x < y
			case string:
				y, _ := r[j].(string)
				return x < y
			}
			panic(rtE(at, "list_sort sorts Int or String lists"))
		})
		return r
	})

	// --- assertions (pure: they only abort)
	def("panic", 1, "", func(in *Interp, a []Value, at Pos) Value { panic(rtE(at, "panic: %s", show(a[0], true))) })
	def("expect", 2, "", func(in *Interp, a []Value, at Pos) Value {
		if !argBool("expect", a, 0, at) {
			panic(rtE(at, "expectation failed: %s", show(a[1], true)))
		}
		return unitV
	})
	def("expect_eq", 2, "", func(in *Interp, a []Value, at Pos) Value {
		if !equal(a[0], a[1]) {
			panic(rtE(at, "expect_eq failed\n    got:      %s\n    expected: %s", show(a[0], false), show(a[1], false)))
		}
		return unitV
	})

	// --- io
	def("print", 1, "io", func(in *Interp, a []Value, at Pos) Value {
		os.Stdout.WriteString(argStr("print", a, 0, at))
		return unitV
	})
	def("println", 1, "io", func(in *Interp, a []Value, at Pos) Value {
		os.Stdout.WriteString(argStr("println", a, 0, at) + "\n")
		return unitV
	})
	def("read_line", 0, "io", func(in *Interp, a []Value, at Pos) Value {
		s, err := stdin.ReadString('\n')
		if err != nil && s == "" {
			return none()
		}
		return some(strings.TrimRight(s, "\r\n"))
	})
	def("args", 0, "io", func(in *Interp, a []Value, at Pos) Value {
		l := List{}
		for _, s := range in.args {
			l = append(l, s)
		}
		return l
	})

	// --- term
	def("term_raw", 0, "term", func(in *Interp, a []Value, at Pos) Value {
		if err := termRaw(); err != nil {
			return errV("stdin is not a terminal: " + err.Error())
		}
		return ok(unitV)
	})
	def("term_restore", 0, "term", func(in *Interp, a []Value, at Pos) Value { termRestore(); return unitV })
	def("term_key", 0, "term", func(in *Interp, a []Value, at Pos) Value { return termKey() })

	// --- time
	def("now_ms", 0, "time", func(in *Interp, a []Value, at Pos) Value { return time.Now().UnixMilli() })
	def("sleep_ms", 1, "time", func(in *Interp, a []Value, at Pos) Value {
		time.Sleep(time.Duration(argInt("sleep_ms", a, 0, at)) * time.Millisecond)
		return unitV
	})

	// --- net
	def("tcp_listen", 1, "net", func(in *Interp, a []Value, at Pos) Value {
		l, err := net.Listen("tcp", argStr("tcp_listen", a, 0, at))
		if err != nil {
			return errV(err.Error())
		}
		return ok(&Handle{Kind: "listener", L: l})
	})
	def("tcp_accept", 1, "net", func(in *Interp, a []Value, at Pos) Value {
		c, err := argHandle("tcp_accept", "listener", a, 0, at).L.Accept()
		if err != nil {
			return errV(err.Error())
		}
		return ok(&Handle{Kind: "conn", C: c})
	})
	def("tcp_read", 3, "net", func(in *Interp, a []Value, at Pos) Value {
		h := argHandle("tcp_read", "conn", a, 0, at)
		max, timeout := argInt("tcp_read", a, 1, at), argInt("tcp_read", a, 2, at)
		h.C.SetReadDeadline(time.Now().Add(time.Duration(timeout) * time.Millisecond))
		buf := make([]byte, clamp(max, 1, 1<<20))
		n, err := h.C.Read(buf)
		if n > 0 {
			return ok(string(buf[:n]))
		}
		if err != nil && err != io.EOF {
			return errV(err.Error())
		}
		return ok("")
	})
	def("tcp_write", 2, "net", func(in *Interp, a []Value, at Pos) Value {
		h := argHandle("tcp_write", "conn", a, 0, at)
		if _, err := h.C.Write([]byte(argStr("tcp_write", a, 1, at))); err != nil {
			return errV(err.Error())
		}
		return ok(unitV)
	})
	def("tcp_close", 1, "net", func(in *Interp, a []Value, at Pos) Value {
		h, okH := a[0].(*Handle)
		if !okH {
			panic(rtE(at, "tcp_close: argument must be a Conn or Listener"))
		}
		if h.C != nil {
			h.C.Close()
		}
		if h.L != nil {
			h.L.Close()
		}
		return unitV
	})
}
