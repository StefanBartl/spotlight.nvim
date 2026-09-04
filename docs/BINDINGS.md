# spotlight.nvim — Binding Cheatsheet

Every keymap, user command, autocommand and highlight group defined by
`spotlight.nvim`, at a glance. This file is documentation only and mirrors the
source of truth in `lua/spotlight/bindings/`; any change there must be
reflected here.

Where a line needs more than one line of explanation, it lives elsewhere:
[commands.md](commands.md) for the `:Spotlight` routes, [api.md](api.md) for
the facade functions, [configuration.md](configuration.md) for rebinding.

Every mapping binds directly onto a facade action
(`require("spotlight").<action>`) — there is no `<Plug>` indirection.
which-key, when installed, only labels the preset's leader prefix as a group;
it does not register the individual keys.

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
that exact buffer position — see
[FEATURES/MARKING.md](FEATURES/MARKING.md#toggle-a-spotlight-on-only-this-occurrence)),
uppercase marks every occurrence of that text.

`<leader>sW` follows the same lowercase/uppercase rule: whole-line rendering is
the wider, louder of the two ways to show a spotlight, so it takes the shifted
key. `<leader>sw` is deliberately left free rather than given the opposite
meaning — "token only" is not a separate action, it is this one toggled off.

### Why no lhs is a prefix of another

A mapping that is also the prefix of a longer one costs a `'timeoutlen'` pause
on *every* press. `<leader>sk` and `<leader>sK` are fine together — `k`/`K`
diverge at that very character, neither extends the other. Worth keeping when
you rebind.

The preset moved from `<leader>m` to `<leader>s`; the letters
(`k`/`K`/`L`/`C`/`q`/`W`) are unchanged, only the group changed. `<leader>s` is
the busier prefix: it is already a bare leaf binding in the author's config
(`search.nvim`'s tabbed UI) and carries real bindings at `sh`, `sM`, `sS`, `sT`
plus the two-level `sp` (`spf`/`spg`, pickers.nvim) and a filetree.nvim
buffer-local `sm`. None of those collide, confirmed against every sibling
plugin repo directly rather than against a cheatsheet — several `<leader>s*`
mentions elsewhere turned out to be commented-out or aspirational code rather
than live bindings.

Three of the six letters used here have a **commented** (inactive)
`snacks.lua` picker slot at the exact same chord: `<leader>sk`
(`snacks.picker.keymaps()`), `<leader>sq` (`snacks.picker.qflist()`) and
`<leader>sC` (`snacks.picker.commands()`). None are registered, so there is no
live conflict, but uncommenting any of the three later would silently shadow
(or be shadowed by, depending on load order) the matching spotlight mapping.
`<leader>sw` is a fourth commented slot, left free here for its own reason —
which also keeps it clear if it is ever activated. Also checked against the
`]`/`[` motions `]q`, `]l`, `]d`, `]w`.

Living with the bare `<leader>s` leaf binding: every `<leader>s*` mapping,
spotlight's included, waits out `'timeoutlen'` before firing, in case the user
meant the bare prefix. That trade already existed for the ~7 other real
`<leader>s*` bindings before spotlight moved here; this does not introduce it.

### Right-click context menu

`spotlight.integrations.menu` contributes the normal-mode rows above
(`toggle_here`, `toggle`, `next`, `prev`, `line_toggle`, `quickfix`, `list`,
`clear` — not the `x`-mode `_selection` variants) as entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects. spotlight.nvim has no
dependency on `menu` and never opens a context menu itself. `menu.enable =
false` opts out. See
[FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md#right-click-context-menu).

## User commands

One verb, built with `lib.nvim.bindings.usercmd.composer` — `<Tab>`
completion, argument typing and validation come from the route tree. **Full
reference with arguments and behaviour: [commands.md](commands.md).**

| Command | Action | One line |
| --- | --- | --- |
| `:Spotlight` | `toggle` | Default route: every occurrence of the cursor token |
| `:Spotlight toggle [text]` | `toggle` / `add` / `remove` | Every occurrence: cursor token, `'<,'>` selection, or explicit text |
| `:Spotlight here` | `toggle_here` / `toggle_here_at` | Only this occurrence: cursor token or `'<,'>` selection |
| `:Spotlight add {text}` | `add` | Add a spotlight for a literal string |
| `:Spotlight remove {text}` | `remove` | Remove by exact text |
| `:Spotlight clear` | `clear` | Remove every spotlight |
| `:Spotlight list [jump\|remove\|lock\|line] [filter]` | `list` / `list_remove` / `list_lock` / `list_line` | Open the list; the action decides what selecting does |
| `:Spotlight[!] next` | `next` | Next occurrence (`!` ignores `nav.scope`) |
| `:Spotlight[!] prev` | `prev` | Previous occurrence (`!` ignores `nav.scope`) |
| `:Spotlight qf [text]` | `quickfix` | Matching lines in this buffer → quickfix |
| `:Spotlight qf all [text]` | `quickfix_all` | Same, across every loaded buffer |
| `:Spotlight yank [text]` | `yank` | Matching lines → unnamed register |
| `:Spotlight line [text]` | `line_toggle` | Toggle whole-line rendering |
| `:Spotlight lock [text]` | `lock_toggle` | Toggle the palette-slot lock |
| `:Spotlight map [text]` | `map` | Mark matching lines in the sign column |
| `:Spotlight map clear` | `map_clear` | Clear the occurrence map in this buffer |
| `:Spotlight sets save {name}` | `sets_save` | Save the active spotlights under a name |
| `:Spotlight sets switch {name}` | `sets_switch` | Replace the active spotlights with a saved set |
| `:Spotlight sets delete {name}` | `sets_delete` | Delete a saved set |
| `:Spotlight sets list` | `sets_list` | List every saved set and its count |
| `:Spotlight winopt [on\|off\|toggle\|status]` | `winopt_*` | Per-window opt-out; no argument = `toggle` |
| `:Spotlight persist [on\|off\|default\|status]` | `persist_*` | Per-file persistence override; no argument = `status` |
| `:Spotlight refresh` | `refresh` | Redefine the palette, re-apply every match |

`toggle` and `here` are the only range-aware routes; `next` and `prev` take a
bang instead. Every keymap action has a command and vice versa: no feature
exists only on a key.

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
Configure them via `palette.colors` / `palette.colors_light` — redefining a
group yourself would be overwritten by the next `ColorScheme`.

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

Every action is also a plain Lua function, for binding your own keys with
`keymaps.preset = false`. The `action` column of the command table above names
them; the signatures and return values are in [api.md](api.md).

## Global variables

| Variable | Purpose |
| --- | --- |
| `vim.g.loaded_spotlight` | Load guard. Set it to `1` before the plugin is sourced to disable it entirely. |
