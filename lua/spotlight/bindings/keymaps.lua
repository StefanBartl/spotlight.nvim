---@module 'spotlight.bindings.keymaps'
---@brief The preset keymaps.
---@description
--- Every key is an individually overridable config value, and setting any of
--- them to `false` drops just that mapping — so a user can keep the preset and
--- still free one `lhs`, without having to opt out of the whole set and rebuild
--- it by hand. Setting `keymaps.preset = false` binds nothing at all; every
--- action is still reachable via `:Spotlight` and as a plain function on the
--- `spotlight` module.
---
--- Maps bind directly onto the facade actions — no `<Plug>` indirection.
--- which-key (when installed) labels the `<leader>m` prefix; the per-key labels
--- come from each mapping's own `desc`.

local lib = require("spotlight.util.lib")

local M = {}

---@internal
--- Bind `lhs` unless it was disabled with `false`.
---@param lhs string|false|nil
---@param mode string|string[]
---@param rhs function
---@param desc string
---@return nil
local function bind(lhs, mode, rhs, desc)
  if type(lhs) ~= "string" or lhs == "" then
    return
  end
  lib.map(mode, lhs, rhs, { silent = true, desc = desc })
end

--- Bind the preset keys.
---@param cfg Spotlight.Config
---@return nil
function M.setup(cfg)
  local api = require("spotlight")
  local k = cfg.keymaps

  -- One `lhs` per action for both modes: normal mode spotlights the resolved
  -- token, visual mode the exact selection. Same intent, so the same key.
  --
  -- `toggle_here` (lowercase k) marks only the one occurrence the cursor/
  -- selection is on; `toggle` (uppercase K) marks every occurrence of that
  -- text in the buffer. The lowercase key is the one reached for by default —
  -- it is also the narrower, more reversible action — with the wider one a
  -- deliberate shift to the shifted key.
  bind(k.toggle_here, "n", api.toggle_here, "spotlight: toggle this occurrence only")
  bind(k.toggle_here, "x", api.toggle_here_selection, "spotlight: toggle this selection only")

  bind(k.toggle, "n", api.toggle, "spotlight: toggle every occurrence of the token under cursor")
  bind(k.toggle, "x", api.toggle_selection, "spotlight: toggle every occurrence of the selection")

  bind(k.list, "n", api.list, "spotlight: open the spotlight list")
  bind(k.clear, "n", api.clear, "spotlight: clear all spotlights")
  bind(k.quickfix, "n", function()
    api.quickfix(nil)
  end, "spotlight: matching lines to quickfix")

  bind(k.next, "n", api.next, "spotlight: next occurrence (×count)")
  bind(k.prev, "n", api.prev, "spotlight: previous occurrence (×count)")
end

return M
