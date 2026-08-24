-- TESTS/commands_spec.lua
-- The public surface: that setup() wires everything, that :Spotlight and every
-- one of its routes exists and works, and that the preset keymaps land on the
-- configured keys (and only on the ones not disabled with `false`).

local t = require("harness")

local M = {}

--- Whether a normal-mode mapping exists for `lhs`.
---@param lhs string
---@param mode string
---@return boolean
local function mapped(lhs, mode)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == vim.fn.substitute(lhs, "<leader>", vim.g.mapleader or "\\", "g") or m.lhs == lhs then
      return true
    end
  end
  return false
end

function M.run()
  vim.g.mapleader = " "

  local api = require("spotlight")
  local registry = require("spotlight.core.registry")

  -- ---------- setup ----------
  api.setup()
  t.eq("setup: the :Spotlight command exists", vim.fn.exists(":Spotlight"), 2)
  t.eq("setup: the palette groups are defined", vim.fn.hlexists("Spotlight1"), 1)
  t.eq("setup: all eight palette groups are defined", vim.fn.hlexists("Spotlight8"), 1)

  registry.clear()
  t.fixture({ "req=aaa ip=10.0.0.1", "req=bbb", "req=aaa" })

  -- ---------- the command routes ----------
  vim.cmd("Spotlight add aaa")
  t.eq("cmd/add: one spotlight active", registry.count(), 1)
  t.eq("cmd/add: the literal text was used", registry.all()[1].text, "aaa")

  vim.cmd("Spotlight add bbb")
  t.eq("cmd/add: a second spotlight", registry.count(), 2)

  vim.cmd("Spotlight remove bbb")
  t.eq("cmd/remove: back to one", registry.count(), 1)

  vim.cmd("Spotlight toggle aaa")
  t.eq("cmd/toggle: an existing text is removed", registry.count(), 0)
  vim.cmd("Spotlight toggle aaa")
  t.eq("cmd/toggle: an absent text is added", registry.count(), 1)
  vim.cmd("Spotlight clear")

  -- ---------- :Spotlight here ("this occurrence only") ----------
  t.ok("cmd/here: cursor placed on the first aaa", t.cursor_on(1, "aaa"))
  vim.cmd("Spotlight here")
  t.eq("cmd/here: one spotlight added", registry.count(), 1)
  t.eq("cmd/here: scoped to this buffer position", registry.all()[1].scope, "buffer")
  vim.cmd("Spotlight here")
  t.eq("cmd/here: pressing it again on the same spot removes it", registry.count(), 0)

  -- Restore the plain invariant the rest of the suite below expects: one
  -- global "aaa" spotlight active.
  vim.cmd("Spotlight toggle aaa")
  t.eq("cmd/here: unrelated to the global toggle identity", registry.count(), 1)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("Spotlight next")
  t.eq("cmd/next: the cursor moved onto a match", vim.api.nvim_win_get_cursor(0)[1], 1)
  vim.cmd("Spotlight prev")
  t.ok("cmd/prev: still on a match", require("spotlight.nav").under_cursor() ~= nil)

  vim.cmd("Spotlight qf")
  t.eq("cmd/qf: matching lines in the quickfix list", #vim.fn.getqflist(), 2)
  vim.fn.setqflist({}, "r")
  vim.cmd("cclose")

  vim.cmd("Spotlight refresh")
  t.eq("cmd/refresh: the matches are still applied", #vim.fn.getmatches(), registry.count())

  vim.cmd("Spotlight persist status")
  t.eq("cmd/persist: status does not change the registry", registry.count(), 1)

  vim.cmd("Spotlight clear")
  t.eq("cmd/clear: nothing left", registry.count(), 0)
  t.eq("cmd/clear: no window matches left", #vim.fn.getmatches(), 0)

  -- Bare `:Spotlight` falls through to toggle.
  t.ok("cmd/default: cursor placed", t.cursor_on(1, "aaa"))
  vim.cmd("Spotlight")
  t.eq("cmd/default: bare :Spotlight toggles the token under the cursor", registry.count(), 1)
  vim.cmd("Spotlight clear")

  -- ---------- facade actions ----------
  t.ok("api/add: adds", api.add("zzz"))
  t.eq("api/remove: removes", api.remove("zzz"), true)
  t.eq("api/remove: a missing text is refused, not an error", api.remove("nope"), false)
  t.eq("api/clear: nothing to clear is reported as no change", api.clear(), false)
  t.eq("api/next: no spotlights means no movement", api.next(), false)
  t.eq("api/quickfix: an unknown text is refused", api.quickfix("nope"), false)
  api.add("aaa")
  t.eq("api/spotlights: the live registry is exposed", #api.spotlights(), 1)
  api.clear()

  -- ---------- preset keymaps ----------
  api.setup({ keymaps = { preset = true } })
  t.ok("keymaps: toggle_here (this occurrence only) bound in normal mode", mapped("<leader>sk", "n"))
  t.ok("keymaps: toggle_here bound in visual mode", mapped("<leader>sk", "x"))
  t.ok("keymaps: toggle (every occurrence) bound in normal mode", mapped("<leader>sK", "n"))
  t.ok("keymaps: toggle bound in visual mode", mapped("<leader>sK", "x"))
  t.ok("keymaps: list bound", mapped("<leader>sL", "n"))
  t.ok("keymaps: clear bound", mapped("<leader>sC", "n"))
  t.ok("keymaps: quickfix bound", mapped("<leader>sq", "n"))
  t.ok("keymaps: next bound", mapped("]k", "n"))
  t.ok("keymaps: prev bound", mapped("[k", "n"))

  -- A single key can be freed without opting out of the whole preset.
  vim.keymap.del("n", "]k")
  api.setup({ keymaps = { preset = true, next = false } })
  t.eq("keymaps: next = false leaves the key unbound", mapped("]k", "n"), false)
  t.ok("keymaps: the rest of the preset is still bound", mapped("[k", "n"))

  api.setup()
end

return M
