---@module 'spotlight.ui.list'
---@brief The spotlight list: color swatch, pattern, match count → jump / remove.
---@description
--- Built on `lib.nvim.ui.kit.select`'s **rich items** (`item.lines` with
--- per-span highlight groups), which is exactly the primitive this list needs: a
--- row whose first columns are painted in the spotlight's own `SpotlightN` group
--- and whose remainder is plain text. Without it the swatch would need a
--- hand-rolled float with its own extmark painting; with it there is no
--- rendering code here at all.
---
--- `respect_override` is deliberately **not** set. It exists so a picker-backed
--- call site honours the user's `vim.ui.select` replacement (telescope-ui-select,
--- fzf-lua, dressing) — but a foreign picker only understands plain strings, so
--- delegating would silently drop the per-row colors that are the entire point
--- of this list. This is an internal tool, not a general-purpose picker, so it
--- keeps kit's own chooser.
---
--- Counts are computed here, once, at open time — never maintained live. See
--- `spotlight.core.count` for why.

local config = require("spotlight.config")
local count = require("spotlight.core.count")
local lib = require("spotlight.util.lib")
local nav = require("spotlight.nav")
local registry = require("spotlight.core.registry")

local M = {}

--- Render one spotlight as a rich chooser item.
---@param item Spotlight.Item
---@param n integer|nil # Match count, or nil for "not counted".
---@param swatch string
---@return table
local function row(item, n, swatch)
  local shown = n and tostring(n) or "?"
  local line = ("%s %-40s %s"):format(swatch, item.text, shown)
  return {
    value = item,
    lines = { line },
    highlights = {
      -- Only the swatch is colored; coloring the pattern text too would make a
      -- light-background slot's own foreground fight the chooser's selection
      -- highlight on the active row.
      { line = 0, col_start = 0, col_end = #swatch, hl_group = item.hl },
    },
  }
end

--- Open the list. Selecting an entry jumps to its first occurrence; `<Tab>` is
--- not used for removal because kit's chooser reserves it for multi-select —
--- instead the list is re-opened in "remove" mode via `:Spotlight list remove`
--- (and by `mode = "remove"` here).
---@param mode "jump"|"remove"|nil # Defaults to "jump".
---@return nil
function M.open(mode)
  mode = mode == "remove" and "remove" or "jump"

  local items = registry.all()
  if #items == 0 then
    lib.notify("no active spotlights", vim.log.levels.INFO)
    return
  end

  local list_opts = config.get("list")
  local bufnr = vim.api.nvim_get_current_buf()
  local entries = {}
  local counted = true
  for i, item in ipairs(items) do
    local n = nil
    if list_opts.count then
      n = count.count(bufnr, item, list_opts.count_max_lines)
      if n == nil then
        counted = false
      end
    end
    entries[i] = row(item, n, list_opts.swatch)
  end

  local title = mode == "remove" and "Spotlights — select to remove" or "Spotlights — select to jump"
  if list_opts.count and not counted then
    title = title .. " (buffer above list.count_max_lines: counts shown as ?)"
  end

  local select = lib.try_require("lib.nvim.ui.kit.select")
  if not select or type(select.open) ~= "function" then
    lib.notify("lib.nvim.ui.kit.select unavailable — cannot open the list", vim.log.levels.ERROR)
    return
  end

  select.open({
    title = title,
    items = entries,
    on_select = function(entry)
      -- Rich items pass through the chooser unrendered, so the callback hands
      -- back the item table itself; the spotlight rides along in `.value`.
      local item = type(entry) == "table" and entry.value or nil
      if type(item) ~= "table" then
        return
      end
      if mode == "remove" then
        local removed = registry.remove(item.id)
        if removed and config.get("notify") then
          lib.notify(("removed spotlight: %s"):format(removed.text))
        end
        return
      end
      if not nav.goto_first(item) then
        lib.notify(("no occurrence of %s in this buffer"):format(item.text), vim.log.levels.WARN)
      end
    end,
  })
end

return M
