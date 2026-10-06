# Integrations

Everything here is soft: nothing breaks when the other plugin is absent, and
spotlight never opens a UI it does not own.

## hover.nvim

With [hover.nvim](https://github.com/StefanBartl/hover.nvim) installed,
resting the cursor on a **spotlighted** token says how often it occurs in this
buffer. Only for tokens that are already spotlighted — a spotlight is a
decision the reader already made about *this* token, and it is the only signal
available that separates "a request id worth counting" from "a word".

The gate, the "we did not look" case, and how to turn it off are on their own
page: [hover.md](../hover.md).

- **Module:** `hover.lua`
- **Config:** `hover` (default `true`)

## which-key integration

When which-key is installed, the preset's `<leader>s` prefix is labelled as a
"Spotlight" group. Individual key descriptions need no registration at all:
which-key reads the keymaps itself and labels each from its own `desc`, which
the keymap spec always sets. Only the group label is outside what it can
infer, so only that is handed over. Entirely soft — nothing breaks if
which-key is absent.

The prefix is derived from the configured `keymaps.toggle` value rather than
hard-coded, so moving the preset to a different leader group puts the label
there too.

- **Module:** declared in `bindings/keymaps.lua`'s spec (`which_key = { group
  = "Spotlight" }`), applied by `lib.nvim.bindings.keymap`

## Right-click context menu

`spotlight.integrations.menu` contributes the normal-mode subset of the
preset actions — spotlight this occurrence, spotlight every occurrence,
next/previous, toggle whole-line rendering, quickfix, open the list, clear
all — as entries in the shape [nvzone/menu](https://github.com/nvzone/menu)
expects. The `_selection` variants are left out: a menu callback fires
after nvzone/menu has already closed the menu and restored the triggering
buffer, so there is no active Visual selection by the time it runs.
spotlight.nvim has no dependency on `menu` and never opens a context menu
itself — a host (typically your own `<RightMouse>` dispatcher) composes
the entries into its own menu.

- **Module:** `integrations/menu.lua` (`M.items`, `M.submenu`, `M.enabled`)
- **Config:** `menu.enable` (default `true`); `integrations.ui_menu` (default
  `true`) — `false` keeps ui.nvim's right-click menu (`ui.menu`) from showing
  the fly-out while `items()`/`submenu()` keep working for other hosts.
  `enabled()` is what `ui.menu` asks first.

## mdview.nvim

[mdview.nvim](https://github.com/StefanBartl/mdview.nvim) previews a Markdown
file in the browser, and mirrors your spotlights into it: mark `SYSsystosca` or
`400 (Bad Request)` here and every occurrence in the rendered document is
marked there too, in the same color, within about a second. It is built on the
[scriptable facade](#scriptable-facade) and nothing else — mdview listens for
`User SpotlightChanged`, re-reads `spotlights({ whole_file = true })` and
`colors()`, and paints the same tokens in the page. Neither plugin requires the
other; without mdview nothing here changes.

What carries over: whole-file spotlights only (a "this occurrence only"
spotlight is pinned to a buffer position the rendered page has no counterpart
for), the slot colors from the live `Spotlight1..8` groups (so a colorscheme or
`&background` switch follows), line mode, and the matching semantics — the text
literally, case-sensitive unless the spotlight ignores case, a substring match
for a visual-selection spotlight and a between-word-boundaries match for a word.
Removing a spotlight, `clear` and `sets switch` update the page.

The mirror does not follow the persistence status: a spotlight that is not
persisted for the file is mirrored too, because it is on screen. What leaves
Neovim is the spotlight texts and colors, to mdview's loopback relay and its
preview tabs. If a shared screen must not show what you marked, set mdview's
`browser.spotlight_sync = false` (or run `:MDView spotlight off`).

- **Module:** none here — mdview.nvim reads `init.lua`'s facade
- **Config:** mdview's `browser.spotlight_sync` and `browser.spotlight_max_matches`

## casedesk.nvim

[casedesk.nvim](https://github.com/StefanBartl/casedesk.nvim) keeps the
spotlights **per case**: it saves what you marked into the case folder and puts
it back when you open that case, so "these markings are from case X, those from
case Y" survives switching and restarting. It is built on `spotlight.export()` /
`spotlight.import(items)` and the `User SpotlightChanged` event, nothing else;
neither plugin requires the other.

The spotlights are written as plain text into the case folder, so they can
contain customer data — the same as the persisted snapshot in the cache
directory. A file with `persist off` keeps its tokens out of that export too.

- **Module:** none here — casedesk.nvim reads `init.lua`'s facade
- **Config:** casedesk's `spotlight.*`

## Scriptable facade

Every action is also a plain function on the `spotlight` module — no
`<Plug>` indirection, no action that exists only as a keymap.
`spotlight.spotlights(opts?)` gives read access to a detached snapshot of the
registry (a status line, a scripted check, a mirror in another plugin) and
`spotlight.colors()` to the eight slot colors as the editor renders them. The
`User SpotlightChanged` autocommand tells such a consumer when to re-read: it
fires, coalesced to one event per tick, after every toggle, clear, set switch,
restore and color change. The full list of signatures, the entry shape and the
event payload are in [api.md](../api.md).

- **Module:** `init.lua`
- **Usercmds:** none — this is the underlying API every keymap and command
  binds onto
