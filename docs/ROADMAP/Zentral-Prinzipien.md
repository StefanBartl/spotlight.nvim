# `Zentrale-Prinzipien` applied to spotlight.nvim

Walkthrough of [Zentrale-Prinzipien für nvim-Module](https://github.com/StefanBartl)
against this codebase. Per that checklist's own framing: several "yes" answers
in one section means structural potential, not a defect list. Recorded here so
the answers are auditable and so the *declined* items have a reason attached.

Status as of 2026-07-30, commit after the hardening pass.

## Table of content

- [Verdict](#verdict)
- [1. Events bündeln, Logik entkoppeln](#1-events-bündeln-logik-entkoppeln)
- [2. Eigene Logik lazy laden](#2-eigene-logik-lazy-laden)
- [3. Kontext statt Mehrfach-API-Zugriffe](#3-kontext-statt-mehrfach-api-zugriffe)
- [4. Autocommand-Gruppen sauber nutzen](#4-autocommand-gruppen-sauber-nutzen)
- [5. Event oder Command?](#5-event-oder-command)
- [6. Treesitter notwendig oder nicht?](#6-treesitter-notwendig-oder-nicht)
- [7. Cache vorhanden und explizit?](#7-cache-vorhanden-und-explizit)
- [8. Allokationen im Hot-Path vermeiden](#8-allokationen-im-hot-path-vermeiden)
- [9. Debugbarkeit eingeplant?](#9-debugbarkeit-eingeplant)
- [10. Laufzeit wichtiger als Startup?](#10-laufzeit-wichtiger-als-startup)
- [lib.nvim usage](#libnvim-usage)
- [Kurzform](#kurzform)

---

## Verdict

| Section | Status | Note |
| --- | --- | --- |
| 1. Events bündeln | ✅ | 6 autocmds in 3 groups, each with a distinct job. |
| 2. Lazy laden | ✅ | `ui/list`, `qf`, `core/match` required at call site. |
| 3. Kontext-Objekt | ⚠️ declined | Two reads per action, not per keystroke — see below. |
| 4. Augroup-Disziplin | ✅ | 3 named groups, `clear = true`, reload-safe. |
| 5. Event oder Command | ✅ | The two O(buffer) operations are commands by design. |
| 6. Treesitter | ✅ | Not used. Not applicable — tokens are not syntax. |
| 7. Cache | ✅ | `stdpath("cache")` via `lib.nvim.store.project`, regenerable. |
| 8. Hot-Path-Allokationen | ✅ | One fixed table reused per chunk; no `table.insert`. |
| 9. Debugbarkeit | ✅ | Added in the follow-up pass; was the one real gap. |
| 10. Laufzeit vs Startup | ✅ | No per-keystroke or per-change event exists. |

One genuine gap was found by this walkthrough (§9, no debug switch) and fixed.
One item is declined with a reason (§3).

---

## 1. Events bündeln, Logik entkoppeln

> *Gibt es eigene `nvim_create_autocmd`-Aufrufe? Reagieren mehrere Module auf
> dasselbe Event? Wird Logik mehrfach an Events gebunden?*

Six autocommands, all in `lua/spotlight/bindings/autocmds.lua`, none anywhere
else — a single registration site, which is the point of the section. Three
groups, each with one job: window fill, palette redefinition, persistence
lifecycle.

`WinNew`/`BufWinEnter`/`TabNewEntered` share **one** callback rather than three,
which is the bundling this asks for. They cannot be reduced further: each catches
a case the others miss (a `:split`, a buffer shown in an existing window, a tab
created with its window in place), and there is no single event that covers all
three.

No module registers its own handler. `core/registry.lua` exposes an `on_change`
observer instead, which `persist.lua` subscribes to — so "the spotlight set
changed" is defined once and no caller has to remember to trigger a save. That is
the decoupling the section is after, applied to plugin-internal events rather than
Vim ones.

**Status: ✅**

---

## 2. Eigene Logik lazy laden

> *Wird das Modul beim Startup geladen, obwohl es selten gebraucht wird? Könnte
> `require` in einen Handler verschoben werden?*

`setup()` loads config, palette, persist, bindings. Three modules are
deliberately **not** in that graph and are required at their call site instead:

| Module | Required from | Why |
| --- | --- | --- |
| `ui/list.lua` | `init.lua` `M.list()` | Pulls in `lib.nvim.ui.kit.select` → chooser → surface. The heaviest subtree in the dependency graph, and it is needed only when the list is actually opened. |
| `qf.lua` | `init.lua` `M.quickfix()` | Only reachable from one key and one subcommand. |
| `core/match.lua` | `bindings/autocmds.lua` `WinClosed` | Only `forget_window` is needed there. |

Beyond that, the recommended install is `event = "VeryLazy"`, and `ft` is
explicitly *not* recommended — logs arrive with every filetype and often with
none, so gating on filetype would make the plugin absent exactly when wanted.
`cmd = "Spotlight"` is documented as the option for someone who wants nothing
loaded until first use.

**Status: ✅**

---

## 3. Kontext statt Mehrfach-API-Zugriffe

> *Ruft das Modul mehrfach `nvim_buf_get_*` oder `vim.fn.*` auf? Könnte ein
> Context-Objekt (bufnr, path, ft, root) einmal erzeugt werden?*

**Assessed and declined**, unlike cascade.nvim which does have a `CascadeContext`.

The duplication is real but shallow: `cursor.token()` and `nav.under_cursor()`
each do one `nvim_win_get_cursor` plus one `nvim_buf_get_lines` for the single
cursor line. A toggle costs one such pair; a `]k` with `nav.scope = "auto"` costs
one. That is two API calls per **explicit user action**, not per keystroke and not
per redraw.

cascade needs its context object because it runs on `<CR>`, `o`, `O`, `+`, `-` and
`<C-a>` — keys pressed continuously while typing — and each of its detectors would
otherwise re-read the same buffer state. spotlight has no such path: the plugin
deliberately has no `TextChanged` or `CursorMoved` handler at all (§10), so there
is no frequency for a context object to amortize against.

Introducing one would add a type, a constructor and a threading obligation through
every signature, in exchange for saving two API calls per keypress. Reconsider if a
future feature does run on a frequent event — the density map sketched in
[ROADMAP.md](ROADMAP.md) would be the trigger.

No hidden global state: `_G` is never touched (verified by grep), and the module-
level mutable state is exactly four values — the ledger, the registry list, the
round-robin cursor, and the exception table — each private to its module and
reachable only through that module's functions.

**Status: ⚠️ declined, with a documented trigger for revisiting**

---

## 4. Autocommand-Gruppen sauber nutzen

> *Ist das Autocommand einer klaren Gruppe zugeordnet? Kann das Event gezielt
> gelöscht werden? Würde ein Reload ohne Neustart funktionieren?*

Three groups, named for what they do rather than for the plugin:
`spotlight_windows`, `spotlight_highlights`, `spotlight_persist`. All created
through `lib.augroup()` with `clear = true`, so calling `setup()` twice replaces
rather than duplicates — a reload without restart is clean by construction, and
the tests rely on it (`commands_spec.lua` calls `setup()` four times).

Where each event is defined is answerable in one place: every registration is in
`bindings/autocmds.lua`, and `docs/BINDINGS.md` mirrors the table.

Deleting one group by hand works as expected, because the groups are split by
concern, not by convenience — `:autocmd! spotlight_persist` disables persistence
and leaves highlighting intact.

**Status: ✅**

---

## 5. Event oder Command?

> *Wird Logik automatisch ausgeführt, obwohl sie nur auf explizite Aktion gehört?
> Könnte ein `:Command` sinnvoller sein? Läuft Code bei jedem Bufferwechsel?*

This is the section the plugin's design is most directly shaped by. The two
expensive operations are both commands, deliberately:

- **Match counting** could plausibly be an event ("keep the count live"). It is
  not: it is computed when the list opens and never maintained, because keeping it
  current means re-scanning the buffer on every change — reintroducing the exact
  O(file size) cost that choosing `matchadd()` over extmarks avoids.
- **The quickfix filter** is inherently whole-buffer, so it is `:Spotlight qf` and
  a key, never something continuous.

What *does* run on an event is only the bookkeeping that has no alternative: a new
window starts with no `matchadd()` state, so something has to fill it, and no
command can be required of the user for that. That callback is a no-op when the
window already carries the match.

`BufWinEnter` does fire on buffer switches, which the section flags. It is
justified rather than excused: the work is "for each window, for each spotlight,
check a table key" — typically 1–8 lookups — and skipping it means a buffer opened
in an existing window silently loses its highlighting.

**Status: ✅**

---

## 6. Treesitter notwendig oder nicht?

> *Wird Treesitter nur für einfache Pattern-Erkennung genutzt? Reicht ein
> Zeilen-Scan oder Regex?*

Treesitter is not used, and the question does not really apply: a request ID in a
log line is not a syntax node, and log files typically have no parser at all. The
resolver is a Lua-pattern scan over one line; the highlighting is a Vim regex
handed to the renderer.

Worth noting the contrast with cascade.nvim, which offers an opt-in
`lists.precision = "treesitter"` for the one case line-scanning is genuinely blind
to (a fenced code block). spotlight has no equivalent blind spot, so there is
nothing for an opt-in to buy.

**Status: ✅ not applicable**

---

## 7. Cache vorhanden und explizit?

> *Wird ein Ergebnis mehrfach neu berechnet? Ist der Cache regenerierbar und
> invalidierbar? Liegt er in `stdpath("cache")`?*

Persistence goes through `lib.nvim.store.project`, which is backed by
`lib.nvim.cache.disk` under `stdpath("cache")` — so location and lifecycle are
inherited rather than reinvented, and `:Spotlight clear` plus a restart is a full
reset.

Regenerable by construction: the snapshot holds `text` + `slot` + `kind`, and the
regex is **rebuilt** on load rather than stored. Deleting the file loses only the
convenience of restoring a session, never correctness — and a policy change (new
escaping rules, a different boundary decision) applies to restored spotlights
automatically instead of resurrecting an old version's regex.

Two in-memory caches, both explicit and both `false`-sentinel guarded so an absent
module is probed once rather than on every call: the `lib.nvim.logger` instance in
`util/lib.lua`, and the compiled `vim.regex` objects built per counting pass (not
cached across passes — they are cheap relative to the scan that follows, and
caching them would mean invalidating on every `rebuild()`).

Repeated computation that is deliberately *not* cached: match counts. Caching them
means either staleness or invalidation-on-change, and invalidation-on-change is the
thing the whole design exists to avoid.

**Status: ✅**

---

## 8. Allokationen im Hot-Path vermeiden

> *Werden in Schleifen neue Tabellen erzeugt? Werden Strings in Loops
> konkatenziert? Gibt es Closures in häufig aufgerufenen Pfaden?*

There is no hot path in the sense this section means — nothing runs per keystroke
or per redraw. The nearest thing is the counting/filtering scan, which is the one
O(buffer) operation, so it is where the section was actually applied:

- **Chunked reads.** `nvim_buf_get_lines` is called in 5000-line chunks rather
  than once, so a 200k-line buffer never materializes as a single Lua table. Same
  reasoning as the section's "don't allocate in loops", applied one level up.
- **No `table.insert` anywhere** in the codebase (verified by grep): `t[#t+1] = v`
  throughout, and `t[i] = v` where the index is already known (`pattern.alternation`,
  `registry.snapshot`).
- **No string concatenation in a loop.** `pattern.alternation` uses
  `table.concat`; the only `..` uses are in single messages and log lines.
- **No closures created in loops** (verified by grep). The `pcall`-wrapped
  `nvim_win_call` closure in `core/match.lua` is created per spotlight per window
  — bounded by ~8 × window count and only on an explicit add, not in a scan.
- **Index arithmetic over substring copies** in the scan loops:
  `re:match_str(line:sub(offset + 1))` is the one place that does copy, and it is
  needed because `vim.regex:match_str` has no start-offset parameter.

Inline table pre-reservation (`{ [N] = 0 }`) is not used: the sizes here are 1–8
(spotlights) or unknown-until-scanned (quickfix entries), and neither benefits.

**Status: ✅**

---

## 9. Debugbarkeit eingeplant?

> *Ist erkennbar, wann dieses Modul aktiv wird? Gibt es einen einfachen
> Debug-Schalter? Lässt sich das Modul isoliert testen?*

**This walkthrough's one real finding.** The first implementation had no debug
switch at all — `:checkhealth` reported static state, but there was no way to see
*decisions*. Fixed: `debug = false` → `true` routes structured records through one
cached `lib.nvim.logger` instance named `spotlight` (inspectable with
`:LibLogger`), falling back to `vim.notify` at DEBUG level.

The instrumentation is targeted rather than sprinkled. The only question this
plugin ever really gets asked is *"why did nothing light up"*, and exactly four
decisions answer it:

1. which resolver pattern won, with its index in `cursor.patterns`;
2. which windows the ledger applied to or skipped, plus any `matchadd()` Vim rejected;
3. what the snapshot filter kept and dropped;
4. whether nav narrowed to one spotlight or searched them all.

Isolated testing: `TESTS/` runs in plain `nvim --headless -u NONE` with no test
framework, 164 assertions across six specs. Each core module is exercised directly
(`registry.restore`, `count.matching_lines`, `pattern.build`) rather than only
through the facade, which is what makes them testable in isolation at all.

Control flow is traceable because every state change funnels through
`core/registry.lua` and ends in one `notify_change()`.

**Status: ✅ (gap found and closed)**

---

## 10. Laufzeit wichtiger als Startup?

> *Läuft Code bei `CursorMoved`, `TextChanged`, `BufEnter`? Ist der Code dort
> minimal und deterministisch?*

No `CursorMoved`, no `TextChanged`, no `CursorHold` — verified by grep, and stated
in the module header of `bindings/autocmds.lua` so it stays that way. This is not
restraint, it is the payoff of the `matchadd()` decision: a pattern-based highlight
needs no invalidation when the text moves, so there is nothing for a change event
to do.

`BufWinEnter` is the one buffer-lifecycle event, and its callback is minimal and
deterministic: iterate windows, and for each spotlight check whether the ledger
already has it. No I/O, no scan, no allocation beyond the window list.

Startup optimization is genuinely not the relevant axis here — `setup()` defines 8
highlight groups, merges a config table, and registers 6 autocmds. Runtime is
where the design effort went, which is the answer this section is looking for.

**Status: ✅**

---

## lib.nvim usage

The checklist's **WICHTIG** note, item by item:

| Required | Used | Where |
| --- | --- | --- |
| `lib.notify` instead of `vim.notify`/`print` | ✅ | `util/lib.lua` `M.notify`, native fallback |
| `lib.map` instead of `vim.keymap.set` | ✅ | `util/lib.lua` `M.map`, native fallback |
| `lib.usercmd` | ✅ | `usercmd.composer` — the whole `:Spotlight` verb |
| `lib.autocmd` / `lib.augroup` | ✅ | `util/lib.lua` `M.autocmd` / `M.augroup` |
| `lib.cross` (cross-platform) | ✅ | `util/path.lua` via `cross.platform.is_windows`, with a `has("win32")` fallback |
| `lib.hover_select` (now `ui.kit.select`) | ✅ | `ui/list.lua`, with rich items for the color swatch |
| `lib.lazy` | ⚠️ not used | Three modules are lazily required at their call site instead (§2). `lib.lua.lazy.require` would add an indirection layer for three requires; reconsider if that count grows. |
| `lib.memo` | ⚠️ not used | Nothing here is expensive-and-repeated. The two caches that exist are single-value sentinels, where a memo table would be heavier than the thing it caches. |

Also used beyond the list: `store.project` (persistence), `debounce` (coalesced
saves), `ui.hl` (highlight definition), `logger` (§9).

Everything except `usercmd.composer` and `ui.kit.select` is soft-guarded with a
native fallback, and `:checkhealth spotlight` reports each module separately —
"lib.nvim missing" is not a useful diagnosis when the modules carry different
features.

---

## Kurzform

The checklist's own mental short form:

| Question | Answer |
| --- | --- |
| Wann läuft es? | On explicit keys and commands; plus 6 lifecycle autocmds (window fill, palette, load/flush). |
| Muss es jetzt laufen? | Yes for the window fill — a new window has no `matchadd()` state and nothing else can supply it. |
| Lädt es mehr als nötig? | No. The list, quickfix and match modules stay out of the `setup()` graph. |
| Läuft es öfter als nötig? | No per-keystroke or per-change event exists at all. |
| Wird Arbeit wiederholt? | Counting, deliberately (on demand only) — caching it would need invalidation-on-change. |
| Ist der Datenfluss klar? | Yes: every mutation goes through `core/registry.lua` and ends in one change event. |
