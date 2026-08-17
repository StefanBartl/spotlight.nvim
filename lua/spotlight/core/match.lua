---@module 'spotlight.core.match'
---@brief `matchadd()` bookkeeping: `window -> { spotlight id -> match id }`.
---@description
--- The performance-critical decision of this plugin lives here: highlighting is
--- done with |matchadd()|, not with extmarks.
---
--- Extmarks store *positions*, so setting them means scanning the buffer —
--- O(file size) on every add and again on every text change. On a 200 MB log
--- that is not a slow path, it is an unusable one. `matchadd()` instead hands
--- the *pattern* to Vim's renderer, which evaluates it in C over the visible
--- lines only: cost is proportional to the window, independent of the file, and
--- a text change needs no re-scan at all because nothing position-shaped was
--- ever stored.
---
--- The price is that a match is window-local — a `:split` shows the same buffer
--- with no highlights — so this module keeps the ledger that makes it look
--- global: which match id belongs to which spotlight in which window, so a
--- spotlight can be removed from every window it was ever applied to, and a
--- newly opened window can be brought up to date (see
--- `spotlight.bindings.autocmds`).
---
--- The direct consequence, and the reason `spotlight.core.count` is only ever
--- called when the list opens: match *counts* cannot be maintained live without
--- reintroducing exactly the O(file size) scan that picking `matchadd()` avoided.

local lib = require("spotlight.util.lib")
local pattern = require("spotlight.core.pattern")

local M = {}

--- `winid -> { [spotlight id] = match id }`.
---@type table<integer, table<integer, integer>>
local ledger = {}

---@internal
--- Whether `win` should carry spotlight matches.
---
--- Floating windows are skipped: they are transient UI (the spotlight list
--- itself, completion popups, notification toasts), and painting the ledger
--- into them means the highlight outlives nothing and has to be cleaned up when
--- the float closes. Ordinary windows — including the quickfix window, where
--- seeing the spotlight colors is the point of `:Spotlight qf` — are eligible.
---
--- The third check is the per-window opt-out (`spotlight.winopt`): a window
--- carrying `vim.w[win].spotlight_disabled` is skipped regardless of buftype
--- or which buffer it shows. Living here, rather than in a separate check
--- each caller remembers to run, means every fill path — `M.apply_window`,
--- `M.apply_all`/`all_windows` — honours it automatically, including the
--- `BufWinEnter` re-fill that runs on every buffer switch in that window,
--- which is what makes the opt-out survive a `:edit` for free.
---@param win integer
---@return boolean
local function eligible(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  if ok and type(cfg) == "table" and cfg.relative ~= nil and cfg.relative ~= "" then
    return false
  end
  if vim.w[win].spotlight_disabled == true then
    return false
  end
  return true
end

---@internal
--- Every eligible window across all tabpages. Spotlights are session-global, so
--- "all windows" genuinely means all of them, not just the current tabpage's.
---@return integer[]
local function all_windows()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if eligible(win) then
      out[#out + 1] = win
    end
  end
  return out
end

---@internal
--- Add `item` to `win`, recording the resulting match id. No-op if the ledger
--- already has this spotlight in this window, which is what makes a blanket
--- "re-apply everything" cheap and safe to call from an autocmd.
---
--- Buffer-scoped items (`item.scope == "buffer"`) additionally require `win`
--- to be currently showing `item.buf`. This is the one place that check has
--- to live: a buffer-scoped item's pattern is pinned to a line/column, which
--- is only meaningful against the buffer it was recorded from — applying it
--- to a window showing a *different* buffer could, in principle, light up an
--- unrelated line that happens to share the same shape. Global items carry no
--- such restriction, which is the whole point of them (the same request id
--- lighting up in `worker.log` as in `app.log`).
---
--- Line mode (`item.line`) is applied here and nowhere else: `item.pattern`
--- stays the token pattern for every other consumer — counting, quickfix,
--- yank, the occurrence map, navigation — and only the string actually handed
--- to `matchadd()` is widened to the whole line (`core.pattern.line`). Writing
--- the widened form into the item instead would silently redefine what a
--- "match" is for all of them: the count would become lines-not-occurrences,
--- and `core.count.matching_lines_by_item`'s earliest-column tie-break would
--- collapse, since a line pattern always matches at column 1.
---
--- The widened match is also registered one priority below the others. A
--- whole-line highlight covers every token highlight on its line, and the
--- palette exists precisely so several spotlights stay distinguishable — at
--- equal priority the line color would swallow the token colors of every
--- other spotlight sharing that line.
---@param win integer
---@param item Spotlight.Item
---@param priority integer
---@return nil
local function add(win, item, priority)
  if item.scope == "buffer" then
    local ok_buf, winbuf = pcall(vim.api.nvim_win_get_buf, win)
    if not ok_buf or winbuf ~= item.buf then
      return
    end
  end
  local per_win = ledger[win]
  if per_win and per_win[item.id] then
    return
  end
  local pat = item.line and pattern.line(item.pattern) or item.pattern
  local prio = item.line and (priority - 1) or priority
  -- matchadd() acts on the current window and takes no window argument, so the
  -- window is entered for the duration of the call.
  local ok, id = pcall(vim.api.nvim_win_call, win, function()
    return vim.fn.matchadd(item.hl, pat, prio)
  end)
  if not ok or type(id) ~= "number" or id <= 0 then
    -- The one way a spotlight can silently fail to appear: Vim rejected the
    -- pattern, or the window went away between the eligibility check and here.
    lib.debug(
      "match: matchadd failed",
      { win = win, spotlight = item.id, pattern = pat, line = item.line, err = not ok and tostring(id) or nil }
    )
    return
  end
  ledger[win] = per_win or {}
  ledger[win][item.id] = id
end

--- Apply every item in `items` to `win`.
---@param win integer
---@param items Spotlight.Item[]
---@param priority integer
---@return nil
function M.apply_window(win, items, priority)
  if not eligible(win) then
    lib.debug("match: window skipped as ineligible (floating or invalid)", { win = win })
    return
  end
  for _, item in ipairs(items) do
    add(win, item, priority)
  end
end

--- Apply every item in `items` to every eligible window.
---@param items Spotlight.Item[]
---@param priority integer
---@return nil
function M.apply_all(items, priority)
  for _, win in ipairs(all_windows()) do
    M.apply_window(win, items, priority)
  end
end

--- Drop any buffer-scoped match `win` is still carrying for a buffer it no
--- longer shows. `matchadd()` matches belong to the *window*, not the buffer —
--- switching `win` to a different file leaves the old match active and would
--- otherwise keep evaluating a line/column-pinned pattern against content it
--- was never meant to see. Global items are untouched: staying visible across
--- whatever buffer a window shows is their entire design.
---@param win integer
---@param items Spotlight.Item[]
---@return nil
function M.reconcile_window(win, items)
  local per_win = ledger[win]
  if not per_win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local ok, winbuf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok then
    return
  end
  for _, item in ipairs(items) do
    if item.scope == "buffer" and item.buf ~= winbuf then
      local match_id = per_win[item.id]
      if match_id then
        pcall(vim.fn.matchdelete, match_id, win)
        per_win[item.id] = nil
      end
    end
  end
end

--- Remove the spotlight with id `spotlight_id` from every window that has it.
---@param spotlight_id integer
---@return nil
function M.remove(spotlight_id)
  for win, per_win in pairs(ledger) do
    local match_id = per_win[spotlight_id]
    if match_id then
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.fn.matchdelete, match_id, win)
      end
      per_win[spotlight_id] = nil
    end
    if next(per_win) == nil then
      ledger[win] = nil
    end
  end
end

--- Remove every tracked match from every window.
---@return nil
function M.clear()
  for win, per_win in pairs(ledger) do
    if vim.api.nvim_win_is_valid(win) then
      for _, match_id in pairs(per_win) do
        pcall(vim.fn.matchdelete, match_id, win)
      end
    end
    ledger[win] = nil
  end
end

--- Re-apply `items` from scratch: drop every tracked match, then add them all
--- back. Needed when a property baked into the `matchadd()` call itself changes
--- (priority, or a rebuilt pattern) — `matchadd()` has no update form.
---@param items Spotlight.Item[]
---@param priority integer
---@return nil
function M.refresh(items, priority)
  M.clear()
  M.apply_all(items, priority)
end

--- Forget a window's ledger entry without touching Vim state. For `WinClosed`,
--- where the matches are already gone with the window and `matchdelete()` on the
--- stale id would only fail.
---@param win integer
---@return nil
function M.forget_window(win)
  ledger[win] = nil
end

--- Strip every match `win` is carrying right now, without waiting for the next
--- fill pass to skip it. Distinct from `M.forget_window`: that one is for a
--- window that has already *closed*, where `matchdelete()` would only fail;
--- this is for a window that is still open and needs its highlights actually
--- removed — the opt-out case, where gating future fills alone would leave
--- existing matches lit until something else happened to refresh them.
---@param win integer
---@return nil
function M.clear_window(win)
  local per_win = ledger[win]
  if not per_win then
    return
  end
  if vim.api.nvim_win_is_valid(win) then
    for _, match_id in pairs(per_win) do
      pcall(vim.fn.matchdelete, match_id, win)
    end
  end
  ledger[win] = nil
end

--- Number of windows currently carrying at least one match. Diagnostics only
--- (`:checkhealth spotlight`).
---@return integer
function M.tracked_windows()
  local n = 0
  for _ in pairs(ledger) do
    n = n + 1
  end
  return n
end

return M
