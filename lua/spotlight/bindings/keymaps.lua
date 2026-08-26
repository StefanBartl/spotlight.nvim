---@module 'spotlight.bindings.keymaps'
---@brief The preset keymaps, declared as named actions.
---@description
--- Every key is an individually overridable config value, and setting any of
--- them to `false` drops just that mapping — so a user can keep the preset and
--- still free one `lhs`, without having to opt out of the whole set and rebuild
--- it by hand. Setting `keymaps.preset = false` binds nothing at all; every
--- action is still reachable via `:Spotlight` and as a plain function on the
--- `spotlight` module.
---
--- Declared through `lib.nvim.bindings.keymap`'s registry rather than bound
--- here by hand. That is not merely tidier: the registry names each action, so
--- a typo in a user's override (`toggl_here = "…"`) is *reported* instead of
--- silently binding nothing, and `keymap.registered("spotlight")` hands the
--- whole surface to `:checkhealth` and to generated docs without either of
--- them re-reading this file.
---
--- Maps bind directly onto the facade actions — no `<Plug>` indirection.
--- which-key labels the `<leader>s` prefix from the spec below; the per-key
--- labels come from each mapping's own `desc`, which which-key reads by itself.

local keymap = require("lib.nvim.bindings.keymap")
local lib = require("spotlight.util.lib")

local M = {}

---@internal
--- The leader-group prefix to hand which-key, derived from the configured
--- `toggle` key rather than hard-coded: a user who moves the preset to a
--- different leader group should get the label there, not on the group they no
--- longer use.
---@param cfg Spotlight.Config
---@return string|nil
local function prefix_of(cfg)
  local toggle = cfg.keymaps and cfg.keymaps.toggle
  if type(toggle) ~= "string" then
    return nil
  end
  return toggle:match("^(<leader>.)%a$")
end

--- Declare and bind the preset's actions.
---@param cfg Spotlight.Config
---@return Lib.Keymap.Registered[]
function M.setup(cfg)
  local api = require("spotlight")

  ---@type Lib.Keymap.Spec
  local spec = {
    prefix = prefix_of(cfg),
    which_key = { group = "Spotlight", mode = { "n", "x" } },
    order = { "toggle_here", "toggle", "list", "clear", "quickfix", "line", "next", "prev" },
    actions = {
      -- One `lhs` per action for both modes: normal mode spotlights the
      -- resolved token, visual mode the exact selection. Same intent, so the
      -- same key — and one action name, so a user moving the key says so once.
      --
      -- `toggle_here` (lowercase k) marks only the one occurrence the cursor/
      -- selection is on; `toggle` (uppercase K) marks every occurrence of that
      -- text in the buffer. The lowercase key is the one reached for by
      -- default — it is also the narrower, more reversible action — with the
      -- wider one a deliberate shift to the shifted key.
      toggle_here = {
        default = "<leader>sk",
        binds = {
          { mode = "n", rhs = api.toggle_here, desc = "toggle this occurrence only" },
          {
            mode = "x",
            rhs = api.toggle_here_selection,
            desc = "toggle this selection only",
          },
        },
      },

      toggle = {
        default = "<leader>sK",
        binds = {
          -- Only the normal-mode toggle is dot-repeatable: `.` re-invokes the
          -- wrapped function fresh, so it re-resolves whatever the cursor is
          -- on *then*, not a captured closure over the original spot. Visual
          -- mode is left alone — dot-repeat is a normal-mode-operator concept,
          -- and the selection it read no longer exists by the time `.` fires.
          {
            mode = "n",
            rhs = lib.dot_repeatable(api.toggle),
            desc = "toggle every occurrence of the token under cursor (dot-repeatable)",
          },
          {
            mode = "x",
            rhs = api.toggle_selection,
            desc = "toggle every occurrence of the selection",
          },
        },
      },

      list = { default = "<leader>sL", rhs = api.list, desc = "open the spotlight list" },
      clear = { default = "<leader>sC", rhs = api.clear, desc = "clear all spotlights" },

      quickfix = {
        default = "<leader>sq",
        rhs = function()
          api.quickfix(nil)
        end,
        desc = "matching lines to quickfix",
      },

      -- Line mode acts on a spotlight that already exists, so there is no
      -- visual counterpart to bind: a selection would resolve to text with no
      -- spotlight attached, which this action refuses by design.
      line = {
        default = "<leader>sW",
        rhs = function()
          api.line_toggle(nil)
        end,
        desc = "toggle whole-line rendering for the token under cursor",
      },

      next = { default = "]k", rhs = api.next, desc = "next occurrence (×count)" },
      prev = { default = "[k", rhs = api.prev, desc = "previous occurrence (×count)" },
    },
  }

  return keymap.register("spotlight", spec, cfg.keymaps)
end

return M
