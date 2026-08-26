---@module 'spotlight.bindings'
---@brief Orchestrates spotlight's bindings: user command, keymaps, autocmds.
---@description
--- The `:Spotlight` verb and the autocommands are always registered — the verb
--- because it is the complete, keymap-independent interface to every action, and
--- the autocommands because they are what makes window-local `matchadd()` behave
--- like a global marking system. Only the keymap preset is optional -- and even
--- that is a question for the keymap registry, not for this file.

local M = {}

--- Wire up every binding for the resolved config.
---@param cfg Spotlight.Config
---@return nil
function M.setup(cfg)
  require("spotlight.bindings.usrcmds").setup()

  -- Called unconditionally, including with `keymaps.preset = false`: the
  -- registry honours `preset` itself, and binding nothing is not the same as
  -- declaring nothing. `:checkhealth` and the generated bindings page ask
  -- `keymap.registered("spotlight")` what EXISTS, which stays true whether or
  -- not the preset is on. Labelling the which-key prefix moved in there too.
  require("spotlight.bindings.keymaps").setup(cfg)

  require("spotlight.bindings.autocmds").setup(cfg)
end

return M
