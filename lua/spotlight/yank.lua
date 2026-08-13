---@module 'spotlight.yank'
---@brief Yank every matching line to the unnamed register.
---@description
--- The quickfix filter's sibling for "I just want the text, not a navigable
--- list" — reuses `core.count.matching_lines` verbatim, so the scanning cost
--- and the "each line reported once, even if several spotlights hit it"
--- guarantee are identical to `:Spotlight qf`. The only difference is the
--- destination.
---
--- Deliberately narrow for now: always the unnamed register (`"`), always raw
--- line text with no line-number prefix. A register argument or a
--- line-numbered variant can follow later once there is a real second use
--- case to design against, rather than guessing at one now.

local config = require("spotlight.config")
local count = require("spotlight.core.count")
local registry = require("spotlight.core.registry")

local M = {}

--- Yank matching lines into the unnamed register, one per line, in buffer
--- order. With `item` given, only that spotlight's matches; otherwise every
--- active spotlight's.
---@param item Spotlight.Item|nil
---@return integer found, string|nil err, boolean truncated
function M.yank(item)
  local items = item and { item } or registry.all()
  if #items == 0 then
    return 0, "no active spotlights", false
  end

  local pats = {}
  for i, it in ipairs(items) do
    pats[i] = it.pattern
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local opts = config.get("quickfix")
  local entries, truncated = count.matching_lines(bufnr, pats, opts.max_entries)

  if #entries == 0 then
    return 0, "no matching lines in this buffer", false
  end

  local lines = {}
  for i, e in ipairs(entries) do
    lines[i] = e.text
  end
  vim.fn.setreg('"', table.concat(lines, "\n") .. "\n", "l")

  return #entries, nil, truncated
end

return M
