-- TESTS/list_count_scope_spec.lua
-- `list.count_scope = "loaded"`: `core.count.scannable_buffers` and
-- `core.count.count_loaded`, plus config validation for the new key.

local t = require("harness")

local M = {}

---@internal
--- An ordinary, non-scratch buffer (`buftype == ""`, like a real log file
--- opened with `:edit`) — deliberately not `t.fixture()`, whose scratch
--- buffers report `buftype == "nofile"` and would be excluded by
--- `scannable_buffers`' own filter, the exact thing under test here.
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

  config.setup()

  -- ---------- scannable_buffers ----------
  local bufA = real_buffer({ "req=aaa" })
  local bufB = real_buffer({ "req=aaa" })

  local function includes(buf)
    for _, b in ipairs(count.scannable_buffers()) do
      if b == buf then
        return true
      end
    end
    return false
  end

  t.ok("scannable_buffers: includes an ordinary loaded buffer (A)", includes(bufA))
  t.ok("scannable_buffers: includes an ordinary loaded buffer (B)", includes(bufB))

  -- A scratch buffer (buftype "nofile" — what `nvim_create_buf(false, true)`,
  -- and so `t.fixture()`, always produces) is exactly the kind of buffer this
  -- filter exists to exclude: no stable file identity, same reasoning as
  -- `util/path.lua`'s own buftype guard.
  local scratch = vim.api.nvim_create_buf(false, true)
  t.eq("scratch buffer reports buftype nofile (sanity check)", vim.bo[scratch].buftype, "nofile")
  t.ok("scannable_buffers: excludes a scratch (nofile) buftype", not includes(scratch))

  vim.cmd("bwipeout! " .. bufB)
  t.ok("scannable_buffers: a wiped buffer is excluded", not includes(bufB))

  -- ---------- count_loaded ----------
  local bufC = real_buffer({ "req=xyz", "req=xyz", "other" })
  local bufD = real_buffer({ "req=xyz" })

  local item = { pattern = "\\C\\Vreq=xyz" }
  local total, exact, scanned = count.count_loaded(item, 200000)
  -- bufA contributes 0 (no "req=xyz" there); bufC contributes 2, bufD 1.
  t.eq("count_loaded: sums matches across every scannable buffer", total, 3)
  t.ok("count_loaded: exact when nothing was skipped", exact)
  t.ok("count_loaded: scanned every scannable buffer", scanned >= 3)

  -- A buffer over max_lines is skipped from the sum, not propagated as nil.
  local total2, exact2 = count.count_loaded(item, 0)
  t.eq("count_loaded: every buffer skipped -> total 0", total2, 0)
  t.ok("count_loaded: not exact once at least one buffer was skipped", not exact2)

  vim.cmd("bwipeout! " .. bufA)
  vim.cmd("bwipeout! " .. scratch)
  vim.cmd("bwipeout! " .. bufC)
  vim.cmd("bwipeout! " .. bufD)

  -- ---------- config validation ----------
  config.setup({ list = { count_scope = "bogus" } })
  t.eq("config: invalid count_scope falls back to 'buffer'", config.get("list.count_scope"), "buffer")
  local reported = false
  for _, issue in ipairs(config.issues) do
    if issue:find("count_scope", 1, true) then
      reported = true
    end
  end
  t.ok("config: invalid count_scope is reported as an issue", reported)

  config.setup({ list = { count_scope = "loaded" } })
  t.eq("config: 'loaded' round-trips", config.get("list.count_scope"), "loaded")

  config.setup()
end

return M
