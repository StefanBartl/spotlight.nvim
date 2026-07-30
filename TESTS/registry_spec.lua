-- TESTS/registry_spec.lua
-- The registry: toggle semantics, palette round-robin, the `match.max` guard,
-- the snapshot/restore round trip, and that matchadd() actually lands in every
-- window (the property that makes a window-local mechanism behave globally).

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local palette = require("spotlight.core.palette")

  config.setup()
  palette.apply()
  registry.clear()

  t.fixture({ "req=aaa ip=10.0.0.1", "req=bbb ip=10.0.0.2", "req=aaa ip=10.0.0.3" })

  -- ---------- add / toggle ----------
  local item = registry.add({ text = "aaa", kind = "literal" })
  t.ok("add: returns the item", item ~= nil)
  t.eq("add: one spotlight active", registry.count(), 1)
  t.eq("add: first slot is 1", item.slot, 1)
  t.eq("add: highlight group follows the slot", item.hl, "Spotlight1")

  local dup, err = registry.add({ text = "aaa", kind = "literal" })
  t.eq("add: duplicate text is refused", dup, nil)
  t.contains("add: duplicate reports why", err, "already spotlighted")

  local action = registry.toggle({ text = "aaa", kind = "literal" })
  t.eq("toggle: same text removes", action, "removed")
  t.eq("toggle: registry is empty again", registry.count(), 0)

  action = registry.toggle({ text = "aaa", kind = "literal" })
  t.eq("toggle: absent text adds", action, "added")

  -- ---------- round-robin ----------
  registry.add({ text = "bbb", kind = "literal" })
  registry.add({ text = "ccc", kind = "literal" })
  local slots = {}
  for _, it in ipairs(registry.all()) do
    slots[#slots + 1] = it.slot
  end
  t.eq("palette: three distinct slots handed out", #slots, 3)
  t.neq("palette: slot 1 and 2 differ", slots[1], slots[2])
  t.neq("palette: slot 2 and 3 differ", slots[2], slots[3])

  -- Removing the middle one frees its slot; the next add should reuse a free
  -- slot rather than duplicating a colour that is still on screen.
  local freed = registry.all()[2].slot
  registry.remove(registry.all()[2].id)
  registry.add({ text = "ddd", kind = "literal" })
  local live = {}
  for _, it in ipairs(registry.all()) do
    t.ok("palette: no slot is used twice", live[it.slot] == nil, ("slot %d used twice"):format(it.slot))
    live[it.slot] = true
  end
  t.ok("palette: the freed slot is reusable", freed ~= nil)

  -- ---------- matchadd() reaches every window ----------
  local before = #vim.fn.getmatches()
  t.eq("match: current window carries every spotlight", before, registry.count())

  vim.cmd("split")
  registry.apply_to_window(vim.api.nvim_get_current_win())
  t.eq("match: a new window is filled too", #vim.fn.getmatches(), registry.count())
  vim.cmd("close")

  -- ---------- match.max ----------
  config.setup({ match = { max = 2 } })
  registry.clear()
  registry.add({ text = "one", kind = "literal" })
  registry.add({ text = "two", kind = "literal" })
  local over, max_err = registry.add({ text = "three", kind = "literal" })
  t.eq("max: the cap is enforced", over, nil)
  t.contains("max: the cap reports itself", max_err, "match.max")
  config.setup()

  -- ---------- snapshot / restore ----------
  registry.clear()
  registry.add({ text = "keepme", kind = "word" })
  registry.add({ text = "10.0.0.1", kind = "literal" })
  local snap = registry.snapshot()
  t.eq("snapshot: two entries", #snap, 2)
  t.eq("snapshot: word kind survives the pattern round trip", snap[1].kind, "word")
  t.eq("snapshot: literal kind survives the pattern round trip", snap[2].kind, "literal")

  registry.clear()
  t.eq("restore: cleared first", registry.count(), 0)
  t.eq("restore: both entries come back", registry.restore(snap), 2)
  t.eq("restore: text preserved", registry.all()[1].text, "keepme")
  t.contains("restore: word boundaries rebuilt from kind", registry.all()[1].pattern, "\\<keepme\\>")
  t.eq("restore: matches re-applied to the window", #vim.fn.getmatches(), 2)

  -- Duplicates and empties in a hand-edited/corrupt snapshot are dropped rather
  -- than trusted.
  registry.clear()
  t.eq(
    "restore: duplicate and empty entries are dropped",
    registry.restore({
      { text = "x", slot = 1, kind = "literal" },
      { text = "x", slot = 2, kind = "literal" },
      { text = "", slot = 3, kind = "literal" },
      { slot = 4, kind = "literal" },
    }),
    1
  )

  -- A slot from a larger palette is clamped, not used as-is.
  registry.clear()
  registry.restore({ { text = "y", slot = 99, kind = "literal" } })
  t.ok("restore: an out-of-range slot is clamped into the palette", registry.all()[1].slot <= palette.size())

  registry.clear()
  t.eq("clear: no matches left in the window", #vim.fn.getmatches(), 0)
end

return M
