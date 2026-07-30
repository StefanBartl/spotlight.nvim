-- docs/TESTS/nav_spec.lua
-- Navigation and the two whole-buffer operations (counting, quickfix), including
-- the `nav.scope = "auto"` narrowing that makes `]k` follow the token under the
-- cursor rather than hopping between unrelated spotlights.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local nav = require("spotlight.nav")
  local count = require("spotlight.core.count")

  config.setup({ nav = { center = false } })
  require("spotlight.core.palette").apply()
  registry.clear()

  local bufnr = t.fixture({
    "req=aaa ip=10.0.0.1",
    "req=bbb ip=10.0.0.2",
    "req=aaa ip=10.0.0.3",
    "req=ccc ip=10.0.0.4",
  })

  registry.add({ text = "aaa", kind = "literal" })
  registry.add({ text = "10.0.0.4", kind = "literal" })

  -- ---------- scope = "all" ----------
  config.setup({ nav = { scope = "all", center = false } })
  registry.rebuild()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  t.ok("nav/all: first jump moves", nav.next())
  t.eq("nav/all: lands on the aaa on line 1", vim.api.nvim_win_get_cursor(0)[1], 1)
  t.ok("nav/all: second jump moves", nav.next())
  t.eq("nav/all: crosses to the other spotlight's line", vim.api.nvim_win_get_cursor(0)[1], 3)
  t.ok("nav/all: third jump moves", nav.next())
  t.eq("nav/all: reaches the ip on line 4", vim.api.nvim_win_get_cursor(0)[1], 4)
  t.ok("nav/all: wraps around", nav.next())
  t.eq("nav/all: back to line 1", vim.api.nvim_win_get_cursor(0)[1], 1)

  t.ok("nav/all: backward jump moves", nav.prev())
  t.eq("nav/all: backward wraps to line 4", vim.api.nvim_win_get_cursor(0)[1], 4)

  -- ---------- scope = "auto" ----------
  config.setup({ nav = { scope = "auto", center = false } })
  registry.rebuild()
  t.ok("nav/auto: cursor placed inside the aaa match", t.cursor_on(1, "aaa"))
  local here = nav.under_cursor()
  t.eq("nav/auto: the spotlight under the cursor is identified", here and here.text, "aaa")
  t.ok("nav/auto: jump moves", nav.next())
  t.eq("nav/auto: follows aaa only, skipping line 2 and the ip on line 4", vim.api.nvim_win_get_cursor(0)[1], 3)

  -- Off any match, every spotlight is back in scope.
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  t.eq("nav/auto: nothing under the cursor on line 2", nav.under_cursor(), nil)

  -- ---------- no wrap ----------
  config.setup({ nav = { scope = "all", wrap = false, center = false } })
  registry.rebuild()
  vim.api.nvim_win_set_cursor(0, { 4, 20 })
  t.eq("nav: wrap = false stops at the end of the buffer", nav.next(), false)
  config.setup({ nav = { center = false } })
  registry.rebuild()

  -- ---------- counting ----------
  local aaa = registry.find_by_text("aaa")
  t.eq("count: two occurrences of aaa", count.count(bufnr, aaa, 200000), 2)
  t.eq("count: above count_max_lines returns nil, not zero", count.count(bufnr, aaa, 2), nil)

  -- Two matches on one line are both counted (the inner loop, not just the
  -- first match per line).
  local twice = t.fixture({ "aaa and aaa again" })
  t.eq("count: both matches on a single line are counted", count.count(twice, aaa, 200000), 2)

  -- ---------- quickfix ----------
  vim.api.nvim_set_current_buf(bufnr)
  local qf = require("spotlight.qf")
  local found = qf.fill(aaa)
  t.eq("qf: one entry per matching line", found, 2)
  local list = vim.fn.getqflist()
  t.eq("qf: quickfix list filled", #list, 2)
  t.eq("qf: first entry is line 1", list[1].lnum, 1)
  t.eq("qf: second entry is line 3", list[2].lnum, 3)

  -- `quickfix.open` hands focus back to the source window, so a second call
  -- still filters the log rather than the quickfix list it just produced.
  t.eq("qf: focus returned to the source buffer after copen", vim.api.nvim_get_current_buf(), bufnr)
  found = qf.fill(nil)
  t.eq("qf: all spotlights together reach three lines", found, 3)

  -- Run from inside the quickfix window it is refused outright, rather than
  -- filtering the list into itself.
  vim.cmd("copen")
  local refused, refuse_err = qf.fill(nil)
  t.eq("qf: refused from inside the quickfix window", refused, 0)
  t.contains("qf: says why it refused", refuse_err, "not from the quickfix window")
  vim.cmd("cclose")
  vim.api.nvim_set_current_buf(bufnr)

  -- A line hit by two spotlights is still reported once: the question is
  -- "which lines", not "which highlights".
  registry.clear()
  registry.add({ text = "aaa", kind = "literal" })
  registry.add({ text = "10.0.0.1", kind = "literal" })
  vim.api.nvim_set_current_buf(bufnr)
  t.eq("qf: a doubly-matched line appears once", qf.fill(nil), 2)

  registry.clear()
  t.eq("qf: no spotlights reports nothing found", qf.fill(nil), 0)
  vim.fn.setqflist({}, "r")
end

return M
