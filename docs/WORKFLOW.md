# Workflow — using spotlight.nvim on a real log

Every feature here is documented on its own in [`docs/FEATURES.md`](FEATURES.md)
and [`docs/BINDINGS.md`](BINDINGS.md). This is the different question: once
you're staring at a 200 MB log and something looks wrong, what do you actually
type, in what order, and where does it bite you if you're not paying
attention.

## The core loop: point, toggle, point again

You open a log because something in it is wrong, not because you want to
admire it. The loop is almost always:

```
<leader>mK   " cursor on a request id -> every occurrence -> spotlight 1, color 1
/next-suspect-thing<CR>
<leader>mK   " cursor on a PID -> spotlight 2, color 2
]k ]k ]k     " walk this PID's occurrences
```

`]k`/`[k` default to `nav.scope = "auto"`: standing inside a spotlight's own
match, they follow *that* token; stand anywhere else and they walk every
active spotlight in file order. This is easy to get backwards under pressure
— if you meant "just this request id" and land off the highlight (say, on the
timestamp two characters to its left), `]k` silently widens to all of them.
When that matters, retoggle onto the token first, then navigate — the auto
scope only works from inside the match.

## `<leader>mk` vs `<leader>mK`: one occurrence or every occurrence

The case is the whole decision. Lowercase (`<leader>mk`, `M.toggle_here`)
pins the highlight to the exact spot the cursor or selection is on and
nowhere else; uppercase (`<leader>mK`, `M.toggle`) is the "every occurrence"
behavior above. Reach for lowercase when the text is common enough that
lighting up every instance would be noise rather than signal — `error`,
`null`, a short id reused across unrelated lines — and uppercase when you
actually want to follow one value everywhere it appears, which is the more
frequent case and the reason it kept `]k`/`[k` navigation, the quickfix
filter, and persistence all working the way they always have.

A `<leader>mk` spotlight is otherwise a first-class spotlight — same palette,
same list, same `clear` — with two differences worth knowing before you rely
on it: it does not survive `:qa` (see the persistence note further down), and
retoggling it removes *that occurrence*, not a second one of the same text
elsewhere, even one right next to it.

## Toggle removes — so pressing the same key twice is not "add again"

`<leader>mK` on an already-spotlighted token *removes* it — `registry.toggle`
keys on the exact text, not on position (`<leader>mk`'s `registry.toggle_at`
keys on position instead, for the reason above). `.` afterward repeats this:
it re-resolves whatever the cursor is on *then*, not the original token, so
`.` on an already-lit token removes it too, the same as pressing `<leader>mK`
on it again would — there is no capture of "the token from before". There is
still no "toggle 3 different tokens" from a single keypress, and a count
prefix (`3<leader>mK`) is deliberately not given a meaning, unlike `3]k`.

The corollary: `:Spotlight add error` and later putting the cursor on an
`error` and pressing `<leader>mK` operate on the *same* spotlight if the text
matches exactly — `find_by_text` compares raw text, not the built regex. So
`:Spotlight add error` (word-bounded, from the cursor path) and a visually
selected `error` (always literal) would collide as "the same spotlight" only
if their `text` fields are identical strings, which they are here — but a
selection of `Error` (capital) is a *different* spotlight from `error`,
because matching is `\C`-pinned and toggle identity is exact-text, not
case-folded.

## Selection bypasses the resolver — including word boundaries

`<leader>mK` in visual mode (or `:'<,'>Spotlight toggle`) always takes the
selected bytes literally, with **no** word-boundary wrapping, regardless of
`match.word_boundaries`. Selecting `err` out of a wall of `error`/`errors`
text lights up `err` everywhere, including inside `error`. That's correct —
selecting is an explicit "match exactly this" — but it's the opposite of what
`<leader>mK` on `err` under the cursor would give you (cursor resolution would
likely resolve the wider identifier via `<cword>`, get word-bounded, and never
match `errors` at all). If a spotlight is matching more than you expected,
check whether it came from a selection. `<leader>mk` (this occurrence only)
sidesteps the whole question — it never widens past the one spot you pointed
at, selection or not.

## The list's match count is per-buffer by default, not per-project

`<leader>mL` opens the list with a count column — computed, by default,
against the **current buffer only**. A spotlight active across `app.log`,
`worker.log`, and `auth.log` shows its count for whichever one you have open
when you press the key. This is the honest tradeoff behind the whole plugin
(an O(project) count means scanning every open buffer, and `matchadd()` was
chosen specifically to avoid O(buffer) work on the hot path) — but it means
"3" in the list is not "3 total," it's "3 here." Set
`list.count_scope = "loaded"` to sum across every *loaded* buffer instead —
opt-in, since it multiplies that one O(buffer) scan by however many buffers
are loaded. A buffer that alone exceeds `list.count_max_lines` is skipped
from the sum rather than making the whole count unknown, shown as `N+`
instead of a plain `N`.

Above `list.count_max_lines` (200000 by default) the count doesn't run at all
and the row shows `?` — on a genuinely huge log, don't wait for a number that
isn't coming.

## `:Spotlight qf` refuses to run from its own output

Filling the quickfix list moves focus to `:copen` and then hands it straight
back to the buffer you filtered — specifically so that pressing `<leader>mq`
again from muscle memory doesn't try to filter the quickfix window into
itself. If you deliberately move into the quickfix window and then press
`<leader>mq` there, it refuses with "run this from the buffer you want to
filter, not from the quickfix window" rather than producing a nested,
confusing second-generation list. Switch back to the log window first.

## A concrete combo: narrow with `qf`, keep highlighting while you read it

```
<leader>mK    " spotlight every occurrence of the request id
<leader>mq    " every line with it -> quickfix, :copen opens automatically
```

(`<leader>mk`'s "this occurrence only" spotlights work with `:Spotlight qf`
too, but there is only ever one line to find — the combo above is what you
want when the point is folding the log down to every line a value touches.)

The spotlight highlight still renders *inside* the quickfix window (it's an
ordinary window as far as `core/match.lua` is concerned), so the token you
filtered on stands out in the filtered view too — you get the fold-down *and*
the highlight in the same list, not one or the other.

## Case sensitivity is pinned per spotlight, not per session

Every spotlight bakes in `\C` at creation time (`match.ignore_case = false`
by default), so toggling `'ignorecase'` mid-session — which people do
constantly while using `/` for real searches — never silently changes what a
spotlight matches. The trap this avoids: without the pin, turning on
`'ignorecase'` for one unrelated search would make every existing spotlight
suddenly match extra text, invisibly.

## Persistence: `default true` means "everything survives `:qa` unless told otherwise"

The out-of-the-box model is opt-out. If you're reading something you don't
want cached to disk — a customer log with credentials or PII in it — the
switch is per **file**, decided *before* or *while* you spotlight it:

```
:Spotlight persist off      " this file's future spotlights: don't persist
<leader>mK                  " now safe to toggle away
```

`<leader>mk` spotlights ("this occurrence only") never touch disk in the first
place, persistence setting or not — see the note in
[FEATURES.md](FEATURES.md#toggle-a-spotlight-on-only-this-occurrence).

The exception is about **origin**, not appearance: it suppresses spotlights
*created while looking at* the excluded file, not every spotlight whose
pattern happens to also match a line in that file. Concretely — a spotlight
you made in `worker.log` still gets written to the cache even if the same
literal string also shows up in an excluded `secrets.log`, because its origin
is `worker.log`. If the goal is "nothing from this investigation touches
disk," turn persistence off *before* toggling anything in that file, not
after — an already-created spotlight's origin doesn't change retroactively.

`:Spotlight persist status` (or the bare `:Spotlight persist` with no
argument) tells you what actually applies to the current file and why —
worth running once when you're not sure whether a global default or a
per-file override is in effect, rather than guessing from memory.

## `:Spotlight refresh` is the "something looks wrong" escape hatch

Two different situations both look like "the highlighting broke," and
`refresh` fixes both by redefining the palette and reapplying every match to
every window from scratch:

- A colorscheme switch left `Spotlight1..8` undefined or wrong (should be
  automatic via the `ColorScheme` autocmd, but a colorscheme plugin that
  fires events unusually can slip past it).
- Another plugin called `:call clearmatches()` in the current window and
  wiped every `matchadd()` id spotlight was tracking, spotlight or not.

There's no autocmd that detects the second case — `clearmatches()` doesn't
notify anyone — so `refresh` is a manual command, not something to expect to
fire itself.

## Keymap collisions: nothing here is a prefix of anything else

`<leader>mC` (clear-all) and `<leader>mL` (list), not `<leader>mkc`/
`<leader>mkl`, are deliberate: a binding that's also the prefix of a longer
one costs a `'timeoutlen'` pause on *every* keystroke that starts with it,
including the ones that were never going for the longer mapping. Worth
remembering if you rebind — reusing `<leader>mk` as a prefix for a new custom
action reintroduces that pause on the existing "this occurrence only" toggle.

## Restart discipline: `VimEnter` loads once, `VimLeavePre` flushes once

Persisted spotlights come back on `VimEnter`, deliberately not from
`setup()` directly — a session plugin or `:cd` may not have settled the
project root yet when `setup()` runs, and the store is keyed by git root. If
you're scripting a startup sequence that changes directory or restores a
session *after* `require("spotlight").setup()`, that's fine — the load
happens later, on the `VimEnter` autocmd, not at `setup()` time. What doesn't
work is expecting `spotlight.spotlights()` to already reflect the persisted
set inside `setup()`'s own callback.

On the way out, writes are debounced during normal use (a burst of toggles
collapses into one save), but `VimLeavePre` flushes immediately — so the
last toggle before `:qa` is never the one silently lost to an unfired
timer. There's nothing to configure here; it's just worth knowing that a
`:qa!` (which still fires `VimLeavePre`) behaves the same as a clean quit,
but a Neovim crash or `kill -9` does not, and loses whatever the debounce
window hadn't flushed yet.
