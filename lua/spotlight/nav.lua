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
  local pos = vim.api.nvim_win_get_cursor(0)
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

--- The pattern to navigate by, honouring `nav.scope`.
---@return string|nil
local function nav_pattern()
  local items = registry.all()
  if #items == 0 then
    return nil
  end
  if config.get("nav.scope") == "auto" then
    local here = M.under_cursor()
    if here then
      return here.pattern
    end
  end
  local pats = {}
  for i, item in ipairs(items) do
    pats[i] = item.pattern
  end
  return pattern.alternation(pats)
end

--- Jump one occurrence in `dir`.
---@param dir 1|-1 # 1 forward, -1 backward.
---@return boolean moved, string|nil err
function M.jump(dir)
  local pat = nav_pattern()
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

  local ok, lnum = pcall(vim.fn.search, pat, flags)
  if not ok or type(lnum) ~= "number" or lnum == 0 then
    return false, "no further occurrence"
  end
  if opts.center then
    vim.cmd("normal! zz")
  end
  return true, nil
end

--- Jump to the next occurrence.
---@return boolean moved, string|nil err
function M.next()
  return M.jump(1)
end

--- Jump to the previous occurrence.
---@return boolean moved, string|nil err
function M.prev()
  return M.jump(-1)
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
