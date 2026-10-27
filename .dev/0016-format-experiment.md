# Step 0016 — Experiment: text vs. JSON tree vs. raw machine code as the agent's output format
Date: 2026-10-27
Status: done (ran on a branch as "0012"; renumbered to 0016 when merged in 0018)

## Goal
The human asked two questions: does GPLM's familiar Rust-like syntax help, or does it create
false friends? And does an LLM need a text syntax at all, or could it emit structured trees or
binaries directly? This step measures that on one small task. Nothing in `core/` or `seed/` was
changed.

## Decisions (with reasons)
- **One task, three output formats, fresh agents.** Each agent was a fresh subagent of the same
  model (Claude Opus 5.5). It could use only Read and Write, it read only its reference file and
  the spec, and it could not compile or run anything. The experimenter ran the checker, the tests
  and the hidden acceptance test, and would have sent diagnostics back. Each round of diagnostics
  counts as one fix round. Without tool access the measure is "first-shot quality plus fix rounds
  driven by compiler feedback", and every round is under our control.
- **Arm b reference = same semantics, no text syntax.** [ast-json.md](0016/ast-json.md) maps 1:1
  to `core/ast.gp` (one JSON object per AST constructor, `Pos` omitted). It repeats the language
  rules, builtins and gaps of `core/LANGUAGE.md` but shows no GPLM text. The converter
  [gpjson.py](0016/gpjson.py) is tooling, not help. It prints the tree as GPLM text and maps
  `kaizo check` diagnostics back to JSON paths (e.g. `fns[1].body[0].x.args[0].f: unknown name shw`).
  It never repairs anything.
- **Arm c uses a reduced spec and a capped effort.** The agent writes a raw Linux x86-64 ELF as
  hex: read stdin, print the most frequent word, first occurrence wins ties
  ([spec-c.md](0016/spec-c.md)). The cap was 2 fix rounds. Reading from stdin means the output
  cannot be hard-coded.
- **Control arm a2 (added).** Arm c's spec is easier, so its cost cannot be compared directly with
  arms a and b. Arm a2 is the same reduced spec written in GPLM text
  ([spec-a2.md](0016/spec-a2.md)). It makes text vs. machine code comparable on the same task.
- **Hidden acceptance tests.** [accept.sh](0016/accept.sh) compares stdout and the exit code with
  [reference.py](0016/reference.py) on 7 cases: the example, an empty file, a file without
  letters, ties at the cut-off with apostrophes and hyphens, a 40 KB file, a missing file and no
  argument. [accept-c.sh](0016/accept-c.sh) has 8 fixed cases, and
  [fuzz-c.py](0016/fuzz-c.py) adds a 500-input differential fuzz for arms c and a2.

## What was done
| Arm | Output format | Spec | Output tokens¹ | Wall time | Checker / assembler errors | Runtime errors | Fix rounds | Final result |
|-----|---------------|------|---------------:|----------:|---------------------------:|---------------:|-----------:|--------------|
| a  | GPLM text ([apps/wordfreq/main.gp](../apps/wordfreq/main.gp), 3.8 KB) | full | 4,375 | 47 s | 0 | 0 | 0 | 4/4 own tests, 7/7 acceptance |
| b  | JSON AST ([arm-b/wordfreq.json](0016/arm-b/wordfreq.json), 21.9 KB) | full | 13,988 | 113 s | 0 (schema 0, checker 0) | 0 | 0 | 4/4 own tests, 7/7 acceptance |
| c  | x86-64 ELF hex ([arm-c/topword.hex](0016/arm-c/topword.hex), 545-byte binary) | reduced | 31,045 | 357 s | 0 (kernel loaded it) | 0 | 0 | 8/8 acceptance, 500/500 fuzz |
| a2 | GPLM text ([arm-a2/topword.gp](0016/arm-a2/topword.gp), 1.2 KB) | reduced | 1,485 | 19 s | 0 | 0 | 0 | 8/8 acceptance, 500/500 fuzz |

¹ Output tokens are summed over the subagent's API calls and include its hidden reasoning. Each
agent also read about 145–170k input tokens (mostly cache), which is about the same for every arm.

Ratios:
- **JSON vs. text** (same full spec): ×3.2 output tokens, ×2.4 wall time, ×5.8 bytes on disk.
  When the JSON is minified it is still 15 KB, against 3.5 KB for the text it converts to.
- **Machine code vs. text** (same reduced spec): ×21 output tokens and ×19 wall time.

Qualitative observations:
- Nothing failed in any arm, so this experiment cannot tell the formats apart on correctness.
  It can only tell them apart on cost.
- The JSON tree removed a class of errors (parse errors) that the text arm did not hit anyway.
- No "false friend" from Rust showed up in arm a: no operators, no `;`, no `return`, no `for`,
  no `&`. The agent used `end`, tail recursion, `list_fold` and `{ r with ... }` correctly the
  first time. With n=1 this is weak evidence. The earlier blind test (step 0006 branch) points the
  same way.
- **Both full-spec agents hit the same language gap.** `list_sort` cannot take a comparator.
  Arm a encoded the sort key as a zero-padded string, `"9999995 word"`, sorted it with
  `list_sort` and decoded it back. Arm b wrote its own merge sort. This cost tokens in both arms.
  It is a language finding, not a format finding.
- The machine-code agent produced a correct, careful program: one RWX `PT_LOAD`, BSS through
  `memsz`, a commented instruction listing. It needed 7× the tokens of the full-spec text program
  for a much smaller task. Its program would be hard to extend or debug, and it targets one OS
  and one CPU only.

## How to verify
```
make core
.dev/0016/accept.sh build/kaizo run apps/wordfreq/main.gp
build/kaizo test apps/wordfreq/main.gp
.dev/0016/gpjson.py check .dev/0016/arm-b/wordfreq.json /tmp/wf.gp && .dev/0016/accept.sh build/kaizo run /tmp/wf.gp
sed 's/#.*//' .dev/0016/arm-c/topword.hex | xxd -r -p > /tmp/topword && chmod +x /tmp/topword && .dev/0016/accept-c.sh /tmp/topword && .dev/0016/fuzz-c.py /tmp/topword
build/kaizo build .dev/0016/arm-a2/topword.gp -o /tmp/tw && .dev/0016/accept-c.sh /tmp/tw && .dev/0016/fuzz-c.py /tmp/tw
```

## Caveats (read before quoting the numbers)
- **n = 1 per arm.** The token counts vary between runs, so a ×3 gap is suggestive, not proven.
  A ×21 gap is probably real.
- **Same model family.** Every agent and the experimenter are Claude Opus 5.5. The experimenter
  wrote the specs, the JSON format and the tests, so wording bias is possible.
- **The task was too easy to separate the arms on correctness.** All arms needed zero rounds, so
  "fix rounds" carries no signal here. The diagnostic path (`gpjson.py` mapping errors to JSON
  paths) was tested, but no agent ever needed it.
- **The JSON format is one design.** A terser encoding (positional arrays, `["ECall", f, args]`)
  would use fewer tokens than named fields. It would still be well above the text, because names
  such as `"k"`, `"let_name"` and `"args"` repeat at every node.
- **Arm c's spec was reduced on purpose**, so compare it only with control a2.
- Models are trained mostly on text code. The result says "text is cheaper for today's LLMs", not
  "text is intrinsically better".

## Recommendation
**Keep text as GPLM's authoring format. Do not add an AST input mode now. Do not pursue direct
binary emission.**
- Text was 3× cheaper than the JSON tree and just as correct. The parse errors a tree format
  prevents did not happen.
- Machine code works for toys, at 20× the cost, and gives up portability (4 targets),
  diagnostics and maintainability.
- A tree format is still worth revisiting if a later, harder blind test shows real parse or
  structure errors in text. Until then, any structured access is better as an *output* of the
  tools than as an input format.
- Fix the gap both agents hit: add a comparator sort, e.g. `list_sort_by(l, fn(a, b) ... end)`,
  where the lambda returns "a goes before b". This is a core change, so it needs its own step.

## Open questions
- Should the next measurement use a harder task (e.g. Snake-sized), n ≥ 3 runs per arm and a
  second model family, so that correctness and fix rounds can differ between formats?
- Should `list_sort_by` go into the language? (Recommended; it is a small core change.)

## Next step
The human decides between: `list_sort_by` (small core step), repeating this experiment at
higher n with a harder task, or the proposals already listed in STATUS.md.
