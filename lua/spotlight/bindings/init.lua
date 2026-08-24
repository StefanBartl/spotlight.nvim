---@module 'spotlight.bindings'
---@brief Orchestrates spotlight's bindings: user command, keymaps, autocmds.
---@description
--- The `:Spotlight` verb and the autocommands are always registered — the verb
--- because it is the complete, keymap-independent interface to every action, and
--- the autocommands because they are what makes window-local `matchadd()` behave
--- like a global marking system. Only the keymap preset is optional.

local M = {}

--- Wire up every binding for the resolved config.
---@param cfg Spotlight.Config
---@return nil
function M.setup(cfg)
  require("spotlight.bindings.usrcmds").setup()
  if cfg.keymaps and cfg.keymaps.preset then
    require("spotlight.bindings.keymaps").setup(cfg)
    -- Label the <leader>s prefix in which-key (no-op if not installed).
    require("spotlight.bindings.which_key").setup(cfg)
  end
  require("spotlight.bindings.autocmds").setup(cfg)
end

return M
