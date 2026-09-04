# Configuration

`require("spotlight").setup()` with no arguments is the intended everyday
configuration; nothing on this page needs setting. Every value shown is the
default, and every key is typed (`Spotlight.Config` and friends in
`lua/spotlight/@types/`), so lua_ls completes and checks the table.

Invalid values are **degraded to their defaults, not thrown**: a malformed
color or an unparseable Lua pattern is dropped, every other setting still
applies, and `:checkhealth spotlight` lists exactly what was rejected. One bad
line should not stop the plugin from loading.

## Table of contents

- [Every default](#every-default)
- [Token resolution](#token-resolution)
- [Colors](#colors)
- [Persistence](#persistence)
- [Keymaps](#keymaps)
- [The bounded values](#the-bounded-values)

## Every default

```lua
require("spotlight").setup({
  -- Register a position preview with hover.nvim, so resting the cursor on a
  -- spotlighted token says how often it occurs in this buffer. A no-op
  -- without hover.nvim installed. See docs/hover.md.
  hover = true,

  palette = {
    -- Both bg AND fg per slot, so contrast is the plugin's property, not the
    -- colorscheme's. Replacing either array replaces it wholesale.
    colors = {                                    -- used when &background = "dark"
      { bg = "#ffd75f", fg = "#1c1c1c" },
      { bg = "#87d7ff", fg = "#1c1c1c" },
      { bg = "#ff87d7", fg = "#1c1c1c" },
      { bg = "#a8e22e", fg = "#1c1c1c" },
      { bg = "#ffaf5f", fg = "#1c1c1c" },
      { bg = "#b48eff", fg = "#ffffff" },
      { bg = "#5fd7af", fg = "#1c1c1c" },
      { bg = "#ff5f5f", fg = "#ffffff" },
    },
    colors_light = { --[[ eight darker slots; see config/DEFAULTS.lua ]] },
    bold = true,
    reapply_on_colorscheme = true,
  },

  match = {
    priority = 10,            -- matchadd() priority; >0 renders above 'hlsearch'
    ignore_case = false,      -- false pins \C, so 'ignorecase' cannot change a spotlight
    word_boundaries = true,   -- \<...\> around all-word-character tokens only
    max = 64,                 -- refuse to add more than this many at once
    max_text_len = 512,       -- longest token accepted, in bytes
  },

  cursor = {
    -- Lua patterns, highest priority first. The first one whose match *spans
    -- the cursor column* wins. See config/DEFAULTS.lua for the full list.
    patterns = { --[[ uuid, ISO timestamp, clock, ipv4[:port], 0x…, sha, user@host, a.b.c, number, token ]] },
    fallback_cword = true,
    max_line_len = 8192,      -- above this, skip the scan and use <cword>
  },

  nav = {
    scope = "auto",           -- "auto": follow the token under the cursor; "all": every spotlight
    wrap = true,
    center = true,            -- zz after jumping
  },

  list = {
    count = true,             -- compute match counts when the list opens
    count_max_lines = 200000, -- above this, show "?" instead of scanning
    count_scope = "buffer",   -- or "loaded": sum across every loaded buffer
    swatch = "  ",            -- the colored chip at the start of each row
  },

  map = {
    sign_text = "▪",          -- ≤ 2 display cells, Neovim's own sign-text limit
    max_entries = 10000,      -- marks placed by one :Spotlight map scan
  },

  quickfix = {
    open = true,              -- open the list after filling (focus returns to your buffer)
    title = "Spotlight",
    max_entries = 10000,      -- stop after this many matching lines
  },

  persist = {
    enable = true,
    default = true,           -- per-file default; false inverts the model to opt-in
    debounce_ms = 500,
  },

  keymaps = {
    preset = true,
    toggle_here = "<leader>sk",  -- only this occurrence
    toggle = "<leader>sK",       -- every occurrence
    list = "<leader>sL",
    clear = "<leader>sC",
    quickfix = "<leader>sq",
    line = "<leader>sW",         -- whole-line rendering for one spotlight
    next = "]k",
    prev = "[k",
  },

  menu = {
    enable = true,            -- contribute entries to an nvzone/menu host
  },

  notify = true,              -- report added/removed/cleared spotlights
  debug = false,              -- structured logs at the decision points
})
```

## Token resolution

### Why `<cword>` is not enough

`<cword>` splits on `'iskeyword'`. So
`550e8400-e29b-41d4-a716-446655440000` is five words, `192.168.1.1` is four,
`0x1f4a` is two — the tokens actually worth tracking in a log are precisely the
ones it cannot see. Hence `cursor.patterns`, with `<cword>` kept as the last
resort for plain identifiers.

The list is searched in order and the first pattern whose match *spans the
cursor column* wins, so **a broad pattern placed early shadows every specific
one after it**. That is the first thing to check when a spotlight covers more
or less than you expected; `debug = true` logs which pattern won and its index.

### Word boundaries follow the token's shape

Not which pattern produced it: an all-word-character token gets `\<…\>` (so
`error` does not light up inside `errors`), anything else cannot have them
(`\<192.168.1.1\>` matches nothing, because `\<` asserts a word start and `1`
after `.` is not one). An explicit selection or `:Spotlight add` is always
literal — you said exactly what you meant.

## Colors

Eight highlight groups, `Spotlight1` … `Spotlight8`, each with an explicit
background **and** foreground. Setting only a background is the usual mistake:
the foreground then comes from whatever the colorscheme left there, which is
how a perfectly readable marker becomes yellow-on-yellow after `:colorscheme`.

`palette.colors` is used for dark themes and `palette.colors_light` for light
ones; switching `'background'` switches between them. Replacing either array
replaces it wholesale — there is no per-slot merge.

Configure the groups through `setup()` rather than by redefining `SpotlightN`
afterwards: they are redefined on `ColorScheme` (a colorscheme clears groups it
does not know about), which would overwrite a manual definition. Set
`palette.reapply_on_colorscheme = false` to stop that, at the cost of losing
the colors on the next theme switch.

`'termguicolors'` should be on; without it the hex values are approximated to
the terminal's 256-color cube and slots get harder to tell apart.
`:checkhealth spotlight` warns about this. The resolved dark/light values per
slot are tabulated in [BINDINGS.md](BINDINGS.md#highlight-groups).

## Persistence

State lives in `lib.nvim.store.project` under `spotlight/state`, keyed by
**git root** — so it also works when you open the project from a
subdirectory, and follows the checkout to another machine.

Two independent switches cover both directions:

```lua
persist = { default = true }   -- opt-out (the default): everything persists
persist = { default = false }  -- opt-in: nothing persists unless a file says so
```

```vim
:Spotlight persist off      " this file: do not persist
:Spotlight persist on       " this file: do persist
:Spotlight persist default  " this file: drop the override, follow the global default
:Spotlight persist status   " what applies here, and why
```

What an exception actually suppresses — spotlights *created while looking at*
that file, not spotlights that *appear* in it — is the one non-obvious part,
and is explained in
[FEATURES/PERSISTENCE.md](FEATURES/PERSISTENCE.md#why-origin-not-appearance).

`persist.enable = false` switches the whole mechanism off, including the
`VimEnter` load and the `VimLeavePre` flush.

## Keymaps

The preset binds when `keymaps.preset` is `true` (the default). Each key is its
own config value, and setting one to `false` frees just that `lhs` without
opting out of the whole preset:

```lua
require("spotlight").setup({
  keymaps = {
    toggle_here = "<leader>hh",
    toggle = "<leader>hH",
    list = "<leader>hl",
    next = false,          -- leave ]k alone
  },
})
```

…or turn the preset off and bind the actions yourself — they are plain
functions, listed in full in [api.md](api.md):

```lua
require("spotlight").setup({ keymaps = { preset = false } })

local spotlight = require("spotlight")
vim.keymap.set("n", "<leader>hh", spotlight.toggle_here, { desc = "spotlight: toggle this occurrence" })
vim.keymap.set("x", "<leader>hh", spotlight.toggle_here_selection, { desc = "spotlight: toggle this selection" })
vim.keymap.set("n", "<leader>hH", spotlight.toggle, { desc = "spotlight: toggle every occurrence" })
vim.keymap.set("x", "<leader>hH", spotlight.toggle_selection, { desc = "spotlight: toggle every occurrence (selection)" })
```

Because the actions are declared through `lib.nvim`'s keymap registry, a typo
in an override (`toggl_here = "…"`) is **reported** rather than silently
binding nothing.

One rule worth keeping when you rebind: **no `lhs` should be a prefix of
another**. A mapping that is also the prefix of a longer one costs a
`'timeoutlen'` pause on *every* press of the shorter one. The defaults are
chosen this way — `<leader>sk` and `<leader>sK` diverge at that very
character. The full preset table and its collision analysis are in
[BINDINGS.md](BINDINGS.md#keymaps).

## The bounded values

Three numbers are hard caps rather than advisory defaults, because the size
they bound is not the plugin's to control:

| Key | Default | What it bounds |
| --- | --- | --- |
| `match.max_text_len` | 512 | The longest token accepted, in bytes — a `v$` on a minified single-line file, or a hand-edited snapshot field |
| `cursor.max_line_len` | 8192 | Above this the resolver's pattern scan is skipped entirely and `<cword>` answers instead |
| `quickfix.max_entries` | 10000 | Matching lines collected by `:Spotlight qf` / `:Spotlight yank`; truncation is reported, never silent |

`map.max_entries` is the same shape for `:Spotlight map`, deliberately a
separate value: it caps a second, unrelated scan. `match.max` (64) caps how
many spotlights can be active at once — a guard, not a design limit, since
`matchadd()` cost is per visible line.

The reasoning behind each is in
[architecture.md](architecture.md#bounded-inputs).
