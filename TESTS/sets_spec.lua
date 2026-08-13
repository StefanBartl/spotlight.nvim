-- TESTS/sets_spec.lua
-- Spotlight sets: exclusive save/switch/delete/list. Switching clears and
-- replaces the active registry (never merges), an unknown name is a no-op
-- rather than data loss, and re-saving overwrites rather than accumulating.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local sets = require("spotlight.sets")
  local api = require("spotlight")

  config.setup()
  registry.clear()
  t.fixture({ "aaa bbb ccc" })

  -- Start from a clean slate for this session's sets too, in case an earlier
  -- spec (or a stale on-disk file from a prior run) left any behind.
  for _, name in ipairs(sets.names()) do
    sets.delete(name)
  end

  -- ---------- save ----------
  registry.add({ text = "aaa", kind = "literal" })
  registry.add({ text = "bbb", kind = "literal" })
  local ok_save, err_save = sets.save("investigation")
  t.ok("save: succeeds", ok_save)
  t.eq("save: no error", err_save, nil)
  t.eq("save: captured both active spotlights", sets.count("investigation"), 2)

  t.eq("save: rejects an empty name", (sets.save("")), false)
  t.eq("save: rejects a nil name", (sets.save(nil)), false)

  -- ---------- switch: replaces, not merges ----------
  registry.clear()
  registry.add({ text = "ccc", kind = "literal" })
  t.eq("switch: registry has one unrelated spotlight before switching", registry.count(), 1)

  local restored, err_switch = sets.switch("investigation")
  t.eq("switch: restored count matches what was saved", restored, 2)
  t.eq("switch: no error", err_switch, nil)
  t.eq("switch: registry now holds exactly the saved set", registry.count(), 2)

  local texts = {}
  for _, item in ipairs(registry.all()) do
    texts[item.text] = true
  end
  t.ok("switch: aaa is present", texts["aaa"])
  t.ok("switch: bbb is present", texts["bbb"])
  t.ok("switch: the pre-switch ccc is gone (replaced, not merged)", not texts["ccc"])

  -- ---------- switch: unknown name is a no-op, not data loss ----------
  local before_count = registry.count()
  local restored2, err_unknown = sets.switch("does-not-exist")
  t.eq("switch: unknown name restores nothing", restored2, 0)
  t.contains("switch: names the reason", err_unknown or "", "no such set")
  t.eq("switch: the active registry is untouched", registry.count(), before_count)

  -- ---------- delete ----------
  t.ok("delete: succeeds for an existing set", sets.delete("investigation"))
  t.eq(
    "delete: no longer in names()",
    (function()
      for _, n in ipairs(sets.names()) do
        if n == "investigation" then
          return true
        end
      end
      return false
    end)(),
    false
  )
  t.eq("delete: an unknown name is refused", sets.delete("investigation"), false)

  -- Switching to a deleted set behaves exactly like an unknown one.
  local restored3, err_deleted = sets.switch("investigation")
  t.eq("switch: a deleted set can no longer be switched to", restored3, 0)
  t.contains("switch: same 'no such set' reason", err_deleted or "", "no such set")

  -- ---------- re-save overwrites, does not accumulate ----------
  registry.clear()
  registry.add({ text = "one", kind = "literal" })
  sets.save("overwrite-me")
  t.eq("save: first save has one entry", sets.count("overwrite-me"), 1)

  registry.clear()
  registry.add({ text = "two", kind = "literal" })
  registry.add({ text = "three", kind = "literal" })
  sets.save("overwrite-me")
  t.eq("save: re-saving replaces rather than accumulates", sets.count("overwrite-me"), 2)

  sets.delete("overwrite-me")

  -- ---------- facade / :Spotlight sets ----------
  registry.clear()
  registry.add({ text = "facade-item", kind = "literal" })
  t.eq("api/sets_save: reports success", api.sets_save("facade-set"), true)
  t.eq("api/sets_switch: unknown name reports failure", api.sets_switch("nope-nope"), false)
  registry.clear()
  t.eq("api/sets_switch: known name reports success", api.sets_switch("facade-set"), true)
  t.eq("api/sets_switch: restored the item", registry.count(), 1)
  t.eq("api/sets_delete: succeeds", api.sets_delete("facade-set"), true)
  t.eq("api/sets_delete: unknown name reports failure", api.sets_delete("facade-set"), false)

  vim.cmd("Spotlight sets save cmdset")
  t.ok("cmd/sets save: created a set", sets.count("cmdset") ~= nil)
  vim.cmd("Spotlight sets list")
  sets.delete("cmdset")

  registry.clear()
end

return M
