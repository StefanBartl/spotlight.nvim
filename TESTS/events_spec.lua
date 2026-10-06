-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/events_spec.lua
-- `User SpotlightChanged`: every change to the list (toggle, remove, clear, set
-- switch, restore, lock/line, buffer wipe) and every color change announces
-- itself, coalesced to one event per editor tick, with a small payload. The
-- event fires from the registry's single notify point, so a second `setup()`
-- does not multiply it.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local events = require("spotlight.core.events")
  local registry = require("spotlight.core.registry")
  local sets = require("spotlight.sets")
  local api = require("spotlight")

  config.setup()
  api.setup()
  t.fixture({ "req=aaa ip=10.0.0.1", "req=bbb", "req=aaa" })

  ---@type table[]
  local log = {}
  vim.api.nvim_create_autocmd("User", {
    pattern = "SpotlightChanged",
    callback = function(args)
      log[#log + 1] = args.data
    end,
  })

  --- Let every scheduled flush run, then report what arrived since `reset()`.
  ---@return table[]
  local function settle()
    vim.wait(40)
    return log
  end
  local function reset()
    vim.wait(40)
    log = {}
  end

  registry.clear()
  reset()

  t.eq("constant: the pattern name is part of the contract", events.PATTERN, "SpotlightChanged")

  -- ---------- add ----------
  registry.add({ text = "aaa", kind = "literal" })
  t.eq("add: nothing fires synchronously", #log, 0)
  settle()
  t.eq("add: one event", #log, 1)
  t.eq("add: reasons", vim.inspect(log[1].reasons), vim.inspect({ "add" }))
  t.eq("add: count", log[1].count, 1)
  t.eq("add: whole_file_count", log[1].whole_file_count, 1)
  t.eq("add: whole_file_changed", log[1].whole_file_changed, true)

  -- ---------- toggle through the facade ----------
  reset()
  t.ok("toggle: cursor placed", t.cursor_on(2, "bbb"))
  t.ok("toggle: added", api.toggle())
  settle()
  t.eq("toggle: one event for the add", #log, 1)
  t.eq("toggle: count follows", log[1].count, 2)
  reset()
  t.ok("toggle: removed again", api.toggle())
  settle()
  t.eq("toggle: one event for the removal", #log, 1)
  t.eq("toggle: reason", log[1].reasons[1], "remove")
  t.eq("toggle: count follows back", log[1].count, 1)

  -- ---------- this occurrence only ----------
  reset()
  t.ok("here: cursor placed", t.cursor_on(1, "aaa"))
  t.ok("here: added", api.toggle_here())
  settle()
  t.eq("here: one event", #log, 1)
  t.eq("here: it counts the pinned spotlight", log[1].count, 2)
  t.eq("here: but not as a whole-file one", log[1].whole_file_count, 1)
  t.eq("here: and says no whole-file spotlight was touched", log[1].whole_file_changed, false)
  reset()
  t.ok("here: removed", api.toggle_here())
  settle()
  t.eq("here: removing it is a pinned change too", log[1].whole_file_changed, false)

  -- ---------- coalescing ----------
  reset()
  registry.add({ text = "one", kind = "literal" })
  registry.add({ text = "two", kind = "literal" })
  registry.add({ text = "three", kind = "literal" })
  settle()
  t.eq("coalesce: three adds in one tick are one event", #log, 1)
  t.eq("coalesce: each reason once", vim.inspect(log[1].reasons), vim.inspect({ "add" }))
  t.eq("coalesce: the count is the state after the burst", log[1].count, 4)

  reset()
  registry.remove(registry.find_by_text("one").id)
  registry.add({ text = "four", kind = "literal" })
  settle()
  t.eq("coalesce: mixed changes are still one event", #log, 1)
  t.eq("coalesce: reasons in first-occurrence order", vim.inspect(log[1].reasons), vim.inspect({ "remove", "add" }))

  reset()
  registry.add({ text = "pinned-only", kind = "literal" })
  registry.add_at({ text = "x", kind = "literal" }, { buf = vim.api.nvim_get_current_buf(), row1 = 1, col1 = 1 })
  settle()
  t.eq("coalesce: a whole-file change merged with a pinned one stays whole-file", log[1].whole_file_changed, true)

  -- ---------- clear ----------
  reset()
  t.ok("clear: something to clear", api.clear())
  settle()
  t.eq("clear: one event", #log, 1)
  t.eq("clear: reason", log[1].reasons[1], "clear")
  t.eq("clear: empty afterwards", log[1].count, 0)
  t.eq("clear: counts whole-file as empty too", log[1].whole_file_count, 0)

  reset()
  t.eq("clear: nothing to clear is no change", api.clear(), false)
  settle()
  t.eq("clear: ... and no event", #log, 0)

  -- ---------- add refused ----------
  registry.add({ text = "dup", kind = "literal" })
  reset()
  local refused = registry.add({ text = "dup", kind = "literal" })
  settle()
  t.eq("refused: the duplicate was not added", refused, nil)
  t.eq("refused: and nothing is announced", #log, 0)

  -- ---------- sets: switch is clear + restore, one event ----------
  for _, name in ipairs(sets.names()) do
    sets.delete(name)
  end
  registry.clear()
  registry.add({ text = "s1", kind = "literal" })
  registry.add({ text = "s2", kind = "literal" })
  t.ok("sets: saved", api.sets_save("evt-set"))
  registry.clear()
  registry.add({ text = "other", kind = "literal" })
  reset()
  t.ok("sets: switched", api.sets_switch("evt-set"))
  settle()
  t.eq("sets: a switch is exactly one event", #log, 1)
  t.eq("sets: reasons clear then restore", vim.inspect(log[1].reasons), vim.inspect({ "clear", "restore" }))
  t.eq("sets: the count is the restored set", log[1].count, 2)

  reset()
  t.eq("sets: an unknown name changes nothing", api.sets_switch("no-such-set"), false)
  settle()
  t.eq("sets: ... and announces nothing", #log, 0)
  sets.delete("evt-set")

  -- ---------- restore (the persistence path) ----------
  reset()
  registry.restore({ { text = "r1", slot = 1, kind = "literal" } })
  settle()
  t.eq("restore: one event, although the change listeners stay quiet", #log, 1)
  t.eq("restore: the reasons say so", log[1].reasons[#log[1].reasons], "restore")
  t.eq("restore: the restored count", log[1].count, 1)

  -- ---------- lock / line ----------
  reset()
  t.ok("lock: set", api.lock_set("r1", true))
  settle()
  t.eq("lock: one event", #log, 1)
  t.eq("lock: reason", log[1].reasons[1], "lock")
  reset()
  t.ok("line: set", api.line_set("r1", true))
  settle()
  t.eq("line: one event", #log, 1)
  t.eq("line: reason", log[1].reasons[1], "line")
  t.eq("line: whole-file", log[1].whole_file_changed, true)

  -- ---------- rebuild (refresh) ----------
  reset()
  api.refresh()
  settle()
  t.eq("refresh: one event", #log, 1)
  t.ok("refresh: carrying the rebuild", vim.tbl_contains(log[1].reasons, "rebuild"))
  t.ok("refresh: and the redefined colors", vim.tbl_contains(log[1].reasons, "colors"))

  -- ---------- a wiped buffer drops its pinned spotlights ----------
  registry.clear()
  local scratch = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "pinned text" })
  registry.add_at({ text = "pinned", kind = "literal" }, { buf = scratch, row1 = 1, col1 = 1 })
  reset()
  vim.api.nvim_buf_delete(scratch, { force = true })
  settle()
  t.eq("buffer wipe: one event", #log, 1)
  t.eq("buffer wipe: reason", log[1].reasons[1], "buffer_wiped")
  t.eq("buffer wipe: a pinned spotlight, so not whole-file", log[1].whole_file_changed, false)
  t.eq("buffer wipe: the registry is empty", log[1].count, 0)

  -- ---------- colors ----------
  reset()
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  settle()
  t.eq("ColorScheme: one event", #log, 1)
  t.eq("ColorScheme: reason", log[1].reasons[1], "colors")
  t.eq("ColorScheme: a color change touches whole-file spotlights", log[1].whole_file_changed, true)

  local saved_bg = vim.o.background
  reset()
  vim.o.background = saved_bg == "dark" and "light" or "dark"
  -- Fired by hand: Neovim does not raise OptionSet for 'background' while the
  -- spec runs from a startup `-c` command (autocmds_spec drives it the same way).
  vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
  settle()
  t.eq("background: switching it is one event", #log, 1)
  t.eq("background: reason", log[1].reasons[1], "colors")
  vim.o.background = saved_bg
  reset()

  -- With the groups left to the user (`palette.reapply_on_colorscheme = false`)
  -- no handler redefines them, so a colorscheme change is not announced: such a
  -- consumer listens to ColorScheme itself (documented in docs/api.md).
  api.setup({ palette = { reapply_on_colorscheme = false } })
  reset()
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  settle()
  t.eq("ColorScheme (no reapply): no handler, so no event", #log, 0)
  api.setup()
  reset()

  -- ---------- setup() twice does not multiply it ----------
  api.setup()
  api.setup()
  reset()
  registry.add({ text = "once", kind = "literal" })
  settle()
  t.eq("setup x3: still one event per change", #log, 1)

  -- ---------- flush() ----------
  reset()
  registry.remove(registry.find_by_text("once").id)
  t.eq("flush: fires a pending event immediately", events.flush(), true)
  t.eq("flush: so the event is there without waiting", #log, 1)
  settle()
  t.eq("flush: and the scheduled flush then finds nothing to do", #log, 1)
  t.eq("flush: nothing pending is not an event", events.flush(), false)

  -- ---------- the payload is plain data ----------
  reset()
  registry.add({ text = "plain", kind = "literal" })
  settle()
  t.eq("payload: reasons is a list", type(log[1].reasons), "table")
  t.eq("payload: count is a number", type(log[1].count), "number")
  t.eq("payload: whole_file_count is a number", type(log[1].whole_file_count), "number")
  t.eq("payload: whole_file_changed is a boolean", type(log[1].whole_file_changed), "boolean")

  registry.clear()
  reset()
end

return M
