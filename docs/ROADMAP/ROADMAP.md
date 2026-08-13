# spotlight.nvim — Roadmap

Ideas that did not go into the first version, with the reason. The bar is a real
need, not plausibility: Tier 1 + Tier 2 sit at ~11 commands, and every entry
below would push that up while making the plugin harder to explain.

## Companion documents

Reviews rather than plans, kept beside this file because they are where the
"declined, and here is why" decisions live:

- [Arch&Coding.md](Arch%26Coding.md) — the architecture and coding guidelines,
  section by section. Includes the native-code/FFI evaluation.
- [Zentral-Prinzipien.md](Zentral-Prinzipien.md) — the per-module structural
  review (events, lazy loading, hot paths, debuggability).
- [Checklist.md](Checklist.md) — the PR-review checkbox pass, with a
  declined-items table listing what would have to change to revisit each one.
- [NEOTREE_FEATURES.md](NEOTREE_FEATURES.md) — which mechanisms here are worth
  lifting into `filetree.nvim`.

---

## Table of content

  - [Companion documents](#companion-documents)
  - [Plausible next](#plausible-next)
    - [Quickfix across all loaded buffers](#quickfix-across-all-loaded-buffers)
    - [`count` and `dot`-repeat on the toggle](#count-and-dot-repeat-on-the-toggle)
    - [A `Spotlight.Item` per-slot lock](#a-spotlightitem-per-slot-lock)
    - [`:Spotlight yank`](#spotlight-yank)
  - [Wanted, needs design](#wanted-needs-design)
    - [Spotlight sets](#spotlight-sets)
    - [Occurrence count in the sign column or on the scrollbar](#occurrence-count-in-the-sign-column-or-on-the-scrollbar)
    - [Per-window opt-out](#per-window-opt-out)

---

## Plausible next

Ordered by expected value per line of code.

---

### Quickfix across all loaded buffers

Same idea for `:Spotlight qf`: `qf.fill` already builds quickfix-shaped entries
with an explicit `bufnr`, so multi-buffer output needs no new plumbing — only a
scope argument (`:Spotlight qf all`) and the same size guard.

---

### `count` and `dot`-repeat on the toggle

`3<leader>mK` has no obvious meaning, but `.` after a toggle arguably does
("spotlight this one too"). `lib.nvim.dotrepeat` exists and cascade.nvim already
uses it.

*Open question:* whether repeating a *toggle* is coherent, since the second press
on the same token removes it.

---

### A `Spotlight.Item` per-slot lock

"Keep this one on slot 1 forever" — useful when a specific token has become the
one you always look for. Currently round-robin owns slot assignment.

*Cost:* a `locked` flag on the item, honoured by `used_slots()` and the snapshot.

---

### `:Spotlight yank`

Copy every matching line to a register instead of the quickfix list. Reuses
`count.matching_lines` entirely; the only new decision is which register and
whether to include line numbers.

---

## Wanted, needs design

---

### Spotlight sets

Named groups of spotlights, switched as a unit ("the auth investigation", "the
timeout investigation"). This is the honest answer to several requests above —
per-buffer scope, export/import, and "I have too many spotlights at once" are all
really asking for sets.

*Needs:* a naming and switching UX that does not turn into a second registry, a
persistence shape that stores several sets without breaking the current snapshot
format, and a decision on whether sets are additive or exclusive.

---

### Occurrence count in the sign column or on the scrollbar

A density map — where in the file this token clusters — is genuinely useful on a
long log and is the one thing the current design cannot show, because it would
need positions.

*Needs:* a way to get that without an O(buffer) scan on every change. Possibly a
one-shot scan behind an explicit command (`:Spotlight map`), which keeps the
performance promise intact by making the cost visible and opt-in.

---

### Per-window opt-out

"Do not spotlight in this window" — e.g. a reference file open in a split.
Currently the ledger fills every non-floating window.

*Needs:* a window-local flag, a way to set it, and a decision about what happens
when the window is reused for another buffer.

---

