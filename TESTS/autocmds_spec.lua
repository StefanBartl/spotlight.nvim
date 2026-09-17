-- Test code: when something here comes back nil -- a window handle, an autocmd
-- list, a registry item -- this file must crash and name it. The nil guards
-- LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/autocmds_spec.lua
-- `spotlight.bindings.autocmds`: the ~30 lines of bookkeeping that paying for
-- `matchadd()` costs. Driven through the real events with
-- `nvim_exec_autocmds` and through the real commands (`:q`, `:bdelete`,
-- `:bwipeout`, `nvim_buf_delete`), because those four are not equivalent and
-- only one of them wipes the buffer out from under a position-pinned spotlight.
--
-- Also the two questions a second `setup()` answers: whether the augroups are
-- genuinely cleared (they are -- `util.lib.augroup` resolves the id through
-- `augroup.create.clear`, not the name), and whether anything else accumulates
-- (the registry change listener does).

local t = require("harness")

local M = {}

---@internal
---@param group string
---@return integer
local function autocmd_count(group)
  local ok, cmds = pcall(vim.api.nvim_get_autocmds, { group = group })
  return ok and #cmds or -1
end

---@internal
--- Which events a group carries, sorted, as one comparable string.
---@param group string
---@return string
local function events_of(group)
  local ok, cmds = pcall(vim.api.nvim_get_autocmds, { group = group })
  if not ok then
    return "<no group>"
  end
  local seen, names = {}, {}
  for _, c in ipairs(cmds) do
    if not seen[c.event] then
      seen[c.event] = true
      names[#names + 1] = c.event
    end
  end
  table.sort(names)
  return table.concat(names, ",")
end

function M.run()
  local api = require("spotlight")
  local autocmds = require("spotlight.bindings.autocmds")
  local config = require("spotlight.config")
  local match = require("spotlight.core.match")
  local persist = require("spotlight.persist")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()
  match.clear()

  -- ---------- what gets registered ----------
  autocmds.setup(config.options)
  t.eq("setup: the window group carries six autocmds", autocmd_count("spotlight_windows"), 6)
  t.eq(
    "setup: on exactly the documented events",
    events_of("spotlight_windows"),
    "BufDelete,BufWinEnter,BufWipeout,TabNewEntered,WinClosed,WinNew"
  )
  t.eq("setup: the highlight group carries two", autocmd_count("spotlight_highlights"), 2)
  t.eq("setup: ColorScheme and OptionSet", events_of("spotlight_highlights"), "ColorScheme,OptionSet")
  t.eq("setup: the persist group carries two", autocmd_count("spotlight_persist"), 2)
  t.eq("setup: VimEnter and VimLeavePre", events_of("spotlight_persist"), "VimEnter,VimLeavePre")
  -- There is deliberately no per-keystroke or per-edit handler anywhere: a
  -- pattern-based highlight needs no invalidation when the text moves, and that
  -- absence is the plugin's central performance claim.
  local all_events = events_of("spotlight_windows") .. "," .. events_of("spotlight_highlights")
  t.eq("setup: no TextChanged handler exists", all_events:find("TextChanged", 1, true), nil)
  t.eq("setup: no CursorMoved handler exists", all_events:find("CursorMoved", 1, true), nil)

  -- ---------- a second setup() clears rather than appends ----------
  autocmds.setup(config.options)
  autocmds.setup(config.options)
  t.eq("idempotent: the window group still carries six, not eighteen", autocmd_count("spotlight_windows"), 6)
  t.eq("idempotent: the highlight group still carries two", autocmd_count("spotlight_highlights"), 2)
  t.eq("idempotent: the persist group still carries two", autocmd_count("spotlight_persist"), 2)

  -- ---------- the opt-out branches ----------
  config.setup({ palette = { reapply_on_colorscheme = false }, persist = { enable = false } })
  autocmds.setup(config.options)
  t.eq("opt-out: reapply_on_colorscheme = false drops the ColorScheme handler", events_of("spotlight_highlights"), "OptionSet")
  t.eq("opt-out: persist.enable = false registers no persistence handler at all", autocmd_count("spotlight_persist"), 0)
  config.setup()
  autocmds.setup(config.options)

  -- ---------- WinNew / BufWinEnter fill a window, and reconcile a stale pin ----------
  local buf_a = t.fixture({ "req=aaa", "req=bbb", "req=aaa" })
  local win_a = vim.api.nvim_get_current_win()
  registry.clear()
  registry.add({ text = "aaa", kind = "literal" })
  t.eq("fill: the current window is filled at add time", match.tracked_windows(), 1)

  vim.cmd("split")
  local win_b = vim.api.nvim_get_current_win()
  match.forget_window(win_b)
  vim.api.nvim_win_call(win_b, function()
    vim.fn.clearmatches()
  end)
  t.eq("fill: precondition -- win_b is empty and untracked", match.tracked_windows(), 1)
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf_a })
  -- The handler defers a tick, because on WinNew the new window is not current
  -- yet and its id is not in the event args either.
  vim.wait(200, function()
    return match.tracked_windows() == 2
  end)
  t.eq("fill: the deferred BufWinEnter pass filled the new window", match.tracked_windows(), 2)

  -- A pin left over from the previous buffer is dropped by the same pass.
  local buf_c = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_c, 0, -1, false, { "req=aaa elsewhere" })
  registry.add_at({ text = "aaa", kind = "literal" }, { buf = buf_a, row1 = 1, col1 = 5 })
  local in_b = function()
    return #vim.api.nvim_win_call(win_b, function()
      return vim.fn.getmatches()
    end)
  end
  t.eq("reconcile: precondition -- win_b carries the global and the pin", in_b(), 2)
  vim.api.nvim_win_set_buf(win_b, buf_c)
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf_c })
  vim.wait(200, function()
    return in_b() == 1
  end)
  t.eq("reconcile: after the buffer switch only the global match is left", in_b(), 1)

  -- ---------- WinClosed forgets the ledger entry ----------
  vim.api.nvim_win_set_buf(win_b, buf_a)
  registry.apply_to_window(win_b)
  local tracked_before = match.tracked_windows()
  vim.api.nvim_exec_autocmds("WinClosed", { pattern = tostring(win_b) })
  t.eq("WinClosed: the ledger entry is dropped", match.tracked_windows(), tracked_before - 1)
  -- A non-numeric `match` (which cannot happen for WinClosed, but the handler
  -- guards for it) must not raise.
  local ok_bad = pcall(vim.api.nvim_exec_autocmds, "WinClosed", { pattern = "not-a-window" })
  t.ok("WinClosed: a non-numeric window id is a quiet no-op", ok_bad)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  vim.api.nvim_set_current_win(win_a)

  -- ---------- the four ways a buffer can go away are not equivalent ----------
  --
  -- Only wiping/deleting the buffer invalidates a position pin; closing a
  -- *window* onto a still-loaded buffer does not, and the handler must not
  -- confuse the two. Each case runs against a real listed buffer.
  ---@param label string
  ---@param kill fun(buf: integer)
  ---@param expect_removed boolean
  local function teardown_case(label, kill, expect_removed)
    registry.clear()
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "req=aaa pinned here" })
    vim.api.nvim_set_current_buf(b)
    registry.add_at({ text = "aaa", kind = "literal" }, { buf = b, row1 = 1, col1 = 5 })
    registry.add({ text = "global", kind = "literal" })
    t.eq(label .. ": precondition -- two spotlights", registry.count(), 2)
    local ok, err = pcall(kill, b)
    t.ok(label .. ": no error (in particular no E937)", ok)
    if not ok then
      t.eq(label .. ": the error, for the record", tostring(err), "<none>")
    end
    t.eq(label .. ": the global spotlight always survives", registry.find_by_text("global") ~= nil, true)
    t.eq(label .. ": the pin is gone", registry.count() == 1, expect_removed)
  end

  teardown_case(":bwipeout", function(b)
    vim.cmd("bwipeout! " .. b)
  end, true)

  teardown_case(":bdelete", function(b)
    vim.cmd("bdelete! " .. b)
  end, true)

  teardown_case("nvim_buf_delete from outside", function(b)
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(scratch)
    vim.api.nvim_buf_delete(b, { force = true })
  end, true)

  -- The E937 shape: the buffer is still displayed in a window when it is
  -- deleted, which is where a handler that deletes buffers itself blows up.
  -- This handler only drops registry entries and `matchdelete()`s, so it is
  -- safe -- asserted rather than assumed, since a sibling repo did blow up here.
  teardown_case("nvim_buf_delete while displayed", function(b)
    vim.api.nvim_buf_delete(b, { force = true })
  end, true)

  -- `:q` closes a window, not the buffer: the pin stays valid, and keeping it is
  -- the correct answer rather than an oversight.
  teardown_case(":q on a split (buffer stays loaded)", function(b)
    vim.cmd("split")
    vim.api.nvim_set_current_buf(b)
    vim.cmd("q")
  end, false)

  -- And the events on their own, which is what a third-party plugin's
  -- `nvim_buf_delete`-equivalent reaches the handler through.
  registry.clear()
  local b_ev = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(b_ev, 0, -1, false, { "req=aaa" })
  vim.api.nvim_set_current_buf(b_ev)
  registry.add_at({ text = "aaa", kind = "literal" }, { buf = b_ev, row1 = 1, col1 = 5 })
  vim.api.nvim_exec_autocmds("BufDelete", { buffer = b_ev })
  t.eq("BufDelete event alone: the pin is dropped", registry.count(), 0)

  registry.add_at({ text = "aaa", kind = "literal" }, { buf = b_ev, row1 = 1, col1 = 5 })
  vim.api.nvim_exec_autocmds("BufWipeout", { buffer = b_ev })
  t.eq("BufWipeout event alone: the pin is dropped", registry.count(), 0)

  -- A pin belonging to a *different* buffer is untouched by either event.
  local b_other = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(b_other, 0, -1, false, { "req=aaa" })
  registry.add_at({ text = "aaa", kind = "literal" }, { buf = b_other, row1 = 1, col1 = 5 })
  vim.api.nvim_exec_autocmds("BufWipeout", { buffer = b_ev })
  t.eq("BufWipeout: another buffer's pin survives", registry.count(), 1)
  registry.clear()
  pcall(vim.api.nvim_buf_delete, b_ev, { force = true })
  pcall(vim.api.nvim_buf_delete, b_other, { force = true })

  -- ---------- nvim_set_hl belongs to config-build time, not to a render ----------
  --
  -- `nvim_set_hl` forces a full redraw, so where it is called from is a
  -- performance property, not a detail. Counted rather than reasoned about.
  local real_set_hl = vim.api.nvim_set_hl
  local hl_calls = 0
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_set_hl = function(...)
    hl_calls = hl_calls + 1
    return real_set_hl(...)
  end

  t.fixture({ "req=aaa", "req=bbb", "req=aaa" })
  registry.clear()
  hl_calls = 0
  registry.add({ text = "aaa", kind = "literal" })
  registry.add({ text = "bbb", kind = "literal" })
  vim.cmd("split")
  registry.apply_to_window(vim.api.nvim_get_current_win())
  registry.set_line(registry.all()[1].id, true)
  registry.set_locked(registry.all()[2].id, true)
  registry.rebuild()
  registry.remove(registry.all()[2].id)
  registry.clear()
  vim.cmd("close")
  t.eq("set_hl: a full add/apply/line/rebuild/remove pass defines zero highlight groups", hl_calls, 0)

  hl_calls = 0
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  t.eq("set_hl: ColorScheme redefines one group per palette slot", hl_calls, require("spotlight.core.palette").size())

  hl_calls = 0
  vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
  t.eq("set_hl: OptionSet background does the same", hl_calls, require("spotlight.core.palette").size())

  hl_calls = 0
  vim.api.nvim_exec_autocmds("OptionSet", { pattern = "wrap" })
  t.eq("set_hl: an unrelated OptionSet does not fire the handler", hl_calls, 0)
  vim.api.nvim_set_hl = real_set_hl

  -- ---------- VimEnter loads, VimLeavePre flushes ----------
  local real_load, real_flush = persist.load, persist.flush
  local loads, flushes = 0, 0
  ---@diagnostic disable-next-line: duplicate-set-field
  persist.load = function()
    loads = loads + 1
    return 0
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  persist.flush = function()
    flushes = flushes + 1
  end

  config.setup({ persist = { enable = true } })
  autocmds.setup(config.options)
  vim.api.nvim_exec_autocmds("VimEnter", {})
  t.eq("VimEnter: the snapshot is loaded once", loads, 1)
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  t.eq("VimLeavePre: a pending save is flushed", flushes, 1)

  -- The lazy-load branch (`vim.v.vim_did_enter == 1` -> schedule a load right
  -- away, because VimEnter has already been and gone) cannot be reached from
  -- this harness: the suite runs from a `-c` command during startup, so the flag
  -- is still 0. What *is* assertable, and is the half that matters for a normal
  -- startup, is that setup() then schedules nothing extra -- one load on
  -- VimEnter, not two.
  loads = 0
  t.eq("precondition: this run is still inside startup", vim.v.vim_did_enter, 0)
  autocmds.setup(config.options)
  vim.wait(60)
  t.eq("startup setup: no extra load is scheduled before VimEnter", loads, 0)
  vim.api.nvim_exec_autocmds("VimEnter", {})
  t.eq("startup setup: VimEnter is the single load", loads, 1)

  persist.load, persist.flush = real_load, real_flush

  -- ---------- what a second full setup() does accumulate ----------
  --
  -- The autocmds and the keymaps are clean (above, and commands_spec); the
  -- registry change listener is not. `persist.setup()` calls
  -- `registry.on_change` unconditionally and there is no unsubscribe, so each
  -- `spotlight.setup()` adds one more subscriber and every later change fans out
  -- to all of them. Harmless today -- they share one debounce handle, so the
  -- disk is still written once -- but it is unbounded, and the only reason it
  -- stays invisible is that `setup()` is normally called once.
  local saves = 0
  local real_save = persist.save
  ---@diagnostic disable-next-line: duplicate-set-field
  persist.save = function()
    saves = saves + 1
  end
  registry.clear()
  t.fixture({ "req=aaa" })
  api.setup()
  saves = 0
  registry.add({ text = "aaa", kind = "literal" })
  local after_one = saves
  t.ok("listener: one registry change notifies at least once", after_one >= 1)
  api.setup()
  api.setup()
  registry.clear()
  saves = 0
  registry.add({ text = "aaa", kind = "literal" })
  t.eq("listener: two more setup() calls add two more subscribers for the same change", saves, after_one + 2)
  persist.save = real_save

  registry.clear()
  match.clear()
  config.setup()
  api.setup()
end

return M
