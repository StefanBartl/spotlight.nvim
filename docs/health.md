# `:checkhealth spotlight`

```vim
:checkhealth spotlight
```

Read-only: it never mutates anything, so running it is always safe. It reports
four sections plus the command verb's own check. For a symptom you already
have, start at [troubleshooting.md](troubleshooting.md) instead — this page
explains what the output *means*.

## `spotlight.nvim`

The environment.

| Line | Meaning |
| --- | --- |
| `Neovim <version>` | OK. The plugin targets **0.9+** |
| `spotlight.nvim targets Neovim 0.9+` | WARN. Everything below may still work, but nothing is guaranteed |
| `'termguicolors' is on` | OK. The palette's `#rrggbb` values render as configured |
| `'termguicolors' is off` | WARN. The hex values are approximated to the terminal's 256-color cube, so slots become harder to tell apart. `vim.o.termguicolors = true` fixes it |

## `spotlight.nvim: lib.nvim`

Each `lib.nvim` module is checked separately, because "lib.nvim missing" is not
a useful answer — a missing `usercmd.composer` and a missing `debounce` are
very different problems.

| Module | Required | What is lost without it |
| --- | --- | --- |
| `lib.nvim.bindings.usercmd.composer` | **yes** | The `:Spotlight` verb does not exist at all |
| `lib.nvim.ui.kit.select` | **yes** | The spotlight list cannot open |
| `lib.nvim.bindings.keymap` | **yes** | The keymap preset is not bound |
| `lib.nvim.store.project` | no | Per-project persistence; falls back to a native equivalent |
| `lib.nvim.debounce` | no | Coalesced state saves |
| `lib.nvim.notify` | no | Namespaced notifications |
| `lib.nvim.logger` | no | Structured debug logs; `debug = true` falls back to `vim.notify` at DEBUG level |
| `lib.nvim.dotrepeat` | no | `.` after the normal-mode toggle |
| `lib.nvim.bindings.autocmd` | no | Guarded autocommands |
| `lib.nvim.ui.hl` | no | Highlight definition |

A required module missing is reported as an **error** with the install line; an
optional one as **info**, because the fallback is intended behaviour and not a
defect.

which-key is reported here too. Its absence is info, never a warning: mappings
carry their own `desc` either way, and only the group label depends on it.

## `spotlight.nvim: configuration`

Either `configuration validated cleanly`, or one **warning per rejected
value** naming the key and what it fell back to. Nothing here is fatal by
design — see
[FEATURES/DIAGNOSTICS.md](FEATURES/DIAGNOSTICS.md#bounded-non-throwing-configuration).

Then the resolved settings, as info lines: palette size for the current
`&background`, the match options (priority and whether it renders above
`'hlsearch'`, case sensitivity, word boundaries, `max`), how many cursor
resolver patterns are loaded and whether the `<cword>` fallback is on, the
list's count settings including its scope, the map's sign text and cap, the
debug switch, and the keymap preset with every bound `lhs`.

Two of those are worth reading even when nothing is wrong: **how many resolver
patterns are loaded** (a dropped pattern is a warning above, but the count is
the quick confirmation), and **the bound `lhs` list** — it is the authoritative
answer to "which key did my override actually take".

## `spotlight.nvim: state`

The live picture: how many spotlights are active across how many tracked
windows, then one line per spotlight with its slot, highlight group and text.

Two annotations appear there:

- `[locked]` — this spotlight keeps its palette slot permanently.
- `[whole line, priority N]` — this spotlight renders in line mode, one
  priority **below** `match.priority`. That is the first thing to check when a
  color appears to have vanished under another.

Then windows currently opted out (only if any are), persistence — on/off, the
resolved project root, what applies to the current file, and every per-file
override — and the saved sets with their spotlight counts.

Finally the composer's own `checkhealth("Spotlight")` verifies the route tree
behind the command.
