# spotlight.nvim — test suite

Plain headless Neovim, no plenary and no busted. The only dependencies are
Neovim itself and `lib.nvim`, so CI does not have to install a test framework to
check one plugin.

## Running

From the plugin root, with `lib.nvim` checked out as a sibling directory:

```bash
nvim --headless -u NONE -c "set rtp+=.,../lib.nvim" -c "luafile TESTS/run.lua" -c "qa!"
```

`run.lua` prints `N passed, M failed`, lists every failure, and exits non-zero
when anything failed. Failures do not abort the run — one broken expectation must
not hide the state of every check after it.

## Layout

| File                       | Covers                                                                              |
| -------------------------- | ----------------------------------------------------------------------------------- |
| `harness.lua`              | The assertion helpers and buffer/cursor fixtures.                                   |
| `cursor_spec.lua`          | Token resolution: structured log tokens, pattern priority, word/literal classification. |
| `registry_spec.lua`        | Toggle semantics, palette round-robin, `match.max`, snapshot/restore, per-window matches. |
| `nav_spec.lua`             | `]k`/`[k`, `nav.scope = "auto"` narrowing, wrap, match counting, quickfix filtering. |
| `persist_spec.lua`         | The per-file exception semantics, and the config layer's validation/fallbacks.       |
| `hardening_spec.lua`       | Security-model limits and config validation for adversarial/oversized input.        |
| `commands_spec.lua`        | Every `:Spotlight` route, the facade actions, and the preset keymaps.                |
| `list_count_scope_spec.lua`| `list.count_scope = "loaded"`: multi-buffer counting, config validation.            |
| `qf_all_spec.lua`          | `:Spotlight qf all`: multi-buffer quickfix, the global entry cap.                    |
| `dotrepeat_spec.lua`       | `.` after the normal-mode toggle: fresh re-resolution, not a captured closure.       |
| `lock_spec.lua`            | Per-slot lock: the palette fallback fix, snapshot/restore, the all-locked case.      |
| `yank_spec.lua`            | `:Spotlight yank`: register content, truncation, the facade convention.             |
| `sets_spec.lua`            | Spotlight sets: exclusive save/switch/delete, the unknown-name no-op guard.         |
| `map_spec.lua`             | Occurrence density: extmark placement, idempotent re-show, no live recompute.       |
| `winopt_spec.lua`          | Per-window opt-out: window-sticky, immediate strip/refill, other windows unaffected. |

## What is deliberately not tested here

Rendering. Whether `matchadd()` produces the right pixels is Vim's business; the
suite asserts that the *ledger* is right (`getmatches()` in each window, one entry
per active spotlight, none left after a clear), which is the part this plugin
owns. The chooser float is likewise exercised only through
`lib.nvim.ui.kit.select`'s own contract.
