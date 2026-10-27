# Step 0011 — Plan: Windows x64, macOS x86-64, macOS arm64
Date: 2026-10-27
Status: implemented (A–F); Windows/macOS verified only structurally until CI runs on GitHub

## Human request
"Make sure kaizo is compilable on other OS (macOS, Windows)." Chosen: Windows x64, macOS arm64,
macOS x86-64; verification on **GitHub Actions** (real macOS/Windows runners).

## Why this is more than a port
kaizo is self-hosted, so "kaizo runs on X" = "kaizo can emit programs for X" + cross-compile itself.
| | Linux x64 (today) | Windows x64 | macOS x86-64 | macOS arm64 |
|---|---|---|---|---|
| format | ELF | PE32+ | Mach-O | Mach-O |
| OS interface | raw syscalls | kernel32/ws2_32 imports (IAT) | libSystem via dyld (GOT, bind opcodes) | same |
| C ABI | — | Win64 (rcx,rdx,r8,r9 + shadow space) | SysV | AAPCS64 (x0..x7) |
| CPU | x86-64 | x86-64 | x86-64 | **arm64: new back end** |
| other | | console API, VEH commits heap pages, no fork | ASLR → position-independent code | + ad-hoc **code signature** (SHA-256) |

## Design
- **Target-independent IR** between codegen and machine code (registers named like x86, mapped to
  arm64 x0..x7, x26 = value stack, x27 = closure, x28 = heap, x29 = frame). Lowerings: `x64.gp`, `a64.gp`.
  arm64 keeps the same frame layout by using x26 as an 8-byte-granular value stack; real `sp` is only
  for C calls.
- **Position-independent code** everywhere (RIP-relative / ADRP), code and data in separate segments
  (RX / RW), and a tiny **self-relocation** pass at start-up for data pointers (needed for macOS ASLR;
  slide is 0 on Linux/Windows).
- **OS layer**: `core/rt/rt.gp` stays portable; `os_linux.gp`, `os_windows.gp`, `os_macos.gp` (+ small
  per-arch files) implement `os_*` functions. Foreign calls via intrinsics `prim_ccall("sym", [args])`
  / `prim_ccall32` (int result sign-extended); `"dll!sym"` picks a Windows DLL.
- New builtins: `bit_and bit_or bit_xor bit_shl bit_shr`, `target()` (compile target name).
- `kaizo build|run|test ... --target linux-x64|windows-x64|macos-x64|macos-arm64` (default = host).
- Tests on Windows: the test binary re-runs itself per test (no fork).
- CI: Linux builds everything (incl. cross-compiled kaizo for each OS); each OS runner runs its
  kaizo: all suites, self-compile, **cross-host fixpoint** (kaizo on Windows/macOS must produce the
  same bytes as the Linux cross build), hello-web over HTTP; Snake terminal test where a pty exists.

## Phases
A. bit ops + `target()` in the compiler → new seed (the compiler may only use features the seed knows)
B. IR + PIC + two segments + self-relocation + OS-layer split, Linux only → fixpoint → new seed
C. Windows x64 (PE writer, imports, Win64 calls, os_windows) — locally checked with objdump (pei-x86-64)
D. macOS x86-64 (Mach-O, dyld bind info, SHA-256 + code signature, os_macos) — checked by a Python verifier
E. arm64 lowering + macOS arm64
F. CI workflow, docs. Needs the human to create a GitHub repo and push.

## Local verification limits
No Wine/macOS/arm64 tools here (objdump knows only x86 + PE). macOS and arm64 are proven only on CI.

## Results (phases A–F)
| Phase | What | Local evidence |
|---|---|---|
| A | `bit_*`, `target()`; seed upgraded first so the compiler may use them | selftest |
| B | IR (`ir.gp`), x86 lowering (`x64.gp`), assembler/linker (`link.gp`), ELF with RX/RW segments (`elf.gp`), PIC, self-relocation, `os_linux.gp` | all suites, fixpoint, e2e 13/13 |
| C | Windows: `pe.gp`, `os_windows.gp`, Win64 calls, VEH heap commit, Ctrl+C handler, test re-exec | `objdump -p`: valid PE32+, 39 imports from kernel32/ws2_32; entry calls land on IAT slots |
| D | macOS x86-64: `macho.gp`, dyld bind opcodes, ad-hoc code signature, `libs/sha256`, `os_macos.gp` | `tests/macho_check.py`: structure + all 245 page hashes match hashlib |
| E | arm64: `a64.gp` (x26 value stack keeps the frame layout), macOS arm64 | 46 reference-encoding tests (`kaizo test core`); Mach-O check passes |
| F | `.github/workflows/ci.yml`, `tests/ci_platform.sh` | the platform script passes 21/21 on Linux |

CI plan: Linux builds and cross-builds; then on windows-latest, macos-latest (arm64) and
macos-15-intel the native kaizo runs every suite, rebuilds itself for **all four targets** and must match
the Linux cross builds byte for byte, serves hello-web over HTTP, and runs Snake (pty test on macOS).

## Observations about the language
- Hex constants written as decimal by hand were wrong 4 times (Mach-O magic ×2, two arm64 opcodes);
  all were caught — by the Mach-O verifier and by encoding tests — but **hex literals** (`0xFADE0CC0`)
  would remove the error class. Proposed as a small language step.
- The "no grouping parentheses" rule caught one slip at parse time with a precise hint.
- Name clashes across compiler files (`Target`, `Linked`) were caught by the global type namespace check.

## Open
- Run CI: needs a GitHub repository (human: create it, `git remote add origin …`, `git push`).
- Not verified anywhere yet: Windows console raw mode (Snake interactively), macOS terminal raw mode
  (checked by the pty test on CI), Rosetta not needed (native Intel runner).
