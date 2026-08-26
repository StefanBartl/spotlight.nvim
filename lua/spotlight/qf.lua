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
--- every active spotlight's are. Reports status only — whether the result was
--- truncated at `quickfix.max_entries` is returned for the caller to notify,
--- not announced here: low-level modules validate and return, the facade is
--- where user-facing messages are decided (see spotlight's boundary-error
--- convention, matched by `spotlight.nav`/`spotlight.persist`).
---@param item Spotlight.Item|nil
---@return integer found, string|nil err, boolean truncated
function M.fill(item)
  local items = item and { item } or registry.all()
  if #items == 0 then
    return 0, "no active spotlights", false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  -- Filtering the quickfix list into itself is never what was meant, and it is
  -- easy to trigger: `quickfix.open` puts the cursor in that window, so the
  -- next invocation would take it as the source. Refuse instead of producing a
  -- confusing second-generation list.
  if vim.bo[bufnr].buftype == "quickfix" then
    return 0, "run this from the buffer you want to filter, not from the quickfix window", false
  end

  local opts = config.get("quickfix")
  local entries, truncated = count.matching_lines_for(bufnr, items, opts.max_entries)

  local title = item and ("%s: %s"):format(opts.title, item.text) or opts.title
  if truncated then
    title = ("%s (first %d)"):format(title, opts.max_entries)
  end
  vim.fn.setqflist({}, " ", { title = title, items = entries })

  if #entries == 0 then
    return 0, "no matching lines in this buffer", false
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
  return #entries, nil, truncated
end

--- `M.fill`'s multi-buffer counterpart: every line matching in every loaded,
--- ordinary file buffer (`core.count.scannable_buffers`), merged into one
--- quickfix list.
---
--- The cap is global, not per-buffer: each buffer is scanned with whatever
--- budget remains (`opts.max_entries` minus what earlier buffers already
--- contributed), and the buffer loop stops outright — not just the append —
--- the moment one buffer's scan reports truncation, mirroring
--- `count.matching_lines`'s own "stop scanning, not just appending" rule one
--- level up.
---@param item Spotlight.Item|nil
---@return integer found, string|nil err, boolean truncated
function M.fill_all(item)
  local items = item and { item } or registry.all()
  if #items == 0 then
    return 0, "no active spotlights", false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  -- Same rationale as `M.fill`: don't start a scan from inside the very list
  -- it would be filtering into.
  if vim.bo[bufnr].buftype == "quickfix" then
    return 0, "run this from the buffer you want to filter, not from the quickfix window", false
  end

  local opts = config.get("quickfix")
  local entries, truncated = {}, false
  for _, buf in ipairs(count.scannable_buffers()) do
    local remaining = opts.max_entries - #entries
    if remaining <= 0 then
      truncated = true
      break
    end
    -- The full `items` list every time: `matching_lines_for` keeps only the
    -- buffer-scoped ones pinned to `buf`, so a spotlight pinned elsewhere is
    -- simply skipped for this buffer rather than wrongly reported in it.
    local buf_entries, buf_truncated = count.matching_lines_for(buf, items, remaining)
    for _, e in ipairs(buf_entries) do
      entries[#entries + 1] = e
    end
    if buf_truncated then
      truncated = true
      break
    end
  end

  local title = item and ("%s: %s (all loaded buffers)"):format(opts.title, item.text)
    or ("%s (all loaded buffers)"):format(opts.title)
  if truncated then
    title = ("%s (first %d)"):format(title, opts.max_entries)
  end
  vim.fn.setqflist({}, " ", { title = title, items = entries })

  if #entries == 0 then
    return 0, "no matching lines in any loaded buffer", false
  end
  if opts.open then
    local from = vim.api.nvim_get_current_win()
    vim.cmd("copen")
    if vim.api.nvim_win_is_valid(from) then
      pcall(vim.api.nvim_set_current_win, from)
    end
  end
  return #entries, nil, truncated
end

return M
