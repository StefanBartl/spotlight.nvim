---@module 'spotlight.@types'
---@brief Type surface for spotlight.nvim.
---@description
--- Every user-configurable key has a type here, so `require("spotlight").setup{}`
--- gets completion and diagnostics from lua_ls without the user having to read
--- `config/DEFAULTS.lua`. Runtime-only shapes (a registered spotlight, the
--- persisted snapshot) live here too, so the modules that pass them around
--- agree on one definition.

-- ---------- runtime model ----------

--- One spotlight: a pattern plus the palette slot it renders in.
--- `pattern` is a **complete Vim regex** (already escaped and flag-prefixed by
--- `spotlight.core.pattern`), ready to hand to |matchadd()| — not the raw text
--- the user pointed at. `text` keeps that raw text for display purposes.
---@class Spotlight.Item
---@field id integer            # Stable session id; also the bookkeeping key in `core.match`.
---@field text string           # Raw token the spotlight was created from (display only).
---@field pattern string        # Complete Vim regex handed to `matchadd()`.
---@field slot integer          # Palette slot, 1..#palette.colors.
---@field hl string             # Highlight group name, e.g. "Spotlight3".
---@field origin string|nil     # Project-relative path of the file it was created in (persist scoping).

--- The on-disk snapshot under the `spotlight/state` project key.
---@class Spotlight.Snapshot
---@field version integer
---@field spotlights Spotlight.StoredItem[]
---@field persist_exceptions table<string, boolean>

--- A spotlight as written to disk. Deliberately narrower than
--- `Spotlight.Item`: ids are session-local and the regex is re-derived from
--- `text` on load, so a changed escaping/flag policy takes effect for restored
--- spotlights too instead of resurrecting a stale regex.
---@class Spotlight.StoredItem
---@field text string
---@field slot integer
---@field kind Spotlight.TokenKind
---@field origin string|nil

--- What the resolver decided the token under the cursor is. Drives whether the
--- generated regex gets word boundaries: a bare `<cword>` fallback wants them
--- (`error` should not match `errors`), a structured log token must not have
--- them (`\<192.168.1.1\>` never matches, since `.` is not a word character).
---@alias Spotlight.TokenKind "word"|"literal"

--- A resolved token, ready to be turned into a spotlight.
---@class Spotlight.Token
---@field text string
---@field kind Spotlight.TokenKind

-- ---------- configuration ----------

---@alias Spotlight.NavScope "auto"|"all"

---@class Spotlight.Config
---@field palette Spotlight.PaletteOpts
---@field match Spotlight.MatchOpts
---@field cursor Spotlight.CursorOpts
---@field nav Spotlight.NavOpts
---@field list Spotlight.ListOpts
---@field quickfix Spotlight.QuickfixOpts
---@field persist Spotlight.PersistOpts
---@field keymaps Spotlight.KeymapOpts
---@field notify boolean # Report added/removed/cleared spotlights via `lib.nvim.notify`.

--- Palette colors. Each entry sets **both** `bg` and `fg` so contrast is
--- guaranteed in light and dark themes alike, rather than inheriting an
--- unknown foreground from the colorscheme.
---@class Spotlight.PaletteOpts
---@field colors Spotlight.Color[]        # Used when `&background == "dark"`.
---@field colors_light Spotlight.Color[]  # Used when `&background == "light"`.
---@field bold boolean                    # Render matches bold.
---@field reapply_on_colorscheme boolean  # Redefine the groups after `:colorscheme`.

---@class Spotlight.Color
---@field bg string # "#rrggbb"
---@field fg string # "#rrggbb"

---@class Spotlight.MatchOpts
---@field priority integer     # |matchadd()| priority. >0 renders above 'hlsearch'.
---@field ignore_case boolean  # false pins `\C` (case-sensitive) regardless of 'ignorecase'.
---@field word_boundaries boolean # Wrap `word`-kind tokens in `\<`/`\>`.
---@field max integer          # Refuse to add more than this many spotlights at once.

---@class Spotlight.CursorOpts
---@field patterns string[] # Lua patterns, highest priority first; first one whose match spans the cursor wins.
---@field fallback_cword boolean # Fall back to `<cword>` when no pattern matches.

---@class Spotlight.NavOpts
---@field scope Spotlight.NavScope # "auto": the spotlight under the cursor if there is one, else all.
---@field wrap boolean             # Wrap around the end of the buffer.
---@field center boolean           # `zz` after jumping.

---@class Spotlight.ListOpts
---@field count boolean          # Compute match counts when the list opens (on demand, never live).
---@field count_max_lines integer # Skip counting above this buffer line count; the list shows "?" instead.
---@field swatch string          # Text painted in the spotlight's own colors as the row's color chip.

---@class Spotlight.QuickfixOpts
---@field open boolean  # `:copen` after filling the list.
---@field title string  # Quickfix list title.

---@class Spotlight.PersistOpts
---@field enable boolean   # Master switch for the whole persistence layer.
---@field default boolean  # Per-file default; `:Spotlight persist off` overrides it for one file.
---@field debounce_ms integer # Coalescing window for the debounced save.

---@class Spotlight.KeymapOpts
---@field preset boolean               # Bind the default keys.
---@field toggle string|false          # Normal + visual: toggle the token/selection.
---@field list string|false            # Open the spotlight list.
---@field clear string|false           # Remove every spotlight.
---@field quickfix string|false        # Send all matching lines to the quickfix list.
---@field next string|false            # Jump to the next occurrence.
---@field prev string|false            # Jump to the previous occurrence.
