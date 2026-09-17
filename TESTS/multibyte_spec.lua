-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a resolved token -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/multibyte_spec.lua
-- Byte offsets in real multibyte content, asserted against handcounted byte
-- columns rather than against "the call returned something".
--
-- Why this file exists, and why the numbers are spelled out. Every position
-- this plugin computes is a BYTE offset: `\%23c` is a byte column (`\%23v`
-- would be the display column), `string.find` counts bytes, `vim.regex`'s
-- `match_str` returns bytes, a quickfix `col` is a byte index, and
-- `nvim_win_get_cursor` reports bytes. A position computed in characters --
-- or a slice that stops at a character's first byte -- does not fail loudly:
-- it lands in the wrong column, or cuts a codepoint in half, and the only
-- visible symptom is a highlight that never appears.
--
-- So the fixture below is annotated with the exact byte columns, every
-- assertion compares against those, and the one place that genuinely cuts a
-- codepoint is pinned with a `BUG:` assertion instead of being smoothed over.

local t = require("harness")

local M = {}

-- ---------- the fixture, with its byte columns spelled out ----------
--
-- L1  "Ä req=aaa Ö"          Ä = C3 84 (2 B), Ö = C3 96 (2 B)
--      bytes 1-2  Ä
--      byte  3    space
--      bytes 4-7  req=
--      bytes 8-10 aaa        <- 1-based byte column 8
--      byte  11   space
--      bytes 12-13 Ö         total 13 bytes, 11 characters
--
-- L2  "日本語 error 日本語"   each CJK glyph = 3 B
--      bytes 1-9   日本語
--      byte  10    space
--      bytes 11-15 error     <- 1-based byte column 11 (character column 5)
--      byte  16    space
--      bytes 17-25 日本語     total 25 bytes, 13 characters
--
-- L3  "🚀 boom 🚀"            each emoji = 4 B
--      bytes 1-4   🚀
--      byte  5     space
--      bytes 6-9   boom      <- 1-based byte column 6
--      byte  10    space
--      bytes 11-14 🚀         total 14 bytes, 8 characters
--
-- L4  "Ärger und Ärger"
--      bytes 1-6   Ärger     <- first occurrence, byte column 1
--      bytes 7-11  " und "
--      bytes 12-17 Ärger     <- second occurrence, byte column 12
--                            total 17 bytes, 15 characters
local L1 = "Ä req=aaa Ö"
local L2 = "日本語 error 日本語"
local L3 = "🚀 boom 🚀"
local L4 = "Ärger und Ärger"

function M.run()
  local config = require("spotlight.config")
  local count = require("spotlight.core.count")
  local cursor = require("spotlight.cursor")
  local map = require("spotlight.map")
  local pattern = require("spotlight.core.pattern")
  local registry = require("spotlight.core.registry")
  local yank = require("spotlight.yank")

  config.setup()
  require("spotlight.core.palette").apply()
  -- The `:Spotlight` verb, for the two Ex-route pins at the end. Registered
  -- here rather than via `setup()` so this spec stays independent of run order
  -- without also arming the keymap preset and the persistence autocmds.
  if vim.fn.exists(":Spotlight") ~= 2 then
    require("spotlight.bindings.usrcmds").setup()
  end
  registry.clear()

  local bufnr = t.fixture({ L1, L2, L3, L4 })

  -- ---------- the fixture itself ----------
  -- Asserted first: every number below is derived from these, so a file that
  -- lost its encoding somewhere must fail here and not fifty assertions later.
  t.eq("fixture: L1 is 13 bytes", #L1, 13)
  t.eq("fixture: L1 is 11 characters", vim.fn.strchars(L1), 11)
  t.eq("fixture: aaa starts at byte 8 of L1", L1:find("aaa", 1, true), 8)
  t.eq("fixture: L2 is 25 bytes", #L2, 25)
  t.eq("fixture: L2 is 13 characters", vim.fn.strchars(L2), 13)
  t.eq("fixture: error starts at byte 11 of L2", L2:find("error", 1, true), 11)
  t.eq("fixture: error starts at character 5 of L2", vim.fn.charidx(L2, 10) + 1, 5)
  t.eq("fixture: L3 is 14 bytes", #L3, 14)
  t.eq("fixture: boom starts at byte 6 of L3", L3:find("boom", 1, true), 6)
  t.eq("fixture: L4 is 17 bytes", #L4, 17)
  t.eq("fixture: the second Ärger starts at byte 12 of L4", L4:find("Ärger", 2, true), 12)
  t.eq("fixture: the buffer round-trips the bytes unchanged", vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1], L2)

  -- ---------- \%Nc is a byte column, not a character or display column ----------
  --
  -- This is the invariant every position-pinned spotlight rests on:
  -- `core.pattern.build_at` writes `cursor.token`'s byte column straight into
  -- `\%Nc`. If that atom counted characters, every pin in multibyte text would
  -- silently miss -- so it is verified here rather than assumed, including the
  -- negative case that would pass if the two happened to coincide.
  local opts = config.get("match")
  local pat_byte = pattern.build_at("error", 2, 11, opts)
  local pat_char = pattern.build_at("error", 2, 5, opts)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  t.eq("build_at: the byte column matches", vim.fn.search(pat_byte, "cnw"), 2)
  t.eq("build_at: and matches at exactly that byte", vim.inspect(vim.fn.searchpos(pat_byte, "cnw")), vim.inspect({ 2, 11 }))
  t.eq("build_at: the character column does NOT match (\\%c counts bytes)", vim.fn.search(pat_char, "cnw"), 0)
  -- The same column read as a display column would also miss: 日本語 is three
  -- glyphs of two cells each, so `error` sits at display column 8, not 11.
  t.eq("build_at: \\%Nv (display column) would have been a different atom", vim.fn.search("\\%8verror", "cnw"), 2)
  t.eq("build_at: ...and \\%11v is not where error is", vim.fn.search("\\%11verror", "cnw"), 0)

  -- ---------- cursor.token returns byte columns in multibyte text ----------
  vim.api.nvim_win_set_cursor(0, { 2, 10 }) -- 0-based byte 10 = the `e` of error
  local tok, pos = cursor.token()
  t.eq("cursor/CJK: resolved the ASCII token between CJK runs", tok.text, "error")
  t.eq("cursor/CJK: position is the 1-based BYTE column", pos.col1, 11)
  t.eq("cursor/CJK: row is 1-based", pos.row1, 2)

  vim.api.nvim_win_set_cursor(0, { 1, 7 }) -- 0-based byte 7 = the first `a`
  local tok1, pos1 = cursor.token()
  t.eq("cursor/umlaut: resolved aaa", tok1.text, "aaa")
  t.eq("cursor/umlaut: byte column 8, not character column 7", pos1.col1, 8)

  vim.api.nvim_win_set_cursor(0, { 3, 5 }) -- 0-based byte 5 = the `b` of boom
  local tok3, pos3 = cursor.token()
  t.eq("cursor/emoji: resolved boom after a 4-byte emoji", tok3.text, "boom")
  t.eq("cursor/emoji: byte column 6, not character column 3", pos3.col1, 6)

  -- The cursor ON a multibyte glyph resolves the glyph run itself, classified
  -- `literal` -- `%w` is byte-wise and ASCII-only, so a CJK run can never be
  -- given `\<`/`\>` word boundaries (which is correct: they would match nothing).
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local tok_cjk, pos_cjk = cursor.token()
  t.eq("cursor/on CJK: the glyph run is the token", tok_cjk.text, "日本語")
  t.eq("cursor/on CJK: classified literal, so it gets no word boundaries", tok_cjk.kind, "literal")
  t.eq("cursor/on CJK: byte column 1", pos_cjk.col1, 1)
  t.eq("cursor/on CJK: no \\< in the built pattern", pattern.build(tok_cjk, opts):find("\\<", 1, true), nil)

  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  local tok_u = cursor.token()
  t.eq("cursor/on umlaut: the whole word, not the ASCII tail", tok_u.text, "Ärger")
  t.eq("cursor/on umlaut: literal, so no boundaries", tok_u.kind, "literal")

  -- ---------- a position-pinned spotlight lands on the right byte ----------
  registry.clear()
  local second = registry.add_at({ text = "Ärger", kind = "literal" }, { buf = bufnr, row1 = 4, col1 = 12 })
  t.ok("add_at/multibyte: created", second ~= nil)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  t.eq(
    "add_at/multibyte: matches the SECOND Ärger, at byte 12",
    vim.inspect(vim.fn.searchpos(second.pattern, "cnw")),
    vim.inspect({ 4, 12 })
  )
  -- The character column of the second occurrence is 11, one less than its byte
  -- column: a pin built from characters would have landed inside " und ".
  local wrong = pattern.build_at("Ärger", 4, 11, opts)
  t.eq("add_at/multibyte: the character column would have missed", vim.fn.search(wrong, "cnw"), 0)
  registry.clear()

  -- ---------- scan columns are byte columns too ----------
  local aaa = registry.add({ text = "aaa", kind = "literal" })
  local err_item = registry.add({ text = "error", kind = "literal" })
  local boom = registry.add({ text = "boom", kind = "literal" })

  local entries = count.matching_lines(bufnr, { aaa.pattern, err_item.pattern, boom.pattern }, 100)
  t.eq("matching_lines: three lines matched", #entries, 3)
  t.eq("matching_lines: L1's col is byte 8", entries[1].col, 8)
  t.eq("matching_lines: L2's col is byte 11", entries[2].col, 11)
  t.eq("matching_lines: L3's col is byte 6", entries[3].col, 6)
  t.eq("matching_lines: the reported text keeps its bytes", entries[2].text, L2)

  local by_item = count.matching_lines_by_item(bufnr, { aaa, err_item, boom }, 100)
  t.eq("matching_lines_by_item: three lines", #by_item, 3)
  t.eq("matching_lines_by_item: L2's col is byte 11", by_item[2].col, 11)
  t.eq("matching_lines_by_item: the winning item is the one whose pattern hit", by_item[2].item.id, err_item.id)

  -- A count over multibyte neighbours: two `Ärger` on one line, and an `aaa`
  -- wedged between two 2-byte umlauts.
  local arger = registry.add({ text = "Ärger", kind = "literal" })
  t.eq("count/multibyte: both occurrences on the line", (count.count(bufnr, arger, 100000)), 2)
  t.eq("count/multibyte: aaa between umlauts is found exactly once", (count.count(bufnr, aaa, 100000)), 1)
  t.eq("count/multibyte: the CJK-flanked token is found", (count.count(bufnr, err_item, 100000)), 1)

  -- A multibyte token as the spotlight itself: 日本語 twice on its line.
  local cjk = registry.add({ text = "日本語", kind = "literal" })
  t.eq("count/CJK token: both runs counted", (count.count(bufnr, cjk, 100000)), 2)
  t.eq(
    "search/CJK token: the first run starts at byte 1",
    vim.inspect(vim.fn.searchpos(cjk.pattern, "cnw")),
    vim.inspect({ 2, 1 })
  )
  -- `escape` only doubles backslashes, so the UTF-8 bytes survive verbatim --
  -- the property that makes a `\V` literal pattern usable on any encoding.
  t.eq("pattern.escape: multibyte bytes pass through untouched", pattern.escape("日本語"), "日本語")

  -- ---------- yank keeps the bytes ----------
  local before_reg = vim.fn.getreg('"')
  local found = yank.yank(cjk)
  t.eq("yank/multibyte: one matching line", found, 1)
  t.eq("yank/multibyte: the register holds the line verbatim", vim.fn.getreg('"'), L2 .. "\n")
  vim.fn.setreg('"', before_reg)

  -- ---------- no extmark may start inside a codepoint ----------
  --
  -- `spotlight.map` is the only extmark consumer in the plugin, and it places
  -- its sign at column 0 by construction. Asserted rather than assumed,
  -- because a sign placed at a computed column is exactly where a byte/char
  -- mix-up would surface as `col out of range` or as a split glyph.
  local marked = map.show(nil)
  t.eq("map/multibyte: one sign per matching line", marked, 4)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, map.namespace(), 0, -1, {})
  t.eq("map/multibyte: four extmarks placed", #marks, 4)
  local all_at_zero, on_a_boundary = true, true
  for _, m in ipairs(marks) do
    local row, col = m[2], m[3]
    if col ~= 0 then
      all_at_zero = false
    end
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    -- `str_utf_start` is 0 only when the byte index already sits on a
    -- codepoint's first byte; anything else means the mark split a glyph.
    if vim.str_utf_start(line, col + 1) ~= 0 then
      on_a_boundary = false
    end
  end
  t.ok("map/multibyte: every sign sits at column 0", all_at_zero)
  t.ok("map/multibyte: no extmark begins inside a codepoint", on_a_boundary)
  map.clear(bufnr)
  registry.clear()

  -- ---------- BUG: a charwise selection ending on a multibyte glyph is cut in half ----------
  --
  -- `cursor.selection` slices the line with `col('v')` .. `col('.')`, and
  -- `col('.')` is the byte index of the FIRST byte of the character under the
  -- cursor -- not of its last. So selecting a single `Ä` / `日` / `🚀`, or any
  -- run whose final character is multibyte, yields a truncated UTF-8 sequence.
  --
  -- The refusal that would make this loud does not exist: the registry accepts
  -- the broken bytes, `matchadd()` accepts the pattern, the user is told
  -- "spotlight 1: <mojibake>" -- and nothing ever lights up, because neither
  -- `search()` nor `vim.regex` can match half a codepoint. Two consequences
  -- worth naming: several distinct glyphs sharing a lead byte collapse onto
  -- the same spotlight text, and the toggle identity is that same broken text.
  --
  -- The fix is to extend the end column to the end of its character
  -- (`vim.str_utf_end`) in `cursor.selection` and in
  -- `bindings/usrcmds.range_text`, which reads `'>` and has the same defect.
  -- Pinned rather than fixed: it changes what two user-facing entry points
  -- produce.
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.cmd("normal! v")
  t.eq("selection: visual mode is active", vim.fn.mode(), "v")
  local sel = cursor.selection()
  t.eq("selection: col('v') and col('.') are both the umlaut's first byte", vim.fn.col("v"), vim.fn.col("."))
  t.eq("BUG: selecting a single 2-byte Ä yields 1 byte, not 2", sel and #sel.text, 1)
  t.eq("BUG: and that byte is the lead byte alone", sel and sel.text, "\195")
  vim.cmd("normal! " .. vim.keycode("<Esc>"))

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! v")
  local sel_cjk = cursor.selection()
  t.eq("BUG: a single 3-byte CJK glyph yields 1 byte", sel_cjk and #sel_cjk.text, 1)
  vim.cmd("normal! " .. vim.keycode("<Esc>"))

  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.cmd("normal! v")
  local sel_emoji = cursor.selection()
  t.eq("BUG: a single 4-byte emoji yields 1 byte", sel_emoji and #sel_emoji.text, 1)
  vim.cmd("normal! " .. vim.keycode("<Esc>"))

  -- A run whose last character is multibyte loses only that character's tail,
  -- which is the quieter and more likely shape of the same defect.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("normal! v")
  local sel_run = cursor.selection()
  t.eq("BUG: 'Ä' selected as a run still yields only the lead byte", sel_run and #sel_run.text, 1)
  vim.cmd("normal! " .. vim.keycode("<Esc>"))

  -- The contrast, so the pin cannot be read as "visual mode never works": a
  -- selection ending on an ASCII byte is exact, multibyte content and all.
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.cmd("normal! v4l")
  local sel_ok = cursor.selection()
  t.eq("selection: a run ending on an ASCII byte is exact", sel_ok and sel_ok.text, "Ärger")
  vim.cmd("normal! " .. vim.keycode("<Esc>"))

  -- ---------- BUG: what the truncated token then does ----------
  registry.clear()
  local broken = registry.add({ text = "\195", kind = "literal" })
  t.ok("BUG: the registry accepts a half codepoint without complaint", broken ~= nil)
  t.ok("BUG: matchadd() accepts the pattern too", pattern.compile(broken.pattern) ~= nil)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  t.eq("BUG: but search() never finds it in a buffer full of Ä and Ö", vim.fn.search(broken.pattern, "cnw"), 0)
  t.eq("BUG: and the count reads 0, so the list shows a spotlight matching nothing", (count.count(bufnr, broken, 100000)), 0)
  -- Ö (C3 96) and Ä (C3 84) share a lead byte, so two visibly different
  -- selections collapse onto one spotlight text -- the second is refused as a
  -- duplicate of the first.
  local dup, dup_err = registry.add({ text = "\195", kind = "literal" })
  t.eq("BUG: a different glyph with the same lead byte is refused as a duplicate", dup, nil)
  t.contains("BUG: ...and says 'already spotlighted'", dup_err, "already spotlighted")
  registry.clear()

  -- ---------- the same defect through the Ex route ----------
  -- `bindings/usrcmds.range_text` reads composer's `ctx.range.col1/col2`, which
  -- come off the `'<`/`'>` marks -- `'>` is the first byte of the last
  -- character, exactly like `col('.')` above.
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.cmd("normal! v")
  vim.cmd("normal! " .. vim.keycode("<Esc>"))
  t.eq("marks: '< and '> both land on the umlaut's first byte", vim.fn.col("'<"), vim.fn.col("'>"))
  vim.cmd("'<,'>Spotlight toggle")
  t.eq("BUG: :'<,'>Spotlight toggle created a spotlight", registry.count(), 1)
  t.eq("BUG: ...whose text is the same single lead byte", #registry.all()[1].text, 1)
  registry.clear()

  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.cmd("normal! v")
  vim.cmd("normal! " .. vim.keycode("<Esc>"))
  vim.cmd("'<,'>Spotlight here")
  t.eq("BUG: :'<,'>Spotlight here created a pinned spotlight", registry.count(), 1)
  t.eq("BUG: ...also from a half codepoint", #registry.all()[1].text, 1)
  t.eq("BUG: ...and its position-pinned pattern matches nothing", vim.fn.search(registry.all()[1].pattern, "cnw"), 0)
  registry.clear()

  -- ---------- hover's token test is byte-wise and ASCII-only ----------
  -- Pinned as behaviour, not a defect: `token_at`'s allowed-character class is
  -- a Lua pattern over bytes, so a multibyte glyph is never "a token" and the
  -- preview declines. A spotlighted 日本語 therefore never gets a count --
  -- worth knowing before someone reports the float as broken.
  local hover = require("spotlight.hover")
  t.eq("hover/token_at: declines on a CJK glyph", hover.token_at(L2, 0), nil)
  t.eq("hover/token_at: declines on an emoji", hover.token_at(L3, 0), nil)
  t.eq("hover/token_at: the ASCII run between them is found", hover.token_at(L2, 10), "error")
  -- An umlaut inside a word cuts the run at the byte, which is why the
  -- resolver's own `<cword>` fallback exists.
  t.eq("hover/token_at: an umlaut ends the run", hover.token_at(L4, 2), "rger")

  registry.clear()
  config.setup()
end

return M
