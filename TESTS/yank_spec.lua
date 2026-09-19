-- TESTS/yank_spec.lua
-- `:Spotlight yank` / `yank.yank` / `api.yank`: matching lines into the
-- unnamed register, reusing `core.count.matching_lines_for` exactly like the
-- quickfix filter does — including its buffer-scoped ("this occurrence
-- only") item handling (PRIN-20; see the pinned-item case below).

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local yank = require("spotlight.yank")
  local api = require("spotlight")

  config.setup()
  -- The `:Spotlight` verb, for the command-route assertions below. Registered
  -- here when it is not already, so this spec does not depend on another one
  -- having called `setup()` first.
  if vim.fn.exists(":Spotlight") ~= 2 then
    require("spotlight.bindings.usrcmds").setup()
  end
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

  -- ---------- a buffer-scoped ("this occurrence only") item is not dropped ----------
  --
  -- Its pattern carries `\%l\%c` position atoms that `vim.regex` never
  -- evaluates (see `core/count.lua`'s `pinned_to`), so a pattern-only scan
  -- would report "no matching lines" even though `:Spotlight qf` finds it and
  -- the highlight is visibly on screen (PRIN-20).
  local pin_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(pin_buf, 0, -1, false, { "only this one, please" })
  vim.api.nvim_set_current_buf(pin_buf)
  local pin = registry.add_at({ text = "this one", kind = "literal" }, { buf = pin_buf, row1 = 1, col1 = 6 })

  local pin_found, pin_err, pin_truncated = yank.yank(pin)
  t.eq("yank/pinned: the pinned occurrence is found, not reported as 0", pin_found, 1)
  t.eq("yank/pinned: no error", pin_err, nil)
  t.ok("yank/pinned: not truncated", not pin_truncated)
  t.eq("yank/pinned: the pinned line lands in the register", vim.fn.getreg('"'), "only this one, please\n")

  registry.clear()
  vim.cmd("bwipeout! " .. pin_buf)
end

return M
