# Architecture

One decision explains almost everything else about this plugin, so it comes
first.

## Table of contents

- [Why matchadd and not extmarks](#why-matchadd-and-not-extmarks)
- [The module tree](#the-module-tree)
- [Two rules that hold throughout](#two-rules-that-hold-throughout)
- [Cross-platform](#cross-platform)
- [Security model](#security-model)
- [Bounded inputs](#bounded-inputs)
- [Tests](#tests)

## Why matchadd and not extmarks

This is the decision the whole plugin is built around, and it is the reason it
stays usable on a log that is too big to open in anything else.

**Extmarks store positions.** Setting them means scanning the buffer — O(file
size) on every add, and again on every text change. On a 200 MB log that is not
a slow path, it is an unusable one.

**`matchadd()` stores the pattern** and hands it to Vim's renderer, which
evaluates it in C over the visible lines only. Cost is proportional to the
window, not to the file. A text change needs no invalidation at all, because
nothing position-shaped was ever stored. There is deliberately no
`TextChanged` and no `CursorMoved` autocommand anywhere in this plugin.

The price is that a match is window-local, so ~30 lines of bookkeeping
(`window -> { spotlight id -> match id }`) plus three window autocommands make
it look global. That trade is the plugin.

Four consequences follow directly, and each looks like a limitation until you
trace it back here:

- **Match counts are computed on demand**, when you open the list, and never
  maintained. Keeping them live would reintroduce exactly the whole-buffer scan
  that choosing `matchadd()` avoided.
- **The occurrence map (`:Spotlight map`) is one-shot**, not live, for the same
  reason: a density map that stayed current would need the invalidation this
  choice exists to avoid.
- **A whole-line highlight ends where the line's text ends.** Extending it to
  the window's right edge needs `line_hl_group`, which is an extmark, which is
  a position.
- **A "this occurrence only" spotlight is session-only.** Its pattern is
  anchored with `\%l`/`\%c`, and a line/column pin does not survive a restart
  the way a text pattern does.

## The module tree

```
plugin/spotlight.lua     load guard (vim.g.loaded_spotlight)

lua/spotlight/
  init.lua               facade: setup + every action
  config/
    DEFAULTS.lua         single source of truth for defaults
    init.lua             deep merge + validation + get("dot.path")
  core/
    pattern.lua          literal token -> Vim regex (\V escaping, \C, boundaries)
    palette.lua          Spotlight1..8, dark/light sets, round-robin slots
    match.lua            the matchadd() ledger: window -> { id -> match id }
    registry.lua         the authoritative spotlight list; the one change event
    count.lua            on-demand counting + the shared line scan
  cursor.lua             token resolver (patterns -> <cword>) and selection reader
  nav.lua                next/prev, "auto" scope narrowing
  qf.lua                 quickfix filter (single buffer and all loaded buffers)
  yank.lua               the same scan, into the unnamed register
  map.lua                sign-column occurrence map
  sets.lua               named snapshots of the registry
  winopt.lua             the per-window opt-out flag
  ui/list.lua            kit.select rich items (color swatch per row)
  persist.lua            store.project + the per-file exception model
  hover.lua              the hover.nvim position preview (soft)
  bindings/
    init.lua             wires the three below, gated by config
    keymaps.lua          the preset, declared through lib.nvim's registry
    usrcmds.lua          the :Spotlight verb, as a composer route tree
    autocmds.lua         window fill, ColorScheme, load/flush
  integrations/
    menu.lua             nvzone/menu entries (soft)
  util/
    lib.lua              guarded lib.nvim bridge (notify/map/autocmd/hl/debounce/logger/dotrepeat)
    path.lua             project-relative file keys (cross-platform)
  health.lua
  @types/init.lua
```

## Two rules that hold throughout

**No module reads a raw options table.** Everything goes through
`config.get("dot.path")`, so there is one place where a value is normalized,
validated and defaulted.

**Every change to the spotlight list funnels through `core/registry.lua`** and
ends in one change event. Persistence subscribes to that event, so no caller
has to remember to trigger a save — which is also why adding a route never
comes with a "and don't forget to persist" step.

## Cross-platform

No shell-outs, no path assumptions. Path keys are normalized to forward
slashes and compared case-insensitively on Windows, where `C:\Repos\x` and
`c:\repos\x` are the same file and would otherwise produce two different
exception keys.

## Security model

Not a claim of hardness — a plugin that highlights text is not a security
boundary — but a statement of what is and is not trusted, so the guards below
have a reason rather than a vibe.

**Nothing is executed, nothing is fetched, nothing is written outside the
cache.** No shell-outs, no `io.*`, no jobs, no network. The only `vim.cmd`
calls are two occurrences of the fixed literal `normal! zz` in `nav.lua`, with
nothing interpolated; the quickfix window is opened through
`lib.nvim.ui.list`, not by composing a command string. The only file written
is the state snapshot, through `lib.nvim.store.project`.

**Regexes cannot backtrack pathologically.** Every pattern handed to Vim is
built by `core/pattern.lua` as `\C\V` plus escaped literal text — no
quantifiers, no groups, no alternation *inside* a branch. So no input, however
crafted, can produce catastrophic backtracking. `\V` (very nomagic) also
reduces escaping to a single character, the backslash, which is why the escape
is one substitution rather than a character class that could fall out of sync
with Vim's magic rules.

**The snapshot is treated as external input.** It is JSON in the cache
directory: writable by anything running as this user, and hand-editable. So
every field is re-validated on load — type, non-empty, length cap, dedup,
count cap, palette slot clamped into range. Crucially the **regex is rebuilt
from `text`**, never read from the file, so a crafted snapshot cannot inject a
pattern.

**Exception keys are data, never paths.** A persisted key like
`../../../etc/passwd` is stored and compared as an opaque table key and JSON
field. The plugin opens no files of its own, so there is nothing for a
traversal to traverse.

**Config values are sanitized, not trusted.** Invalid colors and unparseable
Lua patterns are dropped, numbers are range-checked, and `list.swatch` has
newlines stripped — it is written into a chooser buffer line, where
`nvim_buf_set_lines` treats an embedded newline as a hard error rather than as
two lines.

**No privilege, no elevation, no secrets handled.** Note that spotlighted
tokens *are* persisted to the cache directory by default — if you are reading a
log full of credentials, `:Spotlight persist off` is the switch that keeps them
out of it.

## Bounded inputs

Three limits exist specifically because the size is not the plugin's to
control:

| Guard | Default | Unbounded input it covers |
| --- | --- | --- |
| `match.max_text_len` | 512 | A `v$` on a minified single-line file, or a snapshot field — either would otherwise reach `matchadd()` as a multi-megabyte pattern re-evaluated on every redraw. |
| `cursor.max_line_len` | 8192 | A minified single-line JSON log. The resolver scan is O(line) *per pattern* and a user-supplied Lua pattern may backtrack; above the limit the scan is skipped and `<cword>` answers instead. |
| `quickfix.max_entries` | 10000 | A common token in a large log. Unlike counting, filtering *produces* memory — one entry per matching line, each holding the full line text. Truncation is reported, in the notification and in the list title. |

`map.max_entries` is the same shape for the sign-column map, kept as a separate
value because it caps a second, unrelated scan. `match.max` (64) caps how many
spotlights can be active at once; the palette holds eight, so slot reuse is
normal and exhaustion is not.

## Tests

[`TESTS/`](../TESTS/README.md) — plain headless Neovim, no test framework to
install. The suite asserts that the *ledger* is right (`getmatches()` in each
window, one entry per active spotlight, none left after a clear); whether
`matchadd()` produces the right pixels is Vim's business.
