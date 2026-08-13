-- TESTS/qf_all_spec.lua
-- `qf.fill_all` / `api.quickfix_all` / `:Spotlight qf all`: quickfix filter
-- across every loaded buffer, with a global (not per-buffer) entry cap.

local t = require("harness")

local M = {}

---@internal
--- An ordinary, non-scratch buffer — see list_count_scope_spec.lua for why
--- `t.fixture()`'s scratch buffers (buftype "nofile") won't do here.
---@param lines string[]
---@return integer bufnr
local function real_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

function M.run()
  local config = require("spotlight.config")
  local qf = require("spotlight.qf")
  local registry = require("spotlight.core.registry")
  local api = require("spotlight")

  config.setup()
  registry.clear()

  local bufA = real_buffer({ "req=aaa one", "other", "req=aaa two" })
  local bufB = real_buffer({ "req=aaa three" })
  vim.api.nvim_set_current_buf(bufA)

  local item = registry.add({ text = "aaa", kind = "literal" })

  -- ---------- entries span multiple buffers ----------
  local found, err, truncated = qf.fill_all(item)
  t.eq("fill_all: found across both buffers", found, 3)
  t.eq("fill_all: no error", err, nil)
  t.ok("fill_all: not truncated", not truncated)

  local qflist = vim.fn.getqflist()
  local bufs_seen = {}
  for _, e in ipairs(qflist) do
    bufs_seen[e.bufnr] = true
  end
  t.ok("fill_all: entries include bufA", bufs_seen[bufA] == true)
  t.ok("fill_all: entries include bufB", bufs_seen[bufB] == true)

  -- ---------- global cap stops the buffer loop, not just the append ----------
  config.setup({ quickfix = { max_entries = 1 } })
  local found2, _, truncated2 = qf.fill_all(item)
  t.eq("fill_all: capped at the global max_entries", found2, 1)
  t.ok("fill_all: truncated flag set", truncated2)
  config.setup()

  -- ---------- refuses to run from the quickfix window ----------
  vim.api.nvim_set_current_buf(bufA)
  qf.fill_all(item)
  vim.cmd("copen")
  local ok_run, refused_err = qf.fill_all(item)
  t.eq("fill_all: still refuses from inside the quickfix window", ok_run, 0)
  t.contains("fill_all: names the reason", refused_err or "", "quickfix window")
  vim.cmd("cclose")
  vim.api.nvim_set_current_buf(bufA)

  -- ---------- facade boolean-return convention ----------
  registry.clear()
  t.eq("api/quickfix_all: nothing to find is reported as no change", api.quickfix_all(nil), false)
  registry.add({ text = "aaa", kind = "literal" })
  t.eq("api/quickfix_all: found something", api.quickfix_all(nil), true)

  -- ---------- :Spotlight qf all integration ----------
  registry.clear()
  registry.add({ text = "aaa", kind = "literal" })
  vim.fn.setqflist({}, "r", { items = {} })
  vim.cmd("Spotlight qf all")
  t.ok("cmd/qf all: fills the quickfix list", #vim.fn.getqflist() > 0)

  registry.clear()
  vim.cmd("bwipeout! " .. bufA)
  vim.cmd("bwipeout! " .. bufB)
end

return M
