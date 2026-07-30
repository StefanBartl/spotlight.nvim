# spotlight.nvim — test suite

Plain headless Neovim, no plenary and no busted. The only dependencies are
Neovim itself and `lib.nvim`, so CI does not have to install a test framework to
check one plugin.

## Running

From the plugin root, with `lib.nvim` checked out as a sibling directory:

```bash
nvim --headless -u NONE -c "set rtp+=.,../lib.nvim" -c "luafile docs/TESTS/run.lua" -c "qa!"
```

`run.lua` prints `N passed, M failed`, lists every failure, and exits non-zero
when anything failed. Failures do not abort the run — one broken expectation must
not hide the state of every check after it.

## Layout

| File                | Covers                                                                              |
| ------------------- | ----------------------------------------------------------------------------------- |
| `harness.lua`       | The assertion helpers and buffer/cursor fixtures.                                   |
| `cursor_spec.lua`   | Token resolution: structured log tokens, pattern priority, word/literal classification. |
| `registry_spec.lua` | Toggle semantics, palette round-robin, `match.max`, snapshot/restore, per-window matches. |
| `nav_spec.lua`      | `]k`/`[k`, `nav.scope = "auto"` narrowing, wrap, match counting, quickfix filtering. |
| `persist_spec.lua`  | The per-file exception semantics, and the config layer's validation/fallbacks.       |
| `commands_spec.lua` | Every `:Spotlight` route, the facade actions, and the preset keymaps.                |

## What is deliberately not tested here

Rendering. Whether `matchadd()` produces the right pixels is Vim's business; the
suite asserts that the *ledger* is right (`getmatches()` in each window, one entry
per active spotlight, none left after a clear), which is the part this plugin
owns. The chooser float is likewise exercised only through
`lib.nvim.ui.kit.select`'s own contract.
