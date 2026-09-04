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

- **Module:** `integrations/menu.lua` (`M.items`, `M.submenu`)
- **Config:** `menu.enable` (default `true`)

## Scriptable facade

Every action is also a plain function on the `spotlight` module — no
`<Plug>` indirection, no action that exists only as a keymap.
`spotlight.spotlights()` gives live read access to the registry for a status
line or a scripted check. The full list of signatures is in
[api.md](../api.md).

- **Module:** `init.lua`
- **Usercmds:** none — this is the underlying API every keymap and command
  binds onto
