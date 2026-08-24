---@module 'spotlight.integrations.menu'
---@brief Context-menu entries for nvzone/menu (soft, opt-in integration).
---@description
--- spotlight.nvim does not depend on a menu plugin. It *provides* a list of
--- entries in the shape nvzone/menu expects, built with
--- `lib.nvim.contextmenu`'s helpers, and a host — typically the user's own
--- RightMouse dispatcher — composes them into its own menu, e.g.:
--- >
---   local items = require("spotlight.integrations.menu").items()
---   -- prepend/append `items` to your own menu table, then menu.open(composed)
--- <
--- General/any-buffer, mirroring `spotlight.bindings.keymaps`' normal-mode
--- actions only: nvzone/menu closes the menu and restores the triggering
--- window/buffer before running a callback, so there is no active Visual
--- selection by the time it fires — the `_selection` variants
--- (`toggle_here_selection`, `toggle_selection`) are left out for that
--- reason, same as they have no Ex-command equivalent either. Opt-out via
--- `config.menu.enable`.

local contextmenu = require("lib.nvim.contextmenu")

local M = {}

--- Build the spotlight.nvim menu entries.
--- Returns an empty list when the integration is disabled, so a host can
--- safely `vim.list_extend` it unconditionally.
---@return Lib.ContextMenu.Item[]
function M.items()
  local mcfg = require("spotlight.config").get("menu")
  if mcfg and mcfg.enable == false then return {} end

  local k = require("spotlight.config").get("keymaps") or {}
  local api = require("spotlight")
  local out = {}

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Spotlight this occurrence only", api.toggle_here, k.toggle_here),
    contextmenu.entry(true, "  Spotlight every occurrence", api.toggle, k.toggle),
    contextmenu.entry(true, "  Next occurrence", api.next, k.next),
    contextmenu.entry(true, "  Previous occurrence", api.prev, k.prev)
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Toggle whole-line rendering", function() api.line_toggle(nil) end, k.line),
    contextmenu.entry(true, "  Send matches to quickfix", function() api.quickfix(nil) end, k.quickfix)
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Open spotlight list", api.list, k.list),
    contextmenu.entry(true, "  Clear all spotlights", api.clear, k.clear)
  )

  return out
end

--- Convenience: the spotlight.nvim entries wrapped as a single nested
--- submenu entry, for hosts that prefer a "Spotlight ▸" fly-out instead of
--- inline entries. Returns nil when there is nothing to show.
---@param label? string submenu label (default "  Spotlight")
---@return Lib.ContextMenu.Item|nil
function M.submenu(label)
  return contextmenu.submenu(label or "  Spotlight", M.items())
end

return M
