# Finding your way around what is marked

A color tells you a token is here. These features answer *where else*, *how
many*, and *show me only those lines*.

## The spotlight list

Every active spotlight, one row each: color swatch, token text, and a match
count computed on demand in the current buffer. Selecting a row jumps to its
first occurrence (or removes it, in the `list_remove` variant). Counting is
skipped above `list.count_max_lines` and the row shows `?` instead — opening
the list should never itself become the slow part.

With `list.count_scope = "loaded"`, the count column sums matches across
every *loaded* buffer (ordinary file buffers only — terminal/quickfix/help
buffers are excluded) instead of just the current one, so it answers "how
many total" rather than "how many here". Opt-in, not the default: it
multiplies the one O(buffer) scan in the plugin by however many buffers are
loaded. A buffer that individually exceeds `list.count_max_lines` is skipped
from the sum rather than making the whole count unknown — the row then shows
`N+` (a lower bound) instead of a plain `N`, and the list's title says so.

### Filtering the list

`:Spotlight list [action] [filter]` narrows before showing. Once several
spotlights are active, `remove` mode over twenty entries is a scroll rather
than a choice.

One filter argument rather than separate `--color`/`--origin` flags: the
fields never collide in practice (a slot is a number, an origin is a path,
the text is neither), so one token answers both questions. It matches the
palette slot, the highlight group, the origin path, and the spotlight's text.

A **numeric** query is only a slot query, with no substring fallback.
Falling through would make `1` match slot 10 as well — via the `1` in its own
highlight group name `Spotlight10` — undoing the exact test it just passed.

- **Module:** `ui/list.lua` (`M.filter`, `M.open`), `core/count.lua`
  (`M.count`, `M.count_loaded`, `M.scannable_buffers`)
- **Keymaps:** `<leader>sL` (list/jump)
- **Usercmds:** `:Spotlight list [jump|remove|lock|line] [filter]`
- **Config:** `list.count` (default `true`), `list.count_max_lines` (default
  `200000`), `list.count_scope` (default `"buffer"`, or `"loaded"`),
  `list.swatch`

## Next / previous navigation

`]k` / `[k` jump one occurrence at a time, `unimpaired`-style (`3]k` is three
one-step jumps). Built on `search()`, not a collected position list, so a jump
costs the distance travelled rather than the size of the file, and it
deliberately never touches the search register or `'hlsearch'`. With
`nav.scope = "auto"` (the default), a cursor sitting inside one spotlight's
match navigates only that spotlight; off any match, all spotlights are
searched together.

### Forcing the session-wide search

`:Spotlight! next` / `! prev` ignore `nav.scope` and search every spotlight.
`auto` narrowing is right until the moment you want the opposite, and the
only way out was editing the config and reloading.

It is **per call, not a mode**: the next plain jump narrows again. The
override is a parameter threaded to `nav_pattern`, not stored state, so there
is nothing to reset and nothing to leak into a later jump.

- **Module:** `nav.lua` (`M.jump`, `M.next`, `M.prev`, `M.under_cursor`)
- **Keymaps:** `]k`, `[k`
- **Usercmds:** `:Spotlight[!] next`, `:Spotlight[!] prev`
- **Config:** `nav.scope` (default `"auto"`), `nav.wrap` (default `true`),
  `nav.center` (default `true`)

## Occurrence density (sign column)

The answer to "where in the file does this token cluster": `:Spotlight map`
scans the current buffer once and places a sign on every matching line, in the
matching spotlight's own color — a shape the highlighting itself cannot show,
since `matchadd()` renders only what is currently visible. Deliberately
one-shot and explicit, not live: the whole plugin's design principle is zero
cost per keystroke or text change, and a density map that stayed current would
need exactly the invalidation that principle exists to avoid. Editing the
buffer after `:Spotlight map` leaves the marks exactly where they were; run it
again to refresh them.

With `:Spotlight map {text}`, only that spotlight's lines. `:Spotlight map
clear` removes the marks from the current buffer. Per-buffer, not global —
showing the map in a different buffer never touches another buffer's marks,
and nothing needs cleaning up on `BufWipeout`: Neovim drops a wiped buffer's
extmarks with it, so this feature adds zero new autocmds.

- **Module:** `map.lua` (`M.show`, `M.clear`), `core/count.lua`
  (`M.matching_lines_by_item`)
- **Keymaps:** none — deliberately command-only, matching the feature's own
  "cost visible and opt-in" design principle; a default key would undercut it
- **Usercmds:** `:Spotlight map [text]`, `:Spotlight map clear`
- **Config:** `map.sign_text` (default `"▪"`, ≤2 display cells — Neovim's own
  sign-text limit), `map.max_entries` (default `10000`, independent of
  `quickfix.max_entries`)

## Quickfix filter

Every line in the current buffer matching any spotlight — or one specific
spotlight's matches — sent to the quickfix list, each line reported once even
if several spotlights hit it. Capped at `quickfix.max_entries`, with scanning
stopped (not just truncated after the fact) once the cap is hit, and the
truncation reported in both the notification and the quickfix title.

`:Spotlight qf all` is the multi-buffer counterpart: every loaded, ordinary
file buffer is scanned and merged into one list. The cap is global rather
than per-buffer — each buffer gets whatever budget is left after earlier
ones, and the buffer loop itself stops (not just the entry list) the moment
one buffer's scan reports truncation.

- **Module:** `qf.lua` (`M.fill`, `M.fill_all`), `core/count.lua`
  (`M.matching_lines`, `M.scannable_buffers`)
- **Keymaps:** `<leader>sq`
- **Usercmds:** `:Spotlight qf [text]`, `:Spotlight qf all [text]`
- **Config:** `quickfix.open` (default `true`), `quickfix.title`,
  `quickfix.max_entries` (default `10000`)

## Yank matching lines to a register

`:Spotlight yank` is the quickfix filter's sibling for "I just want the
text": every line in the current buffer matching a spotlight — or one
specific spotlight's matches — yanked into the unnamed register, one line
per match, in buffer order. Reuses `core/count.lua`'s `M.matching_lines`
verbatim, so the scanning cost, the `quickfix.max_entries` cap, and the
"each line reported once" guarantee are identical to `:Spotlight qf`; only
the destination differs. Deliberately narrow for now — always the unnamed
register, always raw line text with no line-number prefix.

- **Module:** `yank.lua` (`M.yank`), `core/count.lua` (`M.matching_lines`)
- **Usercmds:** `:Spotlight yank [text]`
- **Config:** `quickfix.max_entries` (default `10000`, shared with the
  quickfix filter)
