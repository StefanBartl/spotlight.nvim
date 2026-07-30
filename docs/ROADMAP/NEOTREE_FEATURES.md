# Features from spotlight.nvim relevant to `filetree.nvim`

Per the project checklist: which mechanisms implemented here are worth lifting
into `filetree.nvim` (the planned filetree-manager-agnostic, cross-platform layer
over Neotree / NvimTree / Netrw), where they live, and what would have to change.

Honest framing up front: spotlight.nvim is a *buffer-content* plugin, so most of
it has nothing to say about a file tree. What transfers is not the feature but
four **mechanisms** — and one of them (the `matchadd()` ledger) transfers unusually
well, because a filetree window is exactly the kind of window that loses
window-local state on every reopen.

## Table of content

- [Feature list](#feature-list)
- [Is spotlight worth using as a Neotree source](#is-spotlight-worth-using-as-a-neotree-source)
- [Explicitly not transferable](#explicitly-not-transferable)

---

## Feature list

### 1. The window-local-state ledger

| | |
| --- | --- |
| **Feature** | A `window -> { logical id -> vim-side handle }` ledger that re-applies window-local state to every window, tracks what it applied where, and can remove one logical item from every window it ever reached. |
| **Origin** | `lua/spotlight/core/match.lua` — the ledger table at `:29`, `eligible()` at `:41` (floating-window skip), `apply_window()` at `:94`, `remove()` at `:116`, `forget_window()` at `:160`. Driven by the autocmds in `lua/spotlight/bindings/autocmds.lua:52` (`WinNew`/`BufWinEnter`/`TabNewEntered`) and `:74` (`WinClosed`). |
| **Thematic home in filetree.nvim** | A `core/window_state` module, below the manager adapters. |
| **Why it matters there** | Neotree and NvimTree windows are closed and recreated constantly (toggle, `:e` in the tree, tab switch), and anything window-local — `matchadd()` highlighting of git-dirty or filtered entries, `winhighlight` overrides, a custom `statuscolumn` — is lost each time. The same ledger + three-autocmd pattern solves it once for every manager instead of once per manager. |
| **What must change** | The `WinNew`-deferral (`vim.schedule` at `autocmds.lua:52`) exists because the new window is not current yet; a filetree also needs the *buffer* identity in the key, since a tree window is reused for different roots. So the key becomes `(win, root)` rather than `win`. |

### 2. Project-relative path keys, cross-platform

| | |
| --- | --- |
| **Feature** | Turning an absolute path into a stable, portable key: forward-slash normalization, project-root prefix stripping, case-insensitive comparison on Windows, and a defined answer for files outside the project and buffers with no file at all. |
| **Origin** | `lua/spotlight/util/path.lua` — `is_windows()` at `:21`, `slashes()` at `:35`, `root()` at `:45`, `buffer_key()` at `:62`. |
| **Thematic home in filetree.nvim** | `core/paths` — needed by literally every persisted feature (expanded-node state, pinned entries, per-directory sort overrides, bookmarks). |
| **Why it matters there** | This is the bug factory in any filetree plugin that persists state: `C:\Repos\x` and `c:\repos\x` are the same directory and produce two different keys, and a key that embeds the absolute path stops working the moment the checkout moves. `buffer_key()` gets both right in ~25 lines. |
| **What must change** | Add a `dir_key()` sibling — a tree persists *directories*, and a trailing-slash mismatch would split the key the same way a case mismatch does. Also worth extracting the "is this path inside that root" test, which a tree needs on its own for filtering. |

### 3. The two-axis override model (global default + per-path exception)

| | |
| --- | --- |
| **Feature** | A boolean setting with a global default *and* a per-path override, resolved by one function, where the override is persisted independently of the thing it governs — so the model works in both directions (opt-out by default, or inverted to opt-in) without a second config key. |
| **Origin** | `lua/spotlight/persist.lua` — `persists()` at `:74`, `has_override()` at `:84`, `set_exception()` at `:192`, and the "always persist the exception list itself" decision at `:113`. Command surface: `lua/spotlight/bindings/usrcmds.lua`, the `persist` route. |
| **Thematic home in filetree.nvim** | `core/policy` — reused by "follow the current file", "show hidden", "show gitignored", "auto-expand", each of which wants a global default plus per-directory exceptions. |
| **Why it matters there** | Filetree plugins usually expose these as one global boolean, and users then want an exception for one noisy directory (`node_modules` visible in one project, hidden everywhere else). The three-state resolution (`on` / `off` / `default`, where `default` *clears* the override rather than setting it to the default's current value) is the part that is easy to get wrong — see the `:Spotlight persist default` route. |
| **What must change** | Nothing structural. A tree wants the override to be inheritable down the directory tree (an exception on `a/` applying to `a/b/`), which is a longest-prefix lookup instead of an exact-key lookup. |

### 4. Rich chooser rows with a per-row color chip

| | |
| --- | --- |
| **Feature** | A picker list where each row carries its own highlight spans — a colored swatch plus plain text — with no rendering code in the calling plugin. |
| **Origin** | `lua/spotlight/ui/list.lua` — `row()` at `:34` builds the `{ value, lines, highlights }` shape for `lib.nvim.ui.kit.select`; `open()` at `:55`. Also the decision *not* to set `respect_override` (documented in that file's header), because a foreign `vim.ui.select` backend cannot render per-span colors. |
| **Thematic home in filetree.nvim** | Any of its pickers: root switcher, bookmark list, git-status list, "recent directories". |
| **Why it matters there** | A tree's pickers are exactly where a per-row indicator (git status color, file-type icon color, a project badge) is worth having, and this is the minimal known-good shape for one. The `respect_override` trade-off is the reusable insight: honour the user's picker backend for plain lists, keep kit's chooser when the colors *are* the information. |
| **What must change** | Nothing — it is a `lib.nvim` capability, used here as documentation of how. |

### 5. Config validation that degrades instead of throwing

| | |
| --- | --- |
| **Feature** | Per-key normalization that drops invalid values, falls back to the default, collects a human-readable reason, and surfaces the collected list in `:checkhealth` — so one bad line never stops the plugin from loading. |
| **Origin** | `lua/spotlight/config/init.lua` — `M.issues` at `:24`, `normalize_palette()` at `:63`, `normalize_cursor_patterns()` at `:95` (validates user Lua patterns with `pcall(string.find, "", p)`), `normalize_numbers()` at `:116`. Reported by `lua/spotlight/health.lua`. |
| **Thematic home in filetree.nvim** | `config/` — more valuable there than here, because a filetree config is bigger (per-manager sections, icon tables, keymap tables) and a single typo in a nested table is a likelier failure. |
| **Why it matters there** | The `pcall(string.find, "", p)` trick specifically: a filetree takes user glob/pattern lists for filtering, and an invalid one would otherwise throw from inside a directory scan, far from the config line that caused it. |
| **What must change** | Nothing. Pattern generalizes as-is. |

---

## Is spotlight worth using as a Neotree source?

**No, and it should not be.** A Neotree source answers "what are the entries in
this tree" — filesystem, buffers, git status, document symbols. Spotlight has no
tree-shaped data: it owns a flat, session-global list of ~1–8 tokens, which is a
list, not a hierarchy, and `lib.nvim.ui.kit.select` already renders it better than
a tree pane would (the color swatch per row is the whole point, and a tree source
gives up per-row highlight spans).

Two adjacent things *would* be worth doing, and neither is a source:

1. **A `filetree.nvim` command that spotlights from the tree.** Cursor on a file
   entry, one key, and its basename becomes a spotlight — so you can then see
   which of your open logs mention it. That is a ~10-line call into
   `require("spotlight").add(name)`, in filetree's keymap layer, not a source.

2. **Spotlight matches rendering inside the tree window.** Already works: the
   ledger treats any non-floating window as eligible (`core/match.lua:41`), so a
   token that appears in a filename lights up in the tree too, in the same color
   it has in the log. Nothing to build; worth knowing it happens, and worth an
   opt-out if it turns out to be noisy (see "Per-window opt-out" in
   [ROADMAP.md](ROADMAP.md)).

---

## Explicitly not transferable

Listed so they are not mistaken for candidates later:

- **The `matchadd()`-over-extmarks decision** (`core/match.lua` header). It is
  correct here because the highlight is pattern-shaped and the file is huge. A
  filetree's decorations are position-shaped and its buffer is tiny — extmarks are
  the right choice there, and copying this reasoning across would be a
  pessimization.
- **The token resolver** (`cursor.lua`). Entirely about log-line content.
- **On-demand counting** (`core/count.lua`). The size guard it exists to respect
  does not apply to a tree buffer.
- **The palette** (`core/palette.lua`). Eight mutually-distinguishable
  background colors is a marking palette; a filetree wants semantic colors (git
  status, file type) tied to the colorscheme, which is the opposite requirement.
  The `ColorScheme`/`OptionSet background` reapply *pattern* is worth copying; the
  colors are not.
