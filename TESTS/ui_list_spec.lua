-- Test code: when something here comes back nil -- a captured chooser call, a
-- rendered row -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/ui_list_spec.lua
-- `spotlight.ui.list`: the chooser's *input* and its selection handlers.
--
-- ui.nvim is not on this suite's runtimepath (CI checks out lib.nvim only, and
-- `TESTS/README.md` says the chooser float is exercised through `ui.kit.select`'s
-- own contract rather than from here), so `ui.kit.select` is replaced with a
-- double that records the option table it was handed. That is the whole surface
-- this module owns: which rows it builds, how they are labelled and counted,
-- which highlight span the swatch gets, what the title says, and what each mode
-- does to the registry when an entry comes back. No float is opened and no
-- rendering is asserted.

local t = require("harness")

local M = {}

local SELECT = "ui.kit.select"

---@internal
--- Open the list with a recording chooser and hand back what it was given.
---@param mode string|nil
---@param filter string|nil
---@return table|nil opts, { msg: string, level: integer|nil }[] notices
local function open_capturing(mode, filter)
  local captured, seen = nil, {}
  local saved_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    seen[#seen + 1] = { msg = tostring(msg), level = level }
  end
  t.with_modules({
    [SELECT] = {
      open = function(opts)
        captured = opts
      end,
    },
  }, function()
    require("spotlight.ui.list").open(mode, filter)
  end)
  vim.notify = saved_notify
  return captured, seen
end

function M.run()
  local config = require("spotlight.config")
  local list = require("spotlight.ui.list")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()

  -- ---------- M.filter ----------
  local items = {
    { id = 1, text = "req=aaa", slot = 1, hl = "Spotlight1", origin = "logs/app.log" },
    { id = 2, text = "TIMEOUT", slot = 2, hl = "Spotlight2", origin = "logs/worker.log" },
    { id = 3, text = "other", slot = 10, hl = "Spotlight10" },
  }

  local by_text = list.filter(items, "aaa")
  t.eq("filter: matches the spotlight's own text", #by_text, 1)
  t.eq("filter: the right one", by_text[1].id, 1)
  t.eq("filter: is case-insensitive", #(list.filter(items, "timeout")), 1)
  t.eq("filter: ...in both directions", #(list.filter(items, "TIMEout")), 1)
  t.eq("filter: matches the origin path", #(list.filter(items, "worker")), 1)
  t.eq("filter: matches the highlight group name", #(list.filter(items, "spotlight2")), 1)
  t.eq("filter: an item with no origin does not break the scan", #(list.filter(items, "logs/")), 2)
  t.eq("filter: no hit yields an empty list", #(list.filter(items, "nothing-like-this")), 0)

  -- BUG: a spotlight with no `origin` cannot be found by its own text.
  --
  -- The fields are walked with `ipairs({ item.hl, item.origin, item.text })`,
  -- and `ipairs` stops at the first nil. `origin` is nil for every spotlight
  -- created in a buffer without a file on disk (a scratch buffer, a terminal,
  -- `:Spotlight add` from the quickfix window) and for anything restored from a
  -- snapshot that predates the field -- so for those, index 2 is nil and
  -- `item.text` at index 3 is never examined at all. Only the highlight group
  -- name is left, which is the one field the user would never think to type.
  --
  -- The visible symptom is `:Spotlight list <its own text>` answering "no
  -- spotlight matching ..." about a spotlight that is plainly in the list.
  -- Fix: walk a nil-tolerant list (or test the three fields explicitly) instead
  -- of relying on `ipairs` over a table with a hole. Pinned rather than fixed:
  -- it widens what the filter matches, which is user-visible behaviour.
  t.eq("filter: an item WITH an origin is findable by its text", #(list.filter(items, "req=aaa")), 1)
  t.eq("BUG: an item WITHOUT an origin is not findable by its text", #(list.filter(items, "other")), 0)
  t.eq("BUG: ...although the very same item is findable by its highlight group", #(list.filter(items, "spotlight10")), 1)
  t.eq("BUG: ...and by its slot number", #(list.filter(items, "10")), 1)
  -- Proof that `origin` is the only thing standing in the way: give it one and
  -- the text becomes matchable.
  items[3].origin = "logs/scratch.log"
  t.eq("BUG: giving the item an origin makes its text matchable again", #(list.filter(items, "other")), 1)
  items[3].origin = nil

  -- A numeric query is *only* a slot query. The substring fallback would make
  -- "1" match slot 10 as well, through the "1" in its own group name.
  local by_slot = list.filter(items, "1")
  t.eq("filter: a numeric query matches exactly one slot", #by_slot, 1)
  t.eq("filter: slot 1, not slot 10", by_slot[1].slot, 1)
  t.eq("filter: slot 10 is reachable by its own number", list.filter(items, "10")[1].slot, 10)
  t.eq("filter: a slot nobody uses yields nothing", #(list.filter(items, "7")), 0)

  -- ---------- the guards before the chooser opens ----------
  local nothing, no_items = open_capturing("jump", nil)
  t.eq("open: an empty registry never reaches the chooser", nothing, nil)
  t.eq("open: and says so", #no_items, 1)
  t.contains("open: naming the reason", no_items[1].msg, "no active spotlights")

  local bufnr = t.fixture({ "req=aaa one", "req=bbb two", "req=aaa three" })
  registry.add({ text = "req=aaa", kind = "literal" }, { origin = "logs/app.log" })
  registry.add({ text = "req=bbb", kind = "literal" }, { origin = "logs/worker.log" })

  local no_match, filter_notices = open_capturing("jump", "nothing-matches-this")
  t.eq("open: a filter matching nothing never reaches the chooser either", no_match, nil)
  t.contains("open: and quotes the filter back", filter_notices[1].msg, "nothing-matches-this")

  -- ui.kit.select genuinely absent, and present-but-wrong-shaped.
  local seen_missing = {}
  local saved_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    seen_missing[#seen_missing + 1] = { msg = tostring(msg), level = level }
  end
  t.without_modules({ SELECT }, function()
    list.open("jump", nil)
  end)
  t.with_modules({ [SELECT] = { not_open = true } }, function()
    list.open("jump", nil)
  end)
  vim.notify = saved_notify
  t.eq("open: both a missing and a wrong-shaped ui.kit.select are reported", #seen_missing, 2)
  t.contains("open: naming the module", seen_missing[1].msg, "ui.kit.select")
  t.eq("open: at ERROR level", seen_missing[1].level, vim.log.levels.ERROR)

  -- ---------- the rows ----------
  local opts = open_capturing("jump", nil)
  t.eq("open: two rows for two spotlights", #opts.items, 2)
  t.eq("open: each row carries the item itself in .value", opts.items[1].value.text, "req=aaa")
  t.eq("open: and exactly one rendered line", #opts.items[1].lines, 1)
  t.contains("open: whose text holds the spotlight", opts.items[1].lines[1], "req=aaa")
  t.contains("open: and its match count in this buffer", opts.items[1].lines[1], "2")
  t.contains("open: the second row's count too", opts.items[2].lines[1], "1")

  local hl = opts.items[1].highlights[1]
  t.eq("open: exactly one highlight span per row -- the swatch", #opts.items[1].highlights, 1)
  t.eq("open: on the first line", hl.line, 0)
  t.eq("open: starting at column 0", hl.col_start, 0)
  t.eq("open: ending after the swatch's bytes", hl.col_end, #config.get("list.swatch"))
  t.eq("open: in the spotlight's own palette group", hl.hl_group, registry.all()[1].hl)
  t.contains("open: the default title is the jump one", opts.title, "select to jump")

  -- A wider swatch moves the span with it, which is the only thing tying the two
  -- together.
  config.setup({ list = { swatch = "####" } })
  local wide = open_capturing("jump", nil)
  t.eq("open: the swatch span follows list.swatch's byte length", wide.items[1].highlights[1].col_end, 4)
  config.setup()

  -- ---------- labels ----------
  registry.set_locked(registry.all()[1].id, true)
  registry.set_line(registry.all()[2].id, true)
  local pinned = registry.add_at({ text = "req=bbb", kind = "literal" }, { buf = bufnr, row1 = 2, col1 = 5 })
  local labelled = open_capturing("jump", nil)
  t.eq("open: the pinned item is listed too", #labelled.items, 3)
  t.contains("open: a locked item is tagged", labelled.items[1].lines[1], "(locked)")
  t.contains("open: a line-mode item is tagged", labelled.items[2].lines[1], "(whole line)")
  t.contains(
    "open: a buffer-scoped item is tagged -- nothing else in the list shows it",
    labelled.items[3].lines[1],
    "(this occurrence only)"
  )
  t.contains("open: and a pinned item counts as its own single occurrence", labelled.items[3].lines[1], "1")
  registry.set_locked(registry.all()[1].id, false)
  registry.set_line(registry.all()[2].id, false)
  registry.remove(pinned.id)

  -- ---------- counting: off, declined, and partial ----------
  config.setup({ list = { count = false } })
  local uncounted = open_capturing("jump", nil)
  t.contains("open: with list.count = false the count reads '?'", uncounted.items[1].lines[1], "?")
  t.eq("open: and the title says nothing about a ceiling", uncounted.title:find("count_max_lines", 1, true), nil)

  config.setup({ list = { count = true, count_max_lines = 0 } })
  local declined = open_capturing("jump", nil)
  t.contains("open: a buffer over the ceiling reads '?', never '0'", declined.items[1].lines[1], "?")
  t.contains("open: and the title explains why", declined.title, "count_max_lines")

  config.setup({ list = { count = true, count_scope = "loaded" } })
  local loaded = open_capturing("jump", nil)
  t.contains("open: the loaded scope is announced in the title", loaded.title, "all loaded buffers")

  config.setup({ list = { count = true, count_scope = "loaded", count_max_lines = 0 } })
  local partial = open_capturing("jump", nil)
  t.contains("open: a skipped buffer makes the count a lower bound", partial.title, "lower bound")
  t.contains("open: rendered with a trailing +", partial.items[1].lines[1], "0+")
  config.setup()

  -- ---------- the titles, one per mode ----------
  t.contains("open: remove mode's title", (open_capturing("remove", nil)).title, "select to remove")
  t.contains("open: lock mode's title", (open_capturing("lock", nil)).title, "toggle lock")
  t.contains("open: line mode's title", (open_capturing("line", nil)).title, "whole-line rendering")
  t.contains("open: an unknown mode falls back to jump", (open_capturing("sideways", nil)).title, "select to jump")
  t.contains("open: so does no mode at all", (open_capturing(nil, nil)).title, "select to jump")

  -- The filter narrows what the chooser is handed, not just what it shows.
  local narrowed = open_capturing("jump", "req=bbb")
  t.eq("open: a filter narrows the row list itself", #narrowed.items, 1)
  t.eq("open: to the matching spotlight", narrowed.items[1].value.text, "req=bbb")

  -- ---------- on_select ----------
  local jump = open_capturing("jump", "req=aaa")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  jump.on_select(jump.items[1])
  t.eq("on_select/jump: the cursor moved to the first occurrence", vim.api.nvim_win_get_cursor(0)[1], 1)

  -- A spotlight with no occurrence in this buffer reports rather than moving.
  -- Given an explicit origin, because the filter cannot find it by text without
  -- one -- see the pinned defect above.
  registry.add({ text = "nowhere-in-this-buffer", kind = "literal" }, { origin = "logs/absent.log" })
  local absent = open_capturing("jump", "nowhere")
  local seen_absent = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    seen_absent[#seen_absent + 1] = { msg = tostring(msg), level = level }
  end
  absent.on_select(absent.items[1])
  vim.notify = saved_notify
  t.eq("on_select/jump: a spotlight absent from this buffer is reported", #seen_absent, 1)
  t.contains("on_select/jump: naming it", seen_absent[1].msg, "nowhere-in-this-buffer")
  registry.remove(registry.find_by_text("nowhere-in-this-buffer").id)

  local lock = open_capturing("lock", "req=aaa")
  t.eq("on_select/lock: not locked to begin with", registry.find_by_text("req=aaa").locked, nil)
  lock.on_select(lock.items[1])
  t.eq("on_select/lock: the slot is now locked", registry.find_by_text("req=aaa").locked, true)
  -- The row captured the item *table*, so re-selecting the same row toggles back.
  local lock2 = open_capturing("lock", "req=aaa")
  lock2.on_select(lock2.items[1])
  t.eq("on_select/lock: selecting again unlocks", registry.find_by_text("req=aaa").locked, nil)

  local line = open_capturing("line", "req=aaa")
  line.on_select(line.items[1])
  t.eq("on_select/line: whole-line rendering is on", registry.find_by_text("req=aaa").line, true)
  local line2 = open_capturing("line", "req=aaa")
  line2.on_select(line2.items[1])
  t.eq("on_select/line: and off again", registry.find_by_text("req=aaa").line, nil)

  local remove = open_capturing("remove", "req=bbb")
  local before = registry.count()
  remove.on_select(remove.items[1])
  t.eq("on_select/remove: the spotlight is gone", registry.count(), before - 1)
  t.eq("on_select/remove: the right one", registry.find_by_text("req=bbb"), nil)

  -- A callback handed something that is not a row must be a no-op, since the
  -- chooser is the one deciding what comes back.
  local guard = open_capturing("remove", nil)
  local count_before = registry.count()
  guard.on_select("a plain string")
  guard.on_select({})
  guard.on_select({ value = "not a table" })
  t.eq("on_select: a malformed selection changes nothing", registry.count(), count_before)

  registry.clear()
  config.setup()
end

return M
