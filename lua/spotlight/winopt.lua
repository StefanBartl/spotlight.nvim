---@module 'spotlight.winopt'
---@brief Per-window opt-out: "do not spotlight in this window."
---@description
--- The one open question was what happens when the window is later reused for
--- a different buffer. Resolved as window-sticky: the
--- flag lives on the window itself (`vim.w[win].spotlight_disabled`), not on
--- whatever buffer happened to be showing when it was set, so it survives
--- exactly the case the feature is for — "keep a reference split dark no
--- matter what I open in it."
---
--- The gate itself lives in `core.match`'s `eligible()`, not here — every
--- fill path funnels through that one check, including the `BufWinEnter`
--- re-fill that already runs on every buffer switch in a window, which is
--- what makes "survives a buffer switch" free rather than something this
--- module has to wire up itself. This module is only the flag's own
--- get/set/toggle surface, plus stripping already-applied matches
--- immediately when a window opts out (gating alone would only affect
--- future fills, leaving current highlights lit).
---
--- Session-only by construction: a window id means nothing across a
--- restart, so there is nothing to persist and no `@types`/snapshot change.

local match = require("spotlight.core.match")
local registry = require("spotlight.core.registry")

local M = {}

--- Whether `win` is opted out of spotlighting.
---@param win integer|nil # Defaults to the current window.
---@return boolean
function M.is_disabled(win)
  win = win or vim.api.nvim_get_current_win()
  return vim.w[win].spotlight_disabled == true
end

--- Set the opt-out for `win`. Setting `true` strips its current matches
--- immediately; setting `false` re-fills it from the live registry —
--- neither waits for some later, unrelated event to take effect.
---@param value boolean
---@param win integer|nil # Defaults to the current window.
---@return nil
function M.set_disabled(value, win)
  win = win or vim.api.nvim_get_current_win()
  vim.w[win].spotlight_disabled = value or nil
  if value then
    match.clear_window(win)
  else
    registry.apply_to_window(win)
  end
end

--- Flip the opt-out for `win`.
---@param win integer|nil # Defaults to the current window.
---@return boolean now_disabled
function M.toggle(win)
  win = win or vim.api.nvim_get_current_win()
  local now = not M.is_disabled(win)
  M.set_disabled(now, win)
  return now
end

return M
