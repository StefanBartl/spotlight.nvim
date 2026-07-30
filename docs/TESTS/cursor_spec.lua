-- docs/TESTS/cursor_spec.lua
-- The token resolver: the structured-token patterns that `<cword>` cannot see,
-- priority ordering between overlapping patterns, and the shape-based word/literal
-- classification that decides whether the built regex gets word boundaries.

local t = require("harness")
local cursor = require("spotlight.cursor")

local M = {}

function M.run()
  require("spotlight.config").setup()

  -- ---------- structured tokens ----------
  t.fixture({
    "2026-07-27T14:03:11.482Z INFO req=550e8400-e29b-41d4-a716-446655440000 from 192.168.1.42:8080 at 0x1f4a pid=31337",
    "plain errors and error here",
  })

  t.ok("uuid: cursor placed", t.cursor_on(1, "e29b"))
  local tok = cursor.token()
  t.eq("uuid: resolved whole uuid", tok and tok.text, "550e8400-e29b-41d4-a716-446655440000")
  t.eq("uuid: literal kind", tok and tok.kind, "literal")

  t.ok("timestamp: cursor placed", t.cursor_on(1, "14:03"))
  t.eq("timestamp: full ISO 8601 wins over bare clock time", cursor.token().text, "2026-07-27T14:03:11.482Z")

  t.ok("ipv4: cursor placed", t.cursor_on(1, "168"))
  t.eq("ipv4: port included, beats the bare-ipv4 pattern after it", cursor.token().text, "192.168.1.42:8080")

  t.ok("hex: cursor placed", t.cursor_on(1, "1f4a"))
  t.eq("hex: 0x prefix included", cursor.token().text, "0x1f4a")

  -- ---------- shape-based kind ----------
  t.ok("word: cursor placed", t.cursor_on(2, "error here"))
  local word = cursor.token()
  t.eq("word: plain identifier resolved", word.text, "error")
  t.eq("word: all-word-chars classified as word", word.kind, "word")

  local pattern = require("spotlight.core.pattern")
  local opts = require("spotlight.config").get("match")
  t.contains("word: gets \\< boundary", pattern.build(word, opts), "\\<error\\>")
  t.eq("literal: gets no boundary", pattern.build({ text = "1.2.3", kind = "literal" }, opts), "\\C\\V1.2.3")

  -- ---------- cursor outside any token ----------
  t.fixture({ "   " })
  vim.api.nvim_win_set_cursor(0, { 1, 1 })
  t.eq("blank: nothing resolves on whitespace", cursor.token(), nil)

  -- ---------- multiple matches on one line ----------
  t.fixture({ "a=10.0.0.1 b=10.0.0.2 c=10.0.0.3" })
  t.ok("multi: cursor placed on the third ip", t.cursor_on(1, "10.0.0.3"))
  t.eq("multi: the match spanning the cursor wins, not the first on the line", cursor.token().text, "10.0.0.3")
end

return M
