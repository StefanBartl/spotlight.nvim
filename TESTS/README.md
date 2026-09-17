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

Specs are listed explicitly in `run.lua`'s `SPECS` table; a new file has to be
added there or CI will never run it. They are nonetheless written to be
independent of one another: the suite passes in the listed order and in reverse.

## Layout

| File                       | Covers                                                                              |
| -------------------------- | ----------------------------------------------------------------------------------- |
| `harness.lua`              | The assertion helpers, the buffer/cursor fixtures, and the module-seam helpers.     |
| `cursor_spec.lua`          | Token resolution: structured log tokens, pattern priority, word/literal classification. |
| `registry_spec.lua`        | Toggle semantics, palette round-robin, `match.max`, snapshot/restore, per-window matches. |
| `nav_spec.lua`             | `]k`/`[k`, `nav.scope = "auto"` narrowing, wrap, match counting, quickfix filtering. |
| `persist_spec.lua`         | The per-file exception semantics, and the config layer's validation/fallbacks.       |
| `persist_store_spec.lua`   | The store round trip: what `save_now` writes, what `load` accepts, `flush`, `status`. |
| `hardening_spec.lua`       | Security-model limits and config validation for adversarial/oversized input.        |
| `config_edge_spec.lua`     | The remaining normalizers, `get()`'s dot path, and the options/DEFAULTS aliasing.    |
| `commands_spec.lua`        | Every `:Spotlight` route, the facade actions, and the preset keymaps.                |
| `keymaps_spec.lua`         | The keymap *declaration*: action order, per-mode binds, the which-key group prefix.  |
| `autocmds_spec.lua`        | The window/buffer/colour/persistence autocmds, driven through the real events.       |
| `match_ledger_spec.lua`    | `core.match` directly: the eligibility gate, `reconcile_window`, forget vs. clear.   |
| `count_edge_spec.lua`      | The entry caps, the 5000-line chunk boundary, and the pinned-item merges.            |
| `list_count_scope_spec.lua`| `list.count_scope = "loaded"`: multi-buffer counting, config validation.            |
| `qf_all_spec.lua`          | `:Spotlight qf all`: multi-buffer quickfix, the global entry cap.                    |
| `dotrepeat_spec.lua`       | `.` after the normal-mode toggle: fresh re-resolution, not a captured closure.       |
| `lock_spec.lua`            | Per-slot lock: the palette fallback fix, snapshot/restore, the all-locked case.      |
| `yank_spec.lua`            | `:Spotlight yank`: register content, truncation, the facade convention.             |
| `sets_spec.lua`            | Spotlight sets: exclusive save/switch/delete, the unknown-name no-op guard.         |
| `map_spec.lua`             | Occurrence density: extmark placement, idempotent re-show, no live recompute.       |
| `winopt_spec.lua`          | Per-window opt-out: window-sticky, immediate strip/refill, other windows unaffected. |
| `line_spec.lua`            | Whole-line rendering: the widened pattern, the one-below priority, every other consumer left honest. |
| `multibyte_spec.lua`       | Byte offsets in real umlaut/CJK/emoji buffers, against handcounted byte columns.     |
| `qf_buffer_scope_spec.lua` | `:Spotlight qf` against a buffer-scoped ("this occurrence only") spotlight.          |
| `hover_spec.lua`           | The hover.nvim preview: the spotlighted-only gate, and `nil` rather than `0` above the count ceiling. |
| `ui_list_spec.lua`         | The chooser's input: rows, labels, counts, titles, the filter, and each mode's handler. |
| `menu_spec.lua`            | The nvzone/menu entry list the plugin *provides*, against ui.contextmenu's contract. |
| `path_spec.lua`            | The project-relative exception key, on both platform branches.                        |
| `util_lib_spec.lua`        | Both arms of every `lib.nvim` accessor — the bridge and the native fallback.          |
| `health_spec.lua`          | `:checkhealth spotlight`, including the machine it exists for: one with nothing installed. |

## Byte offsets

`multibyte_spec.lua` is worth reading before touching anything positional.

Every position in this plugin is a **byte** offset: `\%23c` is a byte column
(`\%23v` would be the display column), `string.find` and `vim.regex:match_str`
count bytes, a quickfix `col` is a byte index, and `nvim_win_get_cursor` reports
bytes. A position computed in characters does not fail loudly — it lands in the
wrong column, or cuts a codepoint in half, and the only symptom is a highlight
that never appears.

So that file spells out its fixture's byte columns in a comment and asserts
against those numbers, including the negative cases: the same token's character
column and display column both have to *fail* to match, or the assertion would
pass on a plugin that counted the wrong unit and got away with it on ASCII.

## No network, no subprocesses, no real pickers

This plugin shells out to nothing and opens no sockets, so there is nothing to
stub on that front. What *is* replaced is the handful of modules that are not on
this suite's runtimepath, or whose failure arms are otherwise unreachable:

| Seam                                   | Why it is cut                                                      |
| -------------------------------------- | ------------------------------------------------------------------ |
| `ui.kit.select`                        | ui.nvim is not a CI checkout; the chooser's *input* is the part this plugin owns. |
| `ui.contextmenu`                       | Same, and `integrations/menu.lua` binds it to a file-local at load time. |
| `lib.nvim.store.project`               | So that no test writes into the user's real per-project cache.       |
| `lib.nvim.debounce`                    | To make a debounced save assertable without waiting on a timer.      |
| `lib.nvim.bindings.keymap`             | To read the declaration instead of binding real keys.                |
| `lib.nvim.cross.platform.is_windows`   | So both path branches run on either platform, not one each.          |
| every other `lib.nvim.*` accessor      | To drive the "degrade to the native equivalent" arm of `util/lib.lua`. |
| `vim.health`                           | To assert the report as data rather than render it.                  |

Two harness helpers do the work, and both restore what they replaced even if the
body raises:

- `t.with_modules({ [name] = double }, fn)` — swap `package.loaded` entries.
  Enough for anything resolved through `require` / `lib.try_require` at call
  time, which is most of this plugin.
- `t.without_modules({ name }, fn)` — make a module look genuinely **not
  installed**, via a `package.preload` entry that raises. Clearing
  `package.loaded` alone would not do it: the next `require` would simply re-read
  the module from the runtimepath, where it is still sitting.

A module that binds a dependency to a file-local at load time
(`integrations/menu.lua` and `bindings/keymaps.lua` do; `ui/list.lua` does not)
has to be re-required *inside* the swap. `menu_spec.lua` and `keymaps_spec.lua`
do that and put `package.loaded` back afterwards.

One pre-existing side effect is worth knowing about: `sets_spec.lua` exercises
`spotlight.sets` against the **real** `lib.nvim.store.project`, so a run leaves
an empty `spotlight/sets` snapshot in the project's cache directory. It deletes
every set it created, but — unlike `persist.save_now`, which drops the file when
there is nothing worth keeping — `sets` has no such rule, so the empty file
stays behind. Nothing else in the suite touches the real store.

## What is deliberately not tested here

**Rendering.** Whether `matchadd()` produces the right pixels is Vim's business;
the suite asserts that the *ledger* is right (`getmatches()` in each window, one
entry per active spotlight, none left after a clear), which is the part this
plugin owns. The chooser float is likewise exercised only through
`ui.kit.select`'s own contract — `ui_list_spec.lua` asserts the item list handed
to it, never a window.

**`lua/spotlight/@types/init.lua`.** Annotations only, no runtime code.

**`plugin/spotlight.lua`.** A three-line `vim.g.loaded_spotlight` guard with no
branch worth asserting, and `-u NONE` never sources it anyway.

**`config/DEFAULTS.lua` as a data table.** Its *values* are asserted wherever
they are the fallback a normalizer reaches for; the table itself carries no logic.

**The lazy-load arm of `bindings/autocmds.lua`** (`vim.v.vim_did_enter == 1` →
schedule `persist.load()` immediately, because `VimEnter` has already fired). The
suite runs from a `-c` command during startup, so the flag is still 0 and that
branch is unreachable from here. Its counterpart — that `setup()` then schedules
*nothing* extra, so a normal startup loads once and not twice — is asserted.

**What `palette.apply()` looks like.** Its *call count* is asserted (zero during
a render pass; one per slot on `ColorScheme` and on `OptionSet background`),
because `nvim_set_hl` forces a full redraw and therefore belongs at
config-build time rather than in a render path. Which colours land on screen is
not this suite's business.

## Defects this suite pins rather than fixes

Each is marked with a `BUG:` assertion at the site, with the reasoning and the
suggested fix in a comment above it. They are pinned rather than fixed because
each one changes user-visible behaviour.

1. **A charwise Visual selection ending on a multibyte character is cut in
   half** (`multibyte_spec.lua`). `cursor.selection` slices the line with
   `col('v')` .. `col('.')`, and `col('.')` is the *first* byte of the character
   under the cursor, not its last — so selecting a single `Ä` / `日` / `🚀`
   yields one byte. Nothing refuses the result: the registry accepts it,
   `matchadd()` accepts the pattern, the user is told "spotlight 1: …" — and
   nothing ever lights up, because no engine can match half a codepoint.
   Distinct glyphs that share a lead byte also collapse onto one spotlight text,
   so the second is refused as a duplicate of the first.
   `bindings/usrcmds.range_text` reads `'>` and has the same defect, so
   `:'<,'>Spotlight toggle` and `:'<,'>Spotlight here` are affected too. Fix:
   extend the end column to the end of its character (`vim.str_utf_end`) in both
   places.
2. **`health.check()`'s last statement calls into the dependency it just
   reported missing** (`health_spec.lua`). Without
   `lib.nvim.bindings.usercmd.composer`, `:checkhealth spotlight` prints its
   whole report and then dies with a stack trace at the unguarded
   `require("lib.nvim.bindings.usercmd.composer").checkhealth("Spotlight")` — on
   precisely the machine the error branch above it exists for. Fix: `pcall` it,
   or gate it on the probe the `LIB_MODULES` loop already performed.
3. **`ui.list.filter` cannot find a spotlight by its own text when it has no
   `origin`** (`ui_list_spec.lua`). The fields are walked with
   `ipairs({ item.hl, item.origin, item.text })`, and `ipairs` stops at the first
   nil — so for every spotlight created in a buffer with no file on disk, index 2
   is nil and `item.text` at index 3 is never examined. Only the
   highlight-group name is left, which is the one field a user would never type.
   Fix: walk a nil-tolerant list, or test the three fields explicitly.
4. **The merged options table shares its sub-tables with `DEFAULTS`**
   (`config_edge_spec.lua`), although `DEFAULTS.lua` says "Never mutate it at
   runtime". `config.options.match` *is* `DEFAULTS.match`, down to the individual
   palette entries, and the normalizers' fallback branches hand out
   `DEFAULTS.<section>.<list>` by reference as well. Nothing inside the plugin
   writes to one today — that is asserted, so a change which starts to is caught
   — but `config.options` and `config.get` are public. Fix: merge onto
   `vim.deepcopy(DEFAULTS)`.
5. **`integrations/menu.lua` puts padding in the label** where
   `ui.contextmenu.entry`'s own documentation says a leading glyph belongs in
   `opts.icon` and "never in `label`" (`menu_spec.lua`). Every spotlight entry
   therefore indents one column past every other entry in a composed menu, and
   the icon column that exists for exactly this goes unused.

Two further things are pinned as *documented behaviour* rather than as defects:
`spotlight.setup()` is idempotent for the autocmds, the keymaps and the palette,
but `persist.setup()` appends a registry change listener every time it runs, with
no way to unsubscribe (`autocmds_spec.lua`); and `hover.token_at` is a byte-wise,
ASCII-only test, so a spotlighted multibyte token never gets a hover count
(`multibyte_spec.lua`).
