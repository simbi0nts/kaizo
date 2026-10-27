# Step 0017 — `list_sort_by`: stable sort with a comparator
Date: 2026-10-27
Status: done (ran on a branch as "0013"; renumbered to 0017 and merged in 0018, seed rebuilt on top of reference counting)

## Goal
Step 0012 (format experiment, branch `claude/modest-borg-dac383`) found that both blind agents had to
work around `list_sort` sorting only Int/String: one encoded zero-padded string keys, the other wrote
a merge sort by hand. Add `list_sort_by(l, before)` with `before: Fn(T, T) -> Bool`, stable.

## Decisions (with reasons)
- Runtime builtin (`core/rt/rt.gp`), not prelude. The prelude cannot use `prim_*` intrinsics, and every
  public list operation (`list_push`, `list_cons`, `list_slice`, `list_concat`) copies, so a prelude
  merge sort would be O(n²). The runtime version mirrors `list_sort`: top-down merge sort over
  `prim_list_view` halves (recursion depth log n), tail-recursive merge into a preallocated list.
- `before(a, b)` is a strict "a goes first" predicate (like `lt`). Stability: during the merge an element
  of the right half is taken only if `before(right, left)`, so elements that are not ordered either way
  keep input order. A descending sort is `fn(a, b) gt(a, b) end`, multi-key sorts combine with `or`/`and`.
- Seed refreshed — genuinely required: the whole runtime is compiled into every binary, kaizo included,
  so `make selfhost` (seed-built kaizo vs kaizo-built kaizo) differs as soon as `rt.gp` changes.
  The next generation was checked to be a fixpoint before the seed was replaced
  (`build/kaizo-next` rebuilding itself is byte-identical). The core does not use `list_sort_by`, so the
  old seed could still build it.

## What was done
- `core/rt/rt.gp`: `merge_by`, `sort_by`, `list_sort_by`; `core/program.gp`: builtin entry (arity 2, pure).
- `core/LANGUAGE.md`: documented next to `list_sort`.
- `tests/selftest.gp`: test "list_sort_by: stable, empty, large" — ties keep input order on records,
  empty and one-element lists, descending strings, 10 000 records (100 distinct keys) sorted and stable.
- Seed refreshed.
- `apps/wordfreq` is not on this branch (it lives on the unmerged 0012 branch), so it was not changed here.
  Checked out of tree: replacing `make_key`/`parse_digits`/`decode_key` + `list_sort` in `rank` with
  `list_sort_by(entries, fn(a, b) or(gt(a.count, b.count), and(eq(a.count, b.count), lt(a.word, b.word))) end)`
  passes its 4 unit tests and `.dev/0012/accept.sh build/kaizo run apps/wordfreq/main.gp` (7/7).
  Note: sorting by count alone and relying on stability is not enough there, because the unit test
  "ordering" feeds `rank` entries that are not in word order.

## How to verify
```
make all selfhost e2e
build/kaizo test tests/selftest.gp    # includes "list_sort_by: stable, empty, large"
```

## Open questions
- Step number clash: main has `0012-hex-literals.md`, branch `claude/modest-borg-dac383` has
  `0012-format-experiment.md`. One of them needs renumbering when that branch is merged.

## Next step
When the 0012 format-experiment branch is merged, simplify `apps/wordfreq/main.gp` as above.
Otherwise unchanged: run CI on GitHub; human picks from STATUS.md "Proposed next steps".
