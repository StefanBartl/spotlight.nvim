# What you get with the defaults

| Key | Does |
| --- | --- |
| `<leader>sK` | Spotlight the token under the cursor, everywhere it appears |
| `<leader>sk` | Spotlight only this occurrence, pinned to this position |
| `]k` / `[k` | Next and previous occurrence of the token you are on |
| `<leader>sL` | The list: swatch, token, match count; pick one to jump to it |
| `<leader>sq` | Every matching line into the quickfix list |
| `<leader>sC` | Clear every spotlight |

Everything is reachable three ways — a preset keymap, a `:Spotlight`
subcommand, and a plain function on the `spotlight` module — so nothing here
forces you to keep the keys. The full set is
[BINDINGS.md](BINDINGS.md), the routes are
[commands.md](commands.md), and the functions are
[api.md](api.md).
