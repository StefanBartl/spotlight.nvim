-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/read_api_spec.lua
-- The stable read API other plugins build on (mdview.nvim mirrors the
-- spotlights into its browser preview): `spotlight.spotlights(opts?)` returns
-- detached copies in the documented shape, `{ whole_file = true }` keeps only
-- the spotlights that mark every occurrence, and `spotlight.colors()` reports
-- the eight slot colors resolved from the live highlight groups.

local t = require("harness")

local M = {}

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")
  local api = require("spotlight")

  config.setup()
  api.setup()
  registry.clear()
  local buf = t.fixture({ "req=aaa ip=10.0.0.1", "req=bbb", "req=aaa" })

  -- ---------- the shape ----------
  t.eq("shape: an empty registry reads as an empty list", #api.spotlights(), 0)

  registry.add({ text = "aaa", kind = "word" }, { origin = "logs/a.log" })
  registry.add({ text = "10.0.0.1", kind = "literal" })
  local list = api.spotlights()
  t.eq("shape: one entry per spotlight", #list, 2)

  local first = list[1]
  t.eq("shape: text", first.text, "aaa")
  t.eq("shape: slot is the palette slot", type(first.slot), "number")
  t.eq("shape: hl_group names the highlight group of that slot", first.hl_group, "Spotlight" .. first.slot)
  t.eq("shape: hl is the same group under the registry's own name", first.hl, first.hl_group)
  t.eq("shape: line_mode is a boolean, off by default", first.line_mode, false)
  t.eq("shape: origin is carried through", first.origin, "logs/a.log")
  t.eq("shape: a plain toggle is whole-file", first.whole_file, true)
  t.eq("shape: scope is spelled out for a global spotlight", first.scope, "global")
  t.eq("shape: locked is a boolean", first.locked, false)
  t.eq("shape: a word token reports kind = word", first.kind, "word")
  t.eq("shape: case-sensitive by default", first.ignore_case, false)
  t.eq("shape: the regex is still there", type(first.pattern), "string")
  t.eq("shape: an id is there", type(first.id), "number")
  t.eq("shape: no pinned position on a whole-file spotlight", first.row1, nil)

  t.eq("shape: a literal token reports kind = literal", list[2].kind, "literal")
  t.eq("shape: an origin-less spotlight reports none", list[2].origin, nil)
  t.eq("shape: insertion order is kept", list[2].text, "10.0.0.1")

  -- ---------- line mode and lock follow the registry ----------
  t.ok("line: set", api.line_set("aaa", true))
  t.eq("line: line_mode is now true", api.spotlights()[1].line_mode, true)
  t.eq("line: and its alias agrees", api.spotlights()[1].line, true)
  t.ok("lock: set", api.lock_set("aaa", true))
  t.eq("lock: locked is now true", api.spotlights()[1].locked, true)

  -- ---------- ignore_case is read off the effective pattern ----------
  config.setup({ match = { ignore_case = true } })
  registry.add({ text = "ccc", kind = "literal" })
  local ci
  for _, s in ipairs(api.spotlights()) do
    if s.text == "ccc" then
      ci = s
    end
  end
  t.eq("ignore_case: a case-insensitive spotlight says so", ci.ignore_case, true)
  config.setup()

  -- ---------- whole_file: toggle vs. toggle_here ----------
  registry.clear()
  registry.add({ text = "aaa", kind = "literal" })
  t.ok("here: cursor placed on the first aaa", t.cursor_on(1, "aaa"))
  t.ok("here: toggle_here added a pinned spotlight", api.toggle_here())

  local all = api.spotlights()
  t.eq("whole_file: no filter returns both kinds", #all, 2)

  local whole = api.spotlights({ whole_file = true })
  t.eq("whole_file = true: only the toggle() spotlight", #whole, 1)
  t.eq("whole_file = true: and it is whole-file", whole[1].whole_file, true)

  local pinned = api.spotlights({ whole_file = false })
  t.eq("whole_file = false: only the toggle_here() spotlight", #pinned, 1)
  t.eq("whole_file = false: flagged as not whole-file", pinned[1].whole_file, false)
  t.eq("whole_file = false: scope is buffer", pinned[1].scope, "buffer")
  t.eq("whole_file = false: the pinned buffer is reported", pinned[1].buf, buf)
  t.eq("whole_file = false: and its line", pinned[1].row1, 1)
  t.eq("whole_file = false: and its column", pinned[1].col1, 5)

  t.eq("whole_file = nil in an options table is no filter", #api.spotlights({}), 2)

  -- ---------- detached copies ----------
  local snap = api.spotlights()
  snap[1].text = "tampered"
  snap[1].slot = 99
  table.remove(snap)
  t.eq("detached: renaming a copy leaves the registry alone", registry.all()[1].text, "aaa")
  t.ok("detached: so does re-slotting it", registry.all()[1].slot ~= 99)
  t.eq("detached: and shrinking the list", registry.count(), 2)
  t.ok("detached: a second read is a fresh copy", api.spotlights()[1] ~= snap[1])

  -- ---------- colors() ----------
  registry.clear()
  local colors = api.colors()
  t.eq("colors: one entry per palette slot", #colors, #config.get("palette").colors)
  t.eq("colors: eight by default", #colors, 8)
  for i, c in ipairs(colors) do
    t.eq(("colors: slot %d is numbered"):format(i), c.slot, i)
    t.eq(("colors: slot %d names its group"):format(i), c.group, "Spotlight" .. i)
    t.ok(("colors: slot %d fg is #rrggbb"):format(i), c.fg:match("^#%x%x%x%x%x%x$") ~= nil, c.fg)
    t.ok(("colors: slot %d bg is #rrggbb"):format(i), c.bg:match("^#%x%x%x%x%x%x$") ~= nil, c.bg)
    t.eq(("colors: slot %d bold is a boolean"):format(i), type(c.bold), "boolean")
  end

  local saved_bg = vim.o.background
  vim.o.background = "dark"
  vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
  local dark = api.colors()
  t.eq("colors: dark slot 1 bg is the configured dark yellow", dark[1].bg, config.get("palette").colors[1].bg)
  t.eq("colors: dark slot 1 fg is the configured near-black", dark[1].fg, config.get("palette").colors[1].fg)

  vim.o.background = "light"
  vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
  local light = api.colors()
  t.eq("colors: &background = light selects the light palette", light[1].bg, config.get("palette").colors_light[1].bg)
  vim.o.background = saved_bg
  vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })

  -- The *live* group is what is reported, not the configured value: a user
  -- override or a colorscheme that redefined it is what the editor renders.
  vim.api.nvim_set_hl(0, "Spotlight2", { fg = "#123456", bg = "#abcdef" })
  local overridden = api.colors()[2]
  t.eq("colors: a redefined group is read back (bg)", overridden.bg, "#abcdef")
  t.eq("colors: a redefined group is read back (fg)", overridden.fg, "#123456")

  -- A group that lost its channels falls back to the configured color, so an
  -- entry always has both.
  vim.api.nvim_set_hl(0, "Spotlight3", {})
  local emptied = api.colors()[3]
  t.eq("colors: an empty group falls back to the configured bg", emptied.bg, config.get("palette").colors[3].bg)
  t.eq("colors: ... and the configured fg", emptied.fg, config.get("palette").colors[3].fg)

  -- ---------- kind survives a literal token that contains a backslash ----------
  -- The escaped backslash of a Windows path (`C:\<dir>`) puts a `\<` into the
  -- pattern body; only a boundary right behind the `\C\V` prefix makes a word.
  registry.clear()
  registry.add({ text = [[C:\<dir>\x]], kind = "literal" })
  registry.add({ text = "plain", kind = "word" })
  local kinds = api.spotlights()
  t.eq("kind: a literal with a backslash-angle body stays literal", kinds[1].kind, "literal")
  t.eq("kind: a word token is still a word", kinds[2].kind, "word")
  t.eq("kind: the snapshot agrees (no boundaries added on restore)", registry.snapshot()[1].kind, "literal")

  require("spotlight.core.palette").apply()
  registry.clear()
end

return M
