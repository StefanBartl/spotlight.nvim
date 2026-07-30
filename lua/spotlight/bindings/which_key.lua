---@module 'spotlight.bindings.which_key'
---@brief Optional, guarded which-key group label for the preset's prefix.
---@description
--- which-key is a **soft** dependency: without it this is a no-op. When present,
--- a single group label is registered so the preset's keys appear under a named
--- "Spotlight" group instead of a bare prefix. Individual key descriptions
--- already come from each mapping's `desc`, so nothing else needs registering.
---
--- The prefix is derived from the configured `keymaps.toggle` rather than
--- hard-coded: a user who moves the preset to a different leader group should get
--- the label there, not on the group they no longer use.
---
--- Supports both the which-key v3 (`add`) and v2 (`register`) APIs.

local M = {}

--- The leader-group prefix to label: the configured toggle key minus its last
--- character, when that leaves a plausible `<leader>x` prefix.
---@param cfg Spotlight.Config
---@return string|nil
local function prefix_of(cfg)
  local toggle = cfg.keymaps and cfg.keymaps.toggle
  if type(toggle) ~= "string" then
    return nil
  end
  local prefix = toggle:match("^(<leader>.)%a$")
  return prefix
end

--- Register the preset's prefix as a which-key group, if available.
---@param cfg Spotlight.Config
---@return boolean registered
function M.setup(cfg)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end
  local prefix = prefix_of(cfg)
  if not prefix then
    return false
  end
  if type(wk.add) == "function" then
    -- which-key v3
    wk.add({ { prefix, group = "Spotlight", mode = { "n", "x" } } })
    return true
  elseif type(wk.register) == "function" then
    -- which-key v2
    wk.register({ [prefix] = { name = "+Spotlight" } }, { mode = "n" })
    wk.register({ [prefix] = { name = "+Spotlight" } }, { mode = "x" })
    return true
  end
  return false
end

--- Whether which-key is installed (for `:checkhealth` reporting).
---@return boolean
function M.available()
  local ok, wk = pcall(require, "which-key")
  return ok and type(wk) == "table"
end

return M
