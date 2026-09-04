# Marking tokens

Making a spotlight, and the rules that decide what it hits. See
[RENDERING.md](RENDERING.md) for what happens to it afterwards.

## Toggle a spotlight on every occurrence of the token under the cursor

One key adds a spotlight on whatever the cursor resolver decides you are
pointing at, and the same key removes it again if that exact token is already
lit. `matchadd()` highlights the text everywhere it appears — every window,
every buffer whose content happens to contain it — which is the point: a
request id you spotted in `app.log` is the same request id in `worker.log`.

The normal-mode keymap is dot-repeatable: press `<leader>sK` on one token,
move to another, and `.` toggles that one too — "spotlight this one as well",
via `lib.nvim.dotrepeat`. Each firing re-resolves the cursor token fresh
rather than repeating the original action, so `.` on an already-lit token
removes it, exactly like pressing `<leader>sK` on it again would. The
`:Spotlight` command path (bare `:Spotlight` and `:Spotlight toggle` with no
explicit text or range) is dot-repeatable the same way; a count prefix
(`3<leader>sK`) is deliberately not given a meaning — unlike `3]k`, "toggle
three tokens from one keypress" has no established convention to borrow.

- **Module:** `init.lua` (`M.toggle`), `cursor.lua` (`M.token`),
  `util/lib.lua` (`M.dot_repeatable`, `M.dot_run`)
- **Keymaps:** `<leader>sK` (normal mode) — see [keymaps](../BINDINGS.md#keymaps)
- **Usercmds:** `:Spotlight`, `:Spotlight toggle [text]` — see [commands.md](../commands.md)
- **Config:** `keymaps.toggle` (default `<leader>sK`)

## Toggle a visual selection

The same action in visual mode takes the exact selected bytes, literally — no
shape classification, no word boundaries, just what you highlighted. Refused
for a multi-line or whole-line (`V`) selection, since a pattern containing a
newline cannot match anything `matchadd()` sees.

- **Module:** `init.lua` (`M.toggle_selection`), `cursor.lua` (`M.selection`)
- **Keymaps:** `<leader>sK` (visual mode)
- **Usercmds:** `:'<,'>Spotlight toggle`

## Toggle a spotlight on only this occurrence

The narrower sibling of the action above: `<leader>sk` (lowercase) marks
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
that buffer (`BufWinEnter` reconciliation). Whether the rest needs special
handling depends on which engine reads the pattern: `matchadd()` and
`search()` evaluate `\%l`/`\%c`, so rendering and next/previous navigation
need nothing. `vim.regex` does **not** evaluate them — it reports no match on
every line, the pinned one included — so counting, the quickfix filter and
the map resolve such an item from the position recorded on it rather than
scanning for its pattern.

Toggle identity is the exact position, not the text — pressing `<leader>sk`
again on the *same* occurrence removes it, but a second `<leader>sk` on a
different occurrence of the same word adds an independent spotlight, even
while a global spotlight for that same text (from `<leader>sK`) is active.

- **Module:** `init.lua` (`M.toggle_here`, `M.toggle_here_selection`,
  `M.toggle_here_at`), `core/registry.lua` (`M.add_at`, `M.find_at`,
  `M.toggle_at`, `M.remove_for_buffer`), `core/pattern.lua` (`M.build_at`),
  `core/match.lua` (the buffer-scope guard in `add()`, `M.reconcile_window`)
- **Keymaps:** `<leader>sk` (normal + visual mode)
- **Usercmds:** `:Spotlight here`, `:'<,'>Spotlight here`
- **Config:** `keymaps.toggle_here` (default `<leader>sk`)

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

Order matters, and it is the first thing to check when a spotlight covers more
or less than you expected: a broad pattern placed early shadows every specific
one after it. `debug = true` logs which pattern won and its index — see
[DIAGNOSTICS.md](DIAGNOSTICS.md#debug-logging).

- **Module:** `cursor.lua` (`M.token`, `match_spanning`, `kind_of`)
- **Config:** `cursor.patterns`, `cursor.fallback_cword` (default `true`),
  `cursor.max_line_len` (default `8192`)

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
- **Keymaps:** `<leader>sC`
- **Usercmds:** `:Spotlight clear`

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
