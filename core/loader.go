package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed prelude.gp
var preludeSrc string

type SrcFile struct {
	Path string `json:"path"`
	Src  string `json:"src"`
}

// Bundle is every source file a program needs; `kaizo build` appends it to the binary.
type Bundle struct {
	Modules map[string][]SrcFile `json:"modules"` // "main" = the app itself
}

type Module struct {
	Name    string
	Files   []*File
	Fns     map[string]*FnDecl
	Lets    map[string]*LetDecl
	Imports map[string]*Import
	Tests   []*TestDecl
	Globals *Globals
}

type CtorInfo struct {
	Type, Name string
	Arity      int
}

type Program struct {
	Modules map[string]*Module
	Order   []*Module // dependencies first; prelude is Order[0]
	Ctors   map[string]*CtorInfo
	Types   map[string]*TypeDecl
	Records map[string]*TypeDecl
	Bundle  *Bundle
}

const mainModule = "main"

// gpFiles returns the .gp files of a file path or a directory.
func gpFiles(path string) ([]SrcFile, error) {
	st, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	paths := []string{path}
	if st.IsDir() {
		paths, _ = filepath.Glob(filepath.Join(path, "*.gp"))
		sort.Strings(paths)
		if len(paths) == 0 {
			return nil, fmt.Errorf("%s: no .gp files", path)
		}
	}
	var out []SrcFile
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, err
		}
		out = append(out, SrcFile{Path: p, Src: string(b)})
	}
	return out, nil
}

// libDirs: $KAIZO_PATH entries first, then every `libs/` dir from the app's folder upward.
func libDirs(root string) []string {
	var dirs []string
	if kp := os.Getenv("KAIZO_PATH"); kp != "" {
		dirs = append(dirs, filepath.SplitList(kp)...)
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return dirs
	}
	for d := filepath.Dir(abs); ; d = filepath.Dir(d) {
		if st, err := os.Stat(filepath.Join(d, "libs")); err == nil && st.IsDir() {
			dirs = append(dirs, filepath.Join(d, "libs"))
		}
		if filepath.Dir(d) == d {
			break
		}
	}
	return dirs
}

// collect reads the app at root and, transitively, every library it imports.
func collect(root string) (*Bundle, []Diag, error) {
	main, err := gpFiles(root)
	if err != nil {
		return nil, nil, err
	}
	b := &Bundle{Modules: map[string][]SrcFile{mainModule: main}}
	dirs := libDirs(root)
	var diags []Diag
	queue := []string{mainModule}
	for len(queue) > 0 {
		name := queue[0]
		queue = queue[1:]
		for _, sf := range b.Modules[name] {
			f, err := parseFile(sf.Path, sf.Src)
			if err != nil {
				diags = append(diags, err.(Diag))
				continue
			}
			for _, imp := range f.Imports {
				if _, done := b.Modules[imp.Name]; done {
					continue
				}
				var found []SrcFile
				for _, d := range dirs {
					if fs, err := gpFiles(filepath.Join(d, imp.Name)); err == nil {
						found = fs
						break
					}
				}
				if found == nil {
					diags = append(diags, Diag{At: imp.At, Msg: "library " + imp.Name + " not found",
						Hint: "searched: " + strings.Join(dirs, ", ") + " (set KAIZO_PATH to add more)"})
					continue
				}
				b.Modules[imp.Name] = found
				queue = append(queue, imp.Name)
			}
		}
	}
	return b, diags, nil
}

// link parses a bundle and registers all types, constructors and top-level names.
func link(b *Bundle) (*Program, []Diag) {
	prog := &Program{Modules: map[string]*Module{}, Ctors: map[string]*CtorInfo{},
		Types: map[string]*TypeDecl{}, Records: map[string]*TypeDecl{}, Bundle: b}
	var diags []Diag
	for _, t := range []string{"Int", "String", "Bool", "List", "Fn", "Unit", "Listener", "Conn"} {
		prog.Types[t] = &TypeDecl{Name: t}
	}
	prog.Types["Unit"].Ctors = []CtorDecl{{Name: "Unit"}}
	prog.Ctors["Unit"] = &CtorInfo{Type: "Unit", Name: "Unit"}

	addModule := func(name string, files []SrcFile) *Module {
		m := &Module{Name: name, Fns: map[string]*FnDecl{}, Lets: map[string]*LetDecl{}, Imports: map[string]*Import{}}
		prog.Modules[name] = m
		defined := map[string]Pos{}
		def := func(n string, at Pos) bool {
			if prev, dup := defined[n]; dup {
				diags = append(diags, Diag{At: at, Msg: n + " is already defined at " + prev.String()})
				return false
			}
			if _, isB := builtins[n]; isB {
				diags = append(diags, Diag{At: at, Msg: n + " is a builtin and cannot be redefined", Hint: "choose another name"})
				return false
			}
			if name != "prelude" {
				if pm := prog.Modules["prelude"]; pm != nil && (pm.Fns[n] != nil || pm.Lets[n] != nil) {
					diags = append(diags, Diag{At: at, Msg: n + " is defined in the prelude and cannot be redefined"})
					return false
				}
			}
			defined[n] = at
			return true
		}
		for _, sf := range files {
			f, err := parseFile(sf.Path, sf.Src)
			if err != nil {
				diags = append(diags, err.(Diag))
				continue
			}
			m.Files = append(m.Files, f)
			for _, imp := range f.Imports {
				if _, dup := m.Imports[imp.Name]; !dup && def(imp.Name, imp.At) {
					m.Imports[imp.Name] = imp
				}
			}
			for _, fd := range f.Fns {
				if def(fd.Name, fd.At) {
					m.Fns[fd.Name] = fd
				}
			}
			for _, ld := range f.Lets {
				if def(ld.Name, ld.At) {
					m.Lets[ld.Name] = ld
				}
			}
			m.Tests = append(m.Tests, f.Tests...)
			for _, td := range f.Types {
				if prev, dup := prog.Types[td.Name]; dup {
					where := "built in"
					if prev.At.File != "" {
						where = "at " + prev.At.String()
					}
					diags = append(diags, Diag{At: td.At, Msg: "type " + td.Name + " is already defined " + where,
						Hint: "type and constructor names are global across all modules"})
					continue
				}
				prog.Types[td.Name] = td
				if td.IsRecord {
					prog.Records[td.Name] = td
				}
				for _, cd := range td.Ctors {
					if prev, dup := prog.Ctors[cd.Name]; dup {
						diags = append(diags, Diag{At: cd.At, Msg: "constructor " + cd.Name + " is already defined in type " + prev.Type,
							Hint: "type and constructor names are global across all modules"})
						continue
					}
					prog.Ctors[cd.Name] = &CtorInfo{Type: td.Name, Name: cd.Name, Arity: len(cd.Args)}
				}
			}
		}
		return m
	}

	addModule("prelude", []SrcFile{{Path: "<prelude>", Src: preludeSrc}})
	names := make([]string, 0, len(b.Modules))
	for n := range b.Modules {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		addModule(n, b.Modules[n])
	}

	// dependency order (post-order DFS from main) so library lets are evaluated first
	seen := map[string]bool{}
	var visit func(n string)
	visit = func(n string) {
		m := prog.Modules[n]
		if m == nil || seen[n] {
			return
		}
		seen[n] = true
		deps := make([]string, 0, len(m.Imports))
		for d := range m.Imports {
			deps = append(deps, d)
		}
		sort.Strings(deps)
		for _, d := range deps {
			visit(d)
		}
		prog.Order = append(prog.Order, m)
	}
	visit("prelude")
	visit(mainModule)
	return prog, diags
}

// initGlobals binds every top-level fn and import, then evaluates top-level lets.
func (in *Interp) initGlobals() error {
	prog := in.prog
	bg := &Globals{vars: map[string]Value{}}
	for n, b := range builtins {
		bg.vars[n] = b
	}
	pre := prog.Modules["prelude"]
	for _, m := range prog.Order {
		parent := bg
		if m != pre {
			parent = pre.Globals
		}
		m.Globals = &Globals{vars: map[string]Value{}, parent: parent}
	}
	for _, m := range prog.Order {
		root := &Env{g: m.Globals}
		for name, fd := range m.Fns {
			ps := make([]string, len(fd.Params))
			for i, p := range fd.Params {
				ps[i] = p.Name
			}
			qual := fd.Name
			if m.Name != mainModule && m.Name != "prelude" {
				qual = m.Name + "." + fd.Name
			}
			m.Globals.vars[name] = &Closure{Name: qual, Params: ps, Body: fd.Body, Env: root}
		}
		for name := range m.Imports {
			if dep := prog.Modules[name]; dep != nil {
				m.Globals.vars[name] = &ModuleV{dep}
			}
		}
	}
	for _, m := range prog.Order {
		root := &Env{g: m.Globals}
		for _, f := range m.Files {
			for _, ld := range f.Lets {
				v, err := in.protect(func() Value { return in.eval(ld.X, root, false) })
				if err != nil {
					return err
				}
				m.Globals.vars[ld.Name] = v
			}
		}
	}
	return nil
}
