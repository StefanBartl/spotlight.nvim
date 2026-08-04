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
---@param win integer
---@param item Spotlight.Item
---@param priority integer
---@return nil
local function add(win, item, priority)
  local per_win = ledger[win]
  if per_win and per_win[item.id] then
    return
  end
  -- matchadd() acts on the current window and takes no window argument, so the
  -- window is entered for the duration of the call.
  local ok, id = pcall(vim.api.nvim_win_call, win, function()
    return vim.fn.matchadd(item.hl, item.pattern, priority)
  end)
  if not ok or type(id) ~= "number" or id <= 0 then
    -- The one way a spotlight can silently fail to appear: Vim rejected the
    -- pattern, or the window went away between the eligibility check and here.
    lib.debug(
      "match: matchadd failed",
      { win = win, spotlight = item.id, pattern = item.pattern, err = not ok and tostring(id) or nil }
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
