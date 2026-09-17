-- Test code: when something here comes back nil -- a captured spec, an action
-- entry -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/keymaps_spec.lua
-- `spotlight.bindings.keymaps` as a *declaration*. `commands_spec.lua` already
-- checks that the preset lands on the configured keys; what it cannot see is the
-- spec handed to `lib.nvim.bindings.keymap` — the action names, the two binds per
-- toggle action, and the which-key group prefix, which is derived from the
-- configured `toggle` key rather than hard-coded and therefore has a shape to
-- get wrong.
--
-- The keymap registry is replaced with a recording double and the subject loaded
-- fresh against it, since the module binds `require("lib.nvim.bindings.keymap")`
-- to a file-local at load time. Nothing is bound to a real key here.

local t = require("harness")

local M = {}

local KEYMAP = "lib.nvim.bindings.keymap"
local SUBJECT = "spotlight.bindings.keymaps"

---@internal
--- Build the spec for `cfg` against a recording registry.
---@param cfg table
---@return table spec, table|nil overrides
local function capture(cfg)
  local spec, overrides
  local saved = package.loaded[SUBJECT]
  package.loaded[SUBJECT] = nil
  local ok, err = pcall(function()
    t.with_modules({
      [KEYMAP] = {
        register = function(_, s, o)
          spec, overrides = s, o
          return {}
        end,
      },
    }, function()
      require(SUBJECT).setup(cfg)
    end)
  end)
  package.loaded[SUBJECT] = saved
  if not ok then
    error(err, 0)
  end
  return spec, overrides
end

function M.run()
  local config = require("spotlight.config")

  config.setup()
  local spec, overrides = capture(config.options)

  -- ---------- the declaration ----------
  t.eq("spec: registered under the plugin's own name", type(spec), "table")
  t.eq(
    "spec: the action order is the one :checkhealth and the docs read",
    table.concat(spec.order, ","),
    "toggle_here,toggle,list,clear,quickfix,line,next,prev"
  )
  for _, name in ipairs(spec.order) do
    t.ok(("spec: %s is declared"):format(name), spec.actions[name] ~= nil)
  end
  t.eq("spec: no action is declared that the order does not list", vim.tbl_count(spec.actions), #spec.order)
  t.eq("spec: the user's keymap table is handed over as the override source", overrides, config.get("keymaps"))

  -- Each action's default matches DEFAULTS, so the two cannot drift apart
  -- silently -- the defaults are documented in the README from the config table.
  for _, name in ipairs(spec.order) do
    t.eq(("spec: %s's default is the configured one"):format(name), spec.actions[name].default, config.get("keymaps." .. name))
  end

  -- The two toggle actions carry one lhs for both modes; everything else is
  -- normal-mode only, because it acts on a spotlight that already exists.
  t.eq("spec: toggle_here binds two modes", #spec.actions.toggle_here.binds, 2)
  t.eq("spec: normal mode first", spec.actions.toggle_here.binds[1].mode, "n")
  t.eq("spec: then visual", spec.actions.toggle_here.binds[2].mode, "x")
  t.eq("spec: toggle binds two modes as well", #spec.actions.toggle.binds, 2)
  t.eq("spec: line mode has no visual counterpart", spec.actions.line.binds, nil)
  t.eq("spec: ...it is a single rhs", type(spec.actions.line.rhs), "function")
  t.eq("spec: and so is quickfix", type(spec.actions.quickfix.rhs), "function")
  for _, name in ipairs({ "list", "clear", "next", "prev" }) do
    t.eq(("spec: %s is a single normal-mode rhs"):format(name), type(spec.actions[name].rhs), "function")
    t.eq(("spec: %s carries a description"):format(name), type(spec.actions[name].desc), "string")
  end

  -- Every bind has a description, which is what which-key labels each key from.
  for _, name in ipairs(spec.order) do
    local action = spec.actions[name]
    if action.binds then
      for i, bind in ipairs(action.binds) do
        t.eq(("spec: %s bind %d has a desc"):format(name, i), type(bind.desc), "string")
        t.eq(("spec: %s bind %d has a callable rhs"):format(name, i), type(bind.rhs), "function")
      end
    end
  end

  -- The normal-mode toggle is the only dot-repeatable one: `.` has to re-resolve
  -- the cursor token, and a visual selection no longer exists by the time it fires.
  t.contains("spec: the normal-mode toggle advertises dot-repeat", spec.actions.toggle.binds[1].desc, "dot-repeatable")
  t.eq("spec: the visual one does not", spec.actions.toggle.binds[2].desc:find("dot", 1, true), nil)

  -- ---------- the which-key group ----------
  t.eq("spec: the group is labelled Spotlight", spec.which_key.group, "Spotlight")
  t.eq("spec: in both the modes the preset binds", table.concat(spec.which_key.mode, ","), "n,x")
  t.eq("spec: the prefix is derived from the configured toggle key", spec.prefix, "<leader>s")

  -- Moving the preset to another leader group moves the label with it, rather
  -- than leaving it on a group the user no longer uses.
  config.setup({ keymaps = { toggle = "<leader>xK" } })
  local moved = capture(config.options)
  t.eq("prefix: follows a moved toggle key to its new leader group", moved.prefix, "<leader>x")
  t.eq(
    "prefix: while the declared default is untouched -- that is the override's job",
    moved.actions.toggle.default,
    "<leader>sK"
  )

  -- A toggle key that is not a `<leader>` pair has no group to label, and saying
  -- nothing is the right answer -- a wrong prefix would label an unrelated group.
  config.setup({ keymaps = { toggle = "]k" } })
  t.eq("prefix: a non-leader key yields no group label", (capture(config.options)).prefix, nil)
  config.setup({ keymaps = { toggle = "<leader>sKK" } })
  t.eq("prefix: a three-character suffix does not match the shape either", (capture(config.options)).prefix, nil)

  -- `false` is the documented way to free one key, and a whole `keymaps = false`
  -- the way to declare nothing. Neither may raise while building the spec.
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ keymaps = { toggle = false } })
  t.eq("prefix: a disabled toggle key yields no group label", (capture(config.options)).prefix, nil)
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ keymaps = false })
  local no_keymaps = capture(config.options)
  t.eq("spec: keymaps = false still declares every action", #no_keymaps.order, 8)
  t.eq("spec: with no group prefix", no_keymaps.prefix, nil)

  -- The registry is asked to declare the actions even with the preset off: a
  -- `:checkhealth`/docs consumer asks what EXISTS, and that stays true either way.
  config.setup({ keymaps = { preset = false } })
  local off, off_overrides = capture(config.options)
  t.eq("spec: preset = false still declares all eight actions", #off.order, 8)
  t.eq("spec: and it is the registry, not this module, that is told not to bind", off_overrides.preset, false)

  config.setup()
end

return M
