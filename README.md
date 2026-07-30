```
                    __  ___       __    __
   _________  ____  / /_/ (_)___ _/ /_  / /_
  / ___/ __ \/ __ \/ __/ / / __ `/ __ \/ __/
 (__  ) /_/ / /_/ / /_/ / / /_/ / / / / /_
/____/ .___/\____/\__/_/_/\__,_/_/ /_/\__/
    /_/      many tokens, many colors, one log
```

[![CI](https://github.com/StefanBartl/spotlight.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/spotlight.nvim/actions/workflows/ci.yml)
![Neovim](https://img.shields.io/badge/Neovim-0.9+-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Made%20with-Lua-2C2D72?logo=lua&logoColor=white)

> 💡 Pairs well with [buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim):
> its `:Mark` marks the *lines* you want to come back to, spotlight marks the
> *tokens* you are following through them — line context and token context side by
> side in the same log.

You are reading a log. You spot a request id, a PID, an IP, an error code — and
you want to see **every other occurrence, right now**. Several tokens at once, in
colors you can tell apart, and they must stay put: through searches, through
scrolling, through a `:split`.

`*` gives you one token and fights your real search. `:match` gives you three
slots and no management. `matchadd()` is the right primitive but is
window-local, so a split loses everything.

`spotlight.nvim` is that primitive with the bookkeeping done for you: any number
of tokens, eight distinguishable colors, applied in every window, persisted per
project, with a per-file opt-out.

---

## Table of contents

- [Why matchadd and not extmarks](#why-matchadd-and-not-extmarks)
- [Features](#features)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [Keymaps](#keymaps)
- [The :Spotlight command](#the-spotlight-command)
- [Configuration](#configuration)
- [Persistence](#persistence)
- [Colors](#colors)
- [Health](#health)
- [Debugging](#debugging)
- [Security model](#security-model)
- [Architecture](#architecture)
- [Roadmap](#roadmap)

---

## Why matchadd and not extmarks

This is the decision the whole plugin is built around, and it is the reason it
stays usable on a log that is too big to open in anything else.

**Extmarks store positions.** Setting them means scanning the buffer — O(file
size) on every add, and again on every text change. On a 200 MB log that is not a
slow path, it is an unusable one.

**`matchadd()` stores the pattern** and hands it to Vim's renderer, which
evaluates it in C over the visible lines only. Cost is proportional to the
window, not to the file. A text change needs no invalidation at all, because
nothing position-shaped was ever stored. There is deliberately no
`TextChanged` or `CursorMoved` autocommand anywhere in this plugin.

The price is that a match is window-local, so ~30 lines of bookkeeping
(`window -> { spotlight id -> match id }`) plus three window autocommands make it
look global. That trade is the plugin.

The direct consequence: **match counts are computed on demand**, when you open
the list, and never maintained. Keeping them live would reintroduce exactly the
whole-buffer scan that choosing `matchadd()` avoided.

---

## Features

| Feature                | Description                                                                                     |
| ---------------------- | ----------------------------------------------------------------------------------------------- |
| **Toggle under cursor** | One key adds or removes a spotlight on the token you are pointing at.                            |
| **Toggle a selection** | The same key in visual mode takes the exact selected bytes, literally.                           |
| **Log-aware resolver** | UUIDs, ISO timestamps, `192.168.1.1:8080`, `0x1f4a`, git shas, `user@host` — the tokens `<cword>` splits into pieces. Configurable pattern list, in priority order. |
| **Auto-color**         | Eight `Spotlight1..8` groups, round-robin, skipping colors already on screen.                    |
| **Every window**       | New splits, new tabs and buffer switches are filled automatically.                               |
| **The list**           | Color swatch + token + match count → jump to it, or remove it.                                   |
| **Next / previous**    | `]k` / `[k`. On a token, follows *that* token; off one, walks all spotlights.                     |
| **Quickfix filter**    | Every line matching a spotlight → quickfix. "Show me only the lines with this request id."        |
| **Per-project persistence** | Restored on the next session, keyed by git root. On by default.                             |
| **Per-file opt-out**   | `:Spotlight persist off` for a file whose tokens should not be written to disk.                   |
| **Case pinned**        | `\C` baked into the pattern, so a spotlight does not change meaning when you toggle `'ignorecase'`. |
| **`:checkhealth`**     | Per-module `lib.nvim` status, `'termguicolors'`, config validation results, live state.           |
| **Debug switch**       | `debug = true` logs the four decisions that answer "why did nothing light up", via `lib.nvim.logger`. |

Everything is reachable three ways: a preset keymap, a `:Spotlight` subcommand,
and a plain function on the `spotlight` module.

---

## Installation

`lib.nvim` is a **required** dependency — the `:Spotlight` verb is built on
`lib.nvim.usercmd.composer` and the list on `lib.nvim.ui.kit.select`. The
persistence, notify, keymap, autocmd and debounce helpers degrade to native
equivalents if absent; `:checkhealth spotlight` reports each one separately.

**Which loading strategy:**

| Variant              | Startup impact          | When to use                                                                 |
| -------------------- | ----------------------- | --------------------------------------------------------------------------- |
| `event = "VeryLazy"` | Minimal, after UI init  | **Recommended.** Persisted spotlights are restored and the keys are ready before you open a log. |
| `cmd = "Spotlight"`  | None until first use    | You always start from the command, and do not want the preset keys until then. |
| `lazy = false`       | Loads immediately       | Small config, want it available instantly.                                  |

`ft` is not a useful gate here: logs arrive with every filetype and often with
none at all.

### lazy.nvim

*Recommended — no configuration needed:*

```lua
{
  "StefanBartl/spotlight.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VeryLazy",
  config = function()
    require("spotlight").setup()
  end,
}
```

*Or with `opts`, tweaking a value or two:*

```lua
{
  "StefanBartl/spotlight.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VeryLazy",
  opts = {
    persist = { default = false },   -- opt-in instead of opt-out
    match = { ignore_case = true },
  },
}
```

### packer.nvim

```lua
use({
  "StefanBartl/spotlight.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("spotlight").setup()
  end,
})
```

### mini.deps

```lua
local add = MiniDeps.add
add({ source = "StefanBartl/spotlight.nvim", depends = { "StefanBartl/lib.nvim" } })
require("spotlight").setup()
```

### vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/spotlight.nvim'
" after plug#end():
lua require("spotlight").setup()
```

### paq-nvim

```lua
require("paq")({
  "savq/paq-nvim",
  "StefanBartl/lib.nvim",
  "StefanBartl/spotlight.nvim",
})
require("spotlight").setup()
```

### Built-in `vim.pack` (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
  { src = "https://github.com/StefanBartl/spotlight.nvim" },
})
require("spotlight").setup()
```

---

## Quickstart

Open a log. Put the cursor on a request id and press `<leader>mk`: every other
occurrence lights up, in the whole buffer and in every window showing it.

Point at a PID, press it again: a second color. An IP: a third.

- `]k` / `[k` — walk the occurrences of the token you are on.
- `<leader>mK` — the list: swatch, token, match count. Pick one to jump to it.
- `<leader>mq` — every line matching any spotlight, into the quickfix list.
- `<leader>m<C-k>` — clear them all.

Quit and come back tomorrow: they are still there.

---

## Keymaps

Bound when `keymaps.preset` is `true` (the default). Each key is its own config
value, and setting one to `false` frees just that `lhs` without opting out of the
whole preset.

| lhs               | mode | action             | description                                        |
| ----------------- | ---- | ------------------ | -------------------------------------------------- |
| `<leader>mk`      | n    | `toggle`           | Toggle a spotlight on the token under the cursor.  |
| `<leader>mk`      | x    | `toggle_selection` | Toggle a spotlight on the exact selection.         |
| `<leader>mK`      | n    | `list`             | Open the spotlight list.                           |
| `<leader>m<C-k>`  | n    | `clear`            | Remove every spotlight.                            |
| `<leader>mq`      | n    | `quickfix`         | Matching lines → quickfix.                         |
| `]k`              | n    | `next`             | Next occurrence.                                   |
| `[k`              | n    | `prev`             | Previous occurrence.                               |

Note that none of these is a prefix of another: a mapping that is also the prefix
of a longer one costs a `'timeoutlen'` pause on *every* press, which is why
clear-all is `<leader>m<C-k>` and not `<leader>mkc`.

To rebind, either set the config values:

```lua
require("spotlight").setup({
  keymaps = {
    toggle = "<leader>hh",
    list = "<leader>hl",
    next = false,          -- leave ]k alone
  },
})
```

…or turn the preset off and bind the actions yourself — they are plain functions:

```lua
require("spotlight").setup({ keymaps = { preset = false } })

local spotlight = require("spotlight")
vim.keymap.set("n", "<leader>hh", spotlight.toggle, { desc = "spotlight: toggle" })
vim.keymap.set("x", "<leader>hh", spotlight.toggle_selection, { desc = "spotlight: toggle selection" })
```

which-key is a soft dependency: when installed, the preset's leader prefix is
labelled as a "Spotlight" group. Individual descriptions come from each mapping.

See [`docs/BINDINGS.md`](docs/BINDINGS.md) for the full machine-readable
cheatsheet, autocommands included.

---

## The :Spotlight command

One verb with `<Tab>`-completed subcommands, built on `lib.nvim`'s user-command
composer — so completion, argument validation and the generated docs all come
from the same route tree.

| Command                          | Description                                                            |
| -------------------------------- | ---------------------------------------------------------------------- |
| `:Spotlight`                     | Toggle the token under the cursor (same as `<leader>mk`).               |
| `:Spotlight toggle [text]`       | Toggle the cursor token, a `'<,'>` range selection, or explicit `text`. |
| `:Spotlight add {text}`          | Add a spotlight for the literal `text`.                                |
| `:Spotlight remove {text}`       | Remove the spotlight matching `text` exactly.                           |
| `:Spotlight clear`               | Remove every spotlight.                                                 |
| `:Spotlight list [jump\|remove]` | Open the list; `remove` makes selection delete instead of jump.          |
| `:Spotlight next` / `prev`       | Jump one occurrence.                                                    |
| `:Spotlight qf [text]`           | Matching lines → quickfix; with `text`, only that spotlight's.           |
| `:Spotlight persist on\|off\|default\|status` | Per-file persistence — see below.                           |
| `:Spotlight refresh`             | Redefine the palette and re-apply everything to every window.            |

`:'<,'>Spotlight toggle` works from a visual selection: the selection is read
from the `'<`/`'>` marks, which is exactly when they become valid.

---

## Configuration

Every value below is the default. `require("spotlight").setup()` with no
arguments is the intended everyday configuration; nothing here needs setting.

```lua
require("spotlight").setup({
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
    max_text_len = 512,       -- longest token accepted, in bytes (see Security model)
  },

  cursor = {
    -- Lua patterns, highest priority first. The first one whose match *spans the
    -- cursor column* wins. Order matters: a broad pattern placed early shadows
    -- every specific one after it. See config/DEFAULTS.lua for the full list.
    patterns = { --[[ uuid, ISO timestamp, clock, ipv4[:port], 0x…, sha, user@host, a.b.c, number, token ]] },
    fallback_cword = true,
    max_line_len = 8192,      -- above this, skip the scan and use <cword> (see Security model)
  },

  nav = {
    scope = "auto",           -- "auto": follow the token under the cursor; "all": every spotlight
    wrap = true,
    center = true,            -- zz after jumping
  },

  list = {
    count = true,             -- compute match counts when the list opens
    count_max_lines = 200000, -- above this, show "?" instead of scanning
    swatch = "  ",            -- the colored chip at the start of each row
  },

  quickfix = {
    open = true,              -- :copen after filling (focus returns to your buffer)
    title = "Spotlight",
    max_entries = 10000,      -- stop after this many matching lines (see Security model)
  },

  persist = {
    enable = true,
    default = true,           -- per-file default; false inverts the model to opt-in
    debounce_ms = 500,
  },

  keymaps = {
    preset = true,
    toggle = "<leader>mk",
    list = "<leader>mK",
    clear = "<leader>m<C-k>",
    quickfix = "<leader>mq",
    next = "]k",
    prev = "[k",
  },

  notify = true,              -- report added/removed/cleared spotlights
  debug = false,              -- structured logs at the decision points (see below)
})
```

Every key is typed (`Spotlight.Config` and friends in `lua/spotlight/@types/`),
so lua_ls completes and checks the table above.

Invalid values are **degraded to their defaults, not thrown**: a malformed color
or an unparseable Lua pattern is dropped, every other setting still applies, and
`:checkhealth spotlight` lists exactly what was rejected. One bad line should not
stop the plugin from loading.

### Why `<cword>` is not enough

`<cword>` splits on `'iskeyword'`. So
`550e8400-e29b-41d4-a716-446655440000` is five words, `192.168.1.1` is four,
`0x1f4a` is two — the tokens actually worth tracking in a log are precisely the
ones it cannot see. Hence the pattern list, with `<cword>` kept as the last
resort for plain identifiers.

Word boundaries follow the token's **shape**, not which pattern produced it: an
all-word-character token gets `\<…\>` (so `error` does not light up inside
`errors`), anything else cannot have them (`\<192.168.1.1\>` matches nothing,
because `\<` asserts a word start and `1` after `.` is not one). An explicit
selection or `:Spotlight add` is always literal — you said exactly what you meant.

---

## Persistence

State lives in `lib.nvim.store.project` under `spotlight/state`, keyed by **git
root** — so it also works when you open the project from a subdirectory, and
follows the checkout to another machine. Writes are debounced (a burst of toggles
is one logical change) and flushed on `VimLeavePre`, so the last toggle before
`:qa` is never the one that gets lost. Loading happens once, on `VimEnter`.

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

An exception is recorded against the **project-relative file path**, not the
buffer number — so it survives closing and reopening the file.

### What a per-file exception actually suppresses

Spotlights are session-global, but an exception names a *file*, so this needs
saying precisely. **An exception suppresses the spotlights that were *created
while looking at* that file** — each spotlight records its origin once, when you
make it.

It deliberately does not mean "spotlights that *appear* in this file". That is
not implementable and not even well-defined: knowing where a token appears would
mean scanning every file in the project on every save — the exact
O(everything) cost this plugin exists to avoid — and the answer would change
every time a log rotates.

So a spotlight created in `worker.log` stays persisted even if the same string
also occurs in an excluded `secrets.log`. That matches the use case: "this
customer log is full of tokens I do not want written to my cache directory" is a
statement about where the tokens came from.

The exception list itself is always persisted, including for excluded files —
otherwise `:Spotlight persist off` would not survive a restart, which would make
the setting pointless.

---

## Colors

Eight highlight groups, `Spotlight1` … `Spotlight8`, each with an explicit
background **and** foreground. Setting only a background is the usual mistake:
the foreground then comes from whatever the colorscheme left there, which is how
a perfectly readable marker becomes yellow-on-yellow after `:colorscheme`.

There are two arrays — `palette.colors` for dark themes, `palette.colors_light`
for light ones — and switching `'background'` switches between them. The groups
are redefined on `ColorScheme`, because a colorscheme clears groups it does not
know about. Configure them through `setup()` rather than by redefining
`SpotlightN` afterwards; a `ColorScheme` event would overwrite the latter.

Slot allocation is round-robin from the last one handed out, **skipping slots
still in use** while any are free — plain round-robin would happily hand out a
color already on screen while three others sit unused, and two identically
colored spotlights are exactly the confusion the palette exists to prevent.

`'termguicolors'` should be on; without it the hex values are approximated to the
terminal's 256-color cube and slots get harder to tell apart.
`:checkhealth spotlight` warns about this.

---

## Health

```vim
:checkhealth spotlight
```

Reports the Neovim version; `'termguicolors'`; each `lib.nvim` module separately
with what it is used for (a missing `usercmd.composer` and a missing `debounce`
are very different problems); every config value that failed validation and what
it fell back to; the resolved match/cursor/keymap settings; and the live state —
active spotlights with their slots, how many windows carry matches, the project
root, and every per-file persistence override.

---

## Debugging

```lua
require("spotlight").setup({ debug = true })
```

The only question this plugin ever really gets asked is *"why did nothing light
up"*, so `debug = true` logs exactly the four decisions that answer it:

- **which resolver pattern won**, with its index — a surprising token almost
  always means a broader pattern sits ahead of the specific one you expected;
- **which windows the ledger applied to or skipped**, and any `matchadd()` Vim
  rejected — the one way a spotlight can silently fail to appear;
- **what the snapshot filter kept and dropped**, which is the answer to "my
  spotlights did not come back";
- **whether navigation narrowed to one spotlight or searched them all** — the
  entire behavioral difference of `]k`, and invisible from the outside.

Routed through `lib.nvim.logger` (one `spotlight` instance, inspectable with
`:LibLogger`), falling back to `vim.notify` at DEBUG level when that is not
installed. With `debug = false` a log call costs one table lookup.


---

## Security model

Not a claim of hardness — a plugin that highlights text is not a security
boundary — but a statement of what is and is not trusted, so the guards below
have a reason rather than a vibe.

**Nothing is executed, nothing is fetched, nothing is written outside the cache.**
No shell-outs, no `io.*`, no jobs, no network. The only three `vim.cmd` calls are
the fixed literals `normal! zz` and `copen`, with nothing interpolated. The only
file written is the state snapshot, through `lib.nvim.store.project`.

**Regexes cannot backtrack pathologically.** Every pattern handed to Vim is built
by `core/pattern.lua` as `\C\V` plus escaped literal text — no quantifiers, no
groups, no alternation *inside* a branch. So no input, however crafted, can
produce catastrophic backtracking. `\V` (very nomagic) also reduces escaping to a
single character, the backslash, which is why the escape is one substitution
rather than a character class that could fall out of sync with Vim's magic rules.

**The snapshot is treated as external input.** It is JSON in the cache directory:
writable by anything running as this user, and hand-editable. So every field is
re-validated on load — type, non-empty, length cap, dedup, count cap, palette slot
clamped into range. Crucially the **regex is rebuilt from `text`**, never read from
the file, so a crafted snapshot cannot inject a pattern.

**Bounded inputs.** Three limits exist specifically because the size is not the
plugin's to control:

| Guard | Default | Unbounded input it covers |
| --- | --- | --- |
| `match.max_text_len` | 512 | A `v$` on a minified single-line file, or a snapshot field — either would otherwise reach `matchadd()` as a multi-megabyte pattern re-evaluated on every redraw. |
| `cursor.max_line_len` | 8192 | A minified single-line JSON log. The resolver scan is O(line) *per pattern* and a user-supplied Lua pattern may backtrack; above the limit the scan is skipped and `<cword>` answers instead. |
| `quickfix.max_entries` | 10000 | A common token in a large log. Unlike counting, filtering *produces* memory — one entry per matching line, each holding the full line text. Truncation is reported, in the notification and in the list title. |

**Exception keys are data, never paths.** A persisted key like `../../../etc/passwd`
is stored and compared as an opaque table key and JSON field. The plugin opens no
files of its own, so there is nothing for a traversal to traverse.

**Config values are sanitized, not trusted.** Invalid colors and unparseable Lua
patterns are dropped, numbers are range-checked, and `list.swatch` has newlines
stripped — it is written into a chooser buffer line, where `nvim_buf_set_lines`
treats an embedded newline as a hard error rather than as two lines.

**No privilege, no elevation, no secrets handled.** Note that spotlighted tokens
*are* persisted to the cache directory by default — if you are reading a log full
of credentials, `:Spotlight persist off` is the switch that keeps them out of it.

---

## Architecture

```
lua/spotlight/
  init.lua              facade: setup + every action
  config/
    DEFAULTS.lua        single source of truth for defaults
    init.lua            deep merge + validation + get("dot.path")
  core/
    pattern.lua         literal token -> Vim regex (\V escaping, \C, boundaries)
    palette.lua         Spotlight1..8, dark/light sets, round-robin slots
    match.lua           the matchadd() ledger: window -> { id -> match id }
    registry.lua        the authoritative spotlight list; the one change event
    count.lua           on-demand counting + the shared line scan
  cursor.lua            token resolver (patterns -> <cword>) and selection reader
  nav.lua               next/prev, "auto" scope narrowing
  qf.lua                quickfix filter
  ui/list.lua           kit.select rich items (color swatch per row)
  persist.lua           store.project + the per-file exception model
  bindings/
    init.lua            composer
    keymaps.lua         the preset
    usrcmds.lua         the :Spotlight verb
    autocmds.lua        window fill, ColorScheme, load/flush
    which_key.lua       optional group label
  util/
    lib.lua             guarded lib.nvim bridge (notify/map/autocmd/hl/debounce/logger)
    path.lua            project-relative file keys (cross-platform)
  health.lua
  @types/init.lua
```

Two rules hold throughout: no module reads a raw options table (everything goes
through `config.get`), and every change to the spotlight list funnels through
`core/registry.lua` and ends in one change event — which is what persistence
subscribes to, so no caller has to remember to trigger a save.

Cross-platform: no shell-outs, no path assumptions. Path keys are normalized to
forward slashes and compared case-insensitively on Windows, where `C:\Repos\x`
and `c:\repos\x` are the same file and would otherwise produce two different
exception keys.

Tests: [`TESTS/`](TESTS/README.md) — 135 assertions, plain headless
Neovim, no test framework to install.

---

## Roadmap

See [`docs/ROADMAP/ROADMAP.md`](docs/ROADMAP/ROADMAP.md), and the three
checklist walkthroughs beside it —
[Arch&Coding](docs/ROADMAP/Arch%26Coding.md),
[Zentral-Prinzipien](docs/ROADMAP/Zentral-Prinzipien.md),
[Checklist](docs/ROADMAP/Checklist.md) — which record what was assessed and
*declined*, with the trigger for revisiting each.

Deliberately *not*
planned, and why: a regex mode, per-buffer or per-filetype scoping, automatic
rules (`ERROR`/`WARN` highlighted for you), and set export/import. Each is
plausible and each would double the command surface; they go in when a real need
shows up, not before.
