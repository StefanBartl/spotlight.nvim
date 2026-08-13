-- TESTS/yank_spec.lua
-- `:Spotlight yank` / `yank.yank` / `api.yank`: matching lines into the
-- unnamed register, reusing `core.count.matching_lines` exactly like the
-- quickfix filter does.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local yank = require("spotlight.yank")
  local api = require("spotlight")

  config.setup()
  registry.clear()

  t.fixture({ "req=aaa one", "other", "req=aaa two", "req=bbb three" })

  local item = registry.add({ text = "aaa", kind = "literal" })

  -- ---------- register content + linewise type ----------
  local found, err, truncated = yank.yank(item)
  t.eq("yank: found the two matching lines", found, 2)
  t.eq("yank: no error", err, nil)
  t.ok("yank: not truncated", not truncated)
  t.eq("yank: register content, one line per match, no line numbers", vim.fn.getreg('"'), "req=aaa one\nreq=aaa two\n")
  t.eq("yank: register is linewise", vim.fn.getregtype('"'), "V")

  -- ---------- union across all spotlights when no item given ----------
  registry.add({ text = "bbb", kind = "literal" })
  local found2 = yank.yank(nil)
  t.eq("yank: nil item unions every active spotlight's matches", found2, 3)

  -- ---------- truncation ----------
  config.setup({ quickfix = { max_entries = 1 } })
  local found3, _, truncated3 = yank.yank(nil)
  t.eq("yank: capped at max_entries", found3, 1)
  t.ok("yank: truncated flag set", truncated3)
  config.setup()

  -- ---------- nothing to find ----------
  registry.clear()
  local found4, err4 = yank.yank(nil)
  t.eq("yank: nothing active reports 0", found4, 0)
  t.contains("yank: names the reason", err4 or "", "no active spotlights")

  registry.add({ text = "zzz-not-present", kind = "literal" })
  local found5, err5 = yank.yank(nil)
  t.eq("yank: an active spotlight with no matches reports 0", found5, 0)
  t.contains("yank: names the reason", err5 or "", "no matching lines")

  -- ---------- facade boolean-return convention ----------
  registry.clear()
  t.eq("api/yank: nothing to find is reported as no change", api.yank(nil), false)
  registry.add({ text = "aaa", kind = "literal" })
  t.eq("api/yank: found something", api.yank(nil), true)
  t.eq("api/yank: unknown text is refused", api.yank("does-not-exist"), false)

  -- ---------- :Spotlight yank integration ----------
  vim.fn.setreg('"', "")
  vim.cmd("Spotlight yank aaa")
  t.contains("cmd/yank: fills the unnamed register", vim.fn.getreg('"'), "req=aaa")

  registry.clear()
end

return M
