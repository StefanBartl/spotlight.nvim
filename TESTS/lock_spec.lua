-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lock_spec.lua
-- Per-slot lock: `registry.set_locked`, `palette.next_slot`'s locked-aware
-- fallback (the one real algorithmic risk in this feature — an exhausted or
-- fully locked palette must never hang), snapshot/restore round-trip, and
-- the facade/`:Spotlight lock` surface.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local palette = require("spotlight.core.palette")
  local api = require("spotlight")

  config.setup()
  registry.clear()
  t.fixture({ "aaa bbb ccc" })

  -- ---------- set_locked ----------
  local item = registry.add({ text = "aaa", kind = "literal" })
  t.eq("set_locked: not locked by default", item.locked, nil)
  t.ok("set_locked: succeeds for an existing id", registry.set_locked(item.id, true))
  t.eq("set_locked: item.locked is now true", registry.get(item.id).locked, true)
  t.eq("set_locked: the item's slot is unchanged by locking", registry.get(item.id).slot, item.slot)
  t.ok("set_locked: unlocking again succeeds", registry.set_locked(item.id, false))
  t.eq("set_locked: false is stored as nil, not false", registry.get(item.id).locked, nil)
  t.eq("set_locked: an unknown id is refused", registry.set_locked(99999, true), false)

  -- ---------- palette.next_slot: locked slot survives churn ----------
  registry.clear()
  local n = palette.size()
  local locked_item = registry.add({ text = "locked-one", kind = "literal" })
  registry.set_locked(locked_item.id, true)
  local locked_slot = locked_item.slot

  -- Fill and free every other slot several times over; the locked one must
  -- never be handed to a different spotlight.
  for round = 1, n * 2 do
    local it = registry.add({ text = ("churn-%d"):format(round), kind = "literal" })
    if it then
      t.ok(("next_slot: round %d never reuses the locked slot"):format(round), it.slot ~= locked_slot)
      registry.remove(it.id)
    end
  end
  t.eq("next_slot: the locked item itself still holds its slot", registry.get(locked_item.id).slot, locked_slot)

  -- ---------- regression: every slot locked must not hang ----------
  registry.clear()
  local locked_ids = {}
  for i = 1, n do
    local it = registry.add({ text = ("lockall-%d"):format(i), kind = "literal" })
    t.ok(("lockall: slot %d filled"):format(i), it ~= nil)
    registry.set_locked(it.id, true)
    locked_ids[#locked_ids + 1] = it.id
  end
  t.eq("lockall: every palette slot is now locked", #locked_ids, n)

  -- One more add: match.max permitting, this must return promptly (not hang)
  -- and land on *some* valid slot, since none can be honoured without
  -- breaking a lock.
  local overflow, err = registry.add({ text = "overflow", kind = "literal" })
  if overflow then
    t.ok("lockall: an extra spotlight still gets a valid slot (1..n)", overflow.slot >= 1 and overflow.slot <= n)
    registry.remove(overflow.id)
  else
    -- match.max (64) is well above the 8-slot palette, so this branch should
    -- not normally trigger — but either outcome proves termination, which is
    -- the property under test.
    t.ok("lockall: or refused with a reason, but did not hang", type(err) == "string")
  end

  registry.clear()

  -- ---------- snapshot / restore round-trip ----------
  local kept = registry.add({ text = "persisted-lock", kind = "literal" })
  registry.set_locked(kept.id, true)
  local snap = registry.snapshot()
  local found_locked = false
  for _, s in ipairs(snap) do
    if s.text == "persisted-lock" then
      t.eq("snapshot: locked is true", s.locked, true)
      found_locked = true
    end
  end
  t.ok("snapshot: the locked item was found", found_locked)

  registry.clear()
  registry.restore(snap)
  t.eq("restore: locked survives the round trip", registry.all()[1].locked, true)

  -- A malformed stored value must not restore as truthy.
  registry.clear()
  registry.restore({ { text = "bad-lock", slot = 1, kind = "literal", locked = "yes" } })
  t.eq("restore: a non-boolean locked field restores as unlocked, not truthy", registry.all()[1].locked, nil)

  registry.clear()

  -- ---------- facade / :Spotlight lock ----------
  local api_item = registry.add({ text = "aaa", kind = "literal" })
  t.eq("api/lock_set: locks by exact text", api.lock_set("aaa", true), true)
  t.eq("api/lock_set: registry reflects it", registry.get(api_item.id).locked, true)
  t.eq("api/lock_set: unknown text is refused", api.lock_set("does-not-exist", true), false)

  t.eq("api/lock_toggle: toggles by exact text", api.lock_toggle("aaa"), true)
  t.eq("api/lock_toggle: now unlocked", registry.get(api_item.id).locked, nil)

  t.ok("cursor on aaa", t.cursor_on(1, "aaa"))
  t.eq("api/lock_toggle: with no text, resolves the cursor token", api.lock_toggle(nil), true)
  t.eq("api/lock_toggle: cursor-resolved toggle locked it", registry.get(api_item.id).locked, true)

  vim.cmd("Spotlight lock aaa")
  t.eq("cmd/lock: toggles via :Spotlight lock {text}", registry.get(api_item.id).locked, nil)

  registry.clear()
end

return M
