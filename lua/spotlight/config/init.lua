---@module 'spotlight.config'
---@brief Runtime configuration store for spotlight.nvim.
---@description
--- Deep-merges user options over `spotlight.config.DEFAULTS`, validates the
--- handful of values that can break rendering or matching if wrong, and exposes
--- a single `get(path)` accessor (dot-separated) so no other module ever reads a
--- raw options table. This keeps fallback semantics in one place.
---
--- The merge and the dot-path lookup are `lib.lua.config`'s: this module used
--- to carry its own byte-identical copies of both (cascade.nvim had the other
--- copy) — see that lib module's doc comment for why the merge isn't
--- `lib.lua.tables.core.deep_merge`.

require("spotlight.@types")

local DEFAULTS = require("spotlight.config.DEFAULTS")
local lib_config = require("lib.lua.config")
local tables = require("lib.lua.tables.core")

---@class Spotlight.ConfigModule
---@field options Spotlight.Config
local M = {}

-- A fresh copy, not `DEFAULTS` itself: `M.options` is public and read by
-- every other module before `setup()` may ever run, and `DEFAULTS.lua`'s own
-- header says "Never mutate it at runtime" -- a promise this module cannot
-- keep for a caller that reads `M.options` while it still aliases the real
-- defaults table.
M.options = vim.deepcopy(DEFAULTS)

--- Problems found by the last `setup()`, as human-readable strings. Surfaced by
--- `:checkhealth spotlight` rather than thrown: a bad single key should degrade
--- to its default, not stop the plugin from loading.
---@type string[]
M.issues = {}

---@internal
--- `lib_config.deep_merge` replaces a table wholesale, instead of recursing
--- into it, whenever `tables.is_array` says it is list-like -- which is
--- vacuously true for `{}`. A record-shaped section (e.g. `keymaps`, whose
--- default has no array-like keys of its own) has no such array default, so
--- an override like `setup({ keymaps = {} })` would otherwise wipe every
--- default under that key, including the ones the caller never touched: the
--- merge cannot tell "empty override" apart from "explicit empty list", and
--- picks the wrong one. Recursively drop an override that is an empty table
--- where the matching default is *not* itself array-like, so it merges as
--- "nothing to override here" instead of "erase this section". An override
--- that mirrors an actual array default (e.g. `cursor.patterns = {}`) is left
--- untouched -- that is a deliberate, meaningful override, not this bug.
---@param opts table
---@param defaults table
---@return table clean
local function drop_pointless_empty_overrides(opts, defaults)
  local clean = {}
  for k, v in pairs(opts) do
    local d = defaults[k]
    if type(v) == "table" and type(d) == "table" and not tables.is_array(d) then
      if next(v) ~= nil then
        clean[k] = drop_pointless_empty_overrides(v, d)
      end
    else
      clean[k] = v
    end
  end
  return clean
end

---@internal
--- Whether `c` is a usable palette entry (both channels present, `#rrggbb`).
---@param c any
---@return boolean
local function valid_color(c)
  return type(c) == "table"
    and type(c.bg) == "string"
    and type(c.fg) == "string"
    and c.bg:match("^#%x%x%x%x%x%x$") ~= nil
    and c.fg:match("^#%x%x%x%x%x%x$") ~= nil
end

---@internal
--- Drop unusable palette entries, falling back to the defaults if that would
--- leave nothing to round-robin over.
---@param o Spotlight.Config
---@param key "colors"|"colors_light"
---@return nil
local function normalize_palette(o, key)
  local list = o.palette[key]
  if type(list) ~= "table" then
    -- A copy, not `DEFAULTS.palette[key]` itself: assigning the live default
    -- array back into `o` would re-alias it, undoing the deep-copied merge
    -- this module builds `o` from (see `M.setup`).
    o.palette[key] = vim.deepcopy(DEFAULTS.palette[key])
    M.issues[#M.issues + 1] = ("palette.%s is not a list — using defaults"):format(key)
    return
  end
  local kept = {}
  for _, c in ipairs(list) do
    if valid_color(c) then
      kept[#kept + 1] = c
    end
  end
  if #kept == 0 then
    o.palette[key] = vim.deepcopy(DEFAULTS.palette[key])
    M.issues[#M.issues + 1] = ("palette.%s held no valid { bg = '#rrggbb', fg = '#rrggbb' } entry — using defaults"):format(key)
    return
  end
  if #kept < #list then
    M.issues[#M.issues + 1] = ("palette.%s: dropped %d entry/entries that were not { bg = '#rrggbb', fg = '#rrggbb' }"):format(
      key,
      #list - #kept
    )
  end
  o.palette[key] = kept
end

---@internal
--- Drop cursor patterns Lua's matcher rejects. An invalid pattern would
--- otherwise throw from inside the resolver on an unrelated keystroke, far from
--- the config line that caused it.
---@param o Spotlight.Config
---@return nil
local function normalize_cursor_patterns(o)
  local list = o.cursor.patterns
  if type(list) ~= "table" then
    -- Copied for the same reason as `normalize_palette`'s fallback: `o` is
    -- the deep-copied merge result, and aliasing the live `DEFAULTS` array
    -- back in would reopen the same shared-reference hole one level down.
    o.cursor.patterns = vim.deepcopy(DEFAULTS.cursor.patterns)
    M.issues[#M.issues + 1] = "cursor.patterns is not a list — using defaults"
    return
  end
  local kept = {}
  for _, p in ipairs(list) do
    if type(p) == "string" and pcall(string.find, "", p) then
      kept[#kept + 1] = p
    else
      M.issues[#M.issues + 1] = ("cursor.patterns: dropped invalid Lua pattern %s"):format(vim.inspect(p))
    end
  end
  o.cursor.patterns = kept
end

---@internal
--- Clamp the numeric knobs into ranges the rest of the plugin can rely on.
---@param o Spotlight.Config
---@return nil
local function normalize_numbers(o)
  if type(o.match.max) ~= "number" or o.match.max < 1 then
    o.match.max = DEFAULTS.match.max
    M.issues[#M.issues + 1] = "match.max must be a positive number — using the default"
  end
  if type(o.match.priority) ~= "number" then
    o.match.priority = DEFAULTS.match.priority
    M.issues[#M.issues + 1] = "match.priority must be a number — using the default"
  end
  if type(o.list.count_max_lines) ~= "number" or o.list.count_max_lines < 0 then
    o.list.count_max_lines = DEFAULTS.list.count_max_lines
    M.issues[#M.issues + 1] = "list.count_max_lines must be a non-negative number — using the default"
  end
  if type(o.persist.debounce_ms) ~= "number" or o.persist.debounce_ms < 0 then
    o.persist.debounce_ms = DEFAULTS.persist.debounce_ms
    M.issues[#M.issues + 1] = "persist.debounce_ms must be a non-negative number — using the default"
  end
  if type(o.match.max_text_len) ~= "number" or o.match.max_text_len < 1 then
    o.match.max_text_len = DEFAULTS.match.max_text_len
    M.issues[#M.issues + 1] = "match.max_text_len must be a positive number — using the default"
  end
  if type(o.cursor.max_line_len) ~= "number" or o.cursor.max_line_len < 1 then
    o.cursor.max_line_len = DEFAULTS.cursor.max_line_len
    M.issues[#M.issues + 1] = "cursor.max_line_len must be a positive number — using the default"
  end
  if type(o.quickfix.max_entries) ~= "number" or o.quickfix.max_entries < 1 then
    o.quickfix.max_entries = DEFAULTS.quickfix.max_entries
    M.issues[#M.issues + 1] = "quickfix.max_entries must be a positive number — using the default"
  end
  if type(o.map.max_entries) ~= "number" or o.map.max_entries < 1 then
    o.map.max_entries = DEFAULTS.map.max_entries
    M.issues[#M.issues + 1] = "map.max_entries must be a positive number — using the default"
  end
end

---@internal
--- `map.sign_text` must be a non-empty string within Neovim's own 2-cell sign
--- limit — an oversized value would not fail loudly, it would just get
--- silently truncated by `nvim_buf_set_extmark` at a point far from this
--- setting, which is worse than degrading to the default here.
---@param o Spotlight.Config
---@return nil
local function normalize_map_sign_text(o)
  if type(o.map.sign_text) ~= "string" or o.map.sign_text == "" or vim.fn.strdisplaywidth(o.map.sign_text) > 2 then
    M.issues[#M.issues + 1] = "map.sign_text must be a non-empty string of at most 2 display cells — using the default"
    o.map.sign_text = DEFAULTS.map.sign_text
  end
end

---@internal
--- Strip newlines from `list.swatch`.
---
--- The swatch is written straight into the chooser's buffer as part of a line, and
--- `nvim_buf_set_lines` treats an embedded newline as a hard error, not as two
--- lines — so a `"\n"` in this string would turn opening the list into a stack
--- trace. Sanitized rather than rejected: the intent (some visible filler) is
--- clear and recoverable.
---@param o Spotlight.Config
---@return nil
local function normalize_swatch(o)
  if type(o.list.swatch) ~= "string" then
    o.list.swatch = DEFAULTS.list.swatch
    M.issues[#M.issues + 1] = "list.swatch must be a string — using the default"
    return
  end
  local clean = o.list.swatch:gsub("[\r\n]", " ")
  if clean ~= o.list.swatch then
    M.issues[#M.issues + 1] = "list.swatch contained a newline — replaced with a space (it is written into a buffer line)"
    o.list.swatch = clean
  end
end

---@internal
--- Normalize `nav.scope` to a value `spotlight.nav` understands.
---@param o Spotlight.Config
---@return nil
local function normalize_nav(o)
  if o.nav.scope ~= "auto" and o.nav.scope ~= "all" then
    M.issues[#M.issues + 1] = ('nav.scope must be "auto" or "all" — using "%s"'):format(DEFAULTS.nav.scope)
    o.nav.scope = DEFAULTS.nav.scope
  end
end

---@internal
--- Normalize `list.count_scope` to a value `spotlight.core.count` understands.
---@param o Spotlight.Config
---@return nil
local function normalize_list_count_scope(o)
  if o.list.count_scope ~= "buffer" and o.list.count_scope ~= "loaded" then
    M.issues[#M.issues + 1] = ('list.count_scope must be "buffer" or "loaded" — using "%s"'):format(DEFAULTS.list.count_scope)
    o.list.count_scope = DEFAULTS.list.count_scope
  end
end

--- Apply user options. Safe to call once from `setup()`.
---@param opts Spotlight.Config|nil
---@return nil
function M.setup(opts)
  M.issues = {}
  local clean = drop_pointless_empty_overrides(type(opts) == "table" and opts or {}, DEFAULTS)
  -- Merged onto a copy of `DEFAULTS`, not `DEFAULTS` itself: `deep_merge`
  -- only copies the top level and recurses into sections `clean` actually
  -- mentions, so every section left untouched by the caller would otherwise
  -- be taken by reference straight from `DEFAULTS` -- and `DEFAULTS.lua`'s
  -- own header says "Never mutate it at runtime".
  M.options = lib_config.deep_merge(vim.deepcopy(DEFAULTS), clean)
  normalize_palette(M.options, "colors")
  normalize_palette(M.options, "colors_light")
  normalize_cursor_patterns(M.options)
  normalize_numbers(M.options)
  normalize_nav(M.options)
  normalize_list_count_scope(M.options)
  normalize_swatch(M.options)
  normalize_map_sign_text(M.options)
end

--- Read a value by dot-path, e.g. `get("match.priority")`.
---@param path string
---@return any
function M.get(path)
  return lib_config.get(M.options, path)
end

return M
