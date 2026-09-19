# Installation

## Requirements

Neovim **0.9+**, [lib.nvim](https://github.com/StefanBartl/lib.nvim), and
[ui.nvim](https://github.com/StefanBartl/ui.nvim). No Treesitter, no LSP, no
external binary.

Both are **required** dependencies, not a nicety: the `:Spotlight` verb is
built on `lib.nvim.bindings.usercmd.composer`, the list itself on ui.nvim's
`ui.kit.select` — soft-guarded in code but with no usable fallback, since a
themed multi-line-item float is the whole feature — the quickfix filter on
`lib.nvim.ui.list`, and the keymap preset on `lib.nvim.bindings.keymap`. The
persistence, notify, autocmd, dot-repeat and debounce helpers degrade to
native equivalents when absent. `:checkhealth spotlight` reports each module
separately, with what it is used for — see [health.md](health.md).

**Every install spec below lists both.** Leaving out `ui.nvim` still loads
spotlight, but `:Spotlight list` / `<leader>sL` — the single most-used
surface — refuses with "ui.kit.select unavailable" the moment it is opened.

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `git` | Persistence keyed by git root. Without it, state falls back to the working directory |
| [hover.nvim](https://github.com/StefanBartl/hover.nvim) | The occurrence count over a spotlighted token |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md) |

## Which loading strategy

| Variant              | Startup impact          | When to use |
| -------------------- | ----------------------- | ----------- |
| `event = "VeryLazy"` | Minimal, after UI init  | **Recommended.** Persisted spotlights are restored and the keys are ready before you open a log. |
| `cmd = "Spotlight"`  | None until first use    | You always start from the command, and do not want the preset keys until then. |
| `lazy = false`       | Loads immediately       | Small config, want it available instantly. |

`ft` is not a useful gate here: logs arrive with every filetype and often with
none at all.

## lazy.nvim

*Recommended — no configuration needed:*

```lua
{
  "StefanBartl/spotlight.nvim",
  dependencies = { "StefanBartl/lib.nvim", "StefanBartl/ui.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

*Or with `opts`, tweaking a value or two — every key is documented in
[configuration.md](configuration.md):*

```lua
{
  "StefanBartl/spotlight.nvim",
  dependencies = { "StefanBartl/lib.nvim", "StefanBartl/ui.nvim" },
  event = "VeryLazy",
  opts = {
    persist = { default = false },   -- opt-in instead of opt-out
    match = { ignore_case = true },
  },
}
```

## packer.nvim

```lua
use({
  "StefanBartl/spotlight.nvim",
  requires = { "StefanBartl/lib.nvim", "StefanBartl/ui.nvim" },
  config = function()
    require("spotlight").setup()
  end,
})
```

## mini.deps

```lua
local add = MiniDeps.add
add({ source = "StefanBartl/spotlight.nvim", depends = { "StefanBartl/lib.nvim", "StefanBartl/ui.nvim" } })
require("spotlight").setup()
```

## vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/ui.nvim'
Plug 'StefanBartl/spotlight.nvim'
" after plug#end():
lua require("spotlight").setup()
```

## paq-nvim

```lua
require("paq")({
  "savq/paq-nvim",
  "StefanBartl/lib.nvim",
  "StefanBartl/ui.nvim",
  "StefanBartl/spotlight.nvim",
})
require("spotlight").setup()
```

## Built-in `vim.pack` (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
  { src = "https://github.com/StefanBartl/ui.nvim" },
  { src = "https://github.com/StefanBartl/spotlight.nvim" },
})
require("spotlight").setup()
```

## Verifying the install

```vim
:checkhealth spotlight
```

Set `vim.g.loaded_spotlight = 1` before the plugin is sourced to disable it
entirely without removing it.
