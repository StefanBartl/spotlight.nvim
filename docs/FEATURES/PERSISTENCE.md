# Persistence

What survives `:qa`, what deliberately does not, and the one distinction the
per-file opt-out turns on.

## Per-project persistence

Restored on the next session automatically. State is keyed by **git root**
(via `lib.nvim.store.project`), so it survives opening the project from a
subdirectory and follows a checkout to another machine. Writes are debounced
so a burst of toggles is one logical save, and flushed on `VimLeavePre` so the
last toggle before `:qa` is never lost. Loading happens once, on `VimEnter` —
not from `setup()` directly, because a session or `:cd` plugin may not have
settled the project root yet when `setup()` runs.

"This occurrence only" spotlights (see
[MARKING.md](MARKING.md#toggle-a-spotlight-on-only-this-occurrence)) are
excluded regardless of this setting — `core/registry.lua`'s `M.snapshot`
never includes them, since a line/column pin is only meaningful against the
exact buffer state it was recorded from.

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
The exception is recorded against the project-relative file path, not the
buffer number, so it survives closing and reopening the file. The exception
list itself always persists (including for excluded files) — otherwise
`:Spotlight persist off` would not survive a restart, which would make the
setting pointless.

`:Spotlight persist status` (or the bare `:Spotlight persist`) reports what
applies to the current file and why.

- **Module:** `persist.lua` (`M.persists`, `M.set_exception`, `M.status`)
- **Usercmds:** `:Spotlight persist on|off|default|status`
- **Config:** `persist.default` inverts the model between opt-out and opt-in

### Why origin, not appearance

Spotlights are session-global, but an exception names a *file*, so this needs
saying precisely. **An exception suppresses the spotlights that were *created
while looking at* that file** — each spotlight records its origin once, when
you make it.

Two readings were possible: "don't persist spotlights that *appear* in this
file" (not implementable without scanning every file on every save, and the
answer changes every time a log rotates), or "don't persist spotlights that
were *created* while looking at this file" (exact, cheap, recorded once at
creation time). The second is what ships. A spotlight made in `worker.log`
stays persisted even if the same string also occurs in an excluded
`secrets.log` — the exception is about where the token came from, matching
the actual use case: "this customer log is full of tokens I don't want
written to my cache directory."

The practical consequence: turn persistence off *before* toggling anything in
that file. An already-created spotlight's origin does not change
retroactively.

## Cross-platform persistence keys

Per-file exception and origin keys are project-relative paths normalized to
forward slashes and compared case-insensitively on Windows, where
`C:\Repos\x` and `c:\repos\x` name the same file and would otherwise produce
two different exception entries.

- **Module:** `util/path.lua`
