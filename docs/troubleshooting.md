# Troubleshooting

The only question this plugin ever really gets asked is *"why did nothing
light up"*. This page starts there, and the answer is almost never a bug.

For what the health check's output means line by line, see
[health.md](health.md). For what to type while you are actually reading a log,
see [WORKFLOW.md](WORKFLOW.md).

## Turn on the four decisions first

```lua
require("spotlight").setup({ debug = true })
```

`debug = true` logs exactly the four decisions that can produce "nothing
happened", and each one names a different cause:

- **Which resolver pattern won**, with its index — a surprising token almost
  always means a broader pattern sits ahead of the specific one you expected.
  See [configuration.md](configuration.md#token-resolution).
- **Which windows the ledger applied to or skipped**, and any `matchadd()` call
  Vim rejected — the one way a spotlight can silently fail to appear.
- **What the snapshot filter kept and dropped** — the answer to "my spotlights
  did not come back".
- **Whether navigation narrowed to one spotlight or searched them all** — the
  entire behavioral difference of `]k`, and invisible from the outside.

Logs go through `lib.nvim.logger` (one `spotlight` instance, inspectable with
`:LibLogger`), falling back to `vim.notify` at DEBUG level when that is not
installed. With `debug = false` a log call costs one table lookup, so leaving
the switch in your config is free.

## Symptoms

### Nothing lights up when I press the key

Check, in this order:

1. `:checkhealth spotlight` — a **required** `lib.nvim` module missing is
   reported as an error there, and the keymap preset line says which `lhs` is
   actually bound.
2. Does `:Spotlight` (the bare command) work? If it does, the problem is the
   keymap, not the plugin — most likely another mapping owns that `lhs`.
3. `debug = true`, then look at the resolver line. On a token the resolver
   never sees as one token, `:Spotlight add {text}` is the direct route.

### The spotlight covers more, or less, than the token I pointed at

`cursor.patterns` is searched **in order**, and the first pattern whose match
spans the cursor column wins — so a broad pattern placed early shadows every
specific one after it. The debug log names the winning pattern and its index.

An explicit visual selection bypasses the resolver entirely and is always
literal, with no word boundaries. If a spotlight matches inside longer words
when you did not expect it, check whether it came from a selection.

### One of my colors vanished

Two causes, and `:checkhealth spotlight` tells them apart in its state
section:

- A spotlight marked `[whole line, priority N]` renders one priority **below**
  the others, and a whole-line highlight covers every token highlight on its
  line. That is deliberate — at equal priority the line color would swallow
  the token colors of every spotlight sharing that line.
- `'termguicolors'` is off, so two slots have collapsed onto the same
  approximated terminal color.

### The highlighting broke after a colorscheme change, or all at once

`:Spotlight refresh` redefines the palette and re-applies every match to every
window from scratch. It covers both cases:

- A colorscheme switch left `Spotlight1..8` undefined or wrong. This should be
  automatic via the `ColorScheme` autocommand, but a colorscheme plugin that
  fires events unusually can slip past it.
- Another plugin called `:call clearmatches()` in the current window and wiped
  every `matchadd()` id, spotlight's included.

There is no autocommand for the second case — `clearmatches()` notifies nobody
— so `refresh` is a manual command by necessity, not by preference.

### My spotlights did not come back after a restart

- `<leader>sk` ("this occurrence only") spotlights are **session-only** by
  design: a line/column pin does not survive a restart the way a text pattern
  does.
- `:Spotlight persist status` reports what applies to the current file and
  why. A per-file `off` override persists across restarts, which is the point
  of it — `:Spotlight persist default` drops it.
- The snapshot is keyed by **git root**. Opening the same files from outside a
  repository, or from a different checkout, is a different key.
- `debug = true` logs what the snapshot filter kept and dropped on load.

### The count in the list shows `?`, or `N+`

`?` means the buffer is above `list.count_max_lines` (200000 by default) and
was not scanned at all — "we did not look" is deliberately not reported as a
confident `0`.

`N+` is a lower bound, and only appears with `list.count_scope = "loaded"`: at
least one buffer in the sum was individually too large to scan, so it was
skipped rather than making the whole count unknown.

### `:Spotlight qf` refuses to run

Run it from the buffer you want to filter, not from the quickfix window. After
a fill, focus is handed back to the filtered buffer precisely so that pressing
the key again from muscle memory does not try to filter the quickfix window
into itself.

### A window shows no spotlights while the others do

`:Spotlight winopt status`. The opt-out flag lives on the **window**, not the
buffer, so it survives that window later showing something else.
