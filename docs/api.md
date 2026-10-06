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
| `spotlight.spotlights(opts?)` | any | `Spotlight.PublicItem[]` | A detached snapshot of the registry — for a status line, a scripted check, or a plugin that mirrors the spotlights elsewhere |
| `spotlight.colors()` | any | `Spotlight.SlotColor[]` | The palette as the editor renders it, one entry per slot |
| `spotlight.export()` | any | `Spotlight.StoredItem[]` | The active spotlights as plain, JSON-able data — what a set holds — for a host that stores them itself |
| `spotlight.import(items)` | any | `integer` | Clear the active spotlights and restore `items` (exclusive, re-validated); returns how many came back |

Both are read-only and stable: the field names below are part of the contract.

### `spotlight.spotlights(opts?)`

Returns a fresh table of plain copies in insertion order. Sorting, pruning or
editing the result never touches the registry.

`opts.whole_file` filters by scope: `true` keeps only the spotlights that mark
every occurrence (`toggle`, `toggle_selection`, `add`), `false` only the "this
occurrence only" ones (`toggle_here`...), omitted keeps both. A consumer with
no position to pin a single occurrence to — a browser preview of the file — asks
for `{ whole_file = true }`.

| Field | Type | Meaning |
| --- | --- | --- |
| `text` | `string` | The raw token |
| `slot` | `integer` | Palette slot, `1..8` by default |
| `hl_group` | `string` | Highlight group it renders in, e.g. `"Spotlight3"` (`hl` is the same value under the registry's own name) |
| `line_mode` | `boolean` | Rendered across the whole line instead of the token (`line` is an alias) |
| `origin` | `string\|nil` | Project-relative path of the file it was created in |
| `whole_file` | `boolean` | `true` for every-occurrence spotlights, `false` for position-pinned ones |
| `scope` | `"global"\|"buffer"` | The same distinction as a word: `"global"` is whole-file |
| `kind` | `"word"\|"literal"` | How the highlight matches *now*: `"word"` only while it is matched between word boundaries (`\<`...`\>`); `"literal"`: matched anywhere, also inside longer words. A word token reads `"literal"` while `match.word_boundaries` is off |
| `ignore_case` | `boolean` | `false` (the default): matching is case-sensitive, like the highlight |
| `locked` | `boolean` | Its slot is never handed to another spotlight |
| `id` | `integer` | Session id, never reused |
| `pattern` | `string` | The complete Vim regex the highlight uses |
| `buf`, `row1`, `col1` | `integer\|nil` | Only for `whole_file = false`: the pinned position |

`kind` and `ignore_case` are what a mirror needs to reproduce the highlight's
matching rules: `text` is always matched literally (it is not a pattern), case
exactly as written unless `ignore_case`, and only as a whole word when `kind` is
`"word"`. That is why `kind` follows the rendering: with
`match.word_boundaries = false` a word token carries no boundary and is reported
as `"literal"`. The token's own kind is not lost meanwhile — the spotlight
remembers it, so `refresh()` gives the boundaries back once the option is on
again, and `export()` / the persisted snapshot carry it (see below).

### `spotlight.colors()`

One `{ slot, group, fg, bg, bold }` entry per palette slot, with `fg` and `bg`
as `#rrggbb` resolved from the live `Spotlight1..8` groups — so a colorscheme or
a user override is what is reported, and `&background` selects the dark or light
set. A channel a group does not carry falls back to the configured palette
color, so an entry always has both.

### `spotlight.export()` and `spotlight.import(items)`

The registry as data and back, for a plugin that keeps spotlights in its own
storage (casedesk.nvim writes them into each case folder, so a case brings its
own markings back). `export()` returns `Spotlight.StoredItem[]` — `text`,
`slot`, `kind`, `origin`, `locked`, `line` — and nothing else: no ids, no regex.
Here `kind` is what the token was made as, independent of
`match.word_boundaries`: a word token stays a word through an export, an import
and a persisted snapshot even while the option is off. An entry without `kind`
(written before the field was recorded) imports as `"literal"`.
Left out: position-pinned ("this occurrence only") spotlights, and those created
in a file with an explicit `persist off` (that decision means "do not write
tokens from this file to disk", and the host is about to). The global
`persist.default` is not consulted: an export is an explicit request.

`import(items)` is exclusive — the active spotlights are cleared, not merged —
and every field is re-validated like a persisted snapshot (type checks, length
cap, dedup, count cap, the regex rebuilt from `text`), so a hand-edited file
cannot inject a pattern. It announces itself like a set switch (one
`User SpotlightChanged`, reasons `clear` + `restore`) and updates the project's
own persisted snapshot. `import({})` clears.

## Events

spotlight.nvim announces every change to the spotlights as a `User` autocommand:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "SpotlightChanged",
  callback = function(args)
    local items = require("spotlight").spotlights({ whole_file = true })
    local colors = require("spotlight").colors()
    -- args.data: see below
  end,
})
```

It fires after a toggle, an add or remove, `clear`, a `sets switch`, a restore
of the persisted spotlights, a lock or whole-line change, `refresh`, a pinned
spotlight dropped because its buffer was wiped, and a color change
(`:colorscheme`, `&background`). Nothing fires for an action that changed
nothing (clearing an empty list, adding a duplicate, a `refresh` that found every
group and pattern as it was).

The event is **coalesced**: any number of changes within one editor tick — a
`sets switch` is a clear plus a restore, a session restore adds dozens — arrive
as a single event, scheduled with `vim.schedule`. Read the state with
`spotlights()` / `colors()` in the callback; the payload only says what kind of
change it was.

`args.data`:

| Field | Type | Meaning |
| --- | --- | --- |
| `reasons` | `string[]` | Why, each once, in first-occurrence order: `"add"`, `"remove"`, `"clear"`, `"restore"`, `"rebuild"`, `"lock"`, `"line"`, `"buffer_wiped"`, `"colors"` |
| `count` | `integer` | Spotlights in the registry afterwards, of every scope |
| `whole_file_count` | `integer` | Of those, the whole-file ones |
| `whole_file_changed` | `boolean` | `false` only when every merged change concerned a position-pinned spotlight — a mirror that shows whole-file spotlights only can skip the event |

`refresh()` re-adds every match whatever happened, but announces only what came
out different: `colors` when a `Spotlight1..8` group was redefined to other
values, `rebuild` when a pattern or slot changed (a word token once
`match.word_boundaries` was switched, a slot clamped into a smaller palette).

A `colors` reason is a color change: re-read `colors()`. It comes from the
spotlight.nvim handler that redefines `Spotlight1..8`, which
`palette.reapply_on_colorscheme = false` switches off — with that, you own the
groups and a consumer that mirrors them listens to `ColorScheme` itself.

## What is not here

There is no `USECASES/` folder, and deliberately so: every function above is a
single call that completes on its own. The only multi-step recipe worth
writing down is "bind your own keys", and that lives next to the config it
needs, in [configuration.md](configuration.md#keymaps).
