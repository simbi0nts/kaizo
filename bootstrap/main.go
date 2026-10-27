package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

const version = "0.1.0"

const usage = `kaizo ` + version + ` — core of GPLM (General Purpose LLM Language)

usage:
  kaizo run   <file.gp|dir> [args...]   check, then run fn main
  kaizo check <file.gp|dir> [--json]    static checks only
  kaizo test  <file.gp|dir>... [--json] run test blocks
  kaizo build <file.gp|dir> -o <out>    standalone executable (core + bundled sources)
  kaizo version
`

const bundleMagic = "KAIZOBND"

func main() {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sig
		termRestore()
		os.Exit(130)
	}()

	code := run()
	termRestore()
	os.Exit(code)
}

func run() int {
	if b := ownBundle(); b != nil {
		prog, diags := link(b)
		diags = append(diags, check(prog)...)
		if len(diags) > 0 {
			printDiags(diags, false)
			return 1
		}
		return runMain(prog, os.Args[1:])
	}
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	cmd, rest := os.Args[1], os.Args[2:]
	jsonOut := false
	var paths []string
	out := ""
	if cmd != "run" {
		for i := 0; i < len(rest); i++ {
			switch rest[i] {
			case "--json":
				jsonOut = true
			case "-o":
				if i+1 < len(rest) {
					out = rest[i+1]
					i++
				}
			default:
				paths = append(paths, rest[i])
			}
		}
	}
	switch cmd {
	case "version":
		fmt.Println(version)
		return 0
	case "run":
		if len(rest) < 1 {
			fmt.Fprint(os.Stderr, usage)
			return 2
		}
		prog, code := load(rest[0], false)
		if prog == nil {
			return code
		}
		return runMain(prog, rest[1:])
	case "check":
		if len(paths) != 1 {
			fmt.Fprint(os.Stderr, usage)
			return 2
		}
		prog, code := load(paths[0], jsonOut)
		if prog == nil {
			return code
		}
		if jsonOut {
			fmt.Println("[]")
		} else {
			fmt.Println("ok")
		}
		return 0
	case "test":
		if len(paths) == 0 {
			fmt.Fprint(os.Stderr, usage)
			return 2
		}
		code := 0
		for _, p := range paths {
			if c := runTests(p, jsonOut); c != 0 {
				code = c
			}
		}
		return code
	case "build":
		if len(paths) != 1 || out == "" {
			fmt.Fprint(os.Stderr, usage)
			return 2
		}
		return build(paths[0], out)
	}
	fmt.Fprint(os.Stderr, usage)
	return 2
}

// load collects, links and checks a program. On failure it prints diagnostics and returns nil.
func load(path string, jsonOut bool) (*Program, int) {
	b, diags, err := collect(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return nil, 2
	}
	var prog *Program
	if len(diags) == 0 {
		prog, diags = link(b)
	}
	if len(diags) == 0 {
		diags = check(prog)
	}
	if len(diags) > 0 {
		printDiags(diags, jsonOut)
		return nil, 1
	}
	return prog, 0
}

type jsonDiag struct {
	File string `json:"file"`
	Line int    `json:"line"`
	Col  int    `json:"col"`
	Diag
}

func printDiags(ds []Diag, jsonOut bool) {
	if jsonOut {
		out := make([]jsonDiag, len(ds))
		for i, d := range ds {
			out[i] = jsonDiag{d.At.File, d.At.Line, d.At.Col, d}
		}
		j, _ := json.MarshalIndent(out, "", "  ")
		fmt.Println(string(j))
		return
	}
	for _, d := range ds {
		fmt.Fprintln(os.Stderr, d.Error())
	}
	fmt.Fprintf(os.Stderr, "%d error(s)\n", len(ds))
}

func runMain(prog *Program, args []string) int {
	m := prog.Modules[mainModule]
	fd := m.Fns["main"]
	if fd == nil {
		fmt.Fprintln(os.Stderr, "error: no fn main() in the app")
		return 1
	}
	if len(fd.Params) != 0 {
		fmt.Fprintln(os.Stderr, fd.At.String()+": error: fn main must take no parameters (use args() for arguments)")
		return 1
	}
	in := &Interp{prog: prog, args: args}
	if err := in.initGlobals(); err != nil {
		termRestore()
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	_, err := in.protect(func() Value { return in.apply(m.Globals.vars["main"], nil, fd.At) })
	if err != nil {
		termRestore()
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

type testResult struct {
	Name   string `json:"name"`
	Pos    string `json:"pos"`
	Passed bool   `json:"passed"`
	Error  string `json:"error,omitempty"`
}

func runTests(path string, jsonOut bool) int {
	prog, code := load(path, jsonOut)
	if prog == nil {
		return code
	}
	in := &Interp{prog: prog}
	if err := in.initGlobals(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	m := prog.Modules[mainModule]
	var results []testResult
	failed := 0
	for _, t := range m.Tests {
		root := &Env{g: m.Globals}
		_, err := in.protect(func() Value { return in.evalBlock(t.Body, root, false) })
		r := testResult{Name: t.Name, Pos: t.At.String(), Passed: err == nil}
		if err != nil {
			r.Error = err.Error()
			failed++
		}
		results = append(results, r)
	}
	if jsonOut {
		j, _ := json.MarshalIndent(results, "", "  ")
		fmt.Println(string(j))
	} else {
		for _, r := range results {
			if r.Passed {
				fmt.Printf("PASS %s\n", r.Name)
			} else {
				fmt.Printf("FAIL %s\n  %s\n", r.Name, r.Error)
			}
		}
		fmt.Printf("%s: %d passed, %d failed\n", path, len(results)-failed, failed)
	}
	if failed > 0 {
		return 1
	}
	return 0
}

// Executable layout: <core binary> <bundle json> <uint64 json length> "KAIZOBND"
func ownBundle() *Bundle {
	exe, err := os.Executable()
	if err != nil {
		return nil
	}
	data, err := os.ReadFile(exe)
	if err != nil || len(data) < 16 || string(data[len(data)-8:]) != bundleMagic {
		return nil
	}
	n := binary.LittleEndian.Uint64(data[len(data)-16 : len(data)-8])
	if n > uint64(len(data)-16) {
		return nil
	}
	var b Bundle
	if json.Unmarshal(data[uint64(len(data)-16)-n:len(data)-16], &b) != nil {
		return nil
	}
	return &b
}

func build(path, out string) int {
	prog, code := load(path, false)
	if prog == nil {
		return code
	}
	if prog.Modules[mainModule].Fns["main"] == nil {
		fmt.Fprintln(os.Stderr, "error: no fn main() in the app")
		return 1
	}
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	core, err := os.ReadFile(exe)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	payload, _ := json.Marshal(prog.Bundle)
	var buf bytes.Buffer
	buf.Write(core)
	buf.Write(payload)
	binary.Write(&buf, binary.LittleEndian, uint64(len(payload)))
	buf.WriteString(bundleMagic)
	if err := os.WriteFile(out, buf.Bytes(), 0o755); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	fmt.Printf("built %s (%d bytes, %d module(s))\n", out, buf.Len(), len(prog.Bundle.Modules))
	return 0
}
