-- Test code: when something here comes back nil -- a stored snapshot, a saved
-- key -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- Several cases hand in malformed stored data on purpose -- a non-boolean
-- exception, a non-table entry, a numeric key -- to check that load drops them.
-- TESTS/persist_store_spec.lua
-- The persistence *store* round trip, which `persist_spec.lua` deliberately
-- leaves alone: it covers the exception semantics, this covers what actually
-- reaches and comes back from `lib.nvim.store.project`.
--
-- Nothing here touches the real store. A recording double is installed at the
-- `package.loaded` seam (`persist` resolves the store per call, so no reload is
-- needed), which is also what makes the failure arms reachable: a store that
-- raises on save, a store that is not installed at all, a snapshot that was
-- hand-edited into the wrong shape.

local t = require("harness")

local M = {}

local STORE = "lib.nvim.store.project"
local DEBOUNCE = "lib.nvim.debounce"
local KEY = "spotlight/state"

---@internal
--- A recording stand-in for `lib.nvim.store.project`.
---@return table
local function fake_store()
  local s = { data = {}, saves = 0, loads = 0, clears = 0 }
  s.root = function()
    return "/proj/fake"
  end
  s.save = function(key, data)
    s.saves = s.saves + 1
    s.data[key] = vim.deepcopy(data)
    return true
  end
  s.load = function(key)
    s.loads = s.loads + 1
    return s.data[key]
  end
  s.clear = function(key)
    s.clears = s.clears + 1
    s.data[key] = nil
  end
  return s
end

--- A debounce that is not one: the callback runs on `call()`, so a save can be
--- asserted on synchronously instead of waiting on a timer.
---@return table
local function sync_debounce()
  return {
    new = function(fn)
      return {
        call = function(...)
          fn(...)
        end,
        cancel = function() end,
      }
    end,
  }
end

function M.run()
  local config = require("spotlight.config")
  local persist = require("spotlight.persist")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()

  -- Drop whatever debounce handle an earlier spec created, so the synchronous
  -- double below is the one that gets built. Done against a throwaway store so
  -- the flush cannot reach the real one.
  t.with_modules({ [STORE] = fake_store() }, function()
    persist.flush()
  end)

  -- ---------- save_now: the gates ----------
  config.setup({ persist = { enable = false } })
  local ok_disabled, err_disabled = persist.save_now()
  t.eq("save_now: refused while persistence is off", ok_disabled, false)
  t.contains("save_now: and says why", err_disabled, "persistence disabled")

  config.setup({ persist = { enable = true, default = true } })
  t.without_modules({ STORE }, function()
    local ok_nostore, err_nostore = persist.save_now()
    t.eq("save_now: refused without the store module", ok_nostore, false)
    t.contains("save_now: naming the module it needs", err_nostore, "lib.nvim.store.project")
  end)

  -- ---------- save_now: what reaches the store ----------
  local store = fake_store()
  t.with_modules({ [STORE] = store }, function()
    -- A clean slate for the exception table, which is module state shared with
    -- persist_spec: `load` is the only thing that resets it.
    store.data[KEY] = { version = 1, spotlights = {}, persist_exceptions = {} }
    persist.load()
    t.eq("load: the exception table was reset", vim.tbl_count(persist.exceptions()), 0)

    registry.clear()
    registry.add({ text = "kept-one", kind = "literal" }, { origin = "logs/a.log" })
    registry.add({ text = "kept-two", kind = "literal" }, { origin = false })
    store.saves = 0
    local ok, err = persist.save_now()
    t.eq("save_now: succeeded", ok, true)
    t.eq("save_now: no error", err, nil)
    t.eq("save_now: wrote exactly once", store.saves, 1)

    local snap = store.data[KEY]
    t.eq("save_now: the snapshot carries a version", snap.version, 1)
    t.eq("save_now: both spotlights are in it", #snap.spotlights, 2)
    t.eq("save_now: with their text", snap.spotlights[1].text, "kept-one")
    t.eq("save_now: their slot", type(snap.spotlights[1].slot), "number")
    t.eq("save_now: their kind, recovered from the pattern", snap.spotlights[1].kind, "literal")
    t.eq("save_now: their origin", snap.spotlights[1].origin, "logs/a.log")
    t.eq("save_now: an origin-less item stores no origin", snap.spotlights[2].origin, nil)
    t.eq("save_now: and the exception table travels along", type(snap.persist_exceptions), "table")

    -- A buffer-scoped item is session-only and must not appear.
    local buf = t.fixture({ "req=pinned" })
    registry.add_at({ text = "req=pinned", kind = "literal" }, { buf = buf, row1 = 1, col1 = 5 })
    persist.save_now()
    t.eq("save_now: a position-pinned spotlight is left out of the snapshot", #store.data[KEY].spotlights, 2)

    -- The origin filter, at save time.
    persist.set_exception("logs/a.log", false)
    persist.save_now()
    local filtered = store.data[KEY]
    t.eq("save_now: the excluded file's spotlight is dropped", #filtered.spotlights, 1)
    t.eq("save_now: the surviving one is the other", filtered.spotlights[1].text, "kept-two")
    t.eq(
      "save_now: the exception itself is persisted, or 'persist off' would not survive",
      filtered.persist_exceptions["logs/a.log"],
      false
    )

    -- Nothing worth keeping *and* no exceptions: the file is dropped rather than
    -- left behind empty, so a cleared session cannot restore an empty list over
    -- whatever the user set up since.
    persist.set_exception("logs/a.log", nil)
    registry.clear()
    store.clears = 0
    local ok_empty = persist.save_now()
    t.eq("save_now: an empty registry with no exceptions still reports success", ok_empty, true)
    t.eq("save_now: and clears the stored key instead of writing an empty snapshot", store.clears, 1)
    t.eq("save_now: nothing is left on disk", store.data[KEY], nil)

    -- An exception alone is worth a file, though.
    persist.set_exception("logs/only-an-exception.log", false)
    persist.save_now()
    t.ok("save_now: an exception with no spotlights is still written", store.data[KEY] ~= nil)
    t.eq("save_now: with an empty spotlight list", #store.data[KEY].spotlights, 0)
    persist.set_exception("logs/only-an-exception.log", nil)
    registry.clear()
    persist.save_now()
  end)

  -- A store whose save raises is reported, not propagated.
  t.with_modules({
    [STORE] = {
      load = function() end,
      save = function()
        error("disk full")
      end,
    },
  }, function()
    registry.clear()
    registry.add({ text = "will-not-land", kind = "literal" }, { origin = "logs/x.log" })
    local ok, err = persist.save_now()
    t.eq("save_now: a raising store is reported as a failure", ok, false)
    t.contains("save_now: with the underlying message", err, "disk full")
  end)

  -- A store with no clear() at all must not break the drop-the-file path.
  t.with_modules({ [STORE] = { load = function() end, save = function() end } }, function()
    registry.clear()
    local ok = persist.save_now()
    t.eq("save_now: a store without clear() still reports success", ok, true)
  end)

  -- ---------- load ----------
  config.setup({ persist = { enable = false } })
  t.eq("load: returns 0 while persistence is off", persist.load(), 0)
  config.setup({ persist = { enable = true, default = true } })

  t.without_modules({ STORE }, function()
    t.eq("load: returns 0 without the store module", persist.load(), 0)
  end)
  -- The quiet case must stay quiet: a project with nothing persisted yet is
  -- not an error, and must not warn just because the result is empty.
  t.with_modules({ [STORE] = { save = function() end, load = function() end } }, function()
    local notifications = t.notifications(function()
      t.eq("load: no snapshot at all is 0", persist.load(), 0)
    end)
    t.eq("load: and stays silent -- 'nothing yet' is not 'broken'", #notifications, 0)
  end)
  t.with_modules(
    { [STORE] = {
      save = function() end,
      load = function()
        error("unreadable")
      end,
    } },
    function()
      local notifications = t.notifications(function()
        local restored, err = persist.load()
        t.eq("load: a raising store is 0, not a crash", restored, 0)
        t.contains("load: and reports the underlying message", err or "", "unreadable")
      end)
      t.eq("load: a raising store still warns the user (ERR-11)", #notifications, 1)
      t.eq("load: at WARN level", notifications[1].level, vim.log.levels.WARN)
    end
  )
  t.with_modules(
    { [STORE] = {
      save = function() end,
      load = function()
        return "not a table"
      end,
    } },
    function()
      t.eq("load: a non-table snapshot is 0", persist.load(), 0)
    end
  )
  -- ERR-11: a snapshot file that exists but could not be decoded (what
  -- `lib.nvim.cache.disk` reports after backing up the original bytes to
  -- `.corrupt`) must not look like "no snapshot yet" -- both currently
  -- return `0`, but only the corrupt case is worth telling the user about.
  t.with_modules({
    [STORE] = {
      save = function() end,
      load = function()
        return nil, "invalid json: original kept at /fake/state.json.corrupt"
      end,
    },
  }, function()
    local notifications = t.notifications(function()
      local restored, err = persist.load()
      t.eq("load: a corrupt snapshot restores 0, same as no snapshot", restored, 0)
      t.contains("load: but the error is returned", err or "", "invalid json")
    end)
    t.eq("load: exactly one warning for the corrupt snapshot", #notifications, 1)
    t.eq("load: at WARN level", notifications[1].level, vim.log.levels.WARN)
    t.contains("load: naming the underlying decode failure", notifications[1].msg, "invalid json")
  end)

  local store2 = fake_store()
  t.with_modules({ [STORE] = store2 }, function()
    registry.clear()
    store2.data[KEY] = {
      version = 1,
      spotlights = {
        { text = "from-a", slot = 1, kind = "word", origin = "logs/a.log" },
        { text = "from-b", slot = 2, kind = "literal", origin = "logs/b.log" },
        { text = "no-origin", slot = 3, kind = "literal" },
        "not a table",
      },
      persist_exceptions = {
        ["logs/a.log"] = false,
        ["logs/ok.log"] = true,
        ["logs/bad.log"] = "yes",
        [7] = true,
      },
    }
    local restored = persist.load()
    t.eq("load: the excluded file's spotlight is filtered out again on load", restored, 2)
    t.eq("load: the registry holds exactly those", registry.count(), 2)
    t.ok("load: from-b came back", registry.find_by_text("from-b") ~= nil)
    t.ok("load: no-origin came back", registry.find_by_text("no-origin") ~= nil)
    t.eq("load: from-a did not", registry.find_by_text("from-a"), nil)
    t.eq("load: a non-boolean exception value is dropped", persist.exceptions()["logs/bad.log"], nil)
    t.eq("load: a non-string exception key is dropped", persist.exceptions()[7], nil)
    t.eq("load: the well-formed exceptions are kept", persist.exceptions()["logs/ok.log"], true)
    t.eq("load: including the false one", persist.exceptions()["logs/a.log"], false)
    t.eq(
      "load: a literal entry comes back without word boundaries",
      registry.find_by_text("from-b").pattern:find("\\<", 1, true),
      nil
    )
    -- And the word kind round-trips into `\<`/`\>`, rebuilt from `kind` rather
    -- than read from the file.
    registry.clear()
    store2.data[KEY] = {
      version = 1,
      spotlights = { { text = "worded", slot = 1, kind = "word", origin = "logs/b.log" } },
      persist_exceptions = {},
    }
    persist.load()
    t.ok("load: a word entry comes back with boundaries", registry.find_by_text("worded").pattern:find("\\<", 1, true) ~= nil)

    -- The current `persist.default` decides, not the one in force when the
    -- snapshot was written: flipping it to opt-in drops everything without an
    -- explicit `true` override.
    config.setup({ persist = { enable = true, default = false } })
    local restored_optin = persist.load()
    t.eq("load: with default = false only explicitly opted-in files come back", restored_optin, 0)
    config.setup({ persist = { enable = true, default = true } })

    -- A snapshot whose `spotlights` is the wrong shape still applies its
    -- exceptions -- the exception list is the half that must survive.
    registry.clear()
    store2.data[KEY] = { version = 1, spotlights = "broken", persist_exceptions = { ["logs/kept.log"] = false } }
    t.eq("load: a malformed spotlight list yields 0", persist.load(), 0)
    t.eq("load: but the exceptions were still applied", persist.exceptions()["logs/kept.log"], false)

    -- A snapshot with no exception key at all leaves the current table alone.
    store2.data[KEY] = { version = 1, spotlights = {} }
    persist.load()
    t.eq("load: a snapshot without an exception key does not wipe the current one", persist.exceptions()["logs/kept.log"], false)

    -- Reset for the specs that follow.
    store2.data[KEY] = { version = 1, spotlights = {}, persist_exceptions = {} }
    persist.load()
    t.eq("load: the exception table is reset again", vim.tbl_count(persist.exceptions()), 0)
  end)

  -- ---------- save(): the debounced path, and setup()'s subscription ----------
  local store3 = fake_store()
  t.with_modules({ [STORE] = store3, [DEBOUNCE] = sync_debounce() }, function()
    persist.flush()
    registry.clear()
    store3.saves = 0
    persist.setup()
    registry.add({ text = "through-the-listener", kind = "literal" }, { origin = "logs/z.log" })
    t.ok("setup: a registry change reaches the store through the debounce", store3.saves >= 1)

    store3.saves = 0
    config.setup({ persist = { enable = false } })
    persist.save()
    t.eq("save: queues nothing while persistence is off", store3.saves, 0)
    config.setup({ persist = { enable = true, default = true } })

    -- flush() writes synchronously, which is what VimLeavePre needs.
    store3.saves = 0
    persist.flush()
    t.ok("flush: writes immediately", store3.saves >= 1)

    config.setup({ persist = { enable = false } })
    store3.saves = 0
    persist.flush()
    t.eq("flush: writes nothing while persistence is off", store3.saves, 0)
    config.setup({ persist = { enable = true, default = true } })
  end)

  -- ---------- status() ----------
  local named = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(named, "/proj/fake/logs/status.log")
  t.with_modules({ [STORE] = fake_store() }, function()
    t.contains(
      "status: a file with no override says it follows the default",
      persist.status(named),
      "following the global default"
    )
    t.contains("status: naming the key", persist.status(named), "logs/status.log")
    persist.set_exception("logs/status.log", false)
    t.contains("status: an override is called one", persist.status(named), "explicit override")
    t.contains("status: and reports the effective answer", persist.status(named), "not persisted")
    persist.set_exception("logs/status.log", nil)

    local scratch = vim.api.nvim_create_buf(false, true)
    t.contains("status: a buffer with no file says so", persist.status(scratch), "no file on disk")
    t.contains("status: and still reports the global default", persist.status(scratch), "global default")
    pcall(vim.api.nvim_buf_delete, scratch, { force = true })
  end)

  -- ---------- persists()/has_override() on a nil key ----------
  t.eq("persists(nil): follows the default", persist.persists(nil), true)
  t.eq("has_override(nil): there is nothing to override", persist.has_override(nil), false)

  -- Leave no override behind for the specs that follow, and no debounce handle
  -- pointing at a double.
  t.with_modules({ [STORE] = fake_store() }, function()
    persist.flush()
  end)
  pcall(vim.api.nvim_buf_delete, named, { force = true })
  registry.clear()
  config.setup()
end

return M
