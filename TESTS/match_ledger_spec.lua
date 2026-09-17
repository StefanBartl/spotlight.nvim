-- Test code: when something here comes back nil -- a window handle, a ledger
-- entry, a fixture read -- this file must crash and name it. The nil guards
-- LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/match_ledger_spec.lua
-- `spotlight.core.match` on its own terms: the `window -> { spotlight id ->
-- match id }` ledger that makes window-local `matchadd()` behave like a global
-- marking system.
--
-- Every other spec reaches this module through `core.registry`, which only ever
-- drives the happy path. The parts that keep the ledger honest -- the
-- eligibility gate, the buffer-scoped window check, `reconcile_window`, the
-- difference between forgetting a closed window and stripping an open one, and
-- the one path where `matchadd()` itself refuses -- are only reachable directly,
-- so they are driven directly here, with hand-built items rather than through
-- the registry.

local t = require("harness")

local M = {}

---@internal
--- The matches Vim itself reports for `win`, which is the only authority on
--- whether the ledger and reality agree.
---@param win integer
---@return table[]
local function matches_in(win)
  local ok, res = pcall(vim.api.nvim_win_call, win, function()
    return vim.fn.getmatches()
  end)
  return ok and res or {}
end

---@internal
--- A hand-built item, so the low-level calls can be driven without the registry
--- deciding slots, ids or patterns.
---@param id integer
---@param text string
---@param extra table|nil
---@return Spotlight.Item
local function item(id, text, extra)
  local it = {
    id = id,
    text = text,
    pattern = "\\C\\V" .. text,
    slot = 1,
    hl = "Spotlight1",
  }
  for k, v in pairs(extra or {}) do
    it[k] = v
  end
  return it
end

function M.run()
  local config = require("spotlight.config")
  local match = require("spotlight.core.match")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()
  match.clear()

  -- Every assertion below counts *tracked windows*, so the window layout has to
  -- be known: close anything an earlier spec left open, and drop the matches a
  -- `clearmatches()`-free spec may have left in the survivor.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= vim.api.nvim_get_current_win() then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.fn.clearmatches()
  t.eq("precondition: exactly one window is open", #vim.api.nvim_list_wins(), 1)
  t.eq("precondition: carrying no matches", #vim.fn.getmatches(), 0)

  local prio = config.get("match.priority")
  local buf_a = t.fixture({ "req=aaa", "req=bbb", "req=aaa" })
  local win_a = vim.api.nvim_get_current_win()

  -- ---------- apply_window is idempotent ----------
  local one = item(101, "aaa")
  match.apply_window(win_a, { one }, prio)
  t.eq("apply_window: one match registered", #matches_in(win_a), 1)
  t.eq("apply_window: one tracked window", match.tracked_windows(), 1)
  match.apply_window(win_a, { one }, prio)
  match.apply_window(win_a, { one }, prio)
  t.eq("apply_window: re-applying the same item does not duplicate the match", #matches_in(win_a), 1)
  t.eq("apply_window: the match carries the item's own group", matches_in(win_a)[1].group, "Spotlight1")
  t.eq("apply_window: ...at the configured priority", matches_in(win_a)[1].priority, prio)

  -- ---------- an invalid window is refused, not raised on ----------
  local dead = vim.api.nvim_open_win(buf_a, false, { relative = "editor", row = 1, col = 1, width = 5, height = 2 })
  vim.api.nvim_win_close(dead, true)
  local ok_dead = pcall(match.apply_window, dead, { one }, prio)
  t.ok("eligible: a closed window is skipped rather than raising", ok_dead)
  t.eq("eligible: and leaves no ledger entry behind", match.tracked_windows(), 1)

  -- ---------- floating windows are skipped ----------
  local float = vim.api.nvim_open_win(buf_a, false, { relative = "editor", row = 1, col = 1, width = 10, height = 2 })
  match.apply_window(float, { one }, prio)
  t.eq("eligible: a floating window gets no matches", #matches_in(float), 0)
  t.eq("eligible: and is not tracked", match.tracked_windows(), 1)

  -- ---------- the per-window opt-out is honoured by the gate itself ----------
  vim.w[float].spotlight_disabled = nil
  vim.cmd("split")
  local win_b = vim.api.nvim_get_current_win()
  vim.w[win_b].spotlight_disabled = true
  match.apply_window(win_b, { one }, prio)
  t.eq("eligible: an opted-out window gets no matches", #matches_in(win_b), 0)
  t.eq(
    "eligible: ...even from a blanket apply_all",
    (function()
      match.apply_all({ one }, prio)
      return #matches_in(win_b)
    end)(),
    0
  )
  vim.w[win_b].spotlight_disabled = nil
  match.apply_all({ one }, prio)
  t.eq("eligible: clearing the flag lets the next fill through", #matches_in(win_b), 1)
  t.eq("apply_all: both ordinary windows are tracked", match.tracked_windows(), 2)

  -- ---------- clear_window vs forget_window ----------
  match.clear_window(win_b)
  t.eq("clear_window: strips the matches of a still-open window", #matches_in(win_b), 0)
  t.eq("clear_window: and drops its ledger entry", match.tracked_windows(), 1)
  match.clear_window(win_b)
  t.eq("clear_window: a second call on an untracked window is a no-op", match.tracked_windows(), 1)

  match.apply_window(win_b, { one }, prio)
  t.eq("forget_window: precondition -- the window carries a match", #matches_in(win_b), 1)
  match.forget_window(win_b)
  t.eq("forget_window: the ledger entry is gone", match.tracked_windows(), 1)
  t.eq("forget_window: but Vim's own match is untouched (the window is still open)", #matches_in(win_b), 1)
  -- Which is why it is only for WinClosed: the ledger no longer knows about
  -- that match, so a later fill re-adds one and the window ends up with two --
  -- and the orphaned first one can no longer be deleted through this module at
  -- all, only with Vim's own `clearmatches()`. `bindings/autocmds` calls
  -- `forget_window` from `WinClosed` and nowhere else, which is what keeps this
  -- shape unreachable in practice.
  match.apply_window(win_b, { one }, prio)
  t.eq("forget_window: a later fill therefore duplicates it -- hence WinClosed only", #matches_in(win_b), 2)
  match.clear_window(win_b)
  t.eq("forget_window: clear_window can only remove the match the ledger still knows", #matches_in(win_b), 1)
  vim.api.nvim_win_call(win_b, function()
    vim.fn.clearmatches()
  end)
  t.eq("forget_window: the orphan needs Vim's own clearmatches()", #matches_in(win_b), 0)

  -- ---------- buffer-scoped items only reach the window showing their buffer ----------
  local buf_c = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_c, 0, -1, false, { "req=aaa elsewhere" })
  local pinned = item(102, "aaa", { scope = "buffer", buf = buf_a, row1 = 1, col1 = 5 })
  vim.api.nvim_win_set_buf(win_b, buf_c)
  match.apply_all({ pinned }, prio)
  t.eq("add: the pinned item reaches the window showing its buffer", #matches_in(win_a), 2)
  t.eq("add: ...and not the window showing another buffer", #matches_in(win_b), 0)

  -- ---------- reconcile_window drops a stale pin, keeps the global ----------
  vim.api.nvim_win_set_buf(win_b, buf_a)
  match.apply_window(win_b, { one, pinned }, prio)
  t.eq("reconcile: precondition -- win_b now carries both", #matches_in(win_b), 2)
  vim.api.nvim_win_set_buf(win_b, buf_c)
  match.reconcile_window(win_b, { one, pinned })
  local left = matches_in(win_b)
  t.eq("reconcile: one match left after the buffer switch", #left, 1)
  t.eq("reconcile: and it is the global one, not the pinned one", left[1].pattern, one.pattern)
  match.reconcile_window(win_b, { one, pinned })
  t.eq("reconcile: a second pass is a no-op", #matches_in(win_b), 1)
  -- An untracked and an invalid window are both refused quietly.
  match.clear_window(win_b)
  t.eq("reconcile: precondition -- win_b is untracked and clean again", #matches_in(win_b), 0)
  local ok_rec = pcall(match.reconcile_window, win_b, { one, pinned })
  t.ok("reconcile: an untracked window is a quiet no-op", ok_rec)
  local ok_rec2 = pcall(match.reconcile_window, dead, { one, pinned })
  t.ok("reconcile: a closed window too", ok_rec2)

  -- ---------- remove / clear / refresh ----------
  match.clear()
  t.eq("clear: nothing tracked", match.tracked_windows(), 0)
  t.eq("clear: no matches left in win_a", #matches_in(win_a), 0)
  t.eq("clear: none in win_b either", #matches_in(win_b), 0)

  vim.api.nvim_win_set_buf(win_b, buf_a)
  local two = item(103, "bbb", { slot = 2, hl = "Spotlight2" })
  match.apply_all({ one, two }, prio)
  t.eq("apply_all: win_a has both", #matches_in(win_a), 2)
  t.eq("apply_all: win_b has both", #matches_in(win_b), 2)
  match.remove(one.id)
  t.eq("remove: win_a is down to one", #matches_in(win_a), 1)
  t.eq("remove: win_b is down to one", #matches_in(win_b), 1)
  t.eq("remove: the surviving match is the other item's", matches_in(win_a)[1].group, "Spotlight2")
  t.eq("remove: both windows are still tracked", match.tracked_windows(), 2)
  match.remove(two.id)
  t.eq("remove: emptying a window's entry prunes it from the ledger", match.tracked_windows(), 0)
  match.remove(99999)
  t.eq("remove: an unknown spotlight id is a no-op", match.tracked_windows(), 0)

  match.apply_all({ one }, prio)
  local id_before = matches_in(win_a)[1].id
  match.refresh({ one }, prio)
  t.eq("refresh: still exactly one match per window", #matches_in(win_a), 1)
  t.neq("refresh: with a new match id -- matchadd() has no update form", matches_in(win_a)[1].id, id_before)
  t.eq("refresh: both windows tracked again", match.tracked_windows(), 2)

  -- ---------- a pattern Vim rejects fails silently, and leaves no ledger entry ----------
  match.clear()
  local broken = item(104, "broken")
  broken.pattern = "\\V\\%(" -- an unclosed group: matchadd() refuses this
  local ok_broken = pcall(match.apply_window, win_a, { broken }, prio)
  t.ok("matchadd failure: the caller is not raised at", ok_broken)
  t.eq("matchadd failure: no match was registered", #matches_in(win_a), 0)
  t.eq("matchadd failure: and no ledger entry invented", match.tracked_windows(), 0)
  -- The ledger stays usable afterwards: a good item still lands.
  match.apply_window(win_a, { broken, one }, prio)
  t.eq("matchadd failure: a valid sibling item is still applied", #matches_in(win_a), 1)

  -- ---------- the quickfix window is an ordinary window ----------
  match.clear()
  vim.fn.setqflist({ { filename = "x", lnum = 1, text = "req=aaa" } })
  vim.cmd("copen")
  local qf_win = vim.api.nvim_get_current_win()
  t.eq("precondition: the quickfix window is focused", vim.bo[vim.api.nvim_win_get_buf(qf_win)].buftype, "quickfix")
  match.apply_all({ one }, prio)
  t.eq("eligible: the quickfix window carries spotlight matches -- that is the point of :Spotlight qf", #matches_in(qf_win), 1)
  vim.cmd("cclose")
  vim.fn.setqflist({})

  match.clear()
  vim.api.nvim_win_close(float, true)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  registry.clear()
  config.setup()
end

return M
