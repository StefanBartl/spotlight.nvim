---@module 'spotlight.sets'
---@brief Named, saved snapshots of the registry, switched one at a time.
---@description
--- The roadmap left "spotlight sets" with three open questions: a naming and
--- switching UX, a persistence shape, and whether sets are additive or
--- exclusive. This resolves all three the same way: a set is a named
--- snapshot of the registry, taken with `M.save`; `M.switch` clears the
--- active spotlights and restores that snapshot. Exclusive, not additive —
--- switching is meant to feel like opening a saved workspace, not layering
--- one investigation's tokens on top of another's. Nothing stops adding more
--- spotlights *after* switching; only the switch itself replaces.
---
--- Persisted under a second, independent `lib.nvim.store.project` key
--- ("spotlight/sets") alongside the main "spotlight/state" — unrelated to
--- per-file persistence and its exception list, and with none of that
--- module's debounce: `sets save`/`switch`/`delete` are rare, deliberate
--- commands, not a hot toggle path, so every mutation writes synchronously.

require("spotlight.@types")

local lib = require("spotlight.util.lib")
local persist = require("spotlight.persist")
local registry = require("spotlight.core.registry")

local M = {}

local STORE_KEY = "spotlight/sets"
local VERSION = 1

--- Lazily loaded, session-cached: `name -> Spotlight.StoredItem[]`.
---@type table<string, Spotlight.StoredItem[]>|nil
local cache = nil

---@internal
--- The `lib.nvim.store.project` module, or nil when lib.nvim is unavailable.
---@return table|nil
local function store()
  local mod = lib.try_require("lib.nvim.store.project")
  if mod and type(mod.save) == "function" and type(mod.load) == "function" then
    return mod
  end
  return nil
end

---@internal
--- Load the on-disk sets table into `cache`, once per session. Every field is
--- re-validated, the same treatment as the main persistence snapshot: this
--- file is exactly as untrusted (hand-editable JSON in the cache directory).
---@return table<string, Spotlight.StoredItem[]>
local function loaded()
  if cache then
    return cache
  end
  cache = {}
  local s = store()
  if not s then
    return cache
  end
  local ok, data = pcall(s.load, STORE_KEY)
  if not ok or type(data) ~= "table" or type(data.sets) ~= "table" then
    return cache
  end
  for name, items in pairs(data.sets) do
    if type(name) == "string" and type(items) == "table" then
      cache[name] = items
    end
  end
  return cache
end

---@internal
--- Write `cache` to disk synchronously.
---@return boolean ok, string|nil err
local function save_cache()
  local s = store()
  if not s then
    return false, "lib.nvim.store.project unavailable"
  end
  local ok, err = pcall(s.save, STORE_KEY, { version = VERSION, sets = loaded() })
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

--- Every saved set's name, sorted — for `:Spotlight sets list` and tab
--- completion.
---@return string[]
function M.names()
  local names = {}
  for name in pairs(loaded()) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- How many spotlights `name` holds, or nil if no set by that name exists.
--- (A saved set can legitimately hold zero — `M.save` does not refuse an
--- empty registry — so this distinguishes "empty" from "absent" the same way
--- `core.count.M.count` distinguishes "zero matches" from "not counted".)
---@param name string
---@return integer|nil
function M.count(name)
  local items = loaded()[name]
  return items and #items or nil
end

--- Snapshot the current registry under `name`, overwriting it if a set by
--- that name already exists. Buffer-scoped ("this occurrence only")
--- spotlights are excluded, the same as the main persistence snapshot and
--- for the same reason — a line/column pin can't meaningfully belong to a
--- saved set any more than it can survive a restart.
---@param name string
---@return boolean ok, string|nil err
function M.save(name)
  if type(name) ~= "string" or name == "" then
    return false, "a set needs a name"
  end
  loaded()[name] = registry.snapshot()
  return save_cache()
end

--- Clear the active registry and restore the named set.
---
--- Refuses — without touching the active registry — if `name` does not
--- exist: an unknown or mistyped name has to be a no-op, never data loss,
--- since this is an otherwise-destructive operation by design.
---@param name string
---@return integer restored, string|nil err
function M.switch(name)
  local items = loaded()[name]
  if not items then
    return 0, ("no such set: %s"):format(tostring(name))
  end
  registry.clear()
  -- Re-validated as untrusted input by registry.restore, exactly like
  -- persist.load's own snapshot — this file is the same class of
  -- hand-editable on-disk JSON.
  local restored = registry.restore(items)
  -- registry.restore deliberately does not fire notify_change() ("a load is
  -- not a user edit"), so without this explicit save the switched-to state
  -- would only reach the main persisted snapshot on some later, unrelated
  -- registry change — a reopen right after switching could otherwise
  -- resurrect the pre-switch state instead of the one just restored.
  persist.save_now()
  return restored, nil
end

--- Delete the named set. Never touches the active registry.
---@param name string
---@return boolean ok
function M.delete(name)
  local c = loaded()
  if not c[name] then
    return false
  end
  c[name] = nil
  save_cache()
  return true
end

return M
