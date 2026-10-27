# Step 0012 — Hexadecimal integer literals
Date: 2026-10-27
Status: done

## Goal
Remove the error class seen in step 0011: four hex constants converted to decimal by hand were wrong
(Mach-O magic numbers, arm64 opcodes). The language gets `0x1F` / `-0x1F` Int literals and the
compiler's own encodings are rewritten in hex.

## Decisions (with reasons)
- Syntax `0x` / `0X` followed by hex digits in any case, with an optional leading `-` exactly like
  decimal literals (`-0x1F` is one token). Same 63-bit Int as decimal; no `_` separators, no octal or
  binary (no need seen yet).
- `0x` with no digits is a lex error with a hint ("hex literal has no digits: 0x" /
  "write hex digits after 0x, e.g. 0x1F or -0xff") instead of lexing `0` followed by identifier `x`.
- Seed dance: the lexer change was built by the old seed, verified, and the seed refreshed *before*
  any core file used a hex literal, so the committed seed can always build the core.
- Only constants that *are* hex values were rewritten: opcodes and masks (`a64.gp`, all words
  ≥ 100000 plus `0xFFFF`, `0x3FFFFFF`), file-format magic/flags/load-command ids (`macho.gp`,
  `pe.gp`), OS flags and ioctl numbers (`gen.gp`, `core/rt/os_*.gp`: TCGETS/TCSETS, O_*, SOCK_*,
  MAP_*, GENERIC_*, SO_*, STATUS_ACCESS_VIOLATION). Sizes, counts, buffer lengths, errno numbers,
  file modes and range bounds stay decimal.

## What was done
- `core/lexer.gp`: `hex_val`, `scan_while_hex`, `parse_hex`, `is_hex_prefix`; Int branch of
  `lex_loop` handles the prefix; test "lexer: hex literals" (values, case, negative, both errors).
- `tests/selftest.gp`: test "hex literals" (`0x1F`, `0X1F`, `0xFADE0CC0` = 4208856256, `-0x1F`, `-0xff`).
  While writing it the decimal value of `0xFADE0CC0` was again computed wrong by hand — the test
  caught it, which is the point of this step.
- Seed refreshed (commit 1), then 187 literals (134 lines) rewritten in `a64.gp`, `macho.gp`, `pe.gp`,
  `gen.gp`, `rt/os_linux.gp`, `rt/os_macos.gp`, `rt/os_windows.gp`; seed refreshed again (commit 2).
- `core/LANGUAGE.md`: hex literal syntax; removed "No hex literals yet".

## How to verify
```
make test selfhost e2e      # all suites, fixpoint, e2e
build/kaizo test core       # 46 arm64 encoding tests + lexer hex test
build/kaizo build core -o /tmp/k-x64 --target macos-x64
build/kaizo build core -o /tmp/k-a64 --target macos-arm64
python3 tests/macho_check.py /tmp/k-x64 /tmp/k-a64
```
Equivalence of the rewrite: `apps/hello-web` built for all four targets by the old seed and by the
rewritten compiler is byte-identical. The compiler binary itself differs only in embedded
file:line:col strings and the embedded runtime source text (columns shift as literals shorten).

## Open questions
None.

## Next step
Back to the step 0011 list: run CI on GitHub; human picks from STATUS.md "Proposed next steps".
