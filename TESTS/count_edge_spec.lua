-- Test code: when something here comes back nil -- a fixture read, a compiled
-- regex, a scan result -- this file must crash and name it. The nil guards
-- LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- Several cases hand in hand-built items (a bare `pattern`, a fabricated pin)
-- to reach scan paths the registry would never produce.
-- TESTS/count_edge_spec.lua
-- `spotlight.core.count`'s caps and merges — the parts that only show up on
-- inputs the happy path never produces: the entry caps and the "stop scanning,
-- not just appending" rule, the chunk boundary of the 5000-line reads, the
-- merge of a position-pinned item into a regex scan, a pattern Vim refuses, and
-- a pattern that matches the empty string (which would otherwise spin forever).
--
-- The scan is the one O(buffer) operation in the plugin, so its bounds are not
-- cosmetic: `quickfix.max_entries`/`map.max_entries` are what stop a filter on a
-- large log from building a list the size of the file.

local t = require("harness")

local M = {}

---@internal
--- An ordinary (`buftype == ""`) buffer, so `scannable_buffers` accepts it.
---@param lines string[]
---@return integer bufnr
local function real_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

function M.run()
  local config = require("spotlight.config")
  local count = require("spotlight.core.count")
  local qf = require("spotlight.qf")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()

  -- ---------- a pattern Vim refuses ----------
  local broken = { pattern = "\\V\\%(", id = -1, text = "broken", slot = 1, hl = "Spotlight1" }
  local n, scanned = count.count(real_buffer({ "anything" }), broken, 1000)
  t.eq("count: an uncompilable pattern is 'not counted' (nil), not a real zero (ERR-11)", n, nil)
  t.eq("count: and reports zero lines scanned", scanned, 0)
  local entries, truncated = count.matching_lines(real_buffer({ "anything" }), { "\\V\\%(" }, 10)
  t.eq("matching_lines: an uncompilable pattern yields no entries", #entries, 0)
  t.eq("matching_lines: and is not reported as truncated", truncated, false)
  t.eq("matching_lines: an empty pattern list is the same", #(count.matching_lines(real_buffer({ "x" }), {}, 10)), 0)

  -- ---------- a pattern that matches the empty string ----------
  -- `\.\*` is "any character, any number of times" in `\V`, so it matches at
  -- every position including end-of-line. `count_in_line` advances by one byte
  -- on a zero-width match specifically so this terminates; without that guard
  -- the editor would hang on the first such spotlight.
  local zero_width = { pattern = "\\C\\V\\.\\*", id = -2, text = "zw", slot = 1, hl = "Spotlight1" }
  local buf_zw = real_buffer({ "abc", "", "de" })
  local ok_zw, zw_n = pcall(count.count, buf_zw, zero_width, 1000)
  t.ok("count: a zero-width-matching pattern terminates", ok_zw)
  t.ok("count: ...with a finite count", type(zw_n) == "number" and zw_n < 100)

  -- ---------- the chunk boundary ----------
  -- Lines are fetched 5000 at a time, so a match on the last line of the first
  -- chunk, the first of the second, and the last of the buffer all have to be
  -- reported with the right `lnum`.
  local big = {}
  for i = 1, 5002 do
    big[i] = "filler " .. i
  end
  big[1] = "req=edge first"
  big[5000] = "req=edge chunk-end"
  big[5001] = "req=edge chunk-start"
  big[5002] = "req=edge last"
  local buf_big = real_buffer(big)
  local item_edge = registry.add({ text = "req=edge", kind = "literal" })
  t.eq("chunking: the buffer really is longer than one chunk", vim.api.nvim_buf_line_count(buf_big), 5002)
  t.eq("chunking: every occurrence across the boundary is counted", (count.count(buf_big, item_edge, 10000)), 4)
  local edge_entries = count.matching_lines(buf_big, { item_edge.pattern }, 100)
  t.eq("chunking: four entries", #edge_entries, 4)
  t.eq("chunking: lnum 1", edge_entries[1].lnum, 1)
  t.eq("chunking: lnum 5000 (last line of chunk one)", edge_entries[2].lnum, 5000)
  t.eq("chunking: lnum 5001 (first line of chunk two)", edge_entries[3].lnum, 5001)
  t.eq("chunking: lnum 5002 (last line of the buffer)", edge_entries[4].lnum, 5002)
  t.eq("count: a buffer one line over the ceiling is declined, not counted", count.count(buf_big, item_edge, 5001), nil)
  t.eq("count: exactly at the ceiling it is counted", (count.count(buf_big, item_edge, 5002)), 4)

  -- ---------- the entry cap ----------
  local capped, was_truncated = count.matching_lines(buf_big, { item_edge.pattern }, 2)
  t.eq("cap: exactly max_entries entries are returned", #capped, 2)
  t.eq("cap: and truncation is reported", was_truncated, true)
  t.eq("cap: the entries kept are the first ones in buffer order", capped[1].lnum, 1)
  t.eq("cap: ...and the second", capped[2].lnum, 5000)

  -- An omitted / nonsensical cap falls back to the configured one rather than to
  -- "unbounded": a guard whose absence removes the guard is worse than none.
  config.setup({ quickfix = { max_entries = 1 } })
  local defaulted = count.matching_lines(buf_big, { item_edge.pattern }, nil)
  t.eq("cap: nil falls back to quickfix.max_entries", #defaulted, 1)
  local defaulted0 = count.matching_lines(buf_big, { item_edge.pattern }, 0)
  t.eq("cap: 0 falls back too", #defaulted0, 1)
  local defaulted_neg = count.matching_lines(buf_big, { item_edge.pattern }, -5)
  t.eq("cap: a negative cap falls back as well", #defaulted_neg, 1)
  config.setup()

  -- ---------- matching_lines_for: the pinned merge ----------
  registry.clear()
  local buf_mix = real_buffer({
    "req=aaa one", -- 1: global hit
    "nothing here", -- 2
    "req=bbb two", -- 3: pinned hit only
    "req=aaa three", -- 4: global hit AND a pin -> one entry
  })
  local g = registry.add({ text = "req=aaa", kind = "literal" })
  local p3 = registry.add_at({ text = "req=bbb", kind = "literal" }, { buf = buf_mix, row1 = 3, col1 = 1 })
  local p4 = registry.add_at({ text = "req=aaa", kind = "literal" }, { buf = buf_mix, row1 = 4, col1 = 1 })

  local mixed, mixed_trunc = count.matching_lines_for(buf_mix, { g, p3, p4 }, 100)
  t.eq("for: three lines, not four -- the doubly-matched line 4 appears once", #mixed, 3)
  t.eq("for: not truncated", mixed_trunc, false)
  t.eq("for: sorted in buffer order (1)", mixed[1].lnum, 1)
  t.eq("for: sorted in buffer order (3)", mixed[2].lnum, 3)
  t.eq("for: sorted in buffer order (4)", mixed[3].lnum, 4)
  t.eq("for: the pinned-only line carries its own recorded column", mixed[2].col, 1)
  t.eq("for: and the buffer's text", mixed[2].text, "req=bbb two")

  -- A pin belonging to another buffer is skipped rather than reported here.
  local buf_other = real_buffer({ "req=zzz" })
  local p_other = registry.add_at({ text = "req=zzz", kind = "literal" }, { buf = buf_other, row1 = 1, col1 = 1 })
  local no_leak = count.matching_lines_for(buf_mix, { p_other }, 100)
  t.eq("for: a pin from another buffer contributes nothing", #no_leak, 0)

  -- Truncation in the regex phase short-circuits the pinned merge entirely --
  -- the answer is already known to be incomplete, so the extra reads are pure cost.
  local short, short_trunc = count.matching_lines_for(buf_mix, { g, p3 }, 1)
  t.eq("for: the regex phase's cap stops the whole scan", #short, 1)
  t.eq("for: and is reported", short_trunc, true)
  t.eq("for: the pinned line was not merged in", short[1].lnum, 1)

  -- The cap can also be reached *during* the pinned merge: two pinned-only
  -- lines with a cap of one global hit plus one pin.
  local buf_pins = real_buffer({ "one", "two", "three" })
  local pa = registry.add_at({ text = "one", kind = "literal" }, { buf = buf_pins, row1 = 1, col1 = 1 })
  local pb = registry.add_at({ text = "two", kind = "literal" }, { buf = buf_pins, row1 = 2, col1 = 1 })
  local pins, pins_trunc = count.matching_lines_for(buf_pins, { pa, pb }, 1)
  t.eq("for: the cap applies to the pinned merge too", #pins, 1)
  t.eq("for: and reports truncation from there", pins_trunc, true)

  -- ---------- matching_lines_by_item: which item won the line ----------
  registry.clear()
  local buf_by = real_buffer({
    "zzz then aaa", -- 1: aaa at byte 10, zzz at byte 1 -> zzz wins (earlier column)
    "aaa alone", -- 2: aaa
    "nothing", -- 3
  })
  local a_item = registry.add({ text = "aaa", kind = "literal" })
  local z_item = registry.add({ text = "zzz", kind = "literal" })
  local by, by_trunc = count.matching_lines_by_item(buf_by, { a_item, z_item }, 100)
  t.eq("by_item: two lines matched", #by, 2)
  t.eq("by_item: not truncated", by_trunc, false)
  t.eq("by_item: the earliest column decides which item owns the line", by[1].item.id, z_item.id)
  t.eq("by_item: and the column is that item's", by[1].col, 1)
  t.eq("by_item: line 2 belongs to the only item that hit it", by[2].item.id, a_item.id)
  t.eq("by_item: its column too", by[2].col, 1)

  t.eq("by_item: no items at all yields nothing", #(count.matching_lines_by_item(buf_by, {}, 100)), 0)
  t.eq(
    "by_item: an item whose pattern Vim refuses is skipped, not fatal",
    #(count.matching_lines_by_item(buf_by, { broken }, 100)),
    0
  )

  local by_capped, by_capped_trunc = count.matching_lines_by_item(buf_by, { a_item, z_item }, 1)
  t.eq("by_item: the cap applies", #by_capped, 1)
  t.eq("by_item: and reports truncation", by_capped_trunc, true)

  -- The pinned half, including the sort that the appended pins require.
  registry.clear()
  local buf_bp = real_buffer({ "aaa first", "pin only", "aaa third" })
  local g2 = registry.add({ text = "aaa", kind = "literal" })
  local pin2 = registry.add_at({ text = "pin", kind = "literal" }, { buf = buf_bp, row1 = 2, col1 = 1 })
  local bp = count.matching_lines_by_item(buf_bp, { g2, pin2 }, 100)
  t.eq("by_item: pinned lines are merged in", #bp, 3)
  t.eq("by_item: and the result is re-sorted (1)", bp[1].lnum, 1)
  t.eq("by_item: and the result is re-sorted (2)", bp[2].lnum, 2)
  t.eq("by_item: and the result is re-sorted (3)", bp[3].lnum, 3)
  t.eq("by_item: the pinned entry carries the pinned item", bp[2].item.id, pin2.id)
  local bp_cap, bp_cap_trunc = count.matching_lines_by_item(buf_bp, { g2, pin2 }, 2)
  t.eq("by_item: the cap stops the pinned merge", #bp_cap, 2)
  t.eq("by_item: reported as truncated", bp_cap_trunc, true)
  config.setup({ map = { max_entries = 1 } })
  t.eq("by_item: nil falls back to map.max_entries, not to unbounded", #(count.matching_lines_by_item(buf_bp, { g2 }, nil)), 1)
  config.setup()

  -- ---------- count for a pinned item is a lookup, not a scan ----------
  registry.clear()
  local buf_pin = real_buffer({ "req=aaa" })
  local buf_nopin = real_buffer({ "req=aaa" })
  local pin = registry.add_at({ text = "req=aaa", kind = "literal" }, { buf = buf_pin, row1 = 1, col1 = 1 })
  local pn, plines = count.count(buf_pin, pin, 100000)
  t.eq("count/pinned: one known point in its own buffer", pn, 1)
  t.eq("count/pinned: reported as one line scanned, which is a real count", plines, 1)
  t.eq("count/pinned: zero in any other buffer", (count.count(buf_nopin, pin, 100000)), 0)
  -- The ceiling does not apply: there is no scan to decline.
  t.eq("count/pinned: the max_lines ceiling is irrelevant to a lookup", (count.count(buf_pin, pin, 0)), 1)

  -- ---------- qf.fill_all spends one shared budget across buffers ----------
  -- A token that appears in no other buffer this spec left loaded: `fill_all`
  -- scans *every* scannable buffer, so a shared token would count the fixtures.
  registry.clear()
  local b1 = real_buffer({ "req=fillall", "req=fillall" })
  local b2 = real_buffer({ "req=fillall", "req=fillall" })
  vim.api.nvim_set_current_buf(b1)
  registry.add({ text = "req=fillall", kind = "literal" })
  config.setup({ quickfix = { max_entries = 3, open = false } })
  local found, err, trunc = qf.fill_all(nil)
  t.eq("fill_all: no error", err, nil)
  t.eq("fill_all: the cap is global, not per buffer", found, 3)
  t.eq("fill_all: and truncation is reported", trunc, true)
  config.setup({ quickfix = { open = false } })
  local found_all = qf.fill_all(nil)
  t.eq("fill_all: with room, every matching line across both buffers", found_all, 4)
  vim.fn.setqflist({})
  config.setup()

  registry.clear()
  for _, b in ipairs({ buf_big, buf_mix, buf_other, buf_pins, buf_by, buf_bp, buf_pin, buf_nopin, b1, b2, buf_zw }) do
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
  config.setup()
end

return M
