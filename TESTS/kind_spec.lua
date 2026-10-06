-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- A snapshot written before `kind` existed has no such field; the case below
-- hands one in on purpose.
-- TESTS/kind_spec.lua
-- The token kind lives on the registry item. With `match.word_boundaries =
-- false` a word token has no `\<` in its pattern, so a kind read back from the
-- pattern said "literal" and the token stayed literal after `rebuild()` and
-- after a snapshot round trip -- even once the option was switched back on.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local api = require("spotlight")

  config.setup()
  registry.clear()
  t.fixture({ "error errors", "C:\\<dir>\\x" })

  -- ---------- boundaries on: unchanged behaviour ----------
  local on = registry.add({ text = "error", kind = "word" })
  t.eq("on: the item records its kind", on.kind, "word")
  t.contains("on: the pattern carries the boundary", on.pattern, "\\<error\\>")
  t.eq("on: the read API says word", api.spotlights()[1].kind, "word")
  registry.clear()

  -- ---------- boundaries off: a word token stays a word ----------
  config.setup({ match = { word_boundaries = false } })
  local item = registry.add({ text = "error", kind = "word" })
  t.eq("off: the item still records word", item.kind, "word")
  t.eq("off: no boundary in the pattern", item.pattern:find("\\<", 1, true), nil)
  t.eq("off: the snapshot keeps word, not what the pattern shows", registry.snapshot()[1].kind, "word")
  t.eq("off: export keeps it too", api.export()[1].kind, "word")
  -- The read API describes the rendering, which is literal while boundaries are off.
  t.eq("off: the read API reports how it matches now", api.spotlights()[1].kind, "literal")

  registry.rebuild()
  t.eq("off: rebuild keeps the kind", registry.all()[1].kind, "word")
  t.eq("off: ... and the snapshot after it", registry.snapshot()[1].kind, "word")

  -- ---------- the snapshot round trip survives the option being switched back on ----------
  local snap = registry.snapshot()
  local roundtrip = vim.json.decode(vim.json.encode(snap))
  registry.clear()
  registry.restore(roundtrip)
  t.eq("off: a restored word token keeps its kind", registry.all()[1].kind, "word")
  t.eq("off: ... without boundaries while they are off", registry.all()[1].pattern:find("\\<", 1, true), nil)

  config.setup()
  registry.rebuild()
  t.contains("on again: rebuild now gives the word token its boundary", registry.all()[1].pattern, "\\<error\\>")
  t.eq("on again: and the read API reports word", api.spotlights()[1].kind, "word")

  -- The same for a token restored (not rebuilt) after the switch.
  config.setup({ match = { word_boundaries = false } })
  registry.clear()
  registry.restore(roundtrip)
  config.setup()
  registry.clear()
  registry.restore(roundtrip)
  t.contains("on again: a restored word token is bounded", registry.all()[1].pattern, "\\<error\\>")

  -- ---------- a literal stays a literal in both modes ----------
  registry.clear()
  registry.add({ text = "error", kind = "literal" })
  t.eq("literal: kind recorded", registry.all()[1].kind, "literal")
  registry.rebuild()
  t.eq("literal: no boundary after rebuild", registry.all()[1].pattern:find("\\<", 1, true), nil)
  t.eq("literal: still literal", registry.snapshot()[1].kind, "literal")

  -- A backslash-angle body is still no word (the derivation fallback's old case).
  registry.clear()
  registry.add({ text = [[C:\<dir>\x]], kind = "literal" })
  registry.rebuild()
  t.eq("backslash: a literal stays literal across rebuild", registry.snapshot()[1].kind, "literal")

  -- ---------- an item without a kind falls back to the pattern ----------
  registry.clear()
  local bare = registry.add({ text = "bare", kind = "word" })
  bare.kind = nil
  t.eq("fallback: bounded pattern reads as word", registry.snapshot()[1].kind, "word")
  registry.rebuild()
  t.contains("fallback: rebuild keeps the boundary", registry.all()[1].pattern, "\\<bare\\>")
  local plain = registry.add({ text = "plain", kind = "literal" })
  plain.kind = nil
  t.eq("fallback: unbounded pattern reads as literal", registry.snapshot()[2].kind, "literal")

  -- ---------- a snapshot from before the field existed ----------
  registry.clear()
  local old = { { text = "legacy", slot = 2 }, { text = "legacy-word", slot = 3, kind = "bogus" } }
  t.eq("old snapshot: restores", registry.restore(old), 2)
  t.eq("old snapshot: no kind restores as literal", registry.all()[1].kind, "literal")
  t.eq("old snapshot: an unknown kind too", registry.all()[2].kind, "literal")
  t.eq("old snapshot: no boundary built", registry.all()[1].pattern:find("\\<", 1, true), nil)
  t.eq("old snapshot: slot kept", registry.all()[1].slot, 2)

  -- ---------- a pinned spotlight is literal, whatever the token was ----------
  registry.clear()
  local pinned = registry.add_at({ text = "error", kind = "word" }, { buf = vim.api.nvim_get_current_buf(), row1 = 1, col1 = 1 })
  t.eq("pinned: literal", pinned.kind, "literal")
  t.eq("pinned: the read API agrees", api.spotlights()[1].kind, "literal")

  config.setup()
  registry.clear()
end

return M
