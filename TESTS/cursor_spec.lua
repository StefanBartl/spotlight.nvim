-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/cursor_spec.lua
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
  local word = assert(cursor.token(), "cursor is on a word")
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

  -- ---------- position, for "this occurrence only" spotlights ----------
  -- `M.token`'s second return value must point at the exact occurrence the
  -- cursor is on, not just any occurrence of the same text — the whole reason
  -- `core.pattern.build_at` needs it.
  t.fixture({ "a=10.0.0.1 b=10.0.0.2 c=10.0.0.3" })
  t.ok("pos/pattern: cursor placed on the third ip", t.cursor_on(1, "10.0.0.3"))
  local tok3, pos3 = cursor.token()
  t.eq("pos/pattern: resolves the third occurrence", tok3.text, "10.0.0.3")
  t.eq("pos/pattern: row is 1-based", pos3.row1, 1)
  t.eq("pos/pattern: column points at the third, not the first, occurrence", pos3.col1, ("a=10.0.0.1 b=10.0.0.2 c="):len() + 1)

  t.fixture({ "error and error again" })
  t.ok("pos/word: cursor placed on the second error", t.cursor_on(1, "error again"))
  local tok_w, pos_w = cursor.token()
  t.eq("pos/word: resolves the second occurrence's text", tok_w.text, "error")
  t.eq("pos/word: column points at the second occurrence, not the first", pos_w.col1, ("error and "):len() + 1)

  -- ---------- nothing under the cursor ----------
  -- `expand("<cword>")` does not return "" there, it raises E348. Both
  -- fallback paths in cursor.lua read as if it returned "", so the error used
  -- to escape whichever keymap called token() -- and it named Vim, not this
  -- plugin, which is the worst kind of report to receive.
  t.fixture({ "" })
  local empty_ok, empty_tok = pcall(cursor.token)
  t.ok("empty line: token() does not raise", empty_ok)
  t.eq("empty line: nothing resolved", empty_ok and empty_tok or nil, nil)

  t.fixture({ "        " })
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  local ws_ok, ws_tok = pcall(cursor.token)
  t.ok("whitespace-only line: token() does not raise", ws_ok)
  t.eq("whitespace-only line: nothing resolved", ws_ok and ws_tok or nil, nil)

  local sel_tok, sel_err, sel_pos = cursor.selection()
  t.eq("pos/selection: outside visual mode there is no position either", sel_pos, nil)
  t.eq("pos/selection: outside visual mode there is no token", sel_tok, nil)
  t.ok("pos/selection: reports why", sel_err ~= nil)
end

return M
