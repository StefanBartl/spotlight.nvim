# Lua API

Every action is a plain function on the `spotlight` module — no `<Plug>`
indirection, and no action that exists only as a keymap. The preset keymaps
and every `:Spotlight` route bind directly onto these, so anything reachable
by key or command is reachable from Lua on identical terms.

```lua
local spotlight = require("spotlight")
```

## Setup

| Function | Returns | Description |
| --- | --- | --- |
| `spotlight.setup(opts?)` | `nil` | Apply configuration, define the highlight groups, wire every binding. `opts` is a `Spotlight.Config` — see [configuration.md](configuration.md) |

Calling `setup()` again is safe: the augroups are cleared and rebuilt, and the
keymap registry re-registers the preset.

## Marking

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.toggle()` | n | `boolean` | Toggle every occurrence of the resolved token under the cursor |
| `spotlight.toggle_selection()` | x | `boolean` | Toggle every occurrence of the exact visual selection (literal) |
| `spotlight.toggle_here()` | n | `boolean` | Toggle only this occurrence of the resolved token under the cursor |
| `spotlight.toggle_here_selection()` | x | `boolean` | Toggle only this occurrence of the exact visual selection |
| `spotlight.toggle_here_at(text, pos)` | any | `boolean` | Toggle only the occurrence at an explicit `{ buf, row1, col1 }` |
| `spotlight.add(text)` | any | `boolean` | Add a spotlight for a literal string |
| `spotlight.remove(text)` | any | `boolean` | Remove by exact text |
| `spotlight.clear()` | any | `boolean` | Remove every spotlight |

## The list

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.list(filter?)` | n | `nil` | Open the list; selection jumps |
| `spotlight.list_remove(filter?)` | n | `nil` | Open the list; selection removes |
| `spotlight.list_lock(filter?)` | n | `nil` | Open the list; selection toggles the lock |
| `spotlight.list_line(filter?)` | n | `nil` | Open the list; selection toggles whole-line rendering |

`filter` is the same single token the command takes: it matches the palette
slot, the highlight group, the origin path, or the spotlight's text.

## Navigation

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.next(all_scopes?)` | n | `boolean` | Next occurrence. `all_scopes = true` ignores `nav.scope` for this call |
| `spotlight.prev(all_scopes?)` | n | `boolean` | Previous occurrence, same argument |

Both honour `vim.v.count1`, so a count prefix on a mapping works without any
extra wiring.

## Extracting matches

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.quickfix(text?)` | n | `boolean` | Matching lines in the current buffer → quickfix |
| `spotlight.quickfix_all(text?)` | n | `boolean` | Same, across every loaded ordinary file buffer |
| `spotlight.yank(text?)` | any | `boolean` | Matching lines in the current buffer → unnamed register |
| `spotlight.map(text?)` | any | `boolean` | Mark every matching line in the sign column |
| `spotlight.map_clear()` | any | `boolean` | Clear the sign-column occurrence map |

## Rendering

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.lock_set(text, value)` | any | `boolean` | Set the slot lock for the spotlight matching `text` exactly |
| `spotlight.lock_toggle(text?)` | any | `boolean` | Toggle the slot lock for `text`, or the cursor token |
| `spotlight.line_set(text, value)` | any | `boolean` | Set whole-line rendering for the spotlight matching `text` exactly |
| `spotlight.line_toggle(text?)` | any | `boolean` | Toggle whole-line rendering for `text`, or the cursor token |
| `spotlight.refresh()` | any | `nil` | Redefine the palette and re-apply every match |

## Sets

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.sets_save(name)` | any | `boolean` | Save the active spotlights as a named set (overwrites) |
| `spotlight.sets_switch(name)` | any | `boolean` | Clear the active spotlights and restore a saved set |
| `spotlight.sets_delete(name)` | any | `boolean` | Delete a saved set |
| `spotlight.sets_list()` | any | `nil` | Report every saved set and its spotlight count |

## Scope and persistence

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.winopt_set(value, win?)` | any | `boolean` | Set the per-window opt-out |
| `spotlight.winopt_toggle(win?)` | any | `boolean` | Toggle the per-window opt-out |
| `spotlight.winopt_status(win?)` | any | `nil` | Report whether spotlighting is on in `win` |
| `spotlight.persist_set(value)` | any | `boolean` | `true` / `false` / `nil` override for the current file |
| `spotlight.persist_status()` | any | `nil` | Report the effective persistence status |

## Reading the registry

| Function | Mode | Returns | Description |
| --- | --- | --- | --- |
| `spotlight.spotlights()` | any | `Spotlight.Item[]` | The live registry — for a status line or a scripted check |

Each `Spotlight.Item` carries at least `text`, `pattern`, `slot`, `hl`,
`locked` and `line`; the authoritative shape is
`lua/spotlight/@types/init.lua`.

## What is not here

There is no `USECASES/` folder, and deliberately so: every function above is a
single call that completes on its own. The only multi-step recipe worth
writing down is "bind your own keys", and that lives next to the config it
needs, in [configuration.md](configuration.md#keymaps).
