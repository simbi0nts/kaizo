# Step 0029 — T1a: infix operators and grouping
Date: 2026-10-28
Status: done (measurement batched with the rest of T1)

## Why
New direction (ROADMAP "Direction"): a token-optimized general-purpose tool for agents; syntax chosen
by measured agent cost only. Steps 0023–0028: the call-only syntax made GPLM programs 1.26–1.5x
Python's size, and the operator habit (`==`) was a source of Haiku first-try errors.

## What changed
- Lexer: `+ - * / % < >` and `== != <= >= && ||` are tokens. `-` before a digit is a negative literal
  only when the previous token cannot end a value (ident, literal, `)`, `]`, `}`, true/false/end),
  so `x-1`, `x -1` and `[-1]` all mean what they look like.
- Parser: precedence climbing; every operator desugars to the existing builtin call
  (`a + b` → `add(a, b)`, `a == b` → `eq(a, b)`, `!p` → `not(p)`, `-x` → `sub(0, x)`), so the type
  checker, RC and code generators are unchanged. `( )` groups expressions again.
  Precedence low→high: `||`, `&&`, comparisons, `+ -`, `* / %`, prefix `- !`.
- Hint for `if x = 1`: "to compare use ==". The call forms keep working (old programs unchanged).
- LANGUAGE.md: the "No operators" rule replaced by a 3-line operator rule (net shorter).
- tests/selftest.gp "infix operators"; type_errors/operator_eq.gp now tests the `=` hint. Seed refreshed.

## Not measured yet
Per the gate, T1 changes are measured together (operators, loops, char literals, interpolation) with
≥3 runs per spec on Haiku and Opus, to keep eval cost proportional.
