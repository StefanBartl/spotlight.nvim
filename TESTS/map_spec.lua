-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/map_spec.lua
-- Occurrence density (sign column): `map.show`/`map.clear`, one-shot and
-- never live — rendering itself is never asserted (matches the suite's own
-- convention), only extmark placement counts via nvim_buf_get_extmarks.

local t = require("harness")

local M = {}

---@internal
local function mark_count(bufnr, ns)
  return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
end

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local map = require("spotlight.map")
  local api = require("spotlight")

  config.setup()
  registry.clear()

  local bufnr = t.fixture({ "req=aaa one", "req=bbb two", "req=aaa three", "other" })
  local ns = map.namespace()

  registry.add({ text = "aaa", kind = "literal" })
  registry.add({ text = "bbb", kind = "literal" })

  -- ---------- all spotlights ----------
  local marked, err, truncated = map.show(nil)
  t.eq("show: marks one line per match, both spotlights", marked, 3)
  t.eq("show: no error", err, nil)
  t.ok("show: not truncated", not truncated)
  t.eq("show: extmark count matches", mark_count(bufnr, ns), 3)

  -- ---------- one spotlight only ----------
  local marked2 = map.show("aaa")
  t.eq("show(text): marks only that spotlight's lines", marked2, 2)
  t.eq("show(text): fewer marks than the all-spotlights case", mark_count(bufnr, ns), 2)

  -- ---------- clear ----------
  map.clear()
  t.eq("clear: empties the buffer's namespace", mark_count(bufnr, ns), 0)

  -- ---------- re-show does not accumulate ----------
  map.show(nil)
  local first_count = mark_count(bufnr, ns)
  map.show(nil)
  t.eq("show: repeated calls do not accumulate marks", mark_count(bufnr, ns), first_count)

  -- ---------- invariant: nothing recomputes live ----------
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "req=aaa one EDITED, no longer matches at this spot conceptually" })
  t.eq("invariant: editing the buffer after show() leaves marks unchanged", mark_count(bufnr, ns), first_count)

  map.clear()
  registry.clear()

  -- ---------- item highlight is per-spotlight ----------
  t.fixture({ "req=aaa", "req=bbb" })
  local ha = registry.add({ text = "aaa", kind = "literal" })
  local hb = registry.add({ text = "bbb", kind = "literal" })
  map.show(nil)
  local marks = vim.api.nvim_buf_get_extmarks(vim.api.nvim_get_current_buf(), ns, 0, -1, { details = true })
  local groups = {}
  for _, m in ipairs(marks) do
    groups[m[4].sign_hl_group] = true
  end
  t.ok("show: signs use spotlight A's own highlight group", groups[ha.hl])
  t.ok("show: signs use spotlight B's own highlight group", groups[hb.hl])
  map.clear()
  registry.clear()

  -- ---------- nothing to mark ----------
  t.fixture({ "no tokens here" })
  registry.add({ text = "zzz", kind = "literal" })
  local marked3, err3 = map.show(nil)
  t.eq("show: nothing found reports 0", marked3, 0)
  t.contains("show: names the reason", err3 or "", "no matching lines")
  registry.clear()

  -- ---------- config validation ----------
  config.setup({ map = { sign_text = "abc" } }) -- 3 display cells, over the limit
  t.eq("config: over-wide sign_text falls back to the default", config.get("map.sign_text"), "▪")
  config.setup({ map = { max_entries = -1 } })
  t.eq("config: non-positive max_entries falls back to the default", config.get("map.max_entries"), 10000)
  config.setup()

  -- ---------- facade / :Spotlight map ----------
  t.fixture({ "req=ccc" })
  registry.add({ text = "ccc", kind = "literal" })
  t.eq("api/map: reports success", api.map(nil), true)
  t.eq("api/map_clear: always reports true", api.map_clear(), true)

  vim.cmd("Spotlight map")
  t.ok("cmd/map: places marks", mark_count(vim.api.nvim_get_current_buf(), ns) > 0)
  vim.cmd("Spotlight map clear")
  t.eq("cmd/map clear: removes them", mark_count(vim.api.nvim_get_current_buf(), ns), 0)

  registry.clear()
end

return M
