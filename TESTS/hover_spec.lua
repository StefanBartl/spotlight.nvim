-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil, duplicate-set-field
-- TESTS/hover_spec.lua — the hover.nvim contribution.
--
-- The property that makes this integration acceptable at all is the gate:
-- **it answers only for tokens that are already spotlighted.** Every token in
-- a log is a token, and a preview that counted whatever the cursor touched
-- would fire on every word — exactly the unasked-float noise hover.nvim's
-- opt-in model exists to prevent. A spotlight is a decision the reader
-- already made about *this* token, and it is the only signal available that
-- says "this one matters to me".
--
-- So the spotlighted/not-spotlighted pair below is the case worth breaking
-- the build over. The count itself is `core.count`'s job and has its own
-- specs; what is pinned here is that "we did not look" is not smoothed into
-- a zero.

local t = require("harness")
local hover = require("spotlight.hover")
local api = vim.api

local M = {}

function M.run()
  -- ---------------------------------------------------------- token shape --
  t.eq("hover: token in prose", hover.token_at("req-42abc started", 2), "req-42abc")
  t.eq("hover: token with dots", hover.token_at("see 10.0.0.1 here", 6), "10.0.0.1")
  t.eq("hover: token with a colon", hover.token_at("at file.lua:42 it", 5), "file.lua:42")
  t.eq("hover: on whitespace", hover.token_at("a  b", 1), nil)
  t.eq("hover: empty line", hover.token_at("", 0), nil)
  t.eq("hover: past the end", hover.token_at("abc", 99), nil)

  -- --------------------------------------------------------- registration --
  local captured = {}
  local real_registry = package.loaded["hover.registry"]
  package.loaded["hover.registry"] = {
    register = function(name, contribution)
      captured.name = name
      captured.contribution = contribution
    end,
    position_at = function() end,
  }

  hover._reset()
  t.ok("hover: setup registers", hover.setup())
  t.eq("hover: under this plugin's name", captured.name, "spotlight.nvim")
  t.ok("hover: as a position preview", type(captured.contribution.positions) == "table")

  -- ------------------------------------------------------------- the gate --
  local answer = captured.contribution.positions[1]
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "req-42abc started",
    "req-42abc retried",
    "req-99zzz ignored",
    "req-42abc done",
  })

  require("spotlight.core.registry").clear()
  t.eq("hover: nothing spotlighted, nothing said", answer(buf, 1, 2), nil)

  local sl = require("spotlight")
  local prev_buf = api.nvim_get_current_buf()
  api.nvim_set_current_buf(buf)
  api.nvim_win_set_cursor(0, { 1, 2 })
  sl.add("req-42abc")

  local hit = answer(buf, 1, 2)
  t.ok("hover: a spotlighted token answers", type(hit) == "table")
  t.contains("hover: with its own name in the title", hit.title, "req-42abc")
  t.contains("hover: and the count", table.concat(hit.lines, "\n"), "3 occurrences")

  t.eq("hover: an unspotlighted token on the same buffer stays silent", answer(buf, 3, 2), nil)
  t.eq("hover: an invalid buffer stays silent", answer(-1, 1, 2), nil)

  -- One occurrence must not read as "1 occurrences".
  sl.add("started")
  local single = answer(buf, 1, 12)
  t.ok("hover: a single occurrence answers", type(single) == "table")
  t.contains("hover: in the singular", table.concat(single.lines, "\n"), "1 occurrence in")

  require("spotlight.core.registry").clear()
  pcall(api.nvim_set_current_buf, prev_buf)
  pcall(api.nvim_buf_delete, buf, { force = true })

  -- ---------------------------------------------------------- degradation --
  package.loaded["hover.registry"] = nil
  local real_preload = package.preload["hover.registry"]
  package.preload["hover.registry"] = function()
    error("module 'hover.registry' not found")
  end
  hover._reset()
  t.eq("hover: without hover.nvim, setup declines", hover.setup(), false)
  package.preload["hover.registry"] = real_preload

  package.loaded["hover.registry"] = { register = function() end }
  hover._reset()
  t.eq("hover: an older hover.nvim without positions is declined", hover.setup(), false)

  hover._reset()
  package.loaded["hover.registry"] = real_registry
end

return M
