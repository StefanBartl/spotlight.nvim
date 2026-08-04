---@module 'spotlight.util.path'
---@brief Project-root-relative file keys, used to scope persistence exceptions.
---@description
--- A persistence exception is recorded against the *file path relative to the
--- project root*, not the buffer number: a buffer number is gone the moment the
--- file is closed, and the whole point of the exception is that it survives
--- reopening the same file (and, since the store is keyed per project, moving
--- the checkout to another machine).
---
--- Cross-platform: paths are normalized to forward slashes and the root prefix
--- is compared case-insensitively on Windows, where `C:\Repos\x` and
--- `c:\repos\x` are the same file and would otherwise produce two different
--- exception keys.

local lib = require("spotlight.util.lib")

local M = {}

---@internal
--- Whether the current platform has case-insensitive, backslash-separated paths.
---@return boolean
local function is_windows()
  local cross = lib.try_require("lib.nvim.cross.platform.is_windows")
  if type(cross) == "function" then
    local ok, yes = pcall(cross)
    if ok then
      return yes == true
    end
  end
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

---@internal
--- Normalize a path to forward slashes with no trailing slash.
---@param p string
---@return string
local function slashes(p)
  p = (p:gsub("\\", "/"))
  return (p:gsub("/+$", ""))
end

--- The project root for the current working directory: the git root when there
--- is one, else the cwd. Resolved through `lib.nvim.store.project`, which is the
--- same resolution the store itself uses — so an exception key and the store
--- bucket it lives in can never disagree about what "the project" is.
---@return string
function M.root()
  local store = lib.try_require("lib.nvim.store.project")
  if store and type(store.root) == "function" then
    local ok, root = pcall(store.root)
    if ok and type(root) == "string" and root ~= "" then
      return slashes(root)
    end
  end
  return slashes(vim.fn.getcwd())
end

--- Project-relative key for `bufnr`'s file, or nil for a buffer with no file on
--- disk (a scratch buffer, a terminal, the quickfix window). Callers treat nil
--- as "no exception can apply here", which is the honest answer: there is no
--- stable identity to hang one on.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return string|nil
function M.buffer_key(bufnr)
  bufnr = bufnr or 0
  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok or type(name) ~= "string" or name == "" then
    return nil
  end
  local bt = vim.bo[bufnr].buftype
  if bt ~= "" and bt ~= "acwrite" then
    return nil
  end

  local abs = slashes(vim.fn.fnamemodify(name, ":p"))
  local root = M.root()
  local a, r = abs, root
  if is_windows() then
    a, r = abs:lower(), root:lower()
  end
  if r ~= "" and a:sub(1, #r + 1) == r .. "/" then
    return abs:sub(#root + 2)
  end
  -- Outside the project: keep the absolute path. The exception still works for
  -- this file, it simply is not portable to another checkout — which matches
  -- reality, since the file is not part of the checkout either.
  return abs
end

return M
