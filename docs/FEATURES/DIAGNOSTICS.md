# Diagnostics

What the plugin tells you about itself. For symptoms and what to do about
them, start at [troubleshooting.md](../troubleshooting.md).

## `:checkhealth spotlight`

Reports the Neovim version, `'termguicolors'`, each `lib.nvim` module's
availability separately (a missing `usercmd.composer` and a missing
`debounce` are different problems), every config value that failed
validation and what it fell back to, the resolved match/cursor/list/map/keymap
settings, and live state — active spotlights with their slots, how many
windows carry matches, the project root, saved sets, and every per-file
persistence override.

Section by section, and what each warning means, is in
[health.md](../health.md).

- **Module:** `health.lua`

## Debug logging

`debug = true` logs exactly the four decisions that answer "why did nothing
light up": which cursor-resolver pattern won and its index, which windows the
match ledger applied to or skipped (and any `matchadd()` rejection), what the
persisted snapshot filter kept and dropped, and whether navigation narrowed to
one spotlight or searched them all. Routed through `lib.nvim.logger` when
available (one `spotlight` instance, inspectable with `:LibLogger`), falling
back to `vim.notify` at DEBUG level otherwise. With `debug = false` a log call
costs one table lookup.

- **Module:** `util/lib.lua` (`M.debug`)
- **Config:** `debug` (default `false`)

## `:Spotlight refresh`

Redefines the palette and re-applies every spotlight to every window from
scratch — the escape hatch for the one thing `matchadd()` cannot do (update a
match in place), and the fix if another plugin has cleared the current
window's matches with `:call clearmatches()`. There is no autocommand that
detects the second case, because `clearmatches()` notifies nobody; this is a
manual command by necessity, not by preference.

- **Module:** `init.lua` (`M.refresh`)
- **Usercmds:** `:Spotlight refresh`

## Bounded, non-throwing configuration

Invalid config values are degraded to their defaults rather than raising an
error: a malformed color or an unparseable Lua pattern is dropped, every
other setting still applies, and `:checkhealth spotlight` lists exactly what
was rejected. One bad line should not stop the plugin from loading.

Numeric limits (`match.max_text_len`, `cursor.max_line_len`,
`quickfix.max_entries`) are enforced as hard caps rather than advisory
defaults, so no single crafted or oversized input can turn a highlight or a
quickfix fill into a multi-second stall. Why each of the three exists is in
[architecture.md](../architecture.md#bounded-inputs).

- **Module:** `config/init.lua`
