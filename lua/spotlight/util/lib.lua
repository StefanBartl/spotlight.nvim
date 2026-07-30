---@module 'spotlight.util.lib'
---@brief Soft, guarded bridge to a handful of `lib.nvim` helpers.
---@description
--- `lib.nvim` is a **required** dependency — the `:Spotlight` verb is built on
--- `lib.nvim.usercmd.composer`, persistence on `lib.nvim.store.project`, the
--- list on `lib.nvim.ui.kit.select`. These specific accessors nonetheless stay
--- soft-guarded, because each has a usable native equivalent: a missing
--- `lib.nvim.notify` should degrade a message to `vim.notify`, not break the
--- keymap that wanted to report success.
---@see spotlight-lib

local M = {}

--- Resolve a sub-module of `lib` once, swallowing load errors. Accepts both
--- table modules (`lib.nvim.notify`) and bare function modules (`lib.nvim.map`
--- returns a function, not a table).
---@param name string
---@return table|function|nil
local function try_require(name)
  local ok, mod = pcall(require, name)
  if ok and (type(mod) == "table" or type(mod) == "function") then
    return mod
  end
  return nil
end

M.try_require = try_require

--- Notify the user. Uses `lib.nvim.notify` if available, else `vim.notify`.
---@param msg string
---@param level integer|nil # vim.log.levels.*; defaults to INFO
---@return nil
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  local lib = try_require("lib.nvim.notify")
  if lib and type(lib.create) == "function" then
    local ok, notifier = pcall(lib.create, "[spotlight]")
    if ok and type(notifier) == "table" and type(notifier.notify) == "function" then
      if pcall(notifier.notify, msg, level) then
        return
      end
    end
  end
  vim.notify(("[spotlight] %s"):format(msg), level)
end

--- Cached `lib.nvim.logger` instance (`false` once probed absent, so the check
--- is never retried).
---@type table|false|nil
local _logger = nil

--- Resolve (and cache) the `lib.nvim.logger` instance, or `false` if absent.
---@return table|false
local function logger()
  if _logger ~= nil then
    return _logger
  end
  local lib = try_require("lib.nvim.logger")
  if lib and type(lib.new) == "function" then
    local ok, inst = pcall(lib.new, { name = "spotlight" })
    _logger = (ok and type(inst) == "table") and inst or false
  else
    _logger = false
  end
  return _logger
end

--- Debug-log `msg` (plus optional structured `ctx`) at spotlight's decision
--- points, when `debug` is enabled in the config.
---
--- The interesting question in this plugin is never "what does the code do" but
--- "why did nothing light up" — which token did the resolver actually pick, was
--- the pattern applied to this window or skipped as ineligible, did the snapshot
--- filter drop the spotlight before writing. Those are exactly the points that
--- log here, so a report can be answered from the log rather than from guessing.
---
--- Reads the config lazily rather than taking an `enabled` argument, so a call
--- site does not have to thread the flag through. The common case (debug off)
--- costs one table lookup.
---
--- Bridges to `lib.nvim.logger` (one cached "spotlight" instance, inspectable
--- with `:LibLogger`) when available; falls back to `vim.notify` at DEBUG level,
--- since there is no native substitute for a structured logger but debug output
--- should still be visible rather than silently dropped.
---@param msg string
---@param ctx table|nil
---@return nil
function M.debug(msg, ctx)
  -- Required lazily: spotlight.config requires nothing from this module, but
  -- requiring it at the top here would still make the dependency circular-looking
  -- to a reader and pointless to resolve at load time.
  local ok, config = pcall(require, "spotlight.config")
  if not ok or config.get("debug") ~= true then
    return
  end
  local log = logger()
  if log then
    pcall(log.debug, msg, ctx)
    return
  end
  local text = ctx and ("%s %s"):format(msg, vim.inspect(ctx)) or msg
  vim.notify(("[spotlight] %s"):format(text), vim.log.levels.DEBUG)
end

--- Whether `lib.nvim.logger` is available (for `:checkhealth` reporting).
---@return boolean
function M.has_logger()
  return logger() ~= false
end

--- Set a keymap. Uses `lib.nvim.map` if available, else `vim.keymap.set`.
---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts table|nil
---@return nil
function M.map(mode, lhs, rhs, opts)
  opts = opts or {}
  local lib = try_require("lib.nvim.map")
  if type(lib) == "function" then
    if pcall(lib, mode, lhs, rhs, opts) then
      return
    end
  end
  vim.keymap.set(mode, lhs, rhs, opts)
end

--- Create (and clear) an autocommand group. Returns the group id.
---@param name string
---@return integer
function M.augroup(name)
  local lib = try_require("lib.nvim.autocmd.augroup")
  if lib and type(lib.create) == "table" and type(lib.create.clear) == "function" then
    local ok, id = pcall(lib.create.clear, name)
    if ok and type(id) == "number" then
      return id
    end
  end
  return vim.api.nvim_create_augroup(name, { clear = true })
end

--- Register an autocommand. Uses `lib.nvim.autocmd` (which wraps the callback
--- in a `pcall` and reports failures) if available, else the native API.
---@param event string|string[]
---@param callback fun(args: table)
---@param opts table
---@return nil
function M.autocmd(event, callback, opts)
  local lib = try_require("lib.nvim.autocmd")
  if lib and type(lib.create) == "function" then
    if pcall(lib.create, event, callback, opts) then
      return
    end
  end
  vim.api.nvim_create_autocmd(event, {
    group = opts.group,
    pattern = opts.pattern,
    desc = opts.desc,
    callback = function(args)
      pcall(callback, args)
    end,
  })
end

--- Set a highlight group. Uses `lib.nvim.ui.hl` if available, else
--- `nvim_set_hl` in the global namespace.
---@param group string
---@param opts table
---@return nil
function M.hl(group, opts)
  local lib = try_require("lib.nvim.ui.hl")
  if lib and type(lib.set) == "function" then
    if pcall(lib.set, group, opts) then
      return
    end
  end
  pcall(vim.api.nvim_set_hl, 0, group, opts)
end

--- Create a debounced-call handle. Uses `lib.nvim.debounce` if available, else
--- a local libuv timer with the same `{ call, cancel }` contract (including the
--- `vim.schedule` hop — libuv timer callbacks run off the main loop, where
--- touching `vim.api.*` is unsafe).
---@param fn fun(...: any)
---@param ms integer
---@return { call: fun(...: any), cancel: fun() }
function M.debounce(fn, ms)
  local lib = try_require("lib.nvim.debounce")
  if lib and type(lib.new) == "function" then
    local ok, handle = pcall(lib.new, fn, ms)
    if ok and type(handle) == "table" and type(handle.call) == "function" then
      return handle
    end
  end

  local uv = vim.uv or vim.loop
  local timer = nil
  return {
    call = function(...)
      local args = { ... }
      local n = select("#", ...)
      if timer then
        pcall(timer.stop, timer)
      else
        timer = uv.new_timer()
      end
      timer:start(ms, 0, function()
        vim.schedule(function()
          fn(unpack(args, 1, n))
        end)
      end)
    end,
    cancel = function()
      if timer then
        pcall(timer.stop, timer)
        pcall(timer.close, timer)
        timer = nil
      end
    end,
  }
end

return M
