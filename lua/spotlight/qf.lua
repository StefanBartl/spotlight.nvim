---@module 'spotlight.qf'
---@brief Quickfix filter: every line matching a spotlight, and nothing else.
---@description
--- Answers the question that follows immediately after "highlight this request
--- id": *now show me only the lines it appears in*. That is a fold of the log
--- down to the relevant slice, which is what the quickfix list is for — and
--- unlike the highlighting, it is inherently a whole-buffer operation, so it is
--- an explicit command rather than something that happens continuously.
---
--- The spotlight highlights still render inside the quickfix window itself
--- (`spotlight.core.match` treats it as an ordinary window), so the token stands
--- out in the filtered view too.

local config = require("spotlight.config")
local count = require("spotlight.core.count")
local registry = require("spotlight.core.registry")

local M = {}

--- Send matching lines to the quickfix list.
---
--- With `item` given, only that spotlight's matches are collected; otherwise
--- every active spotlight's are.
---@param item Spotlight.Item|nil
---@return integer found, string|nil err
function M.fill(item)
  local items = item and { item } or registry.all()
  if #items == 0 then
    return 0, "no active spotlights"
  end

  local pats = {}
  for i, it in ipairs(items) do
    pats[i] = it.pattern
  end

  local bufnr = vim.api.nvim_get_current_buf()
  -- Filtering the quickfix list into itself is never what was meant, and it is
  -- easy to trigger: `quickfix.open` puts the cursor in that window, so the
  -- next invocation would take it as the source. Refuse instead of producing a
  -- confusing second-generation list.
  if vim.bo[bufnr].buftype == "quickfix" then
    return 0, "run this from the buffer you want to filter, not from the quickfix window"
  end

  local entries = count.matching_lines(bufnr, pats)
  local opts = config.get("quickfix")

  local title = item and ("%s: %s"):format(opts.title, item.text) or opts.title
  vim.fn.setqflist({}, " ", { title = title, items = entries })

  if #entries == 0 then
    return 0, "no matching lines in this buffer"
  end
  if opts.open then
    local from = vim.api.nvim_get_current_win()
    vim.cmd("copen")
    -- Hand focus back to where the filter was run from: the list is there to be
    -- read alongside the log, and leaving the cursor in it would also make the
    -- next `:Spotlight qf` hit the guard above.
    if vim.api.nvim_win_is_valid(from) then
      pcall(vim.api.nvim_set_current_win, from)
    end
  end
  return #entries, nil
end

return M
