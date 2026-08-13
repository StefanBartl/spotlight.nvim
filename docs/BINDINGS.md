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
| `<leader>mk` | n | `toggle_here` | `keymaps.toggle_here` | Toggle a spotlight on **only this occurrence** of the token under the cursor |
| `<leader>mk` | x | `toggle_here_selection` | `keymaps.toggle_here` | Toggle a spotlight on **only this occurrence** of the exact visual selection |
| `<leader>mK` | n | `toggle` | `keymaps.toggle` | Toggle a spotlight on **every occurrence** of the token under the cursor. Dot-repeatable: `.` re-resolves and toggles the token under the cursor at that later moment |
| `<leader>mK` | x | `toggle_selection` | `keymaps.toggle` | Toggle a spotlight on **every occurrence** of the exact visual selection |
| `<leader>mL` | n | `list` | `keymaps.list` | Open the spotlight list (swatch + token + count) |
| `<leader>mC` | n | `clear` | `keymaps.clear` | Remove every spotlight |
| `<leader>mq` | n | `quickfix` | `keymaps.quickfix` | Matching lines → quickfix list |
| `]k` | n | `next` | `keymaps.next` | Jump to the next occurrence. A count prefix repeats the jump that many times (`3]k` = three one-step jumps, `unimpaired`-style), stopping early rather than erroring if fewer occurrences remain |
| `[k` | n | `prev` | `keymaps.prev` | Jump to the previous occurrence. Same count support as `]k` |

`<leader>mk` / `<leader>mK` are the pair the concept turns on: lowercase marks
only the one occurrence the cursor/selection is on (a new spotlight, pinned to
that exact buffer position — see [FEATURES.md](FEATURES.md#toggle-a-spotlight-on-only-this-occurrence)),
uppercase marks every occurrence of that text, same as before this pair
existed. `<leader>mL`/`<leader>mC` moved off `<leader>mK`/`<leader>m<C-k>` to
free the shifted key for the "every occurrence" toggle.

**No `lhs` above is a prefix of another.** This is deliberate: a mapping that is
also the prefix of a longer one costs a `'timeoutlen'` pause on *every* press.
`<leader>mk` and `<leader>mK` are fine together — `k`/`K` diverge at that very
character, neither extends the other.

Collision-checked against the existing `<leader>m*` group in the author's config
(`<leader>man`, `<leader>ms`, `<leader>mc`, `<leader>mn*`, `<leader>ml*`,
`<leader>mv*`) and against `]`/`[` motions (`]q`, `]l`, `]d`, `]w`).

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
| `:Spotlight list` | `[jump\|remove\|lock]` | no | `list` / `list_remove` / `list_lock` | Open the list; `remove` deletes on select, `lock` toggles the lock on select |
| `:Spotlight next` | — | no | `next` | Jump to the next occurrence |
| `:Spotlight prev` | — | no | `prev` | Jump to the previous occurrence |
| `:Spotlight qf` | `[text]` | no | `quickfix` | Matching lines in the current buffer → quickfix (all, or just `text`'s) |
| `:Spotlight qf all` | `[text]` | no | `quickfix_all` | Same, across every loaded buffer, merged into one list |
| `:Spotlight lock` | `[text]` | no | `lock_toggle` | Toggle whether a spotlight keeps its palette slot permanently (`text`, or the cursor token) |
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
| `require("spotlight").next()` | n | `boolean` | Next occurrence |
| `require("spotlight").prev()` | n | `boolean` | Previous occurrence |
| `require("spotlight").quickfix(text?)` | n | `boolean` | Matching lines in the current buffer → quickfix |
| `require("spotlight").quickfix_all(text?)` | n | `boolean` | Same, across every loaded buffer |
| `require("spotlight").lock_set(text, value)` | any | `boolean` | Set the slot lock for the spotlight matching `text` exactly |
| `require("spotlight").lock_toggle(text?)` | any | `boolean` | Toggle the slot lock for `text`, or the cursor token |
| `require("spotlight").persist_set(v)` | any | `boolean` | `true`/`false`/`nil` override for the current file |
| `require("spotlight").persist_status()` | any | `nil` | Report the effective persistence status |
| `require("spotlight").refresh()` | any | `nil` | Redefine palette + re-apply every match |
| `require("spotlight").spotlights()` | any | `Spotlight.Item[]` | The live registry |

## Global variables

| Variable | Purpose |
| --- | --- |
| `vim.g.loaded_spotlight` | Load guard. Set it to `1` before the plugin is sourced to disable it entirely. |
