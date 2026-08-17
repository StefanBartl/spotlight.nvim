-- TESTS/line_spec.lua
-- Whole-line rendering: `core.pattern.line`'s widened regex, the fact that it
-- reaches `matchadd()` *only* (item.pattern stays the token pattern, so every
-- other consumer keeps its meaning), the priority drop that stops a line
-- highlight from swallowing the other spotlights' colors, snapshot/restore,
-- and the facade / `:Spotlight line` surface.

local t = require("harness")

local M = {}

---@param pat string
---@return table|nil
local function match_for(pat)
  for _, m in ipairs(vim.fn.getmatches()) do
    if m.pattern == pat then
      return m
    end
  end
  return nil
end

function M.run()
  local config = require("spotlight.config")
  local count = require("spotlight.core.count")
  local pattern = require("spotlight.core.pattern")
  local registry = require("spotlight.core.registry")
  local api = require("spotlight")

  config.setup()
  registry.clear()
  t.fixture({ "2026 err here", "2026 errors here", "nothing", "err again err" })

  -- ---------- pattern.line ----------
  local base = pattern.build({ text = "err", kind = "word" }, config.get("match"))
  local wide = pattern.line(base)
  local re = pattern.compile(wide)
  t.ok("pattern.line: compiles", re ~= nil)
  t.eq("pattern.line: spans the whole line", select(2, re:match_str("2026 err here")), 13)
  t.eq("pattern.line: starts at column 0", select(1, re:match_str("2026 err here")), 0)
  t.eq("pattern.line: word boundaries survive the widening", re:match_str("2026 errors here"), nil)

  -- A backslash in the token is escaped by `pattern.escape`; widening must not
  -- disturb that (the `\V` body sits between two position atoms).
  local esc_base = pattern.build({ text = [[path\to]], kind = "literal" }, config.get("match"))
  local esc_re = pattern.compile(pattern.line(esc_base))
  t.ok("pattern.line: an escaped backslash still matches", esc_re ~= nil and esc_re:match_str([[a path\to b]]) == 0)

  -- ---------- the flag reaches matchadd(), and nothing else ----------
  registry.clear()
  vim.fn.clearmatches()
  local item = registry.add({ text = "err", kind = "word" })
  local token_pattern = item.pattern
  t.ok("apply: the token pattern is registered while line mode is off", match_for(token_pattern) ~= nil)

  t.ok("set_line: succeeds for an existing id", registry.set_line(item.id, true))
  t.eq("set_line: item.line is true", registry.get(item.id).line, true)
  t.eq("set_line: item.pattern is NOT rewritten", registry.get(item.id).pattern, token_pattern)

  local widened = match_for(pattern.line(token_pattern))
  t.ok("set_line: matchadd() now carries the widened pattern", widened ~= nil)
  t.eq("set_line: the token pattern is gone from the window", match_for(token_pattern), nil)
  t.eq(
    "set_line: the widened match sits one priority below match.priority",
    widened and widened.priority,
    config.get("match.priority") - 1
  )
  t.eq("set_line: the palette group is unchanged", widened and widened.group, item.hl)

  -- The invariant the whole design rests on: counting still counts
  -- occurrences, not matching lines. Fixture has "err" three times (line 1
  -- once, line 4 twice) — "errors" on line 2 is excluded by the word boundary.
  t.eq("count: unchanged by line mode (occurrences, not lines)", (count.count(0, registry.get(item.id), 10000)), 3)

  local lines = count.matching_lines(0, { registry.get(item.id).pattern }, 100)
  t.eq("quickfix scan: still reports one entry per matching line", #lines, 2)
  t.eq("quickfix scan: the column is the token's, not the line start", lines[1].col, 6)

  t.ok("set_line: unsetting succeeds", registry.set_line(item.id, false))
  t.eq("set_line: false is stored as nil, not false", registry.get(item.id).line, nil)
  t.ok("set_line: the token pattern is back in the window", match_for(token_pattern) ~= nil)
  t.eq("set_line: an unknown id is refused", registry.set_line(99999, true), false)

  -- ---------- buffer-scoped ("this occurrence only") + line mode ----------
  registry.clear()
  vim.fn.clearmatches()
  local here = registry.add_at({ text = "err", kind = "literal" }, { buf = vim.api.nvim_get_current_buf(), row1 = 4, col1 = 1 })
  t.ok("add_at: created", here ~= nil)
  registry.set_line(here.id, true)
  local pinned = pattern.line(here.pattern)
  t.ok("add_at + line: the widened position-anchored pattern is registered", match_for(pinned) ~= nil)
  -- The position atoms are zero-width, so the leading `.*` walks up to them:
  -- line 4 matches whole, line 1 (same text, different position) does not.
  t.eq("add_at + line: matches only the pinned line", vim.fn.search(pinned, "nw"), 4)

  -- ---------- snapshot / restore round-trip ----------
  registry.clear()
  local kept = registry.add({ text = "persisted-line", kind = "literal" })
  registry.set_line(kept.id, true)
  local snap = registry.snapshot()
  local found = false
  for _, s in ipairs(snap) do
    if s.text == "persisted-line" then
      t.eq("snapshot: line is true", s.line, true)
      found = true
    end
  end
  t.ok("snapshot: the line-mode item was found", found)

  registry.clear()
  registry.restore(snap)
  t.eq("restore: line survives the round trip", registry.all()[1].line, true)

  registry.clear()
  registry.restore({ { text = "bad-line", slot = 1, kind = "literal", line = "yes" } })
  t.eq("restore: a non-boolean line field restores as off, not truthy", registry.all()[1].line, nil)

  -- ---------- rebuild keeps the flag ----------
  registry.clear()
  local rebuilt = registry.add({ text = "err", kind = "word" })
  registry.set_line(rebuilt.id, true)
  registry.rebuild()
  t.eq("rebuild: line mode survives a full re-apply", registry.get(rebuilt.id).line, true)
  t.ok("rebuild: the widened pattern is re-registered", match_for(pattern.line(registry.get(rebuilt.id).pattern)) ~= nil)

  -- ---------- facade / :Spotlight line ----------
  registry.clear()
  local api_item = registry.add({ text = "err", kind = "word" })
  t.eq("api/line_set: sets by exact text", api.line_set("err", true), true)
  t.eq("api/line_set: registry reflects it", registry.get(api_item.id).line, true)
  t.eq("api/line_set: unknown text is refused", api.line_set("does-not-exist", true), false)

  t.eq("api/line_toggle: toggles by exact text", api.line_toggle("err"), true)
  t.eq("api/line_toggle: now off", registry.get(api_item.id).line, nil)

  t.ok("cursor on err", t.cursor_on(1, "err"))
  t.eq("api/line_toggle: with no text, resolves the cursor token", api.line_toggle(nil), true)
  t.eq("api/line_toggle: cursor-resolved toggle turned it on", registry.get(api_item.id).line, true)

  vim.cmd("Spotlight line err")
  t.eq("cmd/line: toggles via :Spotlight line {text}", registry.get(api_item.id).line, nil)

  -- A token with no spotlight is refused rather than silently creating one.
  t.eq("api/line_toggle: refuses a token that is not spotlighted", api.line_toggle("not-spotlighted"), false)

  registry.clear()
  vim.fn.clearmatches()
end

return M
