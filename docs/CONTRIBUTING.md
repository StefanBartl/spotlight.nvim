# Contributing to spotlight.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/spotlight.nvim/issues); pull
requests very welcome.

Read [`architecture.md`](architecture.md) first. One decision — `matchadd()`
rather than extmarks — explains almost everything else here, and four things
that look like limitations are consequences of it. A change that does not sit
inside that decision will look reasonable and be wrong.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it
to the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/spotlight.nvim")
require("spotlight").setup({})
```

[lib.nvim](https://github.com/StefanBartl/lib.nvim) has to be on the runtime
path too. Nothing else — no Treesitter, no LSP, no external binary.

Test against a genuinely large log, not a fixture. The whole point of this
plugin is the file that is too big to open in anything else, and a change whose
cost is proportional to the file rather than to the window will not show up on
a 200-line sample.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation, `stylua.toml` decides
  the rest.
- **Cost stays proportional to the window.** `matchadd()` stores the pattern
  and Vim evaluates it in C over the visible lines. Anything that scans the
  whole buffer — to keep a count live, to invalidate on edit, to place a mark —
  gives that away. There is deliberately no `TextChanged` and no `CursorMoved`
  autocommand anywhere in this plugin, and adding one needs a very good
  argument.
- **Match counts are computed on demand**, when the list opens, and never
  maintained. That is the same rule stated for the one place people reach for
  it first.
- **No module reads a raw options table.** Everything goes through
  `config.get("dot.path")`, so there is one place where a value is normalized,
  validated and defaulted — and one place that reports a rejected value in
  `:checkhealth`.
- **Every change to the spotlight list funnels through `core/registry.lua`**
  and ends in one change event. Persistence subscribes to that event, which is
  why adding a route never comes with a "and do not forget to persist" step.
  A route that saves state itself has broken that.
- **Unbounded input gets a bound, and the truncation is reported.**
  `match.max_text_len`, `cursor.max_line_len`, `quickfix.max_entries` and
  `map.max_entries` each exist because the size is not this plugin's to
  control. A new path that accepts arbitrary text needs the same treatment, and
  silently dropping data is not it — see
  [`architecture.md`](architecture.md#bounded-inputs).
- **Three ways to reach everything.** A preset keymap, a `:Spotlight`
  subcommand, and a plain function on the module. A feature that only exists as
  a keymap is not finished.
- **Say why nothing lit up.** The most common report about this plugin is that
  it appears to do nothing. `:checkhealth spotlight` and `debug = true` have to
  be able to answer that for any new path.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/spotlight/core/registry.lua` | The spotlight list and the single change event everything funnels through |
| `lua/spotlight/core/match.lua` | The `matchadd()` bookkeeping: window → spotlight id → match id |
| `lua/spotlight/core/pattern.lua` | Token resolution — the ordered pattern list that sees what `<cword>` cannot |
| `lua/spotlight/core/palette.lua` | The eight colors, the round-robin, the locks, dark and light |
| `lua/spotlight/core/count.lua` | On-demand match counting |
| `lua/spotlight/ui/list.lua` | The list: swatch, token, count, jump |
| `lua/spotlight/integrations/menu.lua` | The nvzone/menu entries |
| `lua/spotlight/bindings/` | `usrcmds.lua`, `keymaps.lua`, `autocmds.lua` — the last of which is the three window autocommands that make a window-local match look global |
| `lua/spotlight/config/` | `DEFAULTS.lua` and the validating `get` |
| `lua/spotlight/util/` | The lib.nvim delegates and path handling |
| `doc/`, `docs/` | The vimdoc, and everything the README links to |
| `TESTS/` | The spec suite |

## Adding an action

1. Put the behaviour in `lua/spotlight/core/`, and route every list change
   through `registry.lua`. Do not persist from the action.
2. Expose it three ways: a function on the module, a `:Spotlight` route in
   `bindings/usrcmds.lua` with completion, and an optional preset keymap.
3. If it takes text from the buffer, bound it and report the truncation.
4. If it needs a new config value, add it to `DEFAULTS.lua` and read it through
   `config.get` — never from a table passed around.
5. If it can produce "nothing happened", make that visible under
   `debug = true`.
6. Add a spec under `TESTS/`.
7. Document it in [`commands.md`](commands.md), [`BINDINGS.md`](BINDINGS.md),
   [`api.md`](api.md) and the matching page under
   [`FEATURES/`](FEATURES/README.md).

Normal-mode actions should also appear in
`lua/spotlight/integrations/menu.lua`. Visual-mode ones must not: nvzone/menu
restores the triggering window before running a callback, so there is no
selection left by then.

## Tests

`TESTS/` is a headless spec suite.

```
nvim --headless -u NONE -c "set rtp+=.,../lib.nvim" \
  -c "luafile TESTS/run.lua" -c "qa!"
```

Exit 0 is a pass; lib.nvim is expected as a sibling checkout.
[GitHub Actions](../.github/workflows/ci.yml) runs it plus stylua and luacheck
on every push and pull request to `main`.

`hardening_spec.lua` covers the bounded inputs. If you add a bound, add a case
there rather than trusting the default to hold.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
