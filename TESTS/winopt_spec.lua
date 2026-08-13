-- TESTS/winopt_spec.lua
-- Per-window opt-out: window-sticky, strips existing matches immediately
-- (not just gates future fills), survives a buffer switch in the same
-- window, and leaves other windows untouched.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local winopt = require("spotlight.winopt")
  local api = require("spotlight")

  config.setup()
  registry.clear()

  t.fixture({ "req=aaa", "req=aaa" })
  local winMain = vim.api.nvim_get_current_win()
  registry.add({ text = "aaa", kind = "literal" })

  t.ok("baseline: the window carries the match before opting out", #vim.fn.getmatches(winMain) > 0)
  t.ok("is_disabled: false by default", not winopt.is_disabled(winMain))

  -- ---------- set_disabled(true): strips existing matches immediately ----------
  winopt.set_disabled(true, winMain)
  t.ok("set_disabled(true): is_disabled now true", winopt.is_disabled(winMain))
  t.eq("set_disabled(true): matches stripped immediately, not just gated for later", #vim.fn.getmatches(winMain), 0)

  -- ---------- set_disabled(false): re-fills ----------
  winopt.set_disabled(false, winMain)
  t.ok("set_disabled(false): is_disabled now false", not winopt.is_disabled(winMain))
  t.ok("set_disabled(false): matches re-applied", #vim.fn.getmatches(winMain) > 0)

  -- ---------- survives a buffer switch in the same window ----------
  winopt.set_disabled(true, winMain)
  t.fixture({ "req=aaa somewhere else" }) -- replaces the current buffer's content in winMain
  registry.apply_to_window(winMain) -- mirrors what BufWinEnter's autocmd does
  t.eq(
    "survives buffer switch: still zero matches after :edit-ing a new buffer in the same window",
    #vim.fn.getmatches(winMain),
    0
  )
  t.ok("survives buffer switch: is_disabled is still true", winopt.is_disabled(winMain))
  winopt.set_disabled(false, winMain)

  -- ---------- a second window is unaffected ----------
  registry.clear()
  t.fixture({ "req=bbb" })
  registry.add({ text = "bbb", kind = "literal" })
  local winA = vim.api.nvim_get_current_win()
  vim.cmd("split")
  local winB = vim.api.nvim_get_current_win()
  t.neq("two distinct windows", winA, winB)

  winopt.set_disabled(true, winB)
  t.ok("second window: winA still carries the match", #vim.fn.getmatches(winA) > 0)
  t.eq("second window: winB does not", #vim.fn.getmatches(winB), 0)
  winopt.set_disabled(false, winB)
  vim.cmd("close")

  -- ---------- toggle ----------
  local now = winopt.toggle(winA)
  t.ok("toggle: flips to disabled", now)
  t.ok("toggle: is_disabled reflects it", winopt.is_disabled(winA))
  local now2 = winopt.toggle(winA)
  t.ok("toggle: flips back", not now2)
  winopt.set_disabled(false, winA)

  registry.clear()

  -- ---------- facade: boolean no-change convention ----------
  t.eq("api/winopt_set: setting to the current value (false) reports no change", api.winopt_set(false, winMain), false)
  t.eq("api/winopt_set: setting to true reports a change", api.winopt_set(true, winMain), true)
  t.eq("api/winopt_set: setting to true again reports no change", api.winopt_set(true, winMain), false)
  t.eq("api/winopt_toggle: always reports true (it always changes something)", api.winopt_toggle(winMain), true)
  api.winopt_set(false, winMain)

  -- ---------- :Spotlight winopt integration ----------
  vim.cmd("Spotlight winopt off")
  t.ok("cmd/winopt off: current window disabled", winopt.is_disabled(vim.api.nvim_get_current_win()))
  vim.cmd("Spotlight winopt on")
  t.ok("cmd/winopt on: current window re-enabled", not winopt.is_disabled(vim.api.nvim_get_current_win()))
  vim.cmd("Spotlight winopt toggle")
  t.ok("cmd/winopt toggle: flips it", winopt.is_disabled(vim.api.nvim_get_current_win()))
  vim.cmd("Spotlight winopt toggle")
  t.ok("cmd/winopt toggle: flips it back", not winopt.is_disabled(vim.api.nvim_get_current_win()))
  vim.cmd("Spotlight winopt status")

  registry.clear()
end

return M
