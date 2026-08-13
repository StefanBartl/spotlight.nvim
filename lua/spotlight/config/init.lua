---@module 'spotlight.config'
---@brief Runtime configuration store for spotlight.nvim.
---@description
--- Deep-merges user options over `spotlight.config.DEFAULTS`, validates the
--- handful of values that can break rendering or matching if wrong, and exposes
--- a single `get(path)` accessor (dot-separated) so no other module ever reads a
--- raw options table. This keeps fallback semantics in one place.

require("spotlight.@types")

local DEFAULTS = require("spotlight.config.DEFAULTS")

---@class Spotlight.ConfigModule
---@field options Spotlight.Config
local M = {}

M.options = DEFAULTS

--- Problems found by the last `setup()`, as human-readable strings. Surfaced by
--- `:checkhealth spotlight` rather than thrown: a bad single key should degrade
--- to its default, not stop the plugin from loading.
---@type string[]
M.issues = {}

---@internal
--- Recursively merge `override` into a copy of `base`. Arrays (list-like
--- tables) are replaced wholesale rather than concatenated, so a user can fully
--- redefine e.g. `cursor.patterns` or `palette.colors` without inheriting the
--- defaults they meant to drop.
---@param base table
---@param override table
---@return table
local function deep_merge(base, override)
  local out = {}
  for k, v in pairs(base) do
    out[k] = v
  end
  for k, v in pairs(override) do
    if type(v) == "table" and type(out[k]) == "table" and not vim.islist(v) then
      out[k] = deep_merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
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
    o.palette[key] = DEFAULTS.palette[key]
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
    o.palette[key] = DEFAULTS.palette[key]
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
    o.cursor.patterns = DEFAULTS.cursor.patterns
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
  M.options = deep_merge(DEFAULTS, type(opts) == "table" and opts or {})
  normalize_palette(M.options, "colors")
  normalize_palette(M.options, "colors_light")
  normalize_cursor_patterns(M.options)
  normalize_numbers(M.options)
  normalize_nav(M.options)
  normalize_list_count_scope(M.options)
  normalize_swatch(M.options)
end

--- Read a value by dot-path, e.g. `get("match.priority")`.
---@param path string
---@return any
function M.get(path)
  if type(path) ~= "string" then
    return nil
  end
  local node = M.options
  for key in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
  end
  return node
end

return M
