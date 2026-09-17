-- Test code: when something here comes back nil -- a config lookup, a palette
-- list -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: assign-type-mismatch
-- Deliberately invalid values throughout: the point of every case here is that
-- a bad key degrades to its default instead of raising.
-- TESTS/config_edge_spec.lua
-- The half of `spotlight.config` the other specs do not reach: the numeric
-- knobs nothing else validates, the light palette, `list.count`/`map.sign_text`
-- boundaries, `get()`'s dot-path edges, and the relationship between the merged
-- options table and the DEFAULTS table it was built from.
--
-- That last one is the interesting part. `DEFAULTS.lua`'s own module doc says
-- "Never mutate it at runtime" -- and the merge cannot enforce it, which is
-- pinned below.

local t = require("harness")

local M = {}

function M.run()
  local DEFAULTS = require("spotlight.config.DEFAULTS")
  local config = require("spotlight.config")

  config.setup()

  -- ---------- setup() resets, it does not accumulate ----------
  config.setup({ match = { max = 7 }, list = { count = false } })
  t.eq("setup: the override applies", config.get("match.max"), 7)
  t.eq("setup: and a second key too", config.get("list.count"), false)
  config.setup({})
  t.eq("setup: a later setup({}) restores the default, it is not cumulative", config.get("match.max"), 64)
  t.eq("setup: ...for every key", config.get("list.count"), true)

  config.setup({ nav = { scope = "sideways" } })
  t.ok("setup: issues were collected", #config.issues >= 1)
  config.setup()
  t.eq("setup: issues are reset on the next setup, not appended to", #config.issues, 0)

  -- A missing or non-table argument is the no-op case, not an error.
  config.setup(nil)
  t.eq("setup(nil): defaults apply", config.get("match.max"), 64)
  config.setup(42)
  t.eq("setup(non-table): treated as {}", config.get("match.max"), 64)
  t.eq("setup(non-table): and nothing is reported as an issue", #config.issues, 0)

  -- Unknown keys are carried through rather than rejected -- worth knowing,
  -- since a typo in a user's config is therefore silent here (the keymap
  -- registry is the layer that reports one, and only for keymap names).
  config.setup({ nonexistent_section = { a = 1 } })
  t.eq("setup: an unknown key is kept, not rejected", config.get("nonexistent_section.a"), 1)
  t.eq("setup: and is not reported as an issue", #config.issues, 0)
  config.setup()

  -- ---------- the numeric knobs ----------
  ---@param path string
  ---@param section table
  ---@param default any
  local function falls_back(path, section, default)
    config.setup(section)
    t.eq(("validate: %s falls back to %s"):format(path, tostring(default)), config.get(path), default)
    local reported = false
    for _, issue in ipairs(config.issues) do
      if issue:find(path:gsub("^.*%.", ""), 1, true) then
        reported = true
      end
    end
    t.ok(("validate: %s reports the fallback for :checkhealth"):format(path), reported)
  end

  falls_back("match.max_text_len", { match = { max_text_len = 0 } }, 512)
  falls_back("match.max_text_len", { match = { max_text_len = "long" } }, 512)
  falls_back("cursor.max_line_len", { cursor = { max_line_len = 0 } }, 8192)
  falls_back("quickfix.max_entries", { quickfix = { max_entries = 0 } }, 10000)
  falls_back("quickfix.max_entries", { quickfix = { max_entries = -1 } }, 10000)
  falls_back("map.max_entries", { map = { max_entries = 0 } }, 10000)
  falls_back("map.max_entries", { map = { max_entries = {} } }, 10000)
  falls_back("list.count_max_lines", { list = { count_max_lines = "lots" } }, 200000)
  falls_back("persist.debounce_ms", { persist = { debounce_ms = false } }, 500)

  -- Zero is legal for count_max_lines (it means "never count") but not for the
  -- caps, which is the one asymmetry in that block.
  config.setup({ list = { count_max_lines = 0 } })
  t.eq("validate: count_max_lines = 0 is accepted -- it means 'never count'", config.get("list.count_max_lines"), 0)
  config.setup({ persist = { debounce_ms = 0 } })
  t.eq("validate: debounce_ms = 0 is accepted -- it means 'save immediately'", config.get("persist.debounce_ms"), 0)
  config.setup({ match = { priority = -5 } })
  t.eq("validate: a negative priority is accepted -- it puts spotlights below 'hlsearch'", config.get("match.priority"), -5)
  config.setup()

  -- ---------- the light palette gets the same treatment as the dark one ----------
  config.setup({ palette = { colors_light = "nope" } })
  t.eq("palette: a non-list colors_light falls back to the defaults", #config.get("palette.colors_light"), 8)
  t.contains("palette: and says which list it was", table.concat(config.issues, " | "), "colors_light")

  config.setup({ palette = { colors_light = { { bg = "#000000" } } } })
  t.eq("palette: an entry without fg is dropped -- both channels or nothing", #config.get("palette.colors_light"), 8)

  config.setup({
    palette = {
      colors_light = {
        { bg = "#000000", fg = "#ffffff" },
        { bg = "#fff", fg = "#ffffff" },
        { bg = "000000", fg = "#ffffff" },
        { bg = "#AABBCC", fg = "#FFFFFF" },
      },
    },
  })
  local light = config.get("palette.colors_light")
  t.eq("palette: the two well-formed entries are kept", #light, 2)
  t.eq("palette: uppercase hex is well-formed", light[2].bg, "#AABBCC")
  t.ok("palette: the two malformed ones are reported", #config.issues >= 1)

  -- The dark list is normalized independently of the light one.
  config.setup({ palette = { colors = { { bg = "#000000", fg = "#ffffff" } } } })
  t.eq("palette: a one-entry dark list is legal", #config.get("palette.colors"), 1)
  t.eq("palette: and does not shrink the light list", #config.get("palette.colors_light"), 8)
  config.setup()

  -- ---------- map.sign_text is bounded by Neovim's own 2-cell sign limit ----------
  ---@param value any
  ---@param expected string
  ---@param why string
  local function sign_text(value, expected, why)
    config.setup({ map = { sign_text = value } })
    t.eq(
      ("sign_text: %s -> %s (%s)"):format(vim.inspect(value), vim.inspect(expected), why),
      config.get("map.sign_text"),
      expected
    )
  end

  sign_text("a", "a", "one cell")
  sign_text("ab", "ab", "exactly two cells")
  sign_text("abc", "▪", "three cells, over the limit")
  sign_text("日", "日", "one double-width glyph is two cells")
  sign_text("日本", "▪", "two double-width glyphs are four cells")
  sign_text("", "▪", "empty")
  sign_text(42, "▪", "not a string")
  config.setup()

  -- ---------- list.swatch ----------
  config.setup({ list = { swatch = "x\ry\nz" } })
  t.eq("swatch: both CR and LF are replaced", config.get("list.swatch"), "x y z")
  config.setup({ list = { swatch = "" } })
  t.eq("swatch: an empty swatch is legal -- it only means a zero-width colour cell", config.get("list.swatch"), "")
  config.setup()

  -- ---------- cursor.patterns ----------
  config.setup({ cursor = { patterns = 5 } })
  t.eq("patterns: a non-list falls back to the defaults", #config.get("cursor.patterns"), 11)
  config.setup({ cursor = { patterns = { "%d+", 42, "%f[", "%w+" } } })
  t.eq("patterns: the two usable entries survive", #config.get("cursor.patterns"), 2)
  config.setup({ cursor = { patterns = {} } })
  t.eq("patterns: an empty list is accepted -- <cword> alone is a valid resolver", #config.get("cursor.patterns"), 0)
  config.setup()

  -- ---------- get()'s dot path ----------
  t.eq("get: a missing leaf is nil", config.get("match.nonexistent"), nil)
  t.eq("get: a missing branch is nil, not an error", config.get("nope.nope.nope"), nil)
  t.eq("get: walking into a non-table is nil", config.get("match.max.deeper"), nil)
  t.eq("get: a nil path is nil", config.get(nil), nil)
  t.eq("get: an empty path returns the whole table", config.get(""), config.options)
  t.eq("get: a section comes back as a table", type(config.get("match")), "table")
  t.eq("get: a top-level scalar", config.get("notify"), true)

  -- ---------- BUG: the merged options share sub-tables with DEFAULTS ----------
  --
  -- `lib.lua.config.deep_merge` copies only the top level and recurses solely
  -- into sections the *override* mentions. Every section a user did not mention
  -- is therefore taken by reference, so `config.options.<section>` IS
  -- `DEFAULTS.<section>` -- and `DEFAULTS.lua`'s own module doc says "Never
  -- mutate it at runtime", which nothing here can enforce.
  --
  -- Nothing inside the plugin currently writes to one (asserted below, so a
  -- future change that starts to is caught), but `config.options` is public,
  -- `config.get("cursor")` hands the live list to any caller, and the
  -- fallback branches in the normalizers hand out `DEFAULTS.<section>.<list>`
  -- by reference too. A caller that edits what looks like its own snapshot
  -- silently rewrites the defaults for the rest of the session -- including the
  -- values the *next* `setup()` falls back to.
  --
  -- Fix: merge onto `vim.deepcopy(DEFAULTS)` (and/or deepcopy in the fallback
  -- assignments). Pinned rather than fixed: it changes the identity of every
  -- table `config.get` returns.
  config.setup()
  t.ok("BUG: options.match is the very DEFAULTS.match table", config.options.match == DEFAULTS.match)
  t.ok("BUG: options.cursor too", config.options.cursor == DEFAULTS.cursor)
  t.ok("BUG: and options.palette.colors", config.options.palette.colors == DEFAULTS.palette.colors)
  t.ok("BUG: down to the individual colour entries", config.options.palette.colors[1] == DEFAULTS.palette.colors[1])
  t.ok("BUG: get() hands the live list out as well", config.get("cursor.patterns") == DEFAULTS.cursor.patterns)

  local saved_max = DEFAULTS.match.max
  config.options.match.max = 999
  t.eq("BUG: writing to the snapshot rewrites the immutable defaults", DEFAULTS.match.max, 999)
  DEFAULTS.match.max = saved_max
  config.setup()
  t.eq("restored: DEFAULTS.match.max is back", config.get("match.max"), 64)

  -- The fallback branch is the same story one level down: a rejected list is
  -- replaced by the DEFAULTS list *itself*, not by a copy of it.
  config.setup({ cursor = { patterns = "nope" } })
  t.ok("BUG: the patterns fallback aliases DEFAULTS.cursor.patterns", config.get("cursor.patterns") == DEFAULTS.cursor.patterns)
  config.setup({ palette = { colors = { "nope" } } })
  t.ok("BUG: the palette fallback does the same", config.get("palette.colors") == DEFAULTS.palette.colors)
  config.setup()

  -- The positive half of the pin: as things stand, a full `setup()` leaves
  -- DEFAULTS pristine. This is what would break first if anything downstream
  -- (the keymap registry, the palette, a binding) started writing into the
  -- table it was handed.
  local before = vim.deepcopy(DEFAULTS)
  require("spotlight").setup()
  t.ok("DEFAULTS: a full setup() leaves the defaults untouched", vim.deep_equal(DEFAULTS, before))
  require("spotlight").setup({ keymaps = { preset = false } })
  t.ok("DEFAULTS: ...and so does one with overrides", vim.deep_equal(DEFAULTS, before))

  require("spotlight").setup()
  config.setup()
end

return M
