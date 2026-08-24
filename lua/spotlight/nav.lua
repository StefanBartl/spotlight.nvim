---@module 'spotlight.nav'
---@brief Jump to the next / previous spotlight occurrence.
---@description
--- Built on |search()| rather than on a collected position list, for the same
--- reason `spotlight.core.match` is built on `matchadd()`: `search()` walks
--- outward from the cursor and stops at the first hit, so a jump costs the
--- distance travelled, not the size of the file. Collecting all positions first
--- would make `]k` an O(buffer) operation on a log where that is the whole
--- problem.
---
--- The search deliberately does not touch the search register or 'hlsearch':
--- spotlights are a parallel marking system, and hijacking `/` state would undo
--- the reason for not using `*` in the first place.
---
--- With `nav.scope = "auto"` (the default), a cursor sitting inside one
--- spotlight's match navigates *that* spotlight only — the intent behind
--- pressing `]k` on a request id is to follow that id, not to land on the next
--- unrelated PID two lines down. Off any match, all spotlights are in scope.

local config = require("spotlight.config")
local lib = require("spotlight.util.lib")
local pattern = require("spotlight.core.pattern")
local registry = require("spotlight.core.registry")

local M = {}

--- The spotlight whose match contains the cursor, if any.
---
--- Answered by scanning the cursor line only, not with `search()`: the question
--- is "am I *inside* a match", and `search()` reports where a match *starts* —
--- with the cursor typically mid-token, even the `c` flag says no. One line's
--- worth of `vim.regex` stepping settles it exactly, and costs nothing regardless
--- of file size.
---@return Spotlight.Item|nil
function M.under_cursor()
  local items = registry.all()
  if #items == 0 then
    return nil
  end
  -- Guarded like the identical read in `spotlight.cursor.token`: this function is
  -- public API, so it can be reached from user code at a moment when window 0 is
  -- not a normal window (from inside a `WinClosed` callback, say) rather than only
  -- from a keymap.
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok then
    return nil
  end
  local row0, col0 = pos[1] - 1, pos[2]
  local line = vim.api.nvim_buf_get_lines(0, row0, row0 + 1, false)[1]
  if not line or line == "" then
    return nil
  end

  for _, item in ipairs(items) do
    local re = pattern.compile(item.pattern)
    if re then
      local offset = 0
      while offset <= #line do
        local s, e = re:match_str(line:sub(offset + 1))
        if not s then
          break
        end
        local abs_s, abs_e = offset + s, offset + e
        if col0 >= abs_s and col0 < abs_e then
          return item
        end
        offset = offset + (e > s and e or s + 1)
      end
    end
  end
  return nil
end

---@internal
--- The pattern to navigate by, honouring `nav.scope`.
---@return string|nil
---@param all_scopes boolean|nil  # ignore `nav.scope` for this call
local function nav_pattern(all_scopes)
  local items = registry.all()
  if #items == 0 then
    return nil
  end
  -- `!` forces the session-wide search. With `nav.scope = "auto"` the whole
  -- point is that `]k` narrows to the spotlight under the cursor -- which is
  -- right until the moment you want the opposite, and then the only way out
  -- was to change the config and reload.
  if not all_scopes and config.get("nav.scope") == "auto" then
    local here = M.under_cursor()
    if here then
      -- "Auto narrowed to one spotlight" vs "searched them all" is the whole
      -- behavioral difference of `]k`, and it is invisible from the outside.
      lib.debug("nav: auto scope narrowed to the spotlight under the cursor", { text = here.text })
      return here.pattern
    end
  end
  local pats = {}
  for i, item in ipairs(items) do
    pats[i] = item.pattern
  end
  lib.debug("nav: searching all spotlights", { count = #pats })
  return pattern.alternation(pats)
end

--- Jump one occurrence in `dir`, `count` times (the `unimpaired` convention:
--- `3]k` is three one-step jumps, not "search for the pattern 3 times faster").
--- Each step re-runs the same one-step `search()`, so a step that finds
--- nothing (wraps with no match, or `search()` returns 0) stops the loop
--- early rather than erroring — a partial jump is still a real jump.
---@param dir 1|-1 # 1 forward, -1 backward.
---@param count integer|nil # defaults to 1.
---@param all_scopes boolean|nil # ignore `nav.scope`, search every spotlight.
---@return boolean moved, string|nil err
function M.jump(dir, count, all_scopes)
  count = (type(count) == "number" and count > 0) and count or 1

  local pat = nav_pattern(all_scopes)
  if not pat then
    return false, "no active spotlights"
  end

  local opts = config.get("nav")
  -- `s` sets the ' mark so `''` returns to where the jump started; `z` starts
  -- the search at the cursor column rather than at column 0, so a second `]k`
  -- on a line with two matches advances instead of re-finding the first.
  local flags = (dir == 1 and "" or "b") .. "sz"
  if not opts.wrap then
    flags = flags .. "W"
  end

  local moved = false
  for _ = 1, count do
    local ok, lnum = pcall(vim.fn.search, pat, flags)
    if not ok or type(lnum) ~= "number" or lnum == 0 then
      break
    end
    moved = true
  end
  if not moved then
    return false, "no further occurrence"
  end
  if opts.center then
    vim.cmd("normal! zz")
  end
  return true, nil
end

--- Jump to the next occurrence, `count` times.
---@param count integer|nil # defaults to 1.
---@return boolean moved, string|nil err
function M.next(count, all_scopes)
  return M.jump(1, count, all_scopes)
end

--- Jump to the previous occurrence, `count` times.
---@param count integer|nil # defaults to 1.
---@return boolean moved, string|nil err
function M.prev(count, all_scopes)
  return M.jump(-1, count, all_scopes)
end

--- Move the cursor to the first occurrence of one specific spotlight, from the
--- top of the buffer. Used by the list, where "jump to this entry" means "show
--- me where it is", not "continue from here".
---@param item Spotlight.Item
---@return boolean moved
function M.goto_first(item)
  local ok, lnum = pcall(vim.fn.search, item.pattern, "sw")
  if not ok or type(lnum) ~= "number" or lnum == 0 then
    return false
  end
  if config.get("nav.center") then
    vim.cmd("normal! zz")
  end
  return true
end

return M
