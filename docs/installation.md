# Installation

## Requirements

Neovim **0.9+** and [lib.nvim](https://github.com/StefanBartl/lib.nvim). No
Treesitter, no LSP, no external binary.

`lib.nvim` is a **required** dependency, not a nicety: the `:Spotlight` verb is
built on `lib.nvim.bindings.usercmd.composer`, the list on
`lib.nvim.ui.kit.select`, and the keymap preset on
`lib.nvim.bindings.keymap`. The persistence, notify, autocmd, dot-repeat and
debounce helpers degrade to native equivalents when absent.
`:checkhealth spotlight` reports each module separately, with what it is used
for — see [health.md](health.md).

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
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

*Or with `opts`, tweaking a value or two — every key is documented in
[configuration.md](configuration.md):*

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

## packer.nvim

```lua
use({
  "StefanBartl/spotlight.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("spotlight").setup()
  end,
})
```

## mini.deps

```lua
local add = MiniDeps.add
add({ source = "StefanBartl/spotlight.nvim", depends = { "StefanBartl/lib.nvim" } })
require("spotlight").setup()
```

## vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/spotlight.nvim'
" after plug#end():
lua require("spotlight").setup()
```

## paq-nvim

```lua
require("paq")({
  "savq/paq-nvim",
  "StefanBartl/lib.nvim",
  "StefanBartl/spotlight.nvim",
})
require("spotlight").setup()
```

## Built-in `vim.pack` (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
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
