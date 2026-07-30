---@module 'spotlight.persist'
---@brief Per-project persistence, with a per-file exception list.
---@description
--- State lives in `lib.nvim.store.project` under the key `spotlight/state`, so
--- reopening the same checkout finds the same spotlights — the store is keyed by
--- git root, not by cwd, so it also survives being opened from a subdirectory.
--- Writes are debounced (`lib.nvim.debounce`) because a burst of toggles is one
--- logical change, and flushed on `VimLeavePre` so the last one is never the one
--- that gets lost. Loading happens once, on `VimEnter`.
---
--- ## What a per-file exception actually suppresses
---
--- This is the question the concept left open, and it has to be answered
--- precisely, because spotlights are session-global while an exception names a
--- *file*. Two readings were possible:
---
---   1. "Do not persist spotlights that *appear* in this file." Not
---      implementable, and not even well-defined: knowing where a pattern
---      appears would mean scanning every file in the project on every save —
---      the exact O(everything) cost this plugin is built to avoid — and the
---      answer would change every time a log rotates.
---   2. "Do not persist spotlights that were *created* while looking at this
---      file." Exact, stable, and cheap: each spotlight records its `origin`
---      (the project-relative path of the buffer it was made in) once, at
---      creation.
---
--- Reading 2 is what is implemented, and it is what the use case actually wants:
--- "I am poking at a customer log full of tokens I do not want written to my
--- cache directory" is a statement about where the tokens came from. A spotlight
--- created in `worker.log` stays persisted even if the same string also appears
--- in an excluded `secrets.log` — its origin is `worker.log`, and nothing about
--- the excluded file changes that.
---
--- The exception list itself is always persisted, even for excluded files.
--- Otherwise `:Spotlight persist off` would not survive a restart, which would
--- make the setting pointless.

require("spotlight.@types")

local config = require("spotlight.config")
local lib = require("spotlight.util.lib")
local path = require("spotlight.util.path")
local registry = require("spotlight.core.registry")

local M = {}

local STORE_KEY = "spotlight/state"
local VERSION = 1

--- `project-relative path -> explicit persist decision for spotlights created
--- in that file`. Absent means "no override, use `persist.default`".
---@type table<string, boolean>
local exceptions = {}

---@type { call: fun(), cancel: fun() }|nil
local saver = nil

--- The `lib.nvim.store.project` module, or nil when lib.nvim is unavailable.
---@return table|nil
local function store()
  local mod = lib.try_require("lib.nvim.store.project")
  if mod and type(mod.save) == "function" and type(mod.load) == "function" then
    return mod
  end
  return nil
end

--- Effective persist decision for a spotlight whose origin is `key`.
--- An explicit override wins; otherwise `persist.default` applies. A spotlight
--- with no origin (created in a scratch buffer, or restored from an older
--- snapshot) follows the default — there is no file to hang an exception on.
---@param key string|nil
---@return boolean
function M.persists(key)
  if key ~= nil and exceptions[key] ~= nil then
    return exceptions[key]
  end
  return config.get("persist.default") == true
end

--- Whether an explicit override exists for `key`.
---@param key string|nil
---@return boolean
function M.has_override(key)
  return key ~= nil and exceptions[key] ~= nil
end

--- The current exception table (read-only by contract). Diagnostics and health.
---@return table<string, boolean>
function M.exceptions()
  return exceptions
end

--- Write the snapshot now, bypassing the debounce.
---@return boolean ok, string|nil err
function M.save_now()
  if config.get("persist.enable") ~= true then
    return false, "persistence disabled"
  end
  local s = store()
  if not s then
    return false, "lib.nvim.store.project unavailable"
  end

  local kept, dropped = {}, {}
  for _, item in ipairs(registry.snapshot()) do
    if M.persists(item.origin) then
      kept[#kept + 1] = item
    else
      dropped[#dropped + 1] = item.text
    end
  end
  -- What the exception model actually did, which is the part users report as
  -- "my spotlights did not come back".
  lib.debug("persist: snapshot filtered", { kept = #kept, dropped = dropped, default = config.get("persist.default") })

  -- Nothing worth keeping: drop the file rather than leaving an empty snapshot
  -- behind, so a cleared session does not restore an empty list over whatever
  -- the user set up in the meantime.
  if #kept == 0 and next(exceptions) == nil then
    if type(s.clear) == "function" then
      pcall(s.clear, STORE_KEY)
    end
    return true, nil
  end

  ---@type Spotlight.Snapshot
  local snapshot = {
    version = VERSION,
    spotlights = kept,
    persist_exceptions = exceptions,
  }
  local ok, err = pcall(s.save, STORE_KEY, snapshot)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

--- Queue a debounced save. Called on every registry change.
---@return nil
function M.save()
  if config.get("persist.enable") ~= true then
    return
  end
  if not saver then
    saver = lib.debounce(function()
      M.save_now()
    end, config.get("persist.debounce_ms"))
  end
  saver.call()
end

--- Load the snapshot and restore spotlights plus the exception list.
---@return integer restored
function M.load()
  if config.get("persist.enable") ~= true then
    return 0
  end
  local s = store()
  if not s then
    return 0
  end
  local ok, data = pcall(s.load, STORE_KEY)
  if not ok or type(data) ~= "table" then
    lib.debug("persist: nothing to load", { key = STORE_KEY, root = path.root(), ok = ok })
    return 0
  end

  if type(data.persist_exceptions) == "table" then
    exceptions = {}
    for key, value in pairs(data.persist_exceptions) do
      if type(key) == "string" and type(value) == "boolean" then
        exceptions[key] = value
      end
    end
  end

  if type(data.spotlights) ~= "table" then
    return 0
  end
  -- Filtered again on load, not only on save: `persist.default` may have been
  -- flipped in the user's config since the snapshot was written, and the
  -- current setting is the one that should decide.
  local allowed = {}
  for _, item in ipairs(data.spotlights) do
    if type(item) == "table" and M.persists(item.origin) then
      allowed[#allowed + 1] = item
    end
  end
  local restored = registry.restore(allowed)
  lib.debug("persist: loaded", {
    root = path.root(),
    stored = #data.spotlights,
    allowed = #allowed,
    restored = restored,
    exceptions = vim.tbl_count(exceptions),
  })
  return restored
end

--- Set the persistence decision for one file.
---@param key string # Project-relative path, from `spotlight.util.path.buffer_key`.
---@param value boolean|nil # nil clears the override, falling back to `persist.default`.
---@return nil
function M.set_exception(key, value)
  exceptions[key] = value
  M.save()
end

--- Subscribe to registry changes. Called once from `setup()`.
---@return nil
function M.setup()
  registry.on_change(function()
    M.save()
  end)
end

--- Flush a pending save. For `VimLeavePre`, where the debounce timer will never
--- get to fire.
---@return nil
function M.flush()
  if saver then
    saver.cancel()
    saver = nil
  end
  if config.get("persist.enable") == true then
    M.save_now()
  end
end

--- Human-readable persistence status for `bufnr`'s file.
---@param bufnr integer|nil
---@return string
function M.status(bufnr)
  if config.get("persist.enable") ~= true then
    return "persistence is disabled globally (persist.enable = false)"
  end
  local key = path.buffer_key(bufnr)
  local default = config.get("persist.default") == true
  if not key then
    return ("this buffer has no file on disk — no per-file override possible; global default: %s"):format(
      default and "on" or "off"
    )
  end
  local effective = M.persists(key)
  if M.has_override(key) then
    return ("%s: %s (explicit override; global default is %s)"):format(
      key,
      effective and "persisted" or "not persisted",
      default and "on" or "off"
    )
  end
  return ("%s: %s (following the global default)"):format(key, effective and "persisted" or "not persisted")
end

return M
