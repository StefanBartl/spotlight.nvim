# Rendering a spotlight

Colors, slots, and what makes a window-local `matchadd()` look global. The
reason it is `matchadd()` at all is in [architecture.md](../architecture.md).

## Auto-color palette

Eight `Spotlight1`..`Spotlight8` highlight groups, each with an explicit
background **and** foreground so contrast is the plugin's property rather than
inherited from the colorscheme. Setting only a background is the usual
mistake: the foreground then comes from whatever the colorscheme left there,
which is how a perfectly readable marker becomes yellow-on-yellow after
`:colorscheme`.

Slots are handed out round-robin from the last one assigned, but skip a slot
that is already in use as long as any slot is free, so two unrelated
spotlights don't end up wearing the same color. Plain round-robin would
happily hand out a color already on screen while three others sit unused, and
two identically colored spotlights are exactly the confusion the palette
exists to prevent.

Separate dark/light color lists switch automatically with `'background'`, and
every group is redefined on `ColorScheme` (a colorscheme clears groups it does
not know about). Configure them through `setup()` rather than by redefining
`SpotlightN` afterwards; a `ColorScheme` event would overwrite the latter.

`'termguicolors'` should be on. Without it the hex values are approximated to
the terminal's 256-color cube and slots get harder to tell apart;
`:checkhealth spotlight` warns about it.

- **Module:** `core/palette.lua` (`M.apply`, `M.next_slot`, `M.clamp`)
- **Config:** `palette.colors`, `palette.colors_light`, `palette.bold`
  (default `true`), `palette.reapply_on_colorscheme` (default `true`)
- **Autocmds:** `ColorScheme`, `OptionSet background` — see
  [autocommands](../BINDINGS.md#autocommands)

## Locking a palette slot

A spotlight can lock its slot — "keep this one on slot 1 forever", for a
token that has become the one you always look for. A locked slot is skipped
by round-robin the same way an in-use one is, but it stays skipped even once
every other slot fills up and reuse becomes unavoidable: it is never handed
to a *different* spotlight, only ever kept by the one that locked it.
Locking doesn't move a spotlight to a new slot, it just stops the one it
already has from being taken later. The lock survives persistence (it is
part of the stored snapshot) and is reachable from the list
(`:Spotlight list lock`) or directly (`:Spotlight lock [text]`).

- **Module:** `core/registry.lua` (`M.set_locked`), `core/palette.lua`,
  `ui/list.lua` (`"lock"` mode)
- **Keymaps:** none — command/list only, to avoid keymap sprawl for an
  occasional action
- **Usercmds:** `:Spotlight lock [text]`, `:Spotlight list lock`

## Applied in every window

`matchadd()` is window-local, so a roughly 30-line ledger
(`window -> { spotlight id -> match id }`) plus three window autocommands make
a spotlight look global: new splits, buffers shown in an existing window, and
new tabs are all filled automatically, and a closed window's ledger entry is
dropped rather than cleaned up with `matchdelete()` (the match already died
with the window).

- **Module:** `core/match.lua`, `bindings/autocmds.lua`
- **Autocmds:** `WinNew`, `BufWinEnter`, `TabNewEntered`, `WinClosed` — see
  [autocommands](../BINDINGS.md#autocommands)

## Per-window opt-out

A window can opt out of this entirely — "do not spotlight in this window",
e.g. a reference file kept open in a split. The flag lives on the window
itself (`vim.w[win].spotlight_disabled`), not on whichever buffer happened
to be showing when it was set, so it is window-sticky: it survives that
window later showing a different buffer, since the same `BufWinEnter` fill
pass that already runs on every buffer switch re-checks the flag for free.
Opting out strips the window's current matches immediately rather than only
gating future fills; opting back in re-fills it immediately the same way.

- **Module:** `winopt.lua`, `core/match.lua` (`eligible`, `M.clear_window`)
- **Usercmds:** `:Spotlight winopt [on|off|toggle|status]`

## Whole-line highlighting

`<leader>sW` (or `:Spotlight line [text]`) switches one spotlight from
"color the token" to "color the whole line the token sits on" — for the case
where the interesting unit is the log entry, not the id inside it. It is a
per-spotlight toggle, so one spotlight can paint its lines while the others
stay on their tokens.

Implemented as a **rendering flag**, not as a different pattern.
`Spotlight.Item.pattern` remains the token pattern; only the string handed to
`matchadd()` is widened, by `core/pattern.lua`'s `M.line` — `\_^\.\*` … `\.\*\_$`
around the pattern, using the `\_`-prefixed anchors because plain `^`/`$` are
special only at the very start/end of a pattern and here they sit next to the
pattern's own `\C\V` prefix. That split is what keeps every other consumer
honest: the match count still counts occurrences rather than lines, the
quickfix and yank scans still report the token's own column, and the
occurrence map's earliest-column tie-break still works — a line pattern would
always match at column 1 and collapse it.

The widened match is registered **one priority below** `match.priority`. A
whole-line highlight covers every token highlight on its line, and the palette
exists precisely so several spotlights stay apart; at equal priority the line
color would swallow the token colors of every other spotlight sharing that
line. `:checkhealth spotlight` reports the effective priority per line-mode
spotlight, since "my color vanished" is the one confusing symptom this can
produce.

Two limits are inherent to the `matchadd()` choice rather than oversights:
the highlight ends where the line's text ends (it does not extend to the
window's right edge — that needs `line_hl_group`, which is an extmark, which
is a position, which is what the whole plugin avoids storing), and two
line-mode spotlights on the *same* line resolve to one winner rather than
blending.

Works on a "this occurrence only" spotlight too — the position atoms
`\%l`/`\%c` are zero-width, so the leading `.*` simply walks up to them and the
whole line of *that one* occurrence lights up. Since such a spotlight has no
text identity, it is reached through `:Spotlight list line` rather than
`:Spotlight line {text}`. The flag is persisted (unlike a position pin, it
means the same thing after a restart) and shown as `(whole line)` in the list.

- **Module:** `core/pattern.lua` (`M.line`), `core/match.lua` (the one place it
  is applied), `core/registry.lua` (`M.set_line`), `init.lua` (`M.line_set`,
  `M.line_toggle`, `M.list_line`)
- **Keymaps:** `<leader>sW` (normal mode) — no visual counterpart: the action
  needs a spotlight that already exists, which a selection cannot resolve to
- **Usercmds:** `:Spotlight line [text]`, `:Spotlight list line`
- **Config:** `keymaps.line` (default `<leader>sW`)
