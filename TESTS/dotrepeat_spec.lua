-- TESTS/dotrepeat_spec.lua
-- `.` after the normal-mode toggle keymap: `lib.dot_repeatable` wraps
-- `api.toggle` via `lib.nvim.dotrepeat`, so `.` re-resolves the cursor token
-- fresh rather than repeating the original toggle. This is also the direct
-- answer to the "is repeating a toggle coherent" question.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local api = require("spotlight")
  local lib = require("spotlight.util.lib")

  config.setup()
  registry.clear()

  t.fixture({ "aaa bbb", "aaa bbb" })

  -- ---------- dot_repeatable always returns a callable ----------
  local wrapped = lib.dot_repeatable(api.toggle)
  t.eq("dot_repeatable: returns a function", type(wrapped), "function")

  -- ---------- first firing: toggles the cursor token, arms '.' ----------
  t.ok("cursor placed on the first aaa", t.cursor_on(1, "aaa"))
  wrapped()
  t.eq("dot: first firing toggles the token under the cursor", registry.count(), 1)
  t.eq("dot: it was 'aaa' that got toggled", registry.all()[1].text, "aaa")

  -- ---------- '.' re-resolves fresh, not a captured closure ----------
  t.ok("cursor moved onto bbb", t.cursor_on(1, "bbb"))
  vim.cmd("normal! .")
  t.eq("dot: '.' toggles the NEW cursor token (bbb), not the original (aaa)", registry.count(), 2)

  local texts = {}
  for _, item in ipairs(registry.all()) do
    texts[item.text] = true
  end
  t.ok("dot: aaa is still active", texts["aaa"])
  t.ok("dot: bbb was added by '.'", texts["bbb"])

  -- ---------- '.' again on the same spot removes it: coherent, not broken ----------
  vim.cmd("normal! .")
  t.eq("dot: a second '.' on the same token removes it, same as a second keypress would", registry.count(), 1)
  t.eq("dot: the survivor is aaa", registry.all()[1].text, "aaa")

  registry.clear()

  -- ---------- dot_run: the :Spotlight command path ----------
  t.ok("cursor on the second-line aaa", t.cursor_on(2, "aaa"))
  lib.dot_run(api.toggle)
  t.eq("dot_run: fires the action once", registry.count(), 1)

  registry.clear()
end

return M
