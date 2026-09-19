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

--- Assert `haystack` contains the literal substring `needle`. A non-string
--- `haystack` (typically a `string|nil` error that was never set) fails the
--- assertion rather than raising.
---@param name string
---@param haystack string|nil
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

--- Run `fn` with `package.loaded` entries replaced by doubles, restoring the
--- originals afterwards even if `fn` raises.
---
--- Every seam this suite needs to cut is read through `require` /
--- `lib.try_require` at call time rather than bound to a file-local at load
--- time, so swapping `package.loaded` is enough: the module under test does not
--- have to be reloaded to see the double.
---@param mods table<string, any> # module name -> replacement
---@param fn fun()
---@return nil
function M.with_modules(mods, fn)
  local saved = {}
  for name, replacement in pairs(mods) do
    saved[name] = { value = package.loaded[name], present = package.loaded[name] ~= nil }
    package.loaded[name] = replacement
  end
  local ok, err = pcall(fn)
  for name, entry in pairs(saved) do
    package.loaded[name] = entry.present and entry.value or nil
  end
  if not ok then
    error(err, 0)
  end
end

--- Run `fn` with every module in `names` appearing **not installed** — a
--- `require` for it raises rather than returning something.
---
--- `package.preload` rather than only clearing `package.loaded`: clearing the
--- cache makes the next `require` re-read the module from the runtimepath, where
--- it is still sitting. A preload entry that raises is what a genuinely absent
--- dependency looks like from the caller's side, which is the branch under test.
---@param names string[]
---@param fn fun()
---@return nil
function M.without_modules(names, fn)
  local saved = {}
  for _, name in ipairs(names) do
    saved[name] = { loaded = package.loaded[name], preload = package.preload[name] }
    package.loaded[name] = nil
    package.preload[name] = function()
      error(("module '%s' not installed (TESTS)"):format(name), 0)
    end
  end
  local ok, err = pcall(fn)
  for name, entry in pairs(saved) do
    package.preload[name] = entry.preload
    package.loaded[name] = entry.loaded
  end
  if not ok then
    error(err, 0)
  end
end

--- Collect the `vim.health.*` calls `fn` makes instead of reporting them.
--- `vim.health` is restored afterwards, and a raise inside `fn` is reported
--- rather than propagated — a health check that dies mid-report is itself one of
--- the things under test.
---@param fn fun()
---@return { level: string, msg: string }[] reports, boolean ok, string|nil err
function M.health_reports(fn)
  local reports = {}
  local saved = vim.health
  ---@diagnostic disable-next-line: assign-type-mismatch
  vim.health = setmetatable({}, {
    __index = function(_, level)
      return function(msg)
        reports[#reports + 1] = { level = level, msg = tostring(msg) }
      end
    end,
  })
  local ok, err = pcall(fn)
  vim.health = saved
  return reports, ok, ok and nil or tostring(err)
end

--- Whether any collected health report at `level` contains `needle`.
---@param reports { level: string, msg: string }[]
---@param level string
---@param needle string
---@return boolean
function M.has_report(reports, level, needle)
  for _, r in ipairs(reports) do
    if r.level == level and r.msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

--- Collect `spotlight.util.lib.notify` calls issued during `fn`, by
--- substituting `lib.nvim.notify` for the duration. `lib.notify` resolves it
--- fresh on every call (see `spotlight.util.lib`'s own seam comment), so
--- swapping the module is enough — no reload needed.
---@param fn fun()
---@return { msg: string, level: integer }[] notifications
function M.notifications(fn)
  local records = {}
  local fake = {
    create = function()
      return {
        notify = function(msg, level)
          records[#records + 1] = { msg = msg, level = level }
        end,
      }
    end,
  }
  M.with_modules({ ["lib.nvim.notify"] = fake }, fn)
  return records
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
