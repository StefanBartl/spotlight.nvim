-- TESTS/harness.lua
-- Minimal assertion harness. No plenary, no busted: the suite runs in a plain
-- `nvim --headless -u NONE`, so the only dependency is Neovim itself and CI does
-- not have to install a test framework to lint one plugin.

local M = {}

M.failures = {}
M.passed = 0

--- Report a failure without aborting the run: one broken expectation should not
--- hide the state of every check after it.
---@param name string
---@param msg string
---@return nil
local function fail(name, msg)
  M.failures[#M.failures + 1] = ("%s: %s"):format(name, msg)
end

--- Assert `cond` is truthy.
---@param name string
---@param cond any
---@param msg string|nil
---@return boolean
function M.ok(name, cond, msg)
  if cond then
    M.passed = M.passed + 1
    return true
  end
  fail(name, msg or "expected a truthy value")
  return false
end

--- Assert `got == want`.
---@param name string
---@param got any
---@param want any
---@return boolean
function M.eq(name, got, want)
  if got == want then
    M.passed = M.passed + 1
    return true
  end
  fail(name, ("expected %s, got %s"):format(vim.inspect(want), vim.inspect(got)))
  return false
end

--- Assert `got ~= want`.
---@param name string
---@param got any
---@param want any
---@return boolean
function M.neq(name, got, want)
  if got ~= want then
    M.passed = M.passed + 1
    return true
  end
  fail(name, ("expected anything but %s"):format(vim.inspect(want)))
  return false
end

--- Assert `haystack` contains the literal substring `needle`.
---@param name string
---@param haystack string
---@param needle string
---@return boolean
function M.contains(name, haystack, needle)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    M.passed = M.passed + 1
    return true
  end
  fail(name, ("expected %s to contain %s"):format(vim.inspect(haystack), vim.inspect(needle)))
  return false
end

--- Replace the current buffer's contents and return it as a scratch fixture.
---@param lines string[]
---@return integer bufnr
function M.fixture(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Put the cursor on the first byte of the literal `needle` on line `lnum`.
---@param lnum integer # 1-based.
---@param needle string
---@return boolean placed
function M.cursor_on(lnum, needle)
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
  local s = line:find(needle, 1, true)
  if not s then
    return false
  end
  vim.api.nvim_win_set_cursor(0, { lnum, s - 1 })
  return true
end

return M
