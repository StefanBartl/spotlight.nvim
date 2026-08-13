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
  - [Wanted, needs design](#wanted-needs-design)
    - [Occurrence count in the sign column or on the scrollbar](#occurrence-count-in-the-sign-column-or-on-the-scrollbar)
    - [Per-window opt-out](#per-window-opt-out)

---

## Wanted, needs design

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

