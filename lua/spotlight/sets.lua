---@module 'spotlight.sets'
---@brief Named, saved snapshots of the registry, switched one at a time.
---@description
--- "Spotlight sets" arrived with three open questions: a naming and switching
--- UX, a persistence shape, and whether sets are additive or exclusive. This
--- module resolves all three the same way: a set is a named
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

--- Lazily loaded, session-cached: `name -> Spotlight.StoredItem[]`. Reads
--- share this cache freely; a write forces a fresh read first (`invalidate`)
--- since it writes the whole file back.
---@type table<string, Spotlight.StoredItem[]>|nil
local cache = nil

---@internal
--- The `lib.nvim.store.project` module, or nil when lib.nvim is unavailable.
---@return table|nil
local function store()
  local mod = lib.try_require("lib.nvim.store.project")
  if type(mod) == "table" and type(mod.save) == "function" and type(mod.load) == "function" then
    return mod
  end
  return nil
end

---@internal
--- Load the on-disk sets table into `cache`, once per session. Every field is
--- re-validated, the same treatment as the main persistence snapshot: this
--- file is exactly as untrusted (hand-editable JSON in the cache directory).
---
--- An unreadable/corrupt file and "no sets saved yet" both leave `cache`
--- empty — there is no third return value here for callers to check, and
--- `M.save`/`M.delete` write the WHOLE file back from `cache` (see
--- `save_cache`). Left unreported, a save right after a corrupt load would
--- silently replace a file that actually held other saved sets with one
--- holding only the set just saved. `lib.nvim.cache.disk` already backs up
--- the original bytes before returning the decode failure, so nothing is
--- destroyed on disk, but the user still needs to know their saved sets did
--- not come back before they save or delete anything (ERR-11).
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
  local ok, data, err = pcall(s.load, STORE_KEY)
  if not ok then
    lib.notify(("could not read saved spotlight sets: %s"):format(tostring(data)), vim.log.levels.WARN)
    return cache
  end
  if err then
    lib.notify(("could not read saved spotlight sets: %s"):format(err), vim.log.levels.WARN)
    return cache
  end
  if type(data) ~= "table" or type(data.sets) ~= "table" then
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
--- Force `cache` to be re-read from disk on the next `loaded()` call.
---
--- `cache` has no TTL and nothing else invalidates it, so without this a
--- write from *this* session is based on whatever was on disk when `loaded()`
--- first ran -- possibly long before -- rather than the current file.
--- `save_cache` then writes that stale snapshot back as the WHOLE file, so
--- any set a different running instance saved or deleted in the meantime is
--- silently overwritten by it. Called right before `M.save`/`M.delete`
--- mutate and write: it narrows the race to the gap between this re-read and
--- that write, rather than leaving the cache stale for the rest of the
--- session.
---@return nil
local function invalidate()
  cache = nil
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
---@param name string|nil An invalid name is refused, not raised on.
---@return boolean ok, string|nil err
function M.save(name)
  if type(name) ~= "string" or name == "" then
    return false, "a set needs a name"
  end
  invalidate()
  loaded()[name] = registry.snapshot()
  return save_cache()
end

--- The active spotlights as plain, serializable data: the shape the sets and the
--- persisted snapshot store (`Spotlight.StoredItem[]`), for a host that keeps
--- them somewhere of its own (casedesk.nvim writes them into the case folder).
---
--- Same exclusions as `M.save`: buffer-scoped ("this occurrence only")
--- spotlights are left out, and so are the ones created in a file with an
--- explicit `persist off` override -- that decision is "do not write tokens
--- from this file to disk", and handing them to a host that writes them to
--- disk would defeat it. The global `persist.default` is deliberately NOT
--- consulted: it governs the automatic snapshot, while an export is an
--- explicit request, so a user with `persist.default = false` still gets
--- their spotlights out.
---@return Spotlight.StoredItem[]
function M.export()
  local out = {}
  for _, item in ipairs(registry.snapshot()) do
    if not (persist.has_override(item.origin) and not persist.persists(item.origin)) then
      out[#out + 1] = item
    end
  end
  return out
end

--- Clear the active registry and restore `items` (as `M.export` produced
--- them): exclusive, never a merge. Every field is re-validated by
--- `registry.restore` -- the data may come from a hand-editable file -- so a
--- crafted list cannot inject a pattern or exceed the caps. A non-list value
--- clears and restores nothing.
---
--- Writes the main persisted snapshot afterwards: `registry.restore`
--- deliberately does not fire the change listeners ("a load is not a user
--- edit"), so without this save the imported state would only reach it on some
--- later, unrelated registry change -- a reopen right after could resurrect the
--- pre-import state instead.
---@param items Spotlight.StoredItem[]|nil
---@return integer restored
function M.import(items)
  registry.clear()
  local restored = registry.restore(type(items) == "table" and items or {})
  persist.save_now()
  return restored
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
  -- Re-validated as untrusted input by registry.restore (inside `import`),
  -- exactly like persist.load's own snapshot — this file is the same class of
  -- hand-editable on-disk JSON.
  return M.import(items), nil
end

--- Delete the named set. Never touches the active registry.
---@param name string
---@return boolean ok
function M.delete(name)
  invalidate()
  local c = loaded()
  if not c[name] then
    return false
  end
  c[name] = nil
  save_cache()
  return true
end

return M
