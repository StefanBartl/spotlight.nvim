# spotlight.nvim — Binding Cheatsheet

Machine-readable overview of every keymap, user command, autocommand and
highlight group defined by `spotlight.nvim`. This file is documentation only and
mirrors the source of truth in `lua/spotlight/bindings/`. Any change there must
be reflected here.

Every mapping binds directly onto a facade action (`require("spotlight").<action>`)
— there is no `<Plug>` indirection. which-key, when installed, only labels the
preset's leader prefix as a group; it does not register the individual keys.

## Keymaps

Bound only when `keymaps.preset = true` (the default). Each `lhs` is its own
config value under `keymaps.*`; setting one to `false` drops just that mapping.

| lhs | mode | action | config key | desc |
| --- | --- | --- | --- | --- |
| `<leader>sk` | n | `toggle_here` | `keymaps.toggle_here` | Toggle a spotlight on **only this occurrence** of the token under the cursor |
| `<leader>sk` | x | `toggle_here_selection` | `keymaps.toggle_here` | Toggle a spotlight on **only this occurrence** of the exact visual selection |
| `<leader>sK` | n | `toggle` | `keymaps.toggle` | Toggle a spotlight on **every occurrence** of the token under the cursor. Dot-repeatable: `.` re-resolves and toggles the token under the cursor at that later moment |
| `<leader>sK` | x | `toggle_selection` | `keymaps.toggle` | Toggle a spotlight on **every occurrence** of the exact visual selection |
| `<leader>sL` | n | `list` | `keymaps.list` | Open the spotlight list (swatch + token + count) |
| `<leader>sC` | n | `clear` | `keymaps.clear` | Remove every spotlight |
| `<leader>sq` | n | `quickfix` | `keymaps.quickfix` | Matching lines → quickfix list |
| `<leader>sW` | n | `line_toggle` | `keymaps.line` | Toggle **whole-line** rendering for the spotlight the token under the cursor belongs to. Refused if that token has no spotlight yet — line mode is a property of one that exists |
| `]k` | n | `next` | `keymaps.next` | Jump to the next occurrence. A count prefix repeats the jump that many times (`3]k` = three one-step jumps, `unimpaired`-style), stopping early rather than erroring if fewer occurrences remain |
| `[k` | n | `prev` | `keymaps.prev` | Jump to the previous occurrence. Same count support as `]k` |

`<leader>sk` / `<leader>sK` are the pair the concept turns on: lowercase marks
only the one occurrence the cursor/selection is on (a new spotlight, pinned to
that exact buffer position — see [FEATURES.md](FEATURES.md#toggle-a-spotlight-on-only-this-occurrence)),
uppercase marks every occurrence of that text, same as before this pair
existed. `<leader>sL`/`<leader>sC` moved off `<leader>sK`/`<leader>s<C-k>` to
free the shifted key for the "every occurrence" toggle.

**No `lhs` above is a prefix of another.** This is deliberate: a mapping that is
also the prefix of a longer one costs a `'timeoutlen'` pause on *every* press.
`<leader>sk` and `<leader>sK` are fine together — `k`/`K` diverge at that very
character, neither extends the other.

Prefix moved from `<leader>m` to `<leader>s` (2026; the letters -- `k`/`K`/`L`/`C`/`q`/`W`
-- are unchanged, only the group changed). `<leader>s` is a busier prefix than
`<leader>m` was: it is already a bare leaf binding in the author's config
(`search.nvim`'s tabbed UI), and carries real bindings at `sh`, `sM`, `sS`, `sT`
plus the two-level `sp` (`spf`/`spg`, pickers.nvim) and a filetree.nvim buffer-local
`sm`. None of those collide with `sk`/`sK`/`sL`/`sC`/`sq`/`sW` -- confirmed against
every sibling plugin repo directly, not just this cheatsheet folder, since several
`<leader>s*` mentions elsewhere turned out to be commented-out/aspirational code
rather than live bindings. Three of the six letters used here have a commented
(inactive) `snacks.lua` picker slot at the exact same chord: `<leader>sk`
(`snacks.picker.keymaps()`), `<leader>sq` (`snacks.picker.qflist()`) and
`<leader>sC` (`snacks.picker.commands()`) -- none currently registered, so there
is no live conflict, but uncommenting any of those three later would silently
shadow (or be shadowed by, depending on load order) the matching spotlight
mapping. `<leader>sw` (lowercase) is a fourth commented slot -- left free here
for the same reason it always was (no narrower counterpart to pair it with),
which also keeps that one clear if it is ever activated.
Also checked against `]`/`[` motions (`]q`, `]l`, `]d`, `]w`).

Living with the bare `<leader>s` leaf binding: every `<leader>s*` mapping,
spotlight's included, waits out `'timeoutlen'` before firing, in case the user
meant the bare prefix. That trade already existed for the ~7 other real
`<leader>s*` bindings before spotlight moved here; this does not introduce it.

`<leader>sW` follows the same lowercase/uppercase rule: whole-line rendering is
the wider, louder of the two ways to show a spotlight, so it takes the shifted
key. `<leader>sw` is deliberately left free rather than given the opposite
meaning — "token only" is not a separate action, it is this one toggled off.

### Right-click context menu

`spotlight.integrations.menu` contributes the normal-mode rows above
(`toggle_here`, `toggle`, `next`, `prev`, `line_toggle`, `quickfix`, `list`,
`clear` — not the `x`-mode `_selection` variants) as entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects. spotlight.nvim has no
dependency on `menu` and never opens a context menu itself — a host
(typically your own `<RightMouse>` dispatcher) composes the entries into
its own menu. See [FEATURES.md](FEATURES.md#right-click-context-menu).
`opts.menu.enable = false` opts out.

## User commands

One verb, built with `lib.nvim.usercmd.composer` — `<Tab>` completion, argument
typing and validation come from the route tree.

| Command | Args | Range | Action | Desc |
| --- | --- | --- | --- | --- |
| `:Spotlight` | — | no | `toggle` | Default route: toggle every occurrence of the token under the cursor |
| `:Spotlight toggle` | `[text]` | yes | `toggle` / `add` / `remove` | Every occurrence: cursor token, `'<,'>` range selection, or explicit `text` |
| `:Spotlight here` | — | yes | `toggle_here` / `toggle_here_at` | Only this occurrence: cursor token, or `'<,'>` range selection |
| `:Spotlight add` | `{text}` | no | `add` | Add a spotlight for the literal `text` |
| `:Spotlight remove` | `{text}` | no | `remove` | Remove the spotlight matching `text` exactly |
| `:Spotlight clear` | — | no | `clear` | Remove every spotlight |
| `:Spotlight list` | `[jump\|remove\|lock\|line] [filter]` | no | `list` / `list_remove` / `list_lock` / `list_line` | Open the list; `remove` deletes on select, `lock` toggles the lock, `line` toggles whole-line rendering. `filter` narrows the list first |
| `:Spotlight next` | — | **yes** | `next` | Jump to the next occurrence. `!` ignores `nav.scope` for that jump |
| `:Spotlight prev` | — | **yes** | `prev` | Jump to the previous occurrence. `!` ignores `nav.scope` for that jump |

### `!` on next/prev, and the list filter (2026-08-24)

**`:Spotlight! next` / `! prev` search every spotlight**, whatever
`nav.scope` says. With `scope = "auto"` the whole point is that `]k` follows
the token under the cursor — which is right until the moment you want the
opposite, and the only way out was editing the config and reloading. The flag
is **per call**, not a mode: the next plain jump narrows again.

**`:Spotlight list [action] [filter]`** narrows the list before showing it.
Once several spotlights are active, `remove` mode over twenty entries is a
scroll rather than a choice.

One filter argument rather than separate `--color`/`--origin` flags: the
fields never collide in practice, so a single token answers both questions.
It matches the palette slot, the highlight group (`Spotlight3`), the origin
path, and the spotlight's own text.

A **numeric** query is only ever a slot query, with no substring fallback —
otherwise `1` would also match slot 10, via the `1` in its own highlight
group name `Spotlight10`, undoing the exact test. Everything else is plain
substring, case-insensitive.
| `:Spotlight qf` | `[text]` | no | `quickfix` | Matching lines in the current buffer → quickfix (all, or just `text`'s) |
| `:Spotlight qf all` | `[text]` | no | `quickfix_all` | Same, across every loaded buffer, merged into one list |
| `:Spotlight yank` | `[text]` | no | `yank` | Matching lines in the current buffer → unnamed register (all, or just `text`'s) |
| `:Spotlight line` | `[text]` | no | `line_toggle` | Toggle whole-line rendering for a spotlight (`text`, or the cursor token) |
| `:Spotlight lock` | `[text]` | no | `lock_toggle` | Toggle whether a spotlight keeps its palette slot permanently (`text`, or the cursor token) |
| `:Spotlight map` | `[text]` | no | `map` | Mark every matching line in the sign column (all spotlights, or just `text`'s) |
| `:Spotlight map clear` | — | no | `map_clear` | Clear the sign-column occurrence map in the current buffer |
| `:Spotlight sets save` | `{name}` | no | `sets_save` | Save the active spotlights as a named set (overwrites) |
| `:Spotlight sets switch` | `{name}` | no | `sets_switch` | Clear the active spotlights and restore a saved set |
| `:Spotlight sets delete` | `{name}` | no | `sets_delete` | Delete a saved set (active spotlights untouched) |
| `:Spotlight sets list` | — | no | `sets_list` | List every saved set and how many spotlights it holds |
| `:Spotlight winopt` | `[on\|off\|toggle\|status]` | no | `winopt_set` / `winopt_toggle` / `winopt_status` | Per-window opt-out; no arg = `toggle` |
| `:Spotlight persist` | `[on\|off\|default\|status]` | no | `persist_set` / `persist_status` | Per-file persistence override; no arg = `status` |
| `:Spotlight refresh` | — | no | `refresh` | Redefine the palette, re-apply every match |

Every keymap action has a command and vice versa: no feature exists only on a key.

## Autocommands

All idempotent — their augroups are cleared on every `setup()`. There is
deliberately **no `TextChanged` and no `CursorMoved`** handler anywhere: a
pattern-based highlight needs no invalidation when the text moves, and that is
the whole reason `matchadd()` was chosen over extmarks.

| Group | Event(s) | Pattern | Purpose |
| --- | --- | --- | --- |
| `spotlight_windows` | `WinNew`, `BufWinEnter`, `TabNewEntered` | `*` | Apply every active spotlight to windows that have none yet. `matchadd()` is window-local, so this is what makes the marking look global. All three are needed: `WinNew` for a `:split`, `BufWinEnter` for a buffer shown in an existing window, `TabNewEntered` for a tab created with its window already in place. Deferred one tick, because on `WinNew` the new window is not yet current. |
| `spotlight_windows` | `WinClosed` | `*` | Drop the closed window's ledger entry. The matches died with the window, so `matchdelete()` on those ids would only fail. |
| `spotlight_windows` | `BufWipeout`, `BufDelete` | `*` | Drop every "this occurrence only" spotlight pinned to the buffer that just disappeared. |
| `spotlight_highlights` | `ColorScheme` | `*` | Redefine `Spotlight1..8`. A colorscheme clears highlight groups it does not know about. Gated by `palette.reapply_on_colorscheme`. |
| `spotlight_highlights` | `OptionSet` | `background` | Switch between `palette.colors` and `palette.colors_light`. |
| `spotlight_persist` | `VimEnter` | `*` | Load the persisted snapshot, once. Not called directly from `setup()`: a session or `:cd` plugin may not have settled the project root yet, and the store is keyed by it. Gated by `persist.enable`. |
| `spotlight_persist` | `VimLeavePre` | `*` | Flush a pending debounced save, so the last toggle before `:qa` is not the one lost. Gated by `persist.enable`. |

## Highlight groups

Defined by `setup()` and re-defined on `ColorScheme` / `OptionSet background`.
Configure them via `palette.colors` / `palette.colors_light` — redefining a group
yourself would be overwritten by the next `ColorScheme`.

| Group | Dark bg/fg | Light bg/fg | Note |
| --- | --- | --- | --- |
| `Spotlight1` | `#ffd75f` / `#1c1c1c` | `#b58900` / `#ffffff` | yellow |
| `Spotlight2` | `#87d7ff` / `#1c1c1c` | `#268bd2` / `#ffffff` | cyan |
| `Spotlight3` | `#ff87d7` / `#1c1c1c` | `#d33682` / `#ffffff` | pink |
| `Spotlight4` | `#a8e22e` / `#1c1c1c` | `#587a00` / `#ffffff` | green |
| `Spotlight5` | `#ffaf5f` / `#1c1c1c` | `#cb4b16` / `#ffffff` | orange |
| `Spotlight6` | `#b48eff` / `#ffffff` | `#6c4bb6` / `#ffffff` | purple |
| `Spotlight7` | `#5fd7af` / `#1c1c1c` | `#2aa198` / `#ffffff` | teal |
| `Spotlight8` | `#ff5f5f` / `#ffffff` | `#dc322f` / `#ffffff` | red |

Each sets both `bg` **and** `fg` (plus `bold`, per `palette.bold`), so contrast
is guaranteed in either theme rather than inherited from the colorscheme.

## Facade actions

Every action, for binding your own keys with `keymaps.preset = false`.

| Function | Mode | Returns | Desc |
| --- | --- | --- | --- |
| `require("spotlight").toggle()` | n | `boolean` | Toggle every occurrence of the resolved token under the cursor |
| `require("spotlight").toggle_selection()` | x | `boolean` | Toggle every occurrence of the exact visual selection (literal) |
| `require("spotlight").toggle_here()` | n | `boolean` | Toggle only this occurrence of the resolved token under the cursor |
| `require("spotlight").toggle_here_selection()` | x | `boolean` | Toggle only this occurrence of the exact visual selection |
| `require("spotlight").toggle_here_at(text, pos)` | any | `boolean` | Toggle only the occurrence at an explicit `{ buf, row1, col1 }` |
| `require("spotlight").add(text)` | any | `boolean` | Add a spotlight for a literal string |
| `require("spotlight").remove(text)` | any | `boolean` | Remove by exact text |
| `require("spotlight").clear()` | any | `boolean` | Remove every spotlight |
| `require("spotlight").list()` | n | `nil` | Open the list; selection jumps |
| `require("spotlight").list_remove()` | n | `nil` | Open the list; selection removes |
| `require("spotlight").list_lock()` | n | `nil` | Open the list; selection toggles the lock |
| `require("spotlight").list_line()` | n | `nil` | Open the list; selection toggles whole-line rendering |
| `require("spotlight").next()` | n | `boolean` | Next occurrence |
| `require("spotlight").prev()` | n | `boolean` | Previous occurrence |
| `require("spotlight").quickfix(text?)` | n | `boolean` | Matching lines in the current buffer → quickfix |
| `require("spotlight").quickfix_all(text?)` | n | `boolean` | Same, across every loaded buffer |
| `require("spotlight").yank(text?)` | any | `boolean` | Matching lines in the current buffer → unnamed register |
| `require("spotlight").lock_set(text, value)` | any | `boolean` | Set the slot lock for the spotlight matching `text` exactly |
| `require("spotlight").lock_toggle(text?)` | any | `boolean` | Toggle the slot lock for `text`, or the cursor token |
| `require("spotlight").line_set(text, value)` | any | `boolean` | Set whole-line rendering for the spotlight matching `text` exactly |
| `require("spotlight").line_toggle(text?)` | any | `boolean` | Toggle whole-line rendering for `text`, or the cursor token |
| `require("spotlight").sets_save(name)` | any | `boolean` | Save the active spotlights as a named set (overwrites) |
| `require("spotlight").sets_switch(name)` | any | `boolean` | Clear the active spotlights and restore a saved set |
| `require("spotlight").sets_delete(name)` | any | `boolean` | Delete a saved set |
| `require("spotlight").sets_list()` | any | `nil` | Report every saved set and its spotlight count |
| `require("spotlight").map(text?)` | any | `boolean` | Mark every matching line in the sign column |
| `require("spotlight").map_clear()` | any | `boolean` | Clear the sign-column occurrence map |
| `require("spotlight").winopt_set(value, win?)` | any | `boolean` | Set the per-window opt-out |
| `require("spotlight").winopt_toggle(win?)` | any | `boolean` | Toggle the per-window opt-out |
| `require("spotlight").winopt_status(win?)` | any | `nil` | Report whether spotlighting is on in `win` |
| `require("spotlight").persist_set(v)` | any | `boolean` | `true`/`false`/`nil` override for the current file |
| `require("spotlight").persist_status()` | any | `nil` | Report the effective persistence status |
| `require("spotlight").refresh()` | any | `nil` | Redefine palette + re-apply every match |
| `require("spotlight").spotlights()` | any | `Spotlight.Item[]` | The live registry |

## Global variables

| Variable | Purpose |
| --- | --- |
| `vim.g.loaded_spotlight` | Load guard. Set it to `1` before the plugin is sourced to disable it entirely. |
