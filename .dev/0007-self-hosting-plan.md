# Step 0007 — Plan: self-hosted native GPLM (remove Go)
Date: 2026-10-27
Status: done (plan + preparation). Note: step 0006 (blind test) lives on branch
`claude/nifty-edison-01274c`, not merged at the time of writing.

## Human request
"You are using existing language Go, make the language from scratch and repeat the process."
Human chose: **self-hosted native compiler**; Go interpreter used **once to bootstrap, then deleted**.

## Target architecture (Theory 1, without a host language)
| Part | v1 |
|------|----|
| Core | `kaizo` — a native x86-64 Linux ELF, **written in GPLM** (`core/*.gp`), compiles GPLM straight to machine code. No assembler, no linker, no libc: raw syscalls. Runtime (`core/rt/rt.gp`) is GPLM using a few `prim_*` intrinsics; it and the prelude are embedded into the `kaizo` binary at compile time (`embed_file`). |
| Libraries | unchanged: `libs/<name>/*.gp` |
| App | native static ELF produced by `kaizo build`; `run`/`test` compile into memory (memfd) and exec it. |

## Bootstrap chain
```
bootstrap/ (Go v0 interpreter) runs core/*.gp  --build core-->  kaizo1 (native)
kaizo1 --build core--> kaizo2 ;  kaizo2 --build core--> kaizo3 ;  require kaizo2 == kaizo3 (fixpoint)
then: delete bootstrap/, commit the fixpoint binary as seed/kaizo (with its sha256)
```
On a new machine: `seed/kaizo build core -o build/kaizo` — no other language needed.
(Trusting-trust note: the seed is a binary; it can always be re-derived from git history
by checking out step 0007..0010 and re-running the Go bootstrap.)

## Native code design (decisions)
- Values: one 64-bit word. Int = `2n+1` (63-bit, low bit 1). Everything else = pointer to
  object `[header: tag | len<<8][payload...]`. Tags: Str, List(len, data ptr), Record(type id,
  fields), Ctor(ctor id, args), Bool (two static objects), Closure(code, arity, captures), Handle(fd).
- Memory: bump allocator in r14 over a 64 GiB MAP_NORESERVE mapping; **no GC yet**
  (fine for compiler runs, games, and demo servers; GC is a later step). 1 GiB own stack.
- Calls: args pushed left→right, closure in r15, **callee pops** its args (`ret imm16`), which
  makes general tail calls (any arity, direct or indirect) a simple frame rewrite + `jmp`.
- Codegen: stack machine (result in rax), no register allocation. ELF: one RWX PT_LOAD at 0x400000.
- Dynamic checks stay (no static types yet): arithmetic on non-Int, non-Bool `if`, wrong
  record field, wrong arity of a function value → runtime error with file:line:col.
- `kaizo test`: test binary forks one child per test, so a failing test can't stop the others.
- Ctrl+C: SIGINT/SIGTERM handler restores the terminal; SIGPIPE ignored.

## New builtins (added to both the Go bootstrap and the native runtime)
`str_byte(s, i)`, `str_from_bytes(list)`, `exit(code)`, `env_get(name)` [io];
`read_file`, `write_file(path, s, mode)`, `list_dir` [new effect `fs`];
`run_image(binary, args)` [new effect `proc`: exec an in-memory executable];
`embed_file("path")` — compile-time file contents (relative to the source file).
Libraries: `libs/map` (persistent string-keyed AVL map in pure GPLM), needed by the compiler.

## Steps
0007 this plan; Go moved to `bootstrap/`, new builtins · 0008 front end in GPLM (lexer, parser,
checker) · 0009 back end (x86-64 encoder, ELF, runtime) · 0010 self-hosting fixpoint, delete Go ·
0011 Snake + Hello web rebuilt natively, all e2e tests.
