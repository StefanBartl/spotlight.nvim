---@module 'spotlight.map'
---@brief One-shot occurrence density: a sign per matching line.
---@description
--- The roadmap's own resolution for "where in the file does this token
--- cluster": a one-shot scan behind an explicit command, not anything live.
--- The plugin's whole design principle is zero cost per keystroke or text
--- change (see `spotlight.core.match`) — a density map that stayed current
--- would need exactly the invalidation that principle exists to avoid. So
--- `M.show` is a manual, explicit action: it scans once, places signs, and
--- does not react to anything afterwards. Editing the buffer leaves the
--- marks exactly where they were placed until `M.show` is called again.
---
--- Per-buffer, not global — showing the map in a different buffer never
--- touches marks placed in another one, and there is nothing to clean up on
--- `BufWipeout`: Neovim already drops a wiped buffer's extmarks with it. This
--- is also why the feature needs zero new autocmds.

local config = require("spotlight.config")
local count = require("spotlight.core.count")
local registry = require("spotlight.core.registry")

local M = {}

--- Dedicated namespace, created once. Exposed for tests/health rather than
--- kept fully private, so a caller can inspect marks without reaching into
--- this module's internals.
local NS = vim.api.nvim_create_namespace("spotlight_map")

--- The namespace `M.show`/`M.clear` operate in.
---@return integer
function M.namespace()
  return NS
end

--- Clear every mark this module placed in `bufnr`.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return nil
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

--- Scan the current buffer once and place one sign per matching line, in the
--- matching spotlight's own highlight group. Idempotent: clears this
--- buffer's previous marks first, so repeated calls never accumulate.
---
--- With `text`, only that spotlight's matches; otherwise every active
--- spotlight's, each line taking on whichever spotlight's pattern matches it
--- first (see `core.count.M.matching_lines_by_item`).
---@param text string|nil
---@return integer marked, string|nil err, boolean truncated
function M.show(text)
  local items
  if type(text) == "string" and text ~= "" then
    local item = registry.find_by_text(text)
    if not item then
      return 0, ("no spotlight for: %s"):format(text), false
    end
    items = { item }
  else
    items = registry.all()
  end
  if #items == 0 then
    return 0, "no active spotlights", false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  M.clear(bufnr)

  local opts = config.get("map")
  local entries, truncated = count.matching_lines_by_item(bufnr, items, opts.max_entries)
  if #entries == 0 then
    return 0, "no matching lines in this buffer", false
  end

  for _, e in ipairs(entries) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, e.lnum - 1, 0, {
      sign_text = opts.sign_text,
      sign_hl_group = e.item.hl,
    })
  end

  return #entries, nil, truncated
end

return M
