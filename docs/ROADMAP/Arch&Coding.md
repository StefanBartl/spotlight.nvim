# `Arch&Coding-Regeln` applied to spotlight.nvim

Walkthrough of the architecture and coding guidelines against this codebase, in
the guidelines' own section order. Items that do not apply are marked as such
with the reason, rather than silently ticked.

Status as of 2026-07-30, commit after the hardening pass.

## Table of content

- [Verdict](#verdict)
- [1. Sicherheitsprinzipien & Fehlerbehandlung](#1-sicherheitsprinzipien--fehlerbehandlung)
- [2. Modularisierung & Strukturprinzipien](#2-modularisierung--strukturprinzipien)
- [3. Buffer- & Window-Management](#3-buffer---window-management)
- [4. Methoden, Metatables & Datenmodelle](#4-methoden-metatables--datenmodelle)
- [5. Dokumentation & Annotationen](#5-dokumentation--annotationen)
- [6. Testbarkeit & Lesbarkeit](#6-testbarkeit--lesbarkeit)
- [7. Fehlerbehandlung & Validierung](#7-fehlerbehandlung--validierung)
- [8. Performance & Speicher](#8-performance--speicher)
- [9-11. Cache, schwache Tabellen, Spezialfälle](#9-11-cache-schwache-tabellen-spezialfälle)
- [Cross-Platform](#cross-platform)
- [Annotations-Regeln](#annotations-regeln)
- [Importreihung](#importreihung)
- [Tables & Strings](#tables--strings)
- [Native code / FFI evaluation](#native-code--ffi-evaluation)

---

## Verdict

| Section | Status |
| --- | --- |
| 1. Sicherheit & Fehlerbehandlung | ✅ |
| 2. Modularisierung | ✅ |
| 3. Buffer/Window-Management | ✅ (one gap found and fixed) |
| 4. Metatables & Datenmodelle | ✅ not applicable, deliberately |
| 5. Dokumentation & Annotationen | ✅ (one gap found and fixed) |
| 6. Testbarkeit | ✅ |
| 7. Error-Wrapping | ⚠️ partially declined — see below |
| 8. Performance & Speicher | ✅ |
| 9–11. Weak tables / memoization | ✅ not applicable |
| Cross-Platform | ✅ |
| Annotations-Regeln | ✅ (one gap found and fixed) |
| Importreihung | ✅ |
| Native code / FFI | ❌ evaluated and rejected |

Three gaps were found by this walkthrough and fixed (§3 an unguarded API call,
§5/Annotations the missing `return {}`). One convention is partially declined
with a reason (§7).

---

## 1. Sicherheitsprinzipien & Fehlerbehandlung

| Rule | Status | Detail |
| --- | --- | --- |
| `pcall()` preferred | ✅ | 40 call sites. Every `lib.nvim` probe, every `matchadd`/`matchdelete`, every `vim.regex` compile, every store read/write, every `search()`, every `nvim_win_call`. |
| Type guards & literal checks | ✅ | Every public function type-checks its arguments before use; the config layer type-checks every key; `registry.restore` re-validates every snapshot field. |
| Explicit returns | ✅ | Every facade action returns `boolean`. `registry.add`, `cursor.selection`, `qf.fill`, `persist.save_now` return `value, err` pairs. No silent failures. |
| No `notify()` in low-level code | ✅ | `core/*`, `cursor.lua`, `nav.lua`, `persist.lua` return errors upward; only `init.lua` (the facade), `ui/list.lua` and `qf.lua`'s truncation warning notify. This was checked, not assumed. |
| Standardized error wrapping | ⚠️ | See §7. |
| Structured error types | ⚠️ | See §7. |
| `@error`/`@raises` tags | ✅ not needed | Nothing here raises by design — errors are returned, not thrown. Tagging would document a mechanism the code does not use. |
| Private functions stay local | ✅ | 28 module-local `local function`s, none exported. |
| Arguments always passed + type-checked | ✅ | The one guard-argument default is `count.matching_lines`'s `max_entries`, which falls back to the *config* value rather than to unbounded — a guard that vanishes when forgotten would fail only on the inputs it exists for. |

The security-relevant half of this section is written up separately, in the
[Security model](../../README.md#security-model) section of the README: what is
trusted (nothing external), what the three input bounds are, and why the regex
construction makes catastrophic backtracking unreachable.

---

## 2. Modularisierung & Strukturprinzipien

| Rule | Status | Detail |
| --- | --- | --- |
| Module = one responsibility | ✅ | `core/pattern` builds regexes, `core/palette` owns colors and slots, `core/match` owns the ledger, `core/registry` owns the list, `core/count` scans. No module does two of those. |
| Pure functions preferred | ✅ | `core/pattern` is entirely pure (`escape`, `build`, `alternation`, `compile`). `core/count` is pure apart from reading the buffer. `cursor.lua` is read-only. |
| Local over global functions | ✅ | Verified by grep: `_G` is never touched. |
| Design patterns where useful | ✅ | Observer (`registry.on_change` → `persist`), Registry (`core/registry`), Facade (`init.lua`). Each chosen for a reason, not for coverage. |
| Tools via registry | ✅ | `core/registry.lua` is exactly that, and it is the single funnel every mutation passes through. |
| No global state | ✅ | Four module-level mutable values (ledger, item list, round-robin cursor, exception table), each private to its module and reachable only through its functions. |

The one architectural rule worth stating explicitly, because it is what keeps the
plugin coherent: **no module reads a raw options table** — everything goes through
`config.get("dot.path")`, so fallback semantics live in one place.

---

## 3. Buffer- & Window-Management

| Rule | Status | Detail |
| --- | --- | --- |
| Bind handle first, then check | ✅ | `core/match.lua` `eligible()`, `all_windows()`, `remove()`, `clear()`. |
| Always check `nvim_*_is_valid()` | ✅ **after a fix** | `nav.under_cursor` read the cursor unguarded while the identical read in `cursor.token` was `pcall`ed. Found by this walkthrough, fixed. |
| No API calls without a guard | ✅ | The remaining unguarded `nvim_buf_get_lines` calls are safe by contract: `strict_indexing = false` returns an empty table for an out-of-range index, and every call site handles the resulting `nil` line. |
| Uniform UI methods | ✅ not applicable | The plugin owns no windows. The one float belongs to `lib.nvim.ui.kit.select`, which manages its own lifecycle. |
| Central `ui_state` module | ✅ not applicable | Same reason — there is no UI state to centralize. The ledger is window *state*, but it is `matchadd()` bookkeeping, not UI handles, and it lives in exactly one module. |
| `cleanup_all()` | ✅ equivalent | `match.clear()` removes every tracked match from every window; `match.forget_window()` drops a dead window's entry. `VimLeavePre` flushes persistence. |
| Race conditions: re-validate in deferred callbacks | ✅ | This is the real risk here, since the window autocmd is `vim.schedule`d. `fill_window()` re-checks `nvim_win_is_valid` inside the deferred callback, and `eligible()` checks again below that. `WinClosed` deliberately does *not* call `matchdelete` — the matches died with the window, so the id is already stale. |

---

## 4. Methoden, Metatables & Datenmodelle

**Not applicable, deliberately.** The guidelines' own wording is "Metatables für
Methoden wenn sinnvoll, **nicht immer**".

`Spotlight.Item` is a plain record: six fields, no behavior. Giving it methods
would mean `item:remove()` reaching back into the registry that owns it —
inverting the ownership that makes `core/registry.lua` the single mutation funnel.
Getters/setters would be pass-throughs over a table that is already only reachable
through the module's own functions.

No ringbuffer (nothing here has a bounded history — `lib.nvim.logger` owns that
concern for the debug records), no `__index` sharing (there is one record shape, so
there is no shared default logic to inherit).

---

## 5. Dokumentation & Annotationen

| Rule | Status |
| --- | --- |
| Uniform file tags (`@module`, `@brief`, `@description`) | ✅ all 22 modules, verified by script |
| Per-function comments (`@param`, `@return`) | ✅ all functions, verified by script |
| Consistent naming (English, snake_case) | ✅ |
| Explicit typing (`@alias`, `@field`) | ✅ 14 classes and 2 aliases in `@types/init.lua` |
| Module linking via `@see` | ✅ `util/lib.lua` → `spotlight-lib` |
| `@error`/`@raises` | ✅ not used — see §1 |
| Per-subdirectory `/types` folder | ⚠️ deviation, see below |
| README (German for config modules) / `doc/*.txt` in English | ✅ Both English here — this is a standalone plugin, not an `nvim/config` module, and the guideline scopes the German README to the latter. |

**Deviation on per-subdirectory types folders.** The guidelines ask for at least
one types file per subdirectory; this plugin has one project-level
`lua/spotlight/@types/init.lua` instead. The reason is that the type surface is
small and *shared*: `Spotlight.Item` is used by `core/`, `ui/`, `nav`, `qf` and
`persist` alike, so splitting it per directory would either duplicate it or create
cross-directory type requires — both worse than one file. cascade.nvim's per-domain
types files exist because its domains genuinely have disjoint types
(`CascadeListOpts` vs `CascadeCycleOpts`); spotlight has one domain.

Revisit if a second domain appears; the roadmap's "spotlight sets" item would be
the trigger.

---

## 6. Testbarkeit & Lesbarkeit

| Rule | Status | Detail |
| --- | --- | --- |
| Small & focused (SRP) | ✅ | Longest function is `registry.restore` at ~42 lines, and it is a validated loop. |
| Clarity over brevity | ✅ | The comment density is deliberately high where a decision is non-obvious (`core/match.lua`'s header, `persist.lua`'s exception-semantics block) and absent where the code says it. |
| Testability by design | ✅ | Every core module is exercised directly, not only through the facade: `registry.restore`, `count.matching_lines`, `pattern.build`, `persist.persists`. |
| Snapshot/restore for state | ✅ | `registry.snapshot()` / `registry.restore()` exist for persistence and are used by `registry_spec.lua` to round-trip. |
| Separate test entry | ✅ | `TESTS/run.lua`, plain headless Neovim, no framework. 164 assertions over 6 specs. Moved from `docs/TESTS/` to the repo root per `FINISH_ME.md`. |

---

## 7. Fehlerbehandlung & Validierung

**Partially declined.** The guidelines ask for a `safe_call(fn, args)` wrapper
returning `{ ok, result, err }` and structured error types like
`InvalidStateError`.

What is implemented instead: every fallible function returns `value, err` where
`err` is a human-readable string, and every risky call is `pcall`-wrapped at the
site where the failure is *recoverable*. That is Lua's own idiom
(`pcall`, `io.open`, `tonumber`) and it is what the rest of the plugin's callers
expect.

Why the wrapper is declined here: there is exactly one consumer of every error —
the facade, which turns it into a notification. A `{ ok, result, err }` envelope
would be constructed and immediately destructured at every call site, and the
structured type would be matched in zero places. The guidelines' rationale is
"robustere Auswertung", and there is no evaluation happening to make more robust.

Where the section *is* applied in spirit: **config validation collects rather than
throws**. `config.issues` accumulates a human-readable reason per rejected key, the
value degrades to its default, and `:checkhealth` reports the list. That is the
structured-error benefit — machine-collectable, individually reportable failures —
at the one place where multiple independent failures genuinely need evaluating.

Reconsider if a second consumer of errors appears (a public API where callers
branch on the failure kind rather than showing it).

---

## 8. Performance & Speicher

| Rule | Status | Detail |
| --- | --- | --- |
| Debounced save | ✅ | `persist.debounce_ms` (500) via `lib.nvim.debounce`, flushed on `VimLeavePre` so the last toggle is not the one lost. |
| Weak references in caches | ✅ not applicable | The two caches are single-value sentinels (logger instance, `false`-probed). A weak table would be heavier than the value. |
| Async instead of blocking | ⚠️ partially | The debounce uses a libuv timer. The counting/filtering scan is synchronous — see below. |
| Memoization | ✅ not applicable | Nothing expensive is repeated: counts are deliberately not cached (§7 of Zentrale-Prinzipien), and regex compiles are cheap relative to the scan they precede. |
| Local variables where possible | ✅ | Every module aliases its requires once at the top. |
| Avoid allocations in loops | ✅ | Chunked buffer reads, `t[#t+1]`, no `table.insert` anywhere, no closures in loops (all verified by grep). |
| `table.concat` over `..` in loops | ✅ | `pattern.alternation`. The 15 remaining `..` uses are all single messages. |
| Index arithmetic over substring copies | ✅ mostly | `cursor.match_spanning` works with `find`'s returned indices. The scan loops do one `line:sub` per match, because `vim.regex:match_str` has no start-offset parameter — a genuine API limitation, not a choice. |
| `collectgarbage()` explicitly | ✅ not used | Correctly: the guidelines gate this on "man hat große Objekte aktiv entfernt". The largest structure here is a capped quickfix list handed straight to `setqflist`, after which Vim owns it. |

**On the synchronous scan.** Counting and filtering block the UI. This is a
conscious trade rather than an omission: both are user-initiated, both are bounded
(`list.count_max_lines`, `quickfix.max_entries`), and both are the *only* O(buffer)
work in the plugin. Moving them to `vim.loop` would mean the list opening before
its counts exist — a progressively-filling list is worse UX than a brief pause, and
the bound is what keeps the pause brief. `lib.nvim.progress` would be the tool if
this ever needs to become async; noted in [ROADMAP.md](ROADMAP.md).

---

## 9-11. Cache, schwache Tabellen, Spezialfälle

Sections 9 (cache hitting), 10 (weak tables & memoization) and 11 (dual
representation, default-values-via-metatable, FIFO histories) all assume a data
structure this plugin does not have: a large, hot, repeatedly-queried collection.

The registry holds 1–8 records. Every operation on it is a linear scan of at most
eight elements — measurably faster than a hash lookup at that size, and the
guidelines' own numbers (table access 3–21 cycles) say so. Introducing weak tables,
memoization or dual representation would add mechanism against no measurable cost.

The one item that *does* apply is "Cache in `stdpath("cache")` und nicht im
Runtime-State", which is satisfied via `lib.nvim.store.project` — covered under
§7 of [Zentral-Prinzipien.md](Zentral-Prinzipien.md).

---

## Cross-Platform

> *Soweit möglich immer so entwickeln, dass POSIX als auch Windows verwendbar sind.*

✅ **No platform-specific code paths exist**, because the plugin does nothing
platform-specific: no shell-outs, no `io.*`, no path construction beyond joining,
no external binaries.

The one place platform matters is `util/path.lua`, and it matters for a real
reason: `C:\Repos\x` and `c:\repos\x` are the same file on Windows and would
otherwise produce two different persistence-exception keys. Handled by normalizing
to forward slashes and comparing the root prefix case-insensitively, with
`lib.nvim.cross.platform.is_windows` as the detector and `vim.fn.has("win32")` as
the fallback.

Developed and tested on Windows 11; CI runs the suite on `ubuntu-latest`, so both
families are exercised on every push.

---

## Annotations-Regeln

| Rule | Status |
| --- | --- |
| Project-level `/@types` folder | ✅ `lua/spotlight/@types/init.lua` |
| `@types` modules end in `return {}` | ✅ **after a fix** — this walkthrough's finding; the file had annotations only |
| Uniform file tags | ✅ |
| Per-function `@param`/`@return`, including `@return nil` | ✅ verified by script — including the `@return nil` cases the rule calls out |
| English, consistent snake_case | ✅ |
| `@see` for module links | ✅ |
| `#` prefix in `@alias`/`@return` | ✅ used in `@field` and `@return` comments per the table's guidance |
| Detailed `class`/`field`/`alias` descriptions | ✅ each field carries a `#` comment explaining what it controls, not just its type |

---

## Importreihung

Required order: System/core → Debug/Notify → Config/Utils → State → UI →
UI-submodules → Controller → Keymaps.

✅ Followed, with the caveat that this plugin has fewer layers than the scheme
assumes. Representative example, `lua/spotlight/init.lua`:

```lua
require("spotlight.@types")            -- types first

local config = require("spotlight.config")        -- config
local cursor = require("spotlight.cursor")        -- utils
local lib = require("spotlight.util.lib")         -- utils (incl. notify/debug bridge)
local nav = require("spotlight.nav")
local palette = require("spotlight.core.palette") -- state
local path = require("spotlight.util.path")
local persist = require("spotlight.persist")
local qf = require("spotlight.qf")
local registry = require("spotlight.core.registry")
```

Within a layer the requires are alphabetical, which is the tie-break the scheme
does not specify. `vim` is a global and needs no require, so the "system/core"
slot is empty throughout.

---

## Tables & Strings

The benchmark-derived recommendations, applied:

| Recommendation | Applied |
| --- | --- |
| `t[i] = v` with inline reserve for max performance | Used where the index is known (`pattern.alternation`, `registry.snapshot`, `count`'s per-chunk loop). Inline reserve (`{ [N] = 0 }`) is **not** used — the sizes are 1–8 or unknown-until-scanned, so there is nothing to reserve. |
| `t[#t+1] = v` for dynamic appends | Used throughout. |
| `table.insert` only when readability wins | Not used anywhere. |
| `table.concat` instead of `..` in loops | `pattern.alternation`. |
| Work with `find`'s indices instead of copies | `cursor.match_spanning`. |
| Lua interns identical literals | Relied on for the `"word"`/`"literal"` kind comparisons and the config dot-paths. |

---

## Native code / FFI evaluation

`FINISH_ME.md` asks explicitly: *"Evaluieren: Macht es Sinn, das Plugin oder
bestimmte Teile davon als kompilierte Binaries auszugeben?"*

**No, and this plugin is an unusually clear case of no.**

The guidelines' own example for FFI is a Lua table holding a million numbers,
where a real C array avoids GC pressure. Nothing here is that shape. Concretely:

- **The highlighting — the expensive part — is already C.** `matchadd()` hands the
  pattern to Vim's own renderer, which evaluates it in C over the visible lines.
  There is no Lua in that loop to compile away. This is the whole reason the plugin
  is fast on a 200 MB log, and it comes for free.
- **The remaining Lua is not the bottleneck.** The counting/filtering scan spends
  its time inside `vim.regex:match_str` — again C. The Lua around it is a loop
  counter and a table append.
- **The largest data structure holds eight records.** There is no allocation
  pressure to relieve.
- **The cost would be severe.** A compiled artifact means per-platform builds, a
  toolchain requirement for contributors, a `luafile`/FFI loading path with a Lua
  fallback anyway, and a plugin that no longer installs by cloning. For a plugin
  whose hot path is already native, that buys nothing.

The honest summary: the performance work in this plugin was *choosing the C
primitive* (`matchadd()` over extmarks), not optimizing Lua. Having made that
choice, there is no Lua left worth compiling.
