-- TESTS/qf_buffer_scope_spec.lua
-- Buffer-scoped ("this occurrence only") items in `core/count.lua` and
-- `qf.lua`: their pattern's `\%l\%c` position atoms only mean anything to
-- Vim's own search/render machinery, never to `vim.regex:match_str` — the API
-- `M.count` and `M.matching_lines` are built on. Left unhandled, a
-- buffer-scoped item always counts as 0 and `qf.fill` on one always reports
-- "no matching lines", even though the spotlight is visibly rendered on
-- screen. This spec pins the fix: buffer-scoped items are resolved from their
-- known position instead of scanned for.

local t = require("harness")

local M = {}

---@internal
--- An ordinary, non-scratch buffer — matches what `count.scannable_buffers`
--- (and so `qf.fill_all`) looks for; see list_count_scope_spec.lua.
---@param lines string[]
---@return integer bufnr
local function real_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

function M.run()
  local config = require("spotlight.config")
  local count = require("spotlight.core.count")
  local qf = require("spotlight.qf")
  local registry = require("spotlight.core.registry")

  config.setup()
  registry.clear()

  -- ---------- count.count: single known point, no scan ----------
  local bufA = real_buffer({ "hello foo world", "other line" })
  local bufB = real_buffer({ "another buffer" })
  vim.api.nvim_set_current_buf(bufA)

  local item = registry.add_at({ text = "foo", kind = "literal" }, { buf = bufA, row1 = 1, col1 = 7 })
  t.eq("add_at: pattern is position-anchored", item.pattern, "\\C\\%1l\\%7c\\Vfoo")

  t.eq("count.count: 1 in the buffer it is pinned to", count.count(bufA, item, 200000), 1)
  t.eq("count.count: 0 in a different buffer", count.count(bufB, item, 200000), 0)

  local total, exact, scanned = count.count_loaded(item, 200000)
  t.eq("count_loaded: sums to 1 across every scannable buffer", total, 1)
  t.ok("count_loaded: exact (nothing skipped)", exact)
  t.ok("count_loaded: scanned at least the pinned buffer", scanned >= 1)

  -- ---------- qf.fill: exactly one line, from the buffer it is pinned to ----------
  local found, err, truncated = qf.fill(item)
  t.eq("qf.fill: finds exactly one line", found, 1)
  t.eq("qf.fill: no error", err, nil)
  t.ok("qf.fill: not truncated", not truncated)

  local qflist = vim.fn.getqflist()
  t.eq("qf.fill: one entry in the quickfix list", #qflist, 1)
  t.eq("qf.fill: entry is on the pinned line", qflist[1].lnum, 1)
  t.eq("qf.fill: entry is at the pinned column", qflist[1].col, 7)
  t.eq("qf.fill: entry belongs to the pinned buffer", qflist[1].bufnr, bufA)

  -- Run from a buffer the item is *not* pinned to: nothing to find there,
  -- same as before this fix — a buffer-scoped item can only ever match in its
  -- own buffer.
  vim.api.nvim_set_current_buf(bufB)
  local found_wrong, err_wrong = qf.fill(item)
  t.eq("qf.fill: nothing found from an unrelated buffer", found_wrong, 0)
  t.contains("qf.fill: names the reason", err_wrong or "", "no matching lines")
  vim.api.nvim_set_current_buf(bufA)

  -- ---------- merges cleanly with regex-matched (global) items ----------
  registry.clear()
  local bufC = real_buffer({ "alpha token beta", "unrelated line here", "alpha token gamma" })
  vim.api.nvim_set_current_buf(bufC)

  registry.add({ text = "alpha", kind = "word" })
  registry.add_at({ text = "unrelated", kind = "literal" }, { buf = bufC, row1 = 2, col1 = 1 })

  local found_all = qf.fill(nil)
  t.eq("qf.fill(nil): global (2 lines) + pinned (1 line), no double-count", found_all, 3)
  local lines_seen = {}
  for _, e in ipairs(vim.fn.getqflist()) do
    lines_seen[e.lnum] = true
  end
  t.ok("qf.fill(nil): includes both 'alpha' lines and the pinned line", lines_seen[1] and lines_seen[2] and lines_seen[3])

  -- A buffer-scoped item whose pinned line a global item *also* matches must
  -- not produce a second entry for that line — "one entry per matching line"
  -- applies across scopes, not only within `M.matching_lines`' own regex pass.
  registry.clear()
  local bufD = real_buffer({ "hello foo world" })
  vim.api.nvim_set_current_buf(bufD)
  registry.add({ text = "foo", kind = "literal" })
  registry.add_at({ text = "foo", kind = "literal" }, { buf = bufD, row1 = 1, col1 = 7 })
  local found_dup = qf.fill(nil)
  t.eq("qf.fill(nil): a line matched by both scopes is reported once", found_dup, 1)

  -- ---------- max_entries cap applies to pinned entries too ----------
  registry.clear()
  local bufE = real_buffer({ "line one", "line two" })
  local one = registry.add_at({ text = "line", kind = "literal" }, { buf = bufE, row1 = 1, col1 = 1 })
  local two = registry.add_at({ text = "line", kind = "literal" }, { buf = bufE, row1 = 2, col1 = 1 })
  local capped, cap_truncated = count.matching_lines_for(bufE, { one, two }, 1)
  t.eq("matching_lines_for: cap honoured across pinned entries", #capped, 1)
  t.ok("matching_lines_for: truncation reported", cap_truncated)

  -- ---------- qf.fill_all: pinned items only surface in their own buffer ----------
  registry.clear()
  local bufF = real_buffer({ "hello foo world" })
  local bufG = real_buffer({ "foo appears here too" })
  vim.api.nvim_set_current_buf(bufF)
  local pinned_f = registry.add_at({ text = "foo", kind = "literal" }, { buf = bufF, row1 = 1, col1 = 7 })

  local found_fa, err_fa, truncated_fa = qf.fill_all(pinned_f)
  t.eq("qf.fill_all: finds only the one pinned occurrence, not bufG's 'foo'", found_fa, 1)
  t.eq("qf.fill_all: no error", err_fa, nil)
  t.ok("qf.fill_all: not truncated", not truncated_fa)
  local qflist_fa = vim.fn.getqflist()
  t.eq("qf.fill_all: the single entry is in the pinned buffer", qflist_fa[1] and qflist_fa[1].bufnr, bufF)

  -- ---------- map's own scan shares the defect, so it shares the fix ----------
  -- `matching_lines_by_item` was added after this bug was first found, and
  -- reached for `vim.regex` the same way: without the pinned branch the sign
  -- column silently has no entry for a "this occurrence only" spotlight.
  registry.clear()
  local bufH = real_buffer({ "alpha token beta", "pinned line here", "alpha token gamma" })
  vim.api.nvim_set_current_buf(bufH)
  local global_h = registry.add({ text = "alpha", kind = "word" })
  local pinned_h = registry.add_at({ text = "pinned", kind = "literal" }, { buf = bufH, row1 = 2, col1 = 1 })

  local by_item, by_item_truncated = count.matching_lines_by_item(bufH, { global_h, pinned_h }, 100)
  t.ok("matching_lines_by_item: not truncated", not by_item_truncated)
  t.eq("matching_lines_by_item: two global lines plus the pinned one", #by_item, 3)
  local by_lnum = {}
  for _, e in ipairs(by_item) do
    by_lnum[e.lnum] = e.item
  end
  t.eq("matching_lines_by_item: the pinned line is attributed to the pinned item", by_lnum[2], pinned_h)
  t.eq("matching_lines_by_item: a global line stays with its own item", by_lnum[1], global_h)
  t.ok(
    "matching_lines_by_item: entries are in buffer order",
    by_item[1].lnum < by_item[2].lnum and by_item[2].lnum < by_item[3].lnum
  )

  -- Pinned elsewhere: invisible here, exactly as in the quickfix path.
  local bufI = real_buffer({ "alpha token beta" })
  local elsewhere, _ = count.matching_lines_by_item(bufI, { pinned_h }, 100)
  t.eq("matching_lines_by_item: a spotlight pinned to another buffer yields nothing", #elsewhere, 0)

  registry.clear()
  vim.api.nvim_set_current_buf(bufA)
  for _, b in ipairs({ bufA, bufB, bufC, bufD, bufE, bufF, bufG, bufH, bufI }) do
    if vim.api.nvim_buf_is_valid(b) then
      vim.cmd("bwipeout! " .. b)
    end
  end
end

return M
