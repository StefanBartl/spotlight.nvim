-- Test code: when something here comes back nil -- a buffer key, a resolved
-- root -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/path_spec.lua
-- `spotlight.util.path`: the project-relative file key a persistence exception
-- is recorded against. Nothing else in the suite touched this module, and it is
-- the one place in the plugin that has to be right on two platforms at once.
--
-- Both platform branches are driven on whatever platform the suite runs on, by
-- replacing `lib.nvim.cross.platform.is_windows` at the seam -- otherwise the
-- case-insensitive comparison would only ever be exercised on the developer's
-- machine and never in CI (or the other way round).
--
-- Paths are synthetic and start with `/`, which `fnamemodify(":p")` treats as
-- already absolute on Windows as well as on Linux, so no assertion here depends
-- on the host's drive letters or on a file existing.

local t = require("harness")

local M = {}

local STORE = "lib.nvim.store.project"
local IS_WINDOWS = "lib.nvim.cross.platform.is_windows"

---@internal
--- A named, ordinary buffer. `buftype` stays "" so `buffer_key` accepts it.
---@param name string
---@return integer bufnr
local function named_buffer(name)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

function M.run()
  local config = require("spotlight.config")
  local path = require("spotlight.util.path")

  config.setup()

  -- ---------- root() ----------
  local cwd = (vim.fn.getcwd():gsub("\\", "/"))
  t.eq("root: resolves through the store, which is installed here", path.root(), cwd)

  t.with_modules({ [STORE] = {
    root = function()
      return "C:\\Repos\\Proj\\"
    end,
  } }, function()
    t.eq("root: backslashes are folded and the trailing slash stripped", path.root(), "C:/Repos/Proj")
  end)

  t.with_modules({ [STORE] = {
    root = function()
      return "/srv/logs///"
    end,
  } }, function()
    t.eq("root: several trailing slashes go too", path.root(), "/srv/logs")
  end)

  -- Each degenerate answer from the store falls back to the cwd rather than
  -- producing a root of "" -- which would make every key look project-relative.
  t.with_modules({ [STORE] = {
    root = function()
      return ""
    end,
  } }, function()
    t.eq("root: an empty answer falls back to the cwd", path.root(), cwd)
  end)
  t.with_modules({ [STORE] = {
    root = function()
      return 42
    end,
  } }, function()
    t.eq("root: a non-string answer falls back", path.root(), cwd)
  end)
  t.with_modules({ [STORE] = {
    root = function()
      error("no git here")
    end,
  } }, function()
    t.eq("root: a raising store falls back", path.root(), cwd)
  end)
  t.with_modules({ [STORE] = { load = function() end } }, function()
    t.eq("root: a store without a root() function falls back", path.root(), cwd)
  end)
  t.without_modules({ STORE }, function()
    t.eq("root: no store at all falls back", path.root(), cwd)
  end)

  -- ---------- buffer_key: the buffers that have no key ----------
  local scratch = vim.api.nvim_create_buf(false, true)
  t.eq("buffer_key: a nameless scratch buffer has no key", path.buffer_key(scratch), nil)

  local term_like = named_buffer("/proj/term-ish.log")
  vim.bo[term_like].buftype = "nofile"
  t.eq("buffer_key: a nofile buftype has no key, name or not", path.buffer_key(term_like), nil)
  vim.bo[term_like].buftype = "quickfix"
  t.eq("buffer_key: a quickfix buftype has no key either", path.buffer_key(term_like), nil)
  -- `acwrite` is the one non-empty buftype that does get a key: it is a real
  -- file path written through a plugin's own BufWriteCmd.
  vim.bo[term_like].buftype = "acwrite"
  t.ok("buffer_key: an acwrite buffer does get one", path.buffer_key(term_like) ~= nil)
  vim.bo[term_like].buftype = ""

  t.eq("buffer_key: an invalid buffer number is nil, not an error", path.buffer_key(999999), nil)

  -- ---------- buffer_key: inside and outside the project ----------
  local root = "/proj/checkout"
  local inside = named_buffer(root .. "/logs/app.log")
  local nested = named_buffer(root .. "/a/b/c/deep.log")
  local outside = named_buffer("/elsewhere/other.log")
  -- The sibling directory whose name merely *starts* with the root: the `.. "/"`
  -- in the prefix test is what stops this from being reported as
  -- project-relative, which would produce a key beginning with "2/".
  local sibling = named_buffer(root .. "2/trap.log")

  t.with_modules({ [STORE] = {
    root = function()
      return root
    end,
  } }, function()
    t.eq("buffer_key: a file under the root becomes a relative key", path.buffer_key(inside), "logs/app.log")
    t.eq("buffer_key: nesting is preserved", path.buffer_key(nested), "a/b/c/deep.log")
    t.eq("buffer_key: a file outside the project keeps its absolute path", path.buffer_key(outside), "/elsewhere/other.log")
    t.eq(
      "buffer_key: a sibling directory sharing the root's prefix is NOT relativized",
      path.buffer_key(sibling),
      root .. "2/trap.log"
    )
  end)

  -- A root handed over with a trailing slash must produce the same key, since
  -- `root()` normalizes it before the comparison.
  t.with_modules({ [STORE] = {
    root = function()
      return root .. "/"
    end,
  } }, function()
    t.eq("buffer_key: a trailing slash on the root changes nothing", path.buffer_key(inside), "logs/app.log")
  end)

  -- ---------- buffer_key: the two platform branches ----------
  --
  -- On Windows `C:\Repos\x` and `c:\repos\x` are the same file, so the prefix
  -- comparison is case-insensitive there and case-sensitive everywhere else.
  -- Both are driven here regardless of the host.
  local mixed_case_root = "/PROJ/CHECKOUT"
  t.with_modules({
    [STORE] = {
      root = function()
        return mixed_case_root
      end,
    },
    [IS_WINDOWS] = function()
      return true
    end,
  }, function()
    t.eq("buffer_key/windows: the prefix match ignores case", path.buffer_key(inside), "logs/app.log")
    -- And the key keeps the *buffer's* own case, not the root's -- the slice is
    -- taken from the original path, not from the lowercased comparison copy.
    t.eq("buffer_key/windows: the returned key is not lowercased", path.buffer_key(nested), "a/b/c/deep.log")
  end)

  t.with_modules({
    [STORE] = {
      root = function()
        return mixed_case_root
      end,
    },
    [IS_WINDOWS] = function()
      return false
    end,
  }, function()
    t.eq(
      "buffer_key/posix: a case difference means a different directory, so the absolute path is kept",
      path.buffer_key(inside),
      root .. "/logs/app.log"
    )
  end)

  -- A raising platform probe must not take the key with it: the native
  -- `has('win32')` answer is the fallback.
  t.with_modules({
    [STORE] = {
      root = function()
        return root
      end,
    },
    [IS_WINDOWS] = function()
      error("probe exploded")
    end,
  }, function()
    t.eq("buffer_key: a raising platform probe falls back to has('win32')", path.buffer_key(inside), "logs/app.log")
  end)

  -- Same for a platform module that is not a function at all.
  t.with_modules({
    [STORE] = {
      root = function()
        return root
      end,
    },
    [IS_WINDOWS] = { not_a_function = true },
  }, function()
    t.eq("buffer_key: a non-function platform module falls back too", path.buffer_key(inside), "logs/app.log")
  end)

  t.without_modules({ IS_WINDOWS }, function()
    t.with_modules({ [STORE] = {
      root = function()
        return root
      end,
    } }, function()
      t.eq("buffer_key: no platform module at all still works", path.buffer_key(inside), "logs/app.log")
    end)
  end)

  -- ---------- buffer_key(nil) is the current buffer ----------
  vim.api.nvim_set_current_buf(inside)
  t.with_modules({ [STORE] = {
    root = function()
      return root
    end,
  } }, function()
    t.eq("buffer_key(nil): defaults to the current buffer", path.buffer_key(nil), "logs/app.log")
    t.eq("buffer_key(0): the same", path.buffer_key(0), "logs/app.log")
  end)

  local back = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(back)
  for _, b in ipairs({ scratch, term_like, inside, nested, outside, sibling }) do
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
  config.setup()
end

return M
