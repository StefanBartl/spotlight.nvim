# The `:Spotlight` command

One verb with `<Tab>`-completed subcommands, built on `lib.nvim`'s user-command
composer — so completion, argument validation and the generated docs all come
from the same route tree. There is no second command; every action the plugin
has is a route here, and every route has a matching function on the
[facade](api.md).

## Table of contents

- [Marking](#marking)
- [The list](#the-list)
- [Navigation](#navigation)
- [Extracting matches](#extracting-matches)
- [Rendering](#rendering)
- [Sets](#sets)
- [Scope and persistence](#scope-and-persistence)
- [Maintenance](#maintenance)

## Marking

| Command | Args | Range | Description |
| --- | --- | --- | --- |
| `:Spotlight` | — | no | Default route: toggle every occurrence of the token under the cursor (same as `<leader>sK`). Dot-repeatable |
| `:Spotlight toggle` | `[text]` | yes | Toggle every occurrence: the cursor token, a `'<,'>` range selection, or explicit `text` |
| `:Spotlight here` | — | yes | Toggle only this occurrence: the cursor token, or a `'<,'>` range selection (same as `<leader>sk`) |
| `:Spotlight add` | `{text}` | no | Add a spotlight for the literal `text` |
| `:Spotlight remove` | `{text}` | no | Remove the spotlight matching `text` exactly |
| `:Spotlight clear` | — | no | Remove every spotlight |

`:'<,'>Spotlight toggle` and `:'<,'>Spotlight here` work from a visual
selection: the selection is read from the `'<`/`'>` marks, which is exactly
when they become valid — by the time a `:` command runs, Visual mode has
already ended. Only a **charwise** selection within a **single line** is
accepted; linewise has no columns to read, blockwise spans several lines by
definition, and a pattern containing a newline cannot match anything
`matchadd()` sees.

`toggle` with explicit `text` toggles by exact text: if a spotlight for that
string exists it is removed, otherwise it is added. That is the same identity
`add`/`remove` use, so the three routes never disagree about what "the same
spotlight" means.

## The list

| Command | Args | Description |
| --- | --- | --- |
| `:Spotlight list` | `[jump\|remove\|lock\|line] [filter]` | Open the list; the action decides what selecting a row does |

Without an action, selecting a row jumps to the spotlight's first occurrence.
`remove` deletes it, `lock` toggles whether it keeps its palette slot
permanently, and `line` toggles whole-line rendering.

`filter` narrows the list before it is shown. One argument rather than
separate `--color`/`--origin` flags: the fields never collide in practice, so
a single token answers both questions. It matches the palette slot, the
highlight group (`Spotlight3`), the origin path, and the spotlight's own text.
A **numeric** query is only ever a slot query, with no substring fallback —
otherwise `1` would also match slot 10, via the `1` in its own highlight group
name `Spotlight10`, undoing the exact test. Everything else is plain
substring, case-insensitive.

## Navigation

| Command | Bang | Description |
| --- | --- | --- |
| `:Spotlight next` | yes | Jump to the next occurrence |
| `:Spotlight prev` | yes | Jump to the previous occurrence |

`!` ignores `nav.scope` for that one jump and searches every spotlight. It is
per call, not a mode: the next plain jump narrows again. With the default
`nav.scope = "auto"`, a plain jump from inside a spotlight's match follows
*that* spotlight and a jump from anywhere else walks all of them.

## Extracting matches

| Command | Args | Description |
| --- | --- | --- |
| `:Spotlight qf` | `[text]` | Matching lines in the current buffer → quickfix (all spotlights, or just `text`'s) |
| `:Spotlight qf all` | `[text]` | Same, across every loaded ordinary file buffer, merged into one list |
| `:Spotlight yank` | `[text]` | Matching lines in the current buffer → unnamed register |
| `:Spotlight map` | `[text]` | Mark every matching line in the sign column |
| `:Spotlight map clear` | — | Clear the sign-column occurrence map in the current buffer |

A line matched by several spotlights is reported once: the question is which
lines, not which highlights. All four share `quickfix.max_entries` /
`map.max_entries` as a hard cap, and truncation is reported rather than
silent.

## Rendering

| Command | Args | Description |
| --- | --- | --- |
| `:Spotlight line` | `[text]` | Toggle whole-line rendering for a spotlight (`text`, or the cursor token) |
| `:Spotlight lock` | `[text]` | Toggle whether a spotlight keeps its palette slot permanently |
| `:Spotlight refresh` | — | Redefine the palette and re-apply every match to every window |

`line` and `lock` both need a spotlight that already exists; on a token with
none they report that rather than creating one. For a "this occurrence only"
spotlight — which has no text identity to name — use `:Spotlight list line`
or `:Spotlight list lock` instead.

## Sets

| Command | Args | Description |
| --- | --- | --- |
| `:Spotlight sets save` | `{name}` | Save the active spotlights as a named set (overwrites) |
| `:Spotlight sets switch` | `{name}` | Clear the active spotlights and restore a saved set |
| `:Spotlight sets delete` | `{name}` | Delete a saved set (active spotlights untouched) |
| `:Spotlight sets list` | — | List every saved set and how many spotlights it holds |

`switch` and `delete` tab-complete from the names that currently exist.
Switching to an unknown name is a refused no-op rather than a clear, because
the active registry is otherwise fully replaced.

## Scope and persistence

| Command | Args | Description |
| --- | --- | --- |
| `:Spotlight persist` | `[on\|off\|default\|status]` | Per-file persistence override; no argument means `status` |
| `:Spotlight winopt` | `[on\|off\|toggle\|status]` | Per-window opt-out; no argument means `toggle` |

`persist default` drops the override for the current file so it follows the
global `persist.default` again. `persist status` reports what applies here and
why. The exception is about a spotlight's **origin**, not its appearances —
see
[FEATURES/PERSISTENCE.md](FEATURES/PERSISTENCE.md#why-origin-not-appearance).

`winopt off` excludes the current window from spotlighting and strips its
matches immediately; `on` re-fills it. The flag lives on the window, so it
survives that window showing a different buffer.

## Maintenance

`:checkhealth spotlight` is not a route of this verb but the other half of the
same job — see [health.md](health.md). `:Spotlight refresh` is listed under
[Rendering](#rendering) and is the escape hatch when another plugin has called
`:call clearmatches()`.

## Where else this is written down

| Place | Form |
| --- | --- |
| `:Spotlight <Tab>` | Live completion from the same route tree this page describes |
| [BINDINGS.md](BINDINGS.md) | The one-line cheatsheet, next to the keymaps and autocommands |
| `:help spotlight-commands` | The same reference as Vim help |
