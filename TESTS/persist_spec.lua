-- TESTS/persist_spec.lua
-- Persistence, and specifically the exception semantics the concept left open:
-- an exception on a file suppresses the spotlights *created in* that file, and
-- nothing else. Also covers the config layer's validation, which degrades bad
-- values to defaults instead of throwing.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local persist = require("spotlight.persist")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()

  -- ---------- effective decision ----------
  config.setup({ persist = { default = true } })
  t.eq("persists: no override follows the default (on)", persist.persists("logs/a.log"), true)
  t.eq("persists: a nil origin follows the default", persist.persists(nil), true)

  persist.set_exception("logs/a.log", false)
  t.eq("persists: an explicit off override wins over the default", persist.persists("logs/a.log"), false)
  t.eq("persists: the override is scoped to that one file", persist.persists("logs/b.log"), true)
  t.eq("has_override: reported for the overridden file", persist.has_override("logs/a.log"), true)
  t.eq("has_override: not reported for others", persist.has_override("logs/b.log"), false)

  persist.set_exception("logs/a.log", nil)
  t.eq("persists: clearing the override restores the default", persist.persists("logs/a.log"), true)
  t.eq("has_override: gone after clearing", persist.has_override("logs/a.log"), false)

  -- The inverted (opt-in) model: default off, single file switched on.
  config.setup({ persist = { default = false } })
  t.eq("persists: default off means off", persist.persists("logs/a.log"), false)
  persist.set_exception("logs/a.log", true)
  t.eq("persists: an explicit on override opts one file in", persist.persists("logs/a.log"), true)
  t.eq("persists: everything else stays off", persist.persists("logs/b.log"), false)
  persist.set_exception("logs/a.log", nil)

  -- ---------- the snapshot filter ----------
  --
  -- This is the concept's open question made concrete: `shared` is created in
  -- b.log and also *appears* in a.log, which is excluded. It must still be
  -- persisted — the exception is about origin, not about where a token shows up.
  config.setup({ persist = { default = true } })
  registry.clear()
  registry.add({ text = "from-a", kind = "literal" }, { origin = "logs/a.log" })
  registry.add({ text = "shared", kind = "literal" }, { origin = "logs/b.log" })
  registry.add({ text = "no-origin", kind = "literal" }, { origin = false })
  persist.set_exception("logs/a.log", false)

  local kept = {}
  for _, item in ipairs(registry.snapshot()) do
    if persist.persists(item.origin) then
      kept[#kept + 1] = item.text
    end
  end
  table.sort(kept)
  t.eq("filter: the excluded file's spotlight is dropped", vim.tbl_contains(kept, "from-a"), false)
  t.eq(
    "filter: a spotlight from another file survives, even though its token also appears in the excluded one",
    vim.tbl_contains(kept, "shared"),
    true
  )
  t.eq("filter: an origin-less spotlight follows the global default", vim.tbl_contains(kept, "no-origin"), true)
  persist.set_exception("logs/a.log", nil)
  registry.clear()

  -- ---------- status text ----------
  config.setup({ persist = { enable = false } })
  t.contains("status: reports the global off switch", persist.status(0), "disabled globally")
  config.setup({ persist = { enable = true, default = true } })

  -- ---------- config validation ----------
  config.setup({
    palette = { colors = { { bg = "not-a-color", fg = "#ffffff" }, { bg = "#000000", fg = "#ffffff" } } },
    cursor = { patterns = { "%d+", "%f[" } },
    match = { max = -3, priority = "high" },
    nav = { scope = "sideways" },
    list = { count_max_lines = -1 },
    persist = { debounce_ms = -50 },
  })
  t.eq("validate: the invalid palette entry is dropped, the valid one kept", #config.get("palette.colors"), 1)
  t.eq("validate: the invalid Lua pattern is dropped", #config.get("cursor.patterns"), 1)
  t.eq("validate: a negative match.max falls back to the default", config.get("match.max"), 64)
  t.eq("validate: a non-numeric priority falls back to the default", config.get("match.priority"), 10)
  t.eq("validate: an unknown nav.scope falls back to the default", config.get("nav.scope"), "auto")
  t.eq("validate: a negative count_max_lines falls back", config.get("list.count_max_lines"), 200000)
  t.eq("validate: a negative debounce falls back", config.get("persist.debounce_ms"), 500)
  t.ok("validate: every problem is reported for :checkhealth", #config.issues >= 7)

  -- A wholly invalid palette must not leave nothing to round-robin over.
  config.setup({ palette = { colors = { "nope" } } })
  t.eq("validate: an entirely invalid palette falls back to the defaults", #config.get("palette.colors"), 8)

  -- Arrays are replaced wholesale, not merged, so a user can genuinely shrink one.
  config.setup({ cursor = { patterns = { "%d+" } } })
  t.eq("merge: a user array replaces the default array instead of extending it", #config.get("cursor.patterns"), 1)

  config.setup()
end

return M
