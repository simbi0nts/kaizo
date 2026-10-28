# Kaizo / GPLM — long-term roadmap (proposal, 2026-10-27)

Where we are (step 0015): self-hosted native compiler in GPLM (no host language), 4 targets
(Linux verified; Windows/macOS built and structurally verified, not yet run), compiler-inferred
reference counting, libs (http, map, rand, sha256, snake, x11), terminal + GUI Snake, web server,
3D demo. Language: dynamic types with static checks (names, arity, exhaustiveness, effects).
Evidence for the theory so far: 2 blind tests (v1: 0 fix rounds; v2 pending).

The theory being tested (specs.md): an LLM-first language lets humans stay out of code and review.
So every phase ends with a *measurement*, not just features.

## Direction (2026-10-28, after steps 0023–0028): a token-optimized, general-purpose tool for agents
Goal set by the user: one toolchain an AI agent uses for backend, frontend, low-level and high-level
apps, optimized for **token usage**. Human readability is not a criterion; syntax is chosen only by
measured agent cost (tokens per task, first-try error rate, fix rounds).

Evidence that drives the order (0023–0028): vs Python, GPLM costs 1.17–1.44x total tokens and
1.26–1.5x program size; the reference adds ~6k prompt tokens per task; every Haiku GPLM error was a
familiar habit the call-only syntax rejects (`==`, inline `if` without `end`, `OPS`).

Gate for every step: evals with ≥3 runs per spec (evals/variance.py); target ≤ Python on total tokens
and on first-try correctness. Milestones, in order:
- **T1 Lean syntax** — infix operators (desugared to the existing builtins), loops over
  ranges/lists, char literals, string interpolation, method-call style; each measured.
- **T2 Lean reference** — core LANGUAGE.md ≤ ~1.5k tokens; `kaizo doc <name>` / `kaizo api` give
  signatures on demand, so libraries add no prompt tokens until used.
- **T3 Lean repair loop** — one-line JSON diagnostics with a suggested fix; agents re-send only the
  changed function, not the whole file.
- **T4 Frontend: wasm32 target** — code generator + tiny JS loader with DOM bindings (`libs/dom`);
  test app: a browser UI talking to a GPLM backend.
- **T5 General-purpose libraries** — json, http client/server, storage, floats, time; low-level:
  raw memory/FFI behind an effect.
- **T6 Full-stack eval** — the same app (backend + frontend) built by agents in GPLM vs
  Python+TypeScript, compared on tokens and correctness.
Phases 3–6 below remain valid; their items are pulled in by these milestones.

## Phase 0 — Consolidate — done (0016–0019; CI green on all four targets)
- Push to GitHub, make CI green on real Windows/macOS runners; fix what they find.
- Resolve open branches: 0006 (blind test v1), list_sort_by (renumber, rebuild seed), blind test v2 results.
- Step-numbering protocol for parallel agents (reserve a number in STATUS.md before starting, or use
  `NNNN-branch` ids) — two sessions already collided on 0013.
Exit: CI green on 4 targets; one linear history; no orphan branches.

## Phase 1 — Make the checker catch what LLMs get wrong — done (0020–0022)
- Static type checker with inference: generics, records, ADTs, `Fn` types **with effects**
  (closes the handler-effect hole), no annotations beyond today's signatures.
- Consequences: runtime type errors become compile errors; RC skips Int values (speed); better hints.
- Source positions for errors inside builtins; `kaizo check --json` stable schema for agent repair loops.
Exit: in blind tests, 0 errors that reach run time and that a type checker could have caught.

## Phase 2 — Measure the theory (continuous)
- `kaizo eval`: a benchmark of ~20 app specs (CLI, data processing, web API, game, GUI) with hidden
  acceptance tests; fresh agents implement them in GPLM and in a baseline language (Python/TypeScript).
- Metrics: tokens, fix rounds, defects found by hidden tests, time to green; tracked per step in CI.
- Use the data for language decisions: text vs AST input, familiar vs unfamiliar syntax, which
  builtins are missing, which diagnostics fail to guide the agent.
Exit: a dashboard showing GPLM vs baseline over time; every language change cites eval results.

## Phase 3 — Libraries as shared assets (Theory 1, part 2)
- Content-addressed libraries: lockfile pinning each import by hash; `kaizo lib add/update/verify`.
- Distribution: git-based registry so agents on different machines share libraries safely.
- Standard libraries: json, http client (needs `tcp_connect`), paths, time/dates, text formatting,
  collections (set, sorted map), testing helpers (property tests). Test project 2b: mini text browser.
Exit: three apps share ≥ 3 libraries via the lockfile; an update to a library cannot silently change an app.

## Phase 4 — Platform and performance
- Numbers: IEEE floats or a decimal/fixed library (graphics and data code are noisy today).
- GUI on Windows (user32/gdi32) and macOS (Cocoa through objc_msgSend) behind one `libs/gui` API.
- Concurrency for servers: structured concurrency expressed as an effect (no shared mutable state).
- Codegen: register allocation, inline allocation fast path, in-place reuse for unique lists,
  smaller binaries. Target: self-compile < 0.3 s, hello-web ≥ 10k req/s.
Exit: the same GUI app runs on all three OSes; servers handle concurrent clients.

## Phase 5 — Agent-native tooling
- Structured editing: AST-level edit operations as an alternative to text (decided by Phase 2 data).
- Query API for agents: definition, type, callers, effects of a name (JSON).
- Incremental compilation and test selection (only re-run what a change can affect).
- Spec → tests → code workflow as a first-class command (the human writes the spec only).
Exit: an agent completes a multi-file change using queries + structured edits with fewer tokens than text.

## Phase 6 — Real software, built only by agents
- Larger projects that stress the design: a web app with persistent storage, a 2D game engine on
  libs/gui, a data pipeline; the compiler itself keeps evolving in GPLM.
- Human role reduced to concept and UI/UX review (the specs.md goal); track every human code edit
  as a defect of the process.
Exit: a non-trivial app (≥ 5k lines) shipped with zero human-written or human-reviewed code.

## Cross-cutting
- Trust: re-derive the seed from a tiny hand-checked binary (stage0-style), reproducible builds in CI.
- Security: capability-style effects for libraries (a lib cannot do `net` unless the app grants it).
- Docs: LANGUAGE.md stays the single source an agent needs; every step updates it.

## Suggested order for the next steps
0016–0019 Phase 0 (done) · 0020–0022 type checker (done) · 0023 `kaizo eval` harness · then alternate
measurement (Phase 2) with one feature track at a time (3 → 4 → 5).
