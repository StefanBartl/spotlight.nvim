# `Checklist.md` applied to spotlight.nvim

The PR-review and coding checklist, filled in for this codebase. Companion to
[Arch&Coding.md](Arch&Coding.md) (the guidelines those items derive from) and
[Zentral-Prinzipien.md](Zentral-Prinzipien.md) (the per-module structural review).
This file is the checkbox pass: status, evidence, and the reason for every item
that is not simply ticked.

Status as of 2026-07-30, commit after the hardening pass.

## Table of content

- [Schnell-Check (10 Punkte)](#schnell-check-10-punkte)
- [PR-Review-Checkliste](#pr-review-checkliste)
- [Coding-Checkliste](#coding-checkliste)
- [Architektur-Checkliste](#architektur-checkliste)
- [Anti-Pattern-Check](#anti-pattern-check)
- [Import- und Dateistruktur-Check](#import--und-dateistruktur-check)
- [Performance-Spickzettel](#performance-spickzettel)
- [Algorithmen und Datenstrukturen](#algorithmen-und-datenstrukturen)
- [Komplexität](#komplexität)
- [Filter/Sources/Sinks](#filtersourcessinks)
- [Reviewer-Notizen](#reviewer-notizen)

---

## Schnell-Check (10 Punkte)

The pre-merge gate.

| Status | Prüfschritt | Evidence | Priorität |
| --- | --- | --- | --- |
| `[x]` | Fehlerbehandlung vorhanden | 40 `pcall` sites; every fallible function returns `value, err`; no silent failures | 🔴 |
| `[x]` | Type Guards | Every public function type-checks its arguments; config type-checks every key; `registry.restore` re-validates every snapshot field | 🔴 |
| `[x]` | Buffer/Window validieren | `nvim_win_is_valid` in `eligible()`, `remove()`, `clear()`, and again inside the deferred autocmd callback | 🔴 |
| `[x]` | Keine globalen States | `_G` never touched (grep-verified); 4 module-private mutable values | 🔴 |
| `[x]` | Single Responsibility | One concern per module; see [Arch&Coding §2](Arch&Coding.md#2-modularisierung--strukturprinzipien) | 🔴 |
| `[x]` | UI-Cleanup | `match.clear()` / `match.forget_window()`; `VimLeavePre` flush. No owned windows to close | 🟡 |
| `[x]` | Performance-Hotspots | Chunked reads, `table.concat`, `t[#t+1]`, no `table.insert` | 🟡 |
| `[x]` | Annotationen vollständig | 22/22 modules with `@module`/`@brief`/`@description`; all functions with `@param`/`@return` (script-verified) | 🟡 |
| `[x]` | Testbarkeit | 164 assertions, 6 specs, core modules called directly; snapshot/restore round-trip | 🟡 |
| `[x]` | Import-Reihenfolge | Types → config → utils → state, alphabetical within a layer | 🟢 |

**Bonuspunkt: custom `lib`-Modul genutzt** — ✅ ten `lib.nvim` modules, itemized in
[Zentral-Prinzipien.md](Zentral-Prinzipien.md#libnvim-usage). Two of the listed
ones (`lib.lazy`, `lib.memo`) are not used, with reasons given there.

---

## PR-Review-Checkliste

### 1. Sicherheit und Fehlerbehandlung

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[x]` | pcall/xpcall | `pcall` throughout. `xpcall` not needed — no traceback is consumed anywhere. |
| `[~]` | Strukturierte Fehler | **Partially declined.** String errors, not typed. There is exactly one consumer (the facade → a notification) and zero call sites that branch on the failure kind. See [Arch&Coding §7](Arch&Coding.md#7-fehlerbehandlung--validierung). Config validation *is* structured (collected, individually reportable) because that is the one place multiple independent failures need evaluating. |
| `[x]` | Explizite Rückgaben | Facade actions return `boolean`; internals return `value, err`. Low-level modules never notify — checked, not assumed. |
| `[x]` | Guards vor API | See §3 below; one gap found by this pass and fixed. |

### 2. Modularität und Struktur

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[x]` | Single Responsibility | 5 `core/` modules, each one concern. |
| `[x]` | Keine Globals | grep-verified. |
| `[x]` | Reine Funktionen | `core/pattern` fully pure; `core/count` and `cursor` read-only. |
| `[x]` | Interne Helfer lokal | 28 local functions, none exported. |
| `[x]` | Tools/Registry | `core/registry.lua` is the single mutation funnel, ending in one change event. |
| `[x]` | Config-Folder mit DEFAULTS.lua | `config/DEFAULTS.lua` + `config/init.lua` (merge, validate, `get("dot.path")`). |

### 3. Buffer-/Window-Management

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[x]` | Handle zuerst binden | `local ok, cfg = pcall(...)` then check, throughout `core/match.lua`. |
| `[x]` | Gültigkeit prüfen | **Fixed during this pass**: `nav.under_cursor` read the cursor unguarded while the identical read in `cursor.token` was `pcall`ed. Now consistent. |
| `[x]` | Einheitliche API | Not applicable — the plugin owns no windows; the one float is `lib.nvim.ui.kit.select`'s. |
| `[x]` | Cleanup | `match.clear()` / `forget_window()`. |
| `[x]` | Race Conditions | The real risk, since the window autocmd is `vim.schedule`d. Re-validated twice inside the deferred callback (`fill_window` → `eligible`). `WinClosed` deliberately skips `matchdelete` — the id is already stale. |

### 4. UI-State-Management

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[x]` | Zentraler State | Not applicable — no UI state. The window ledger is `matchadd()` bookkeeping and lives in exactly one module, reachable only through its functions. |
| `[x]` | Snapshot/Restore | `registry.snapshot()` / `registry.restore()`, used by persistence and round-tripped in the tests. |

### 5. Dokumentation und Annotationen

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[x]` | Kopf-Tags | 22/22, script-verified. |
| `[x]` | Funktions-Tags | All, script-verified, including `@return nil`. |
| `[x]` | Aliase/Typen | 14 classes + 2 aliases in `@types/`; no inline type monsters. |
| `[x]` | Kommentar-Konvention | `#` used in `@field`/`@return` per the Lua LS guidance. |

### 6. Testbarkeit und Lesbarkeit

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[~]` | DI statt Hard-Wiring | Config is injected (`config.get`, never a raw table). Module dependencies are direct `require`s, not injected — with 22 modules and one composition root, a DI container would add indirection without enabling a test that is not already possible (every core module is called directly today). |
| `[x]` | Pure Functions | `core/pattern` entirely; `core/count` bar the buffer read. |
| `[x]` | Test-Entry | `TESTS/run.lua`, plain headless nvim, no framework. |

### 7. Tooling

| Status | Prüfschritt | Note |
| --- | --- | --- |
| `[x]` | Lua LS Settings | `.luarc.json`: `diagnostics.globals = ["vim"]`, `workspace.library` = `$VIMRUNTIME/lua` + luv. |
| `[x]` | Formatter/Linter im CI | stylua + luacheck + the test suite, three jobs. Currently 0 warnings / 0 errors over 31 files. |

---

## Coding-Checkliste

### A. Strings und Tabellen

| Status | Regel | Note |
| --- | --- | --- |
| `[x]` | Keine String-Verkettung in Schleifen | `pattern.alternation` uses `table.concat`. The 15 `..` uses are single messages. |
| `[x]` | String-Indices statt Kopien | `cursor.match_spanning` works with `find`'s indices. One `line:sub` per match remains in the scan loops — `vim.regex:match_str` has no start-offset parameter, an API limitation rather than a choice. |
| `[~]` | Tabellen vorreservieren | Deliberately not: sizes are 1–8 (spotlights) or unknown-until-scanned (quickfix entries). Nothing to reserve. |
| `[x]` | Befüllen mit `t[i]` | Where the index is known; `t[#t+1]` for dynamic appends; `table.insert` nowhere. |
| `[~]` | Tabellenpool/clear | Not applicable — no per-frame table churn exists. |

### B. Performance-Quickwins

| Status | Regel | Note |
| --- | --- | --- |
| `[x]` | Lokale Funktions-Refs in Hot-Loops | Requires aliased once per module; `re:match_str` bound before the scan loop. |
| `[x]` | `vim.fn` nicht micro-optimieren | Followed — the count is what matters, and the resolver makes one `expand("<cword>")` at most. |
| `[~]` | Async statt Blocken | Debounced saves use a libuv timer. The counting/filtering scan is synchronous by choice: user-initiated, bounded, and a progressively-filling list is worse than a brief pause. `lib.nvim.progress` is the tool if that changes. |
| `[~]` | Memoization | Not applicable — counts are deliberately uncached (caching needs invalidation-on-change, the thing the design avoids); regex compiles are cheap relative to the scan. |
| — | `vim.mpack` statt JSON | Not our call: serialization belongs to `lib.nvim.cache.disk`. Worth raising there if snapshot size ever matters — it currently holds ≤ 64 short records. |

### C. Neovim-API sicher verwenden

| Status | Regel | Note |
| --- | --- | --- |
| `[x]` | Handle-Validierung | Before every `nvim_win_*`. The remaining bare `nvim_buf_get_lines` calls are safe by contract (`strict_indexing = false` → empty table → the `nil` line is handled). |
| `[x]` | Deferred Calls absichern | Re-validated inside the `vim.schedule`d window callback. |
| `[x]` | Einheitliche Fenster-API | Not applicable — no owned windows. |

### D. State- und Datenmodelle

| Status | Regel | Note |
| --- | --- | --- |
| `[~]` | Getter/Setter statt Direktzugriff | Module functions are the only access path (`registry.all()`, `persist.exceptions()`), which is the property this asks for. Per-field accessors on `Spotlight.Item` are declined — see [Arch&Coding §4](Arch&Coding.md#4-methoden-metatables--datenmodelle). |
| `[~]` | Metatables gezielt | Not used. One record shape means no shared default logic to inherit. |
| `[~]` | FIFO/Ringbuffer | Not applicable — no bounded history here. `lib.nvim.logger` owns that for debug records. |

### E. Garbage-Collector bewusst steuern

| Status | Regel | Note |
| --- | --- | --- |
| `[~]` | Große Objekte freigeben | No explicit `collectgarbage()`, correctly: the guideline gates it on actively dropping large objects, and the largest structure here (a capped quickfix list) is handed to `setqflist` after which Vim owns it. |
| `[~]` | Coroutine-Recycling | No coroutines. |

### F. Lazy-Loading und On-Demand-Konfiguration

| Status | Note |
| --- | --- |
| `[~]` | The metatable-based lazy-initializing config is **declined**. The whole default table is ~40 scalar values plus two 8-element color arrays; a `__index` resolver would cost more (a metamethod per access, 30–60 cycles by the guidelines' own table) than the eager deep-merge it replaces. Module-level lazy loading *is* applied — three modules stay out of the `setup()` graph. |

---

## Architektur-Checkliste

| Status | Aspekt | Note |
| --- | --- | --- |
| `[x]` | Schichten/Module | Clear: `core/` (mechanism) → feature modules (`cursor`, `nav`, `qf`, `persist`, `ui`) → `bindings/` (wiring) → `init.lua` (facade). Coupling is one-directional; nothing in `core/` requires a feature module. |
| `[x]` | Abhängigkeiten | Config via `config.get`, never a raw table. `registry` passes items to `match` as arguments rather than `match` reaching into `registry` — which is what keeps them independently testable. |
| `[x]` | Erweiterbarkeit | `core/registry.on_change` is the extension point; `cursor.patterns` and `palette.colors` are user-replaceable arrays. |
| `[x]` | Testbarkeit | Core logic is pure or read-only and called directly in the specs. |

---

## Anti-Pattern-Check

| Status | Muster | Result |
| --- | --- | --- |
| `[x]` | Globaler State | None. `_G` never touched. |
| `[x]` | API ohne Guards | One instance found (`nav.under_cursor`) and fixed during this pass. |
| `[x]` | String-Concat im Loop | None. |
| `[x]` | Closures im Loop | None (grep-verified). The `nvim_win_call` closure is per explicit add, bounded by ~8 × windows. |
| `[x]` | Viele kleine temporäre Tabellen | None. Chunked reads reuse one table per 5000 lines. |

---

## Import- und Dateistruktur-Check

| Status | Punkt | Note |
| --- | --- | --- |
| `[x]` | Import-Reihenfolge | Types → config → utils → state; alphabetical within a layer. |
| `[x]` | Datei-Header | 22/22. |
| `[~]` | Typ-Ablage | One project-level `@types/` rather than one per subdirectory. Deviation with a reason: the type surface is small and *shared* across directories, so splitting it would duplicate `Spotlight.Item` or create cross-directory type requires. See [Arch&Coding §5](Arch&Coding.md#5-dokumentation--annotationen). |

---

## Performance-Spickzettel

For the one hotpath (the counting/filtering scan):

| Status | Maßnahme | Applied |
| --- | --- | --- |
| `[x]` | `t[i]` statt `table.insert` | Yes, throughout. |
| `[~]` | `{ [N] = 0 }` Inline-Reserve | No — size unknown until scanned. |
| `[x]` | `table.concat` statt `..` | `pattern.alternation`. |
| `[~]` | Weak-Caches | Not applicable (single-value sentinels). |
| `[x]` | Debounced Writes | `persist.debounce_ms`, flushed on exit. |
| `[~]` | Memoization | Deliberately not, for counts. |
| `[~]` | Async via uv | Only for the debounce timer; the scan is sync by choice. |

Plus one measure the cheatsheet does not list, which matters more here than all of
the above: **chunked buffer reads**. A single `nvim_buf_get_lines(0, -1)` on a
200k-line buffer materializes the whole file as one Lua table before a byte is
examined. Reading in 5000-line chunks bounds peak memory to the chunk.

---

## Algorithmen und Datenstrukturen

The sorting and data-structure sections of the checklist are extensive and mostly
do not apply, so rather than tick fifty boxes, here is what the plugin actually
uses and why it is right at this size:

| Concern | Structure | Justification |
| --- | --- | --- |
| The spotlight list | Flat array, linear scan | n ≤ 64, typically 1–8. `find_by_text` is O(n) over eight elements — faster than hashing at that size, and insertion order is meaningful (it is the round-robin history). No sort is ever needed. |
| The window ledger | Two-level hash, `win → {id → match_id}` | Lookup is by window then by spotlight id, both point queries, no ordering or range needed. Hash is the checklist's own answer for "Key-Value ohne Ordnung". |
| Persistence exceptions | Hash, `path → boolean` | Exact-key point queries. **Would change** if the roadmap's inheritable directory exceptions land: that needs longest-prefix matching, which is the checklist's "Prefix notwendig → Trie". Noted in [ROADMAP.md](ROADMAP.md). |
| Palette slots | Fixed array + one integer cursor | 8 elements, round-robin with a skip. |
| Debug records | Ring buffer | Not ours — `lib.nvim.logger` owns it, which is the correct structure for a bounded history. |

**Delete strategy** (the checklist calls this out explicitly): physical delete, not
tombstones. `registry.remove` does `table.remove` (O(n) over ≤ 64), and the ledger
entry is deleted outright with the window's row dropped when it empties. Tombstones
would exist to avoid rehashing, which is not a cost at this size, and would leak the
distinction into iteration order.

**Iteration order** is insertion order for the registry (documented, and relied on
by the list UI) and unspecified for the two hashes (never iterated for output).

---

## Komplexität

Per-operation, with the parameters named as the checklist requires — `n` =
spotlights (≤ 64), `w` = windows, `L` = buffer lines, `c` = cursor line length:

| Operation | Time | Space | Note |
| --- | --- | --- | --- |
| Resolve token under cursor | O(c × p), p = patterns | O(c) | Bounded by `cursor.max_line_len`; above it, O(token) via `<cword>`. |
| Add / toggle a spotlight | O(n + w) | O(1) | The `n` is the duplicate scan, `w` the ledger fill. |
| Remove a spotlight | O(n + w) | O(1) | |
| Render (per redraw) | **O(visible lines × n)**, in C | O(1) | Vim's renderer, not Lua. Independent of `L` — the entire point of the design. |
| Next / previous occurrence | O(distance to next hit) | O(1) | `search()` walks outward and stops; not O(L). |
| Match count (one spotlight) | O(L) | O(chunk) | On demand only; skipped above `list.count_max_lines`. |
| Quickfix filter | O(L) | O(hits), capped | Stops at `quickfix.max_entries`. |
| Save snapshot | O(n) | O(n) | Debounced. |
| Load snapshot | O(n + w) | O(n) | Once, on `VimEnter`. |

**Cost model**: line-oriented buffer reads and regex match attempts, which is what
dominates. **Input distribution assumed**: log-shaped — many lines, a small number
of distinct tracked tokens. **Worst case named**: everything above is worst-case,
not amortized; there is no amortization anywhere because there is no resizing
structure.

The one number worth restating, because it is the plugin's whole claim: rendering
is independent of file size. That is Ω(visible) rather than Ω(L), and it is a
property of storing patterns instead of positions.

---

## Filter/Sources/Sinks

The checklist's functional-programming section names "große Logdateien analysieren:
zeilenweise Einlesen, Filtern nach Schlüsselwörtern" as the canonical case — which
is literally this plugin's domain, so it is worth stating how far the architecture
matches.

`count.matching_lines` is a source (chunked line reads) → filter (regex match) →
sink (quickfix entries), and it deliberately never holds the whole file: chunked
reads bound the source, and `max_entries` bounds the sink. That is the memory
property the section is after.

It is not written with a generic pump/filter abstraction, and should not be: there
is one pipeline with one filter stage. The abstraction earns its keep when stages
are composed at runtime, and here they are fixed at compile time. What was taken
from the section is the *streaming discipline*, not the machinery.

---

## Reviewer-Notizen

**Found and fixed by these three walkthroughs** (they were worth doing):

1. No debug switch at all — the one genuine structural gap
   ([Zentral-Prinzipien §9](Zentral-Prinzipien.md#9-debugbarkeit-eingeplant)).
2. `@types/init.lua` missing its `return {}` (Annotations-Regeln).
3. `nav.under_cursor` reading the cursor unguarded while the identical read
   elsewhere was `pcall`ed (§3 / Anti-Pattern-Check).

Plus, from the separate security pass: three unbounded inputs and an unsanitized
buffer-line write.

**Declined, each with a documented trigger for revisiting**:

| Item | Reason | Revisit when |
| --- | --- | --- |
| Context object | Two API calls per explicit action, not per keystroke | A feature runs on a frequent event (the density map) |
| `safe_call` envelope + typed errors | One error consumer, zero branch sites | A public API where callers branch on failure kind |
| DI container | 22 modules, one composition root; core modules already directly testable | Module count grows substantially |
| Per-subdirectory `/types` | Type surface is small and shared | A second domain appears ("spotlight sets") |
| Metatable-lazy config | ~40 scalars; a metamethod per access costs more than the eager merge | Config grows an expensive-to-compute default |
| Weak tables / memoization | n ≤ 64; nothing expensive is repeated | A large hot collection appears |
| Async scan | Bounded and user-initiated; partial results are worse UX | The bounds have to be raised significantly |
| Compiled binary / FFI | The hot path is *already* C (`matchadd()`); no Lua left worth compiling | Never, on current architecture. Full reasoning in [Arch&Coding](Arch&Coding.md#native-code--ffi-evaluation) |

**Not re-litigated** — decisions already argued in the code and README, recorded
here so a future review does not reopen them without new information:
`matchadd()` over extmarks, on-demand counting, session-global (not per-buffer)
scope, and origin-based (not appearance-based) persistence exceptions.
