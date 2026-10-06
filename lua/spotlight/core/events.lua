---@module 'spotlight.core.events'
---@brief The `User SpotlightChanged` autocommand: one coalesced "the spotlights changed" signal.
---@description
--- Other plugins that mirror the spotlights somewhere else (mdview.nvim paints
--- them into its browser preview, a statusline shows a count) need exactly one
--- thing from this plugin: to be told when to re-read `require("spotlight").spotlights()`.
--- This module is that signal, and nothing else.
---
--- Who calls `M.changed`:
---
---   * `core/registry.lua` -- from its single `notify_change()`, plus the two
---     paths that deliberately skip the persistence listeners (`restore`,
---     `rebuild`). So every way the list can change ends here, and a new route
---     inherits the event for free, the same way it inherits persistence.
---   * `core/palette.lua` -- from `apply()`, the one place the `SpotlightN`
---     colors are (re)defined, so a `:colorscheme`/`background` switch is a
---     signal too.
---
--- ## Coalescing
---
--- A burst is one logical change: `:Spotlight sets switch` is a `clear()` plus a
--- `restore()`, a session restore adds dozens of spotlights, `:colorscheme`
--- redefines eight groups. Each of those must not become a flood of
--- autocommands the consumer then has to debounce. `M.changed` therefore only
--- records the reason and schedules one `vim.schedule` flush for the current
--- tick; every further call inside that tick merges into the pending payload.
--- No timer: the consumer sees one event per editor tick at most, and a test can
--- wait for it deterministically.

local M = {}

--- The `User` autocommand pattern: `:autocmd User SpotlightChanged ...`.
M.PATTERN = "SpotlightChanged"

---@class Spotlight.ChangedPayload
--- Why, in first-occurrence order, each once: "add" "remove" "clear" "restore"
--- "rebuild" "lock" "line" "buffer_wiped" "colors".
---@field reasons string[]
---@field count integer               # Spotlights in the registry after the change (every scope).
---@field whole_file_count integer    # Of those, the whole-file ones (`toggle`, not `toggle_here`).
---@field whole_file_changed boolean  # false only when every merged change concerned a "this occurrence only" spotlight.

---@class Spotlight.PendingChange
---@field reasons string[]
---@field seen table<string, boolean>
---@field whole_file boolean

---@type Spotlight.PendingChange|nil
local pending = nil

---@internal
--- Build the payload from the merged change and the registry as it is *now*.
--- The registry is required here, not at load time: it requires this module.
---@param p Spotlight.PendingChange
---@return Spotlight.ChangedPayload
local function payload(p)
  local items = require("spotlight.core.registry").all()
  local whole = 0
  for _, item in ipairs(items) do
    if item.scope ~= "buffer" then
      whole = whole + 1
    end
  end
  return {
    reasons = p.reasons,
    count = #items,
    whole_file_count = whole,
    whole_file_changed = p.whole_file,
  }
end

--- Fire the pending event now, if there is one. Scheduled by `M.changed`; also
--- callable directly (a spec, or a caller that must not wait a tick). The
--- scheduled callback then finds nothing pending and does nothing.
---
--- Guarded: a consumer's failing autocommand must not break the action that
--- caused it.
---@return boolean fired
function M.flush()
  local p = pending
  pending = nil
  if not p then
    return false
  end
  local ok = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = M.PATTERN,
    modeline = false,
    data = payload(p),
  })
  return ok
end

--- Record that the spotlights changed and schedule the (coalesced) event.
---@param reason string
---@param whole_file boolean|nil # Does this touch a whole-file spotlight? Default true: when in doubt, say yes.
---@return nil
function M.changed(reason, whole_file)
  local concerns_whole = whole_file ~= false
  if pending then
    if not pending.seen[reason] then
      pending.seen[reason] = true
      pending.reasons[#pending.reasons + 1] = reason
    end
    pending.whole_file = pending.whole_file or concerns_whole
    return
  end
  pending = { reasons = { reason }, seen = { [reason] = true }, whole_file = concerns_whole }
  vim.schedule(M.flush)
end

return M
