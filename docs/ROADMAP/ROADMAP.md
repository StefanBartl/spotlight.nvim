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

## Table of content

- [Deliberately not built](#deliberately-not-built)
- [Plausible next](#plausible-next)
- [Wanted, needs design](#wanted-needs-design)
- [Rejected](#rejected)

---

## Deliberately not built

These were considered and left out on purpose. Each is listed with what would
have to happen for it to be reconsidered.

### Regex mode

A spotlight is "highlight this exact token". Escaping to `\V` and pinning `\C` is
what makes that reliable, and a regex mode would fork every code path that
currently assumes literal-with-known-escaping — the pattern builder, the
snapshot round trip (which rebuilds the regex from the raw text on purpose), the
counting scan, the `\|` alternation used by navigation.

*Reconsider when:* a concrete use case appears that `:Spotlight add` plus a
manual `matchadd()` cannot cover.

### Scope per buffer / filetype

Spotlights are session-global because that is the model: a request id you spotted
in `app.log` is the same id in `worker.log`. Buffer scoping would defeat the
reason for tracking it, and would need a scope selector on every command.

*Reconsider when:* someone actually keeps two unrelated investigations open at
once. A "spotlight set" concept (see below) is probably the better answer to that
than per-buffer scope.

### Auto-rules (`ERROR`/`WARN` highlighted automatically)

This is what a log syntax file or a filetype plugin is for, and doing it here
would mean a rule engine, a precedence model against manual spotlights, and a
palette-budget question (auto-rules eating slots the user wanted).

*Reconsider when:* never, probably. The right shape is a separate log-syntax
plugin.

### Export / import of sets

Would need a file format, a merge policy, and a story for what "import" does to
the spotlights already active. The persistence layer already covers the actual
need (come back tomorrow, find your work).

*Reconsider when:* sharing an investigation with a colleague becomes a real
workflow rather than a hypothetical one.

---

## Plausible next

Ordered by expected value per line of code.

### Match counts across all loaded buffers

The list currently counts in the current buffer only, which is honest but
narrow — the spotlight itself is global. Counting every loaded buffer would tell
you which file the token actually lives in.

*Cost:* one loop and a per-buffer `count_max_lines` check. *Risk:* the list
becomes slow with many large buffers open; would need to stay opt-in
(`list.count_scope = "buffer"|"loaded"`).

### Quickfix across all loaded buffers

Same idea for `:Spotlight qf`: `qf.fill` already builds quickfix-shaped entries
with an explicit `bufnr`, so multi-buffer output needs no new plumbing — only a
scope argument (`:Spotlight qf all`) and the same size guard.

### `count` and `dot`-repeat on the toggle

`3<leader>mK` has no obvious meaning, but `.` after a toggle arguably does
("spotlight this one too"). `lib.nvim.dotrepeat` exists and cascade.nvim already
uses it.

*Open question:* whether repeating a *toggle* is coherent, since the second press
on the same token removes it.

### A `Spotlight.Item` per-slot lock

"Keep this one on slot 1 forever" — useful when a specific token has become the
one you always look for. Currently round-robin owns slot assignment.

*Cost:* a `locked` flag on the item, honoured by `used_slots()` and the snapshot.

### Statusline component

`lib.nvim.ui.statusline` exists. Showing `3 spotlights` plus the swatch colors
would fit in a handful of lines.

### `:Spotlight yank`

Copy every matching line to a register instead of the quickfix list. Reuses
`count.matching_lines` entirely; the only new decision is which register and
whether to include line numbers.

---

## Wanted, needs design

### Spotlight sets

Named groups of spotlights, switched as a unit ("the auth investigation", "the
timeout investigation"). This is the honest answer to several requests above —
per-buffer scope, export/import, and "I have too many spotlights at once" are all
really asking for sets.

*Needs:* a naming and switching UX that does not turn into a second registry, a
persistence shape that stores several sets without breaking the current snapshot
format, and a decision on whether sets are additive or exclusive.

### Occurrence count in the sign column or on the scrollbar

A density map — where in the file this token clusters — is genuinely useful on a
long log and is the one thing the current design cannot show, because it would
need positions.

*Needs:* a way to get that without an O(buffer) scan on every change. Possibly a
one-shot scan behind an explicit command (`:Spotlight map`), which keeps the
performance promise intact by making the cost visible and opt-in.

### Per-window opt-out

"Do not spotlight in this window" — e.g. a reference file open in a split.
Currently the ledger fills every non-floating window.

*Needs:* a window-local flag, a way to set it, and a decision about what happens
when the window is reused for another buffer.

---

## Rejected

- **Live-updating counts.** Reintroduces the O(file size) scan that choosing
  `matchadd()` over extmarks exists to avoid. This is not a "later" item; it is
  incompatible with the design.
- **Extmark-based highlighting as an option.** Two rendering backends means two
  sets of bugs, and the extmark path is unusable for the target use case anyway.
- **Highlighting inside floating windows.** Floats are transient UI (this
  plugin's own list, completion popups, toasts). Matches painted there outlive
  nothing and only create cleanup work.
