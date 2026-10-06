-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/export_import_spec.lua
-- `spotlight.export()` / `spotlight.import(items)`: the registry as plain data
-- and back, for a host that stores the spotlights itself (casedesk.nvim, per
-- case). Import is exclusive and re-validates; export leaves out pinned
-- spotlights and those created in a file with `persist off`.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local persist = require("spotlight.persist")
  local registry = require("spotlight.core.registry")
  local api = require("spotlight")

  config.setup()
  registry.clear()
  t.fixture({ "aaa bbb ccc", "aaa" })

  -- ---------- export: shape ----------
  registry.add({ text = "aaa", kind = "literal" }, { origin = "logs/a.log" })
  registry.add({ text = "bbb", kind = "word" })
  local exported = api.export()
  t.eq("export: one entry per whole-file spotlight", #exported, 2)
  t.eq("export: text", exported[1].text, "aaa")
  t.eq("export: slot", exported[1].slot, registry.all()[1].slot)
  t.eq("export: literal kind", exported[1].kind, "literal")
  t.eq("export: word kind", exported[2].kind, "word")
  t.eq("export: origin kept", exported[1].origin, "logs/a.log")

  -- A JSON round trip loses nothing import needs.
  local roundtrip = vim.json.decode(vim.json.encode(exported))
  t.eq("export: survives a JSON round trip", #roundtrip, 2)

  -- ---------- export: pinned spotlights are session-only ----------
  t.ok("pinned: cursor on the first aaa", t.cursor_on(1, "aaa"))
  api.toggle_here()
  t.eq("pinned: the registry holds three", registry.count(), 3)
  t.eq("pinned: export still has two", #api.export(), 2)

  -- ---------- export: explicit `persist off` for the origin file ----------
  persist.set_exception("logs/secret.log", false)
  registry.add({ text = "secret-token", kind = "literal" }, { origin = "logs/secret.log" })
  local texts = {}
  for _, item in ipairs(api.export()) do
    texts[item.text] = true
  end
  t.ok("persist off: a token from the excluded file is not exported", not texts["secret-token"])
  t.ok("persist off: the others are", texts["aaa"] and texts["bbb"])

  -- persist.default = false must not empty an explicit export.
  persist.set_exception("logs/secret.log", nil)
  config.setup({ persist = { default = false } })
  t.eq("persist.default=false: an export is explicit, so everything is exported", #api.export(), 3)
  config.setup()

  -- ---------- import: exclusive, not a merge ----------
  registry.clear()
  registry.add({ text = "old", kind = "literal" })
  local restored = api.import(roundtrip)
  t.eq("import: reports how many came back", restored, 2)
  t.eq("import: the registry holds exactly the imported list", registry.count(), 2)
  local seen = {}
  for _, item in ipairs(registry.all()) do
    seen[item.text] = item
  end
  t.ok("import: old spotlight is gone", seen["old"] == nil)
  t.ok("import: aaa is back", seen["aaa"] ~= nil)
  t.eq("import: with its slot", seen["aaa"].slot, roundtrip[1].slot)
  t.eq("import: with its origin", seen["aaa"].origin, "logs/a.log")

  -- ---------- import: re-validation of hand-edited data ----------
  local n = api.import({
    { text = "ok", slot = 2, kind = "literal" },
    { text = 42 },
    { text = "" },
    "garbage",
    { text = "ok", slot = 3 },
  })
  t.eq("import: invalid and duplicate entries are dropped", n, 1)
  t.eq("import: only the valid one is active", registry.count(), 1)

  -- ---------- import: empty / non-list clears ----------
  t.eq("import: an empty list clears", api.import({}), 0)
  t.eq("import: ... leaving nothing", registry.count(), 0)
  registry.add({ text = "x", kind = "literal" })
  t.eq("import: nil clears too", api.import(nil), 0)
  t.eq("import: ... leaving nothing (nil)", registry.count(), 0)

  -- ---------- import: one coalesced event with clear + restore ----------
  registry.add({ text = "y", kind = "literal" })
  require("spotlight.core.events").flush()
  ---@type table[]
  local log = {}
  local id = vim.api.nvim_create_autocmd("User", {
    pattern = "SpotlightChanged",
    callback = function(args)
      log[#log + 1] = args.data
    end,
  })
  api.import(roundtrip)
  require("spotlight.core.events").flush()
  vim.api.nvim_del_autocmd(id)
  t.eq("event: a single event for the whole import", #log, 1)
  t.eq("event: reasons are clear + restore", vim.inspect(log[1].reasons), vim.inspect({ "clear", "restore" }))

  registry.clear()
end

return M
