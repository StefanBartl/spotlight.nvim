# Features

`spotlight.nvim` marks tokens in a log — any number of them, in distinguishable
colors, applied in every window, and persisted per project. Everything below is
verified against `lua/spotlight/` as it stands; the roadmap's "plausible next"
and "wanted, needs design" items are not listed here because none of them have
shipped.

## Toggle a spotlight on every occurrence of the token under the cursor

One key adds a spotlight on whatever the cursor resolver decides you are
pointing at, and the same key removes it again if that exact token is already
lit. `matchadd()` highlights the text everywhere it appears — every window,
every buffer whose content happens to contain it — which is the point: a
request id you spotted in `app.log` is the same request id in `worker.log`.

The normal-mode keymap is dot-repeatable: press `<leader>mK` on one token,
move to another, and `.` toggles that one too — "spotlight this one as well",
via `lib.nvim.dotrepeat`. Each firing re-resolves the cursor token fresh
rather than repeating the original action, so `.` on an already-lit token
removes it, exactly like pressing `<leader>mK` on it again would. The
`:Spotlight` command path (bare `:Spotlight` and `:Spotlight toggle` with no
explicit text or range) is dot-repeatable the same way; a count prefix
(`3<leader>mK`) is deliberately not given a meaning — unlike `3]k`, "toggle
three tokens from one keypress" has no established convention to borrow.

- **Module:** `init.lua` (`M.toggle`), `cursor.lua` (`M.token`),
  `util/lib.lua` (`M.dot_repeatable`, `M.dot_run`)
- **Keymaps:** `<leader>mK` (normal mode) — see [keymaps](../docs/BINDINGS.md#keymaps)
- **Usercmds:** `:Spotlight`, `:Spotlight toggle [text]` — see [user commands](../docs/BINDINGS.md#user-commands)
- **Config:** `keymaps.toggle` (default `<leader>mK`)

## Toggle a visual selection

The same action in visual mode takes the exact selected bytes, literally — no
shape classification, no word boundaries, just what you highlighted. Refused
for a multi-line or whole-line (`V`) selection, since a pattern containing a
newline cannot match anything `matchadd()` sees.

- **Module:** `init.lua` (`M.toggle_selection`), `cursor.lua` (`M.selection`)
- **Keymaps:** `<leader>mK` (visual mode)
- **Usercmds:** `:'<,'>Spotlight toggle`

## Toggle a spotlight on only this occurrence

The narrower sibling of the action above: `<leader>mk` (lowercase) marks
*only* the specific occurrence the cursor or selection is on, not every place
the same text appears. Useful when the text is common (`error`, `null`, a
short id reused across unrelated log lines) and lighting up every instance
would just be noise — this pins the highlight to one exact spot instead.

Implemented as a different kind of spotlight, not a variant of the same one:
the pattern handed to `matchadd()` is anchored to the exact line and column
(`\%<line>l\%<col>c`, built by `core/pattern.lua`'s `M.build_at`) ahead of the
literal text, so a duplicate of the same text elsewhere structurally cannot
satisfy it. Because a position only means anything against the buffer it came
from, rendering is restricted to windows currently showing that buffer (see
`core/match.lua`) rather than applied everywhere the way a global spotlight
is — the one place this feature is not "the same mechanism, narrower input."
It follows that a "this occurrence only" spotlight is **session-only**: it is
excluded from the persisted snapshot (a line/column pin does not survive a
restart the way a text pattern does), and it is dropped automatically if its
buffer is wiped out (`BufWipeout`/`BufDelete`) or a window switches away from
that buffer (`BufWinEnter` reconciliation). Everything else — the list, next/
previous navigation, the quickfix filter, counting — needs no special
handling at all: they already operate on `item.pattern` generically, and a
position-anchored pattern is still just a valid Vim regex to them.

Toggle identity is the exact position, not the text — pressing `<leader>mk`
again on the *same* occurrence removes it, but a second `<leader>mk` on a
different occurrence of the same word adds an independent spotlight, even
while a global spotlight for that same text (from `<leader>mK`) is active.

- **Module:** `init.lua` (`M.toggle_here`, `M.toggle_here_selection`,
  `M.toggle_here_at`), `core/registry.lua` (`M.add_at`, `M.find_at`,
  `M.toggle_at`, `M.remove_for_buffer`), `core/pattern.lua` (`M.build_at`),
  `core/match.lua` (the buffer-scope guard in `add()`, `M.reconcile_window`)
- **Keymaps:** `<leader>mk` (normal + visual mode)
- **Usercmds:** `:Spotlight here`, `:'<,'>Spotlight here`
- **Config:** `keymaps.toggle_here` (default `<leader>mk`)

## Log-aware cursor resolver

`<cword>` splits on `'iskeyword'`, so a UUID is five words, an IPv4 address is
four, and a timestamp is a fistful — exactly the tokens worth tracking in a
log. Instead, a configurable, ordered list of Lua patterns (UUID, ISO
timestamp, clock time, `192.168.1.1:8080`, `0x1f4a`, git shas, `user@host`,
dotted paths, plain numbers) is searched across the cursor line, and the first
pattern whose match spans the cursor column wins. `<cword>` is the last
resort. Above `cursor.max_line_len` the pattern scan is skipped entirely and
`<cword>` answers instead, so a minified single-line log cannot make the scan
itself expensive.

- **Module:** `cursor.lua` (`M.token`, `match_spanning`, `kind_of`)
- **Config:** `cursor.patterns`, `cursor.fallback_cword` (default `true`),
  `cursor.max_line_len` (default `8192`)

## Auto-color palette

Eight `Spotlight1`..`Spotlight8` highlight groups, each with an explicit
background **and** foreground so contrast is the plugin's property rather than
inherited from the colorscheme. Slots are handed out round-robin from the last
one assigned, but skip a slot that is already in use as long as any slot is
free, so two unrelated spotlights don't end up wearing the same color.
Separate dark/light color lists switch automatically with `'background'`, and
every group is redefined on `ColorScheme` (a colorscheme clears groups it does
not know about).

A spotlight can lock its slot — "keep this one on slot 1 forever", for a
token that has become the one you always look for. A locked slot is skipped
by round-robin the same way an in-use one is, but it stays skipped even once
every other slot fills up and reuse becomes unavoidable: it is never handed
to a *different* spotlight, only ever kept by the one that locked it.
Locking doesn't move a spotlight to a new slot, it just stops the one it
already has from being taken later. The lock survives persistence (it is
part of the stored snapshot) and is reachable from the list
(`:Spotlight list lock`) or directly (`:Spotlight lock [text]`).

- **Module:** `core/palette.lua` (`M.apply`, `M.next_slot`, `M.clamp`),
  `core/registry.lua` (`M.set_locked`), `ui/list.lua` (`"lock"` mode)
- **Keymaps:** none — command/list only, to avoid keymap sprawl for an
  occasional action
- **Usercmds:** `:Spotlight lock [text]`, `:Spotlight list lock`
- **Config:** `palette.colors`, `palette.colors_light`, `palette.bold`
  (default `true`), `palette.reapply_on_colorscheme` (default `true`)
- **Autocmds:** `ColorScheme`, `OptionSet background` — see
  [autocommands](../docs/BINDINGS.md#autocommands)

## Applied in every window

`matchadd()` is window-local, so a roughly 30-line ledger
(`window -> { spotlight id -> match id }`) plus three window autocommands make
a spotlight look global: new splits, buffers shown in an existing window, and
new tabs are all filled automatically, and a closed window's ledger entry is
dropped rather than cleaned up with `matchdelete()` (the match already died
with the window).

A window can opt out of this entirely — "do not spotlight in this window",
e.g. a reference file kept open in a split. The flag lives on the window
itself (`vim.w[win].spotlight_disabled`), not on whichever buffer happened
to be showing when it was set, so it is window-sticky: it survives that
window later showing a different buffer, since the same `BufWinEnter` fill
pass that already runs on every buffer switch re-checks the flag for free.
Opting out strips the window's current matches immediately rather than only
gating future fills; opting back in re-fills it immediately the same way.

- **Module:** `core/match.lua` (`eligible`, `M.clear_window`),
  `bindings/autocmds.lua`, `winopt.lua`
- **Usercmds:** `:Spotlight winopt [on|off|toggle|status]`
- **Autocmds:** `WinNew`, `BufWinEnter`, `TabNewEntered`, `WinClosed` — see
  [autocommands](../docs/BINDINGS.md#autocommands)

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

- **Module:** `ui/list.lua`, `core/count.lua` (`M.count`, `M.count_loaded`,
  `M.scannable_buffers`)
- **Keymaps:** `<leader>mL` (list/jump)
- **Usercmds:** `:Spotlight list [jump|remove|lock]`
- **Config:** `list.count` (default `true`), `list.count_max_lines` (default
  `200000`), `list.count_scope` (default `"buffer"`, or `"loaded"`),
  `list.swatch`

## Occurrence density (sign column)

The roadmap's own resolution for "where in the file does this token
cluster": `:Spotlight map` scans the current buffer once and places a sign
on every matching line, in the matching spotlight's own color — a shape the
highlighting itself cannot show, since `matchadd()` renders only what is
currently visible. Deliberately one-shot and explicit, not live: the whole
plugin's design principle is zero cost per keystroke or text change, and a
density map that stayed current would need exactly the invalidation that
principle exists to avoid. Editing the buffer after `:Spotlight map` leaves
the marks exactly where they were; run it again to refresh them.

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

## Whole-line highlighting

`<leader>mW` (or `:Spotlight line [text]`) switches one spotlight from
"color the token" to "color the whole line the token sits on" — for the case
where the interesting unit is the log entry, not the id inside it. It is a
per-spotlight toggle, so one spotlight can paint its lines while the others
stay on their tokens.

Implemented as a **rendering flag**, not as a different pattern.
`Spotlight.Item.pattern` remains the token pattern; only the string handed to
`matchadd()` is widened, by `core/pattern.lua`'s `M.line` — `\_^\.\*` … `\.\*\_$`
around the pattern, using the `\_`-prefixed anchors because plain `^`/`$` are
special only at the very start/end of a pattern and here they sit next to the
pattern's own `\C\V` prefix. That split is what keeps every other consumer
honest: the match count still counts occurrences rather than lines, the
quickfix and yank scans still report the token's own column, and the
occurrence map's earliest-column tie-break still works — a line pattern would
always match at column 1 and collapse it.

The widened match is registered **one priority below** `match.priority`. A
whole-line highlight covers every token highlight on its line, and the palette
exists precisely so several spotlights stay apart; at equal priority the line
color would swallow the token colors of every other spotlight sharing that
line. `:checkhealth spotlight` reports the effective priority per line-mode
spotlight, since "my color vanished" is the one confusing symptom this can
produce.

Two limits are inherent to the `matchadd()` choice rather than oversights:
the highlight ends where the line's text ends (it does not extend to the
window's right edge — that needs `line_hl_group`, which is an extmark, which
is a position, which is what the whole plugin avoids storing), and two
line-mode spotlights on the *same* line resolve to one winner rather than
blending.

Works on a "this occurrence only" spotlight too — the position atoms
`\%l`/`\%c` are zero-width, so the leading `.*` simply walks up to them and the
whole line of *that one* occurrence lights up. Since such a spotlight has no
text identity, it is reached through `:Spotlight list line` rather than
`:Spotlight line {text}`. The flag is persisted (unlike a position pin, it
means the same thing after a restart) and shown as `(whole line)` in the list.

- **Module:** `core/pattern.lua` (`M.line`), `core/match.lua` (the one place it
  is applied), `core/registry.lua` (`M.set_line`), `init.lua` (`M.line_set`,
  `M.line_toggle`, `M.list_line`)
- **Keymaps:** `<leader>mW` (normal mode) — no visual counterpart: the action
  needs a spotlight that already exists, which a selection cannot resolve to
- **Usercmds:** `:Spotlight line [text]`, `:Spotlight list line`
- **Config:** `keymaps.line` (default `<leader>mW`)

## Next / previous navigation

`]k` / `[k` jump one occurrence at a time, `unimpaired`-style (`3]k` is three
one-step jumps). Built on `search()`, not a collected position list, so a jump
costs the distance travelled rather than the size of the file, and it
deliberately never touches the search register or `'hlsearch'`. With
`nav.scope = "auto"` (the default), a cursor sitting inside one spotlight's
match navigates only that spotlight; off any match, all spotlights are
searched together.

- **Module:** `nav.lua` (`M.jump`, `M.next`, `M.prev`, `M.under_cursor`)
- **Keymaps:** `]k`, `[k`
- **Usercmds:** `:Spotlight next`, `:Spotlight prev`
- **Config:** `nav.scope` (default `"auto"`), `nav.wrap` (default `true`),
  `nav.center` (default `true`)

## Quickfix filter

Every line in the current buffer matching any spotlight — or one specific
spotlight's matches — sent to the quickfix list, each line reported once even
if several spotlights hit it. Capped at `quickfix.max_entries`, with scanning
stopped (not just truncated after the fact) once the cap is hit, and the
truncation reported in both the notification and the quickfix title.

`:Spotlight qf all` is the multi-buffer counterpart: every loaded, ordinary
file buffer is scanned and merged into one list. The cap is global rather
than per-buffer — each buffer gets whatever budget is left after earlier
ones, and the buffer loop itself stops (not just the entry, list) the moment
one buffer's scan reports truncation.

- **Module:** `qf.lua` (`M.fill`, `M.fill_all`), `core/count.lua`
  (`M.matching_lines`, `M.scannable_buffers`)
- **Keymaps:** `<leader>mq`
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

## Add / remove by explicit text

`:Spotlight add {text}` and `:Spotlight remove {text}` work on a literal
string that doesn't happen to be under the cursor or in a selection —
useful when scripting or acting on a token spotted in a different file.

- **Module:** `init.lua` (`M.add`, `M.remove`)
- **Usercmds:** `:Spotlight add {text}`, `:Spotlight remove {text}`

## Clear all

Removes every active spotlight across every window in one call, and resets
the round-robin color cursor so the next set starts again from slot 1.

- **Module:** `init.lua` (`M.clear`), `core/registry.lua` (`M.clear`),
  `core/palette.lua` (`M.reset`)
- **Keymaps:** `<leader>mC`
- **Usercmds:** `:Spotlight clear`

## Per-project persistence

Restored on the next session automatically. State is keyed by **git root**
(via `lib.nvim.store.project`), so it survives opening the project from a
subdirectory and follows a checkout to another machine. Writes are debounced
so a burst of toggles is one logical save, and flushed on `VimLeavePre` so the
last toggle before `:qa` is never lost.

"This occurrence only" spotlights (see above) are excluded regardless of this
setting — `core/registry.lua`'s `M.snapshot` never includes them, since a
line/column pin is only meaningful against the exact buffer state it was
recorded from.

- **Module:** `persist.lua` (`M.save`, `M.load`, `M.flush`)
- **Config:** `persist.enable` (default `true`), `persist.default` (default
  `true`), `persist.debounce_ms` (default `500`)
- **Autocmds:** `VimEnter` (load), `VimLeavePre` (flush)

## Spotlight sets

Named, saved snapshots of the registry, switched one at a time —
`:Spotlight sets save {name}` captures the currently active spotlights under
a name; `:Spotlight sets switch {name}` clears the active spotlights and
restores that saved set. Exclusive, not additive: switching replaces the
active set rather than layering one investigation's tokens on top of
another's, closer to opening a saved workspace than to tagging. Nothing
stops adding more spotlights after switching — only the switch itself
replaces. `:Spotlight sets delete {name}` removes a saved set without
touching whatever is currently active; `:Spotlight sets list` reports every
saved set and how many spotlights it holds. `switch`/`delete` tab-complete
from the names that currently exist.

Switching to an unknown or mistyped name is refused — a no-op, not data
loss — since the active registry is otherwise fully replaced. Persisted
under a second, independent project key (`spotlight/sets`, alongside the
main `spotlight/state`), written synchronously on every `save`/`switch`/
`delete` rather than debounced, since these are rare, deliberate commands
rather than a hot toggle path. Buffer-scoped ("this occurrence only")
spotlights are excluded from a saved set, for the same reason they are
excluded from regular persistence.

- **Module:** `sets.lua` (`M.save`, `M.switch`, `M.delete`, `M.names`,
  `M.count`)
- **Usercmds:** `:Spotlight sets save {name}`, `:Spotlight sets switch
  {name}`, `:Spotlight sets delete {name}`, `:Spotlight sets list`
- **Config:** none — always on, no debounce to tune

## Per-file persistence opt-out

`:Spotlight persist off` marks the *current file* so spotlights created while
looking at it are not written to disk, without touching the global default.
The exception is recorded against a spotlight's **origin** — the file it was
created in — not against every file the same string happens to appear in,
because answering "where does this token appear" would require an O(every
file) scan on every save. The exception itself always persists (including for
excluded files), otherwise the setting would not survive a restart.

- **Tab:** true
- **Module:** `persist.lua` (`M.persists`, `M.set_exception`, `M.status`)
- **Usercmds:** `:Spotlight persist on|off|default|status`
- **Config:** `persist.default` inverts the model between opt-out and opt-in

### Why origin, not appearance

Two readings of "don't persist this file's spotlights" were possible: "don't
persist spotlights that *appear* in this file" (not implementable without
scanning every file on every save, and the answer changes every time a log
rotates), or "don't persist spotlights that were *created* while looking at
this file" (exact, cheap, recorded once at creation time). The second is what
ships. A spotlight made in `worker.log` stays persisted even if the same
string also occurs in an excluded `secrets.log` — the exception is about
where the token came from, matching the actual use case: "this customer log
is full of tokens I don't want written to my cache directory."

## Case-pinned matching

Every spotlight pattern bakes in `\C`, so a spotlight's meaning does not
silently change when `'ignorecase'` is toggled elsewhere in the session.

- **Module:** `core/pattern.lua`
- **Config:** `match.ignore_case` (default `false`)

## Word-boundary matching by shape

An all-word-character token (`error`) gets `\<`/`\>` so it does not light up
inside `errors`; a token that isn't (`192.168.1.1`, punctuation-bearing
literals) cannot carry boundaries, since `\<` asserts a word start that a
character like `.` never satisfies. The kind is derived from the token's own
shape, not from which resolver branch produced it, which is what keeps this
setting meaningful regardless of pattern ordering. An explicit selection or
`:Spotlight add` is always literal, boundaries or not.

- **Module:** `cursor.lua` (`kind_of`), `core/pattern.lua`
- **Config:** `match.word_boundaries` (default `true`)

## `:checkhealth spotlight`

Reports the Neovim version, `'termguicolors'`, each `lib.nvim` module's
availability separately (a missing `usercmd.composer` and a missing
`debounce` are different problems), every config value that failed
validation and what it fell back to, the resolved match/cursor/keymap
settings, and live state — active spotlights with their slots, how many
windows carry matches, the project root, and every per-file persistence
override.

- **Module:** `health.lua`

## Debug logging

`debug = true` logs exactly the four decisions that answer "why did nothing
light up": which cursor-resolver pattern won and its index, which windows the
match ledger applied to or skipped (and any `matchadd()` rejection), what the
persisted snapshot filter kept and dropped, and whether navigation narrowed to
one spotlight or searched them all. Routed through `lib.nvim.logger` when
available, falling back to `vim.notify` at DEBUG level otherwise. With
`debug = false` a log call costs one table lookup.

- **Module:** `util/lib.lua` (`M.debug`)
- **Config:** `debug` (default `false`)

## `:Spotlight refresh`

Redefines the palette and re-applies every spotlight to every window from
scratch — the escape hatch for the one thing `matchadd()` cannot do (update a
match in place), and the fix if another plugin has cleared the current
window's matches with `:call clearmatches()`.

- **Module:** `init.lua` (`M.refresh`)
- **Usercmds:** `:Spotlight refresh`

## Scriptable facade

Every action is also a plain function on the `spotlight` module — no
`<Plug>` indirection, no action that exists only as a keymap. `spotlight.
spotlights()` gives live read access to the registry for a status line or a
scripted check.

- **Module:** `init.lua`
- **Usercmds:** none — this is the underlying API every keymap and command
  binds onto

## which-key integration

When which-key is installed, the preset's `<leader>m` prefix is labelled as a
"Spotlight" group; individual key descriptions come from each mapping's own
`desc`. Entirely soft — nothing breaks if which-key is absent.

- **Module:** `bindings/which_key.lua`

## Right-click context menu

`spotlight.integrations.menu` contributes the normal-mode subset of the
preset actions — spotlight this occurrence, spotlight every occurrence,
next/previous, toggle whole-line rendering, quickfix, open the list, clear
all — as entries in the shape [nvzone/menu](https://github.com/nvzone/menu)
expects. The `_selection` variants are left out: a menu callback fires
after nvzone/menu has already closed the menu and restored the triggering
buffer, so there is no active Visual selection by the time it runs.
spotlight.nvim has no dependency on `menu` and never opens a context menu
itself — a host (typically your own `<RightMouse>` dispatcher) composes
the entries into its own menu.

- **Module:** `integrations/menu.lua` (`M.items`, `M.submenu`)
- **Config:** `opts.menu.enable` (default `true`)

## Cross-platform persistence keys

Per-file exception and origin keys are project-relative paths normalized to
forward slashes and compared case-insensitively on Windows, where
`C:\Repos\x` and `c:\repos\x` name the same file and would otherwise produce
two different exception entries.

- **Module:** `util/path.lua`

## Bounded, non-throwing configuration

Invalid config values are degraded to their defaults rather than raising an
error: a malformed color or an unparseable Lua pattern is dropped, every
other setting still applies, and `:checkhealth spotlight` lists exactly what
was rejected. Numeric limits (`match.max_text_len`, `cursor.max_line_len`,
`quickfix.max_entries`) are enforced as hard caps rather than advisory
defaults, so no single crafted or oversized input can turn a highlight or a
quickfix fill into a multi-second stall.

- **Module:** `config/init.lua`
