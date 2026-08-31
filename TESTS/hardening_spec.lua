-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- Several cases deliberately hand in malformed stored items -- a missing
-- `text`, a wrong type, a non-table -- to check that restore drops them.
-- TESTS/hardening_spec.lua
-- The guards from the security pass. Each one exists because an input this
-- plugin genuinely does not control — a restored snapshot, a visual selection
-- over a minified file, a common token in a huge log — could otherwise reach
-- something unbounded.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local cursor = require("spotlight.cursor")
  local count = require("spotlight.core.count")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()

  local max_len = config.get("match.max_text_len")

  -- ---------- token length cap ----------
  local ok_token = string.rep("a", max_len)
  local too_long = string.rep("a", max_len + 1)

  t.ok("length: a token exactly at the limit is accepted", registry.add({ text = ok_token, kind = "literal" }) ~= nil)
  registry.clear()

  local refused, err = registry.add({ text = too_long, kind = "literal" })
  t.eq("length: one byte over the limit is refused", refused, nil)
  t.contains("length: the refusal names the option", err, "match.max_text_len")
  t.eq("length: nothing was added", registry.count(), 0)

  -- ---------- the snapshot is re-validated, not trusted ----------
  --
  -- The snapshot is a JSON file in the cache directory: writable by anything
  -- running as this user, and hand-editable. It is the plugin's only external
  -- input.
  registry.clear()
  local restored = registry.restore({
    { text = too_long, slot = 1, kind = "literal" }, -- over the length cap
    { text = "fine", slot = 1, kind = "literal" },
    { text = 42, slot = 1, kind = "literal" }, -- wrong type
    { text = "", slot = 1, kind = "literal" }, -- empty
    "not a table", -- wrong shape entirely
    { slot = 1, kind = "literal" }, -- no text at all
  })
  t.eq("snapshot: only the one valid entry survives", restored, 1)
  t.eq("snapshot: and it is the right one", registry.all()[1].text, "fine")

  -- A crafted snapshot cannot inject a pattern: the regex is rebuilt from
  -- `text`, so any `pattern` field in the file is simply ignored.
  registry.clear()
  registry.restore({
    { text = "plain", slot = 1, kind = "literal", pattern = "\\C\\V.*evil.*" },
  })
  t.eq("snapshot: a pattern field in the file is ignored", registry.all()[1].pattern, "\\C\\Vplain")

  -- Escaping holds for text that is regex-special in other dialects. `\V`
  -- leaves the backslash as the only special character, so that is all that
  -- needs escaping — and the result must match the literal text.
  registry.clear()
  local nasty = [[a.*b[c]d\e^f$g]]
  registry.add({ text = nasty, kind = "literal" })
  local re = require("spotlight.core.pattern").compile(registry.all()[1].pattern)
  t.ok("escaping: the pattern compiles", re ~= nil)
  t.ok("escaping: it matches the literal text", re:match_str("xx" .. nasty .. "yy") ~= nil)
  t.eq("escaping: and does not match what the metacharacters would have meant", re:match_str("aXXXbcd e f g"), nil)
  registry.clear()

  -- ---------- resolver line-length bound ----------
  --
  -- A minified single-line JSON log is a normal thing to be handed. The scan is
  -- O(line) per pattern and a user pattern may backtrack, so above the limit the
  -- scan is skipped entirely and <cword> answers instead.
  config.setup({ cursor = { max_line_len = 64 } })
  local long_line = "word " .. string.rep("x", 200)
  t.fixture({ long_line })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local tok = cursor.token()
  t.eq("line cap: <cword> still answers on an over-long line", tok and tok.text, "word")

  -- Under the limit, the pattern scan runs as usual.
  config.setup({ cursor = { max_line_len = 8192 } })
  t.fixture({ "id=10.0.0.1 rest" })
  t.ok("line cap: cursor placed", t.cursor_on(1, "10.0.0.1"))
  t.eq("line cap: under the limit the pattern scan still wins", cursor.token().text, "10.0.0.1")

  -- ---------- visual selection cap ----------
  config.setup()
  t.fixture({ string.rep("z", max_len + 100) })
  vim.cmd("normal! ggv$")
  local sel, sel_err = cursor.selection()
  t.eq("selection: an over-long selection is refused", sel, nil)
  t.contains("selection: the refusal names the option", sel_err, "match.max_text_len")
  vim.cmd("normal! \27")

  -- ---------- quickfix entry cap ----------
  --
  -- Unlike counting, filtering *produces* memory: one entry per matching line,
  -- each holding the full line text.
  local lines = {}
  for i = 1, 50 do
    lines[i] = "hit " .. i
  end
  local bufnr = t.fixture(lines)
  registry.clear()
  registry.add({ text = "hit", kind = "literal" })
  local pat = registry.all()[1].pattern

  local all, truncated = count.matching_lines(bufnr, { pat }, 10000)
  t.eq("qf cap: unbounded run finds every line", #all, 50)
  t.eq("qf cap: and reports no truncation", truncated, false)

  local capped, was_truncated = count.matching_lines(bufnr, { pat }, 10)
  t.eq("qf cap: the cap is honoured exactly", #capped, 10)
  t.eq("qf cap: and truncation is reported", was_truncated, true)

  config.setup({ quickfix = { open = false, max_entries = 5 } })
  vim.api.nvim_set_current_buf(bufnr)
  local found = require("spotlight.qf").fill(nil)
  t.eq("qf cap: fill() stops at the cap", found, 5)
  t.contains("qf cap: the quickfix title says it was truncated", vim.fn.getqflist({ title = 1 }).title, "first 5")
  vim.fn.setqflist({}, "r")

  -- ---------- swatch sanitization ----------
  --
  -- The swatch goes straight into the chooser's buffer line, and
  -- nvim_buf_set_lines treats an embedded newline as a hard error.
  config.setup({ list = { swatch = "a\nb" } })
  t.eq("swatch: the newline is replaced, not passed through", config.get("list.swatch"), "a b")
  t.ok("swatch: and the substitution is reported", #config.issues >= 1)

  config.setup({ list = { swatch = 42 } })
  t.eq("swatch: a non-string falls back to the default", config.get("list.swatch"), "  ")

  -- ---------- the new numeric guards validate ----------
  config.setup({
    match = { max_text_len = 0 },
    cursor = { max_line_len = -1 },
    quickfix = { max_entries = "lots" },
  })
  t.eq("validate: a zero max_text_len falls back", config.get("match.max_text_len"), 512)
  t.eq("validate: a negative max_line_len falls back", config.get("cursor.max_line_len"), 8192)
  t.eq("validate: a non-numeric max_entries falls back", config.get("quickfix.max_entries"), 10000)

  -- ---------- exception keys are data, never paths to open ----------
  --
  -- A `..` in a persisted key cannot escape anything, because the key is only
  -- ever a table key and a JSON field — the plugin performs no file IO of its own.
  config.setup()
  local persist = require("spotlight.persist")
  persist.set_exception("../../../etc/passwd", false)
  t.eq("paths: a traversal-looking key is stored as an opaque key", persist.persists("../../../etc/passwd"), false)
  t.eq("paths: and affects nothing else", persist.persists("logs/a.log"), true)
  persist.set_exception("../../../etc/passwd", nil)

  registry.clear()
  config.setup()
end

return M
