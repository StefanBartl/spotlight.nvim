-- Test code: when something here comes back nil -- a built entry list, a
-- submenu -- this file must crash and name it. The nil guards LuaLS asks for
-- below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/menu_spec.lua
-- `spotlight.integrations.menu`: the nvzone/menu-shaped entry list spotlight
-- *provides* for a host to compose. Nothing in the suite touched it before,
-- because the module binds `require("ui.contextmenu")` to a file-local at load
-- time and ui.nvim is not on this suite's runtimepath.
--
-- So the seam is cut properly: a double is installed in `package.loaded` and the
-- subject is then loaded *fresh* against it, since a later swap would not reach
-- an already-bound file-local. The double implements ui.contextmenu's own
-- documented contract -- `entry` returns nil when unavailable, `group` drops the
-- nils and inserts a separator only when it appends to a non-empty list,
-- `submenu` returns nil for an empty item list -- so the assertions are about
-- spotlight's use of that contract rather than about the double.

local t = require("harness")

local M = {}

local CONTEXTMENU = "ui.contextmenu"
local SUBJECT = "spotlight.integrations.menu"

---@internal
--- A stand-in for `ui.contextmenu`, faithful to the three functions spotlight
--- calls. Deliberately not a recording no-op: `group`'s nil-dropping and
--- separator rule are what decide the shape spotlight hands back.
---@return table
local function contextmenu_double()
  local cm = {}
  cm.entry = function(available, label, fn, rtxt, opts)
    if not available then
      return nil
    end
    return { name = label, rtxt = rtxt, cmd = fn, icon = (opts or {}).icon }
  end
  cm.group = function(out, ...)
    local n = select("#", ...)
    local compact = {}
    for i = 1, n do
      local it = select(i, ...)
      if it ~= nil then
        compact[#compact + 1] = it
      end
    end
    if #compact == 0 then
      return false
    end
    if #out > 0 then
      out[#out + 1] = { name = "separator" }
    end
    for _, it in ipairs(compact) do
      out[#out + 1] = it
    end
    return true
  end
  cm.submenu = function(label, items)
    if type(items) ~= "table" or #items == 0 then
      return nil
    end
    return { name = label, items = items }
  end
  return cm
end

---@internal
--- Load the subject against a fresh double and run `fn(menu)`.
---@param fn fun(menu: table)
---@return nil
local function with_menu(fn)
  local saved = package.loaded[SUBJECT]
  package.loaded[SUBJECT] = nil
  local ok, err = pcall(function()
    t.with_modules({ [CONTEXTMENU] = contextmenu_double() }, function()
      fn(require(SUBJECT))
    end)
  end)
  package.loaded[SUBJECT] = saved
  if not ok then
    error(err, 0)
  end
end

---@internal
--- The real entries, with the separators filtered out.
---@param items table[]
---@return table[]
local function entries_only(items)
  local out = {}
  for _, it in ipairs(items) do
    if it.name ~= "separator" then
      out[#out + 1] = it
    end
  end
  return out
end

function M.run()
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")

  config.setup()
  require("spotlight.core.palette").apply()
  registry.clear()

  with_menu(function(menu)
    local items = menu.items()
    local real = entries_only(items)

    -- Three groups of 4 / 2 / 2, so two separators between them.
    t.eq("items: eight actions are offered", #real, 8)
    t.eq("items: in three groups, so two separators", #items - #real, 2)
    t.eq("items: the first separator sits after the fourth action", items[5].name, "separator")
    t.eq("items: the second after the sixth", items[8].name, "separator")

    for i, it in ipairs(real) do
      t.eq(("items: entry %d carries a callback"):format(i), type(it.cmd), "function")
      t.eq(("items: entry %d carries a label"):format(i), type(it.name), "string")
    end

    -- The right-hand hint is the *configured* key, read fresh, not the default
    -- baked into the label.
    t.eq("items: the hint text is the configured keymap", real[1].rtxt, config.get("keymaps.toggle_here"))
    t.eq("items: for the wider toggle too", real[2].rtxt, config.get("keymaps.toggle"))
    t.eq("items: and for navigation", real[3].rtxt, config.get("keymaps.next"))
    t.eq("items: ...both ways", real[4].rtxt, config.get("keymaps.prev"))

    -- The visual-mode variants are deliberately absent: nvzone/menu restores the
    -- triggering window before running a callback, so there is no selection left
    -- to read by then.
    local labels = {}
    for _, it in ipairs(real) do
      labels[#labels + 1] = it.name
    end
    local joined = table.concat(labels, " | ")
    t.eq(
      "items: no 'selection' entry exists -- there is no live selection by then",
      joined:lower():find("selection", 1, true),
      nil
    )

    -- A callback really drives the facade.
    t.fixture({ "req=aaa", "req=bbb" })
    registry.add({ text = "req=aaa", kind = "literal" }, { origin = "logs/menu.log" })
    t.eq("items: precondition -- one spotlight", registry.count(), 1)
    local clear_entry = nil
    for _, it in ipairs(real) do
      if it.name:find("Clear all", 1, true) then
        clear_entry = it
      end
    end
    t.ok("items: the clear entry is present", clear_entry ~= nil)
    clear_entry.cmd()
    t.eq("items: its callback reached the facade", registry.count(), 0)

    -- BUG-adjacent, pinned as a contract violation rather than a defect:
    -- `ui.contextmenu.entry`'s own doc says a leading glyph belongs in
    -- `opts.icon` and "never in `label`", because the kit renderer draws icons
    -- as a column of their own — a label that starts with padding indents that
    -- row past every other entry in the composed menu. Every spotlight label
    -- starts with two spaces where a glyph was meant to go, and no entry passes
    -- an `icon` at all.
    local padded, iconless = 0, 0
    for _, it in ipairs(real) do
      if it.name:sub(1, 2) == "  " then
        padded = padded + 1
      end
      if it.icon == nil then
        iconless = iconless + 1
      end
    end
    t.eq("BUG: every label starts with the two spaces ui.contextmenu says not to use", padded, 8)
    t.eq("BUG: and no entry uses the icon column that exists for it", iconless, 8)
  end)

  -- ---------- the opt-out ----------
  config.setup({ menu = { enable = false } })
  with_menu(function(menu)
    t.eq("items: menu.enable = false yields an empty list, safe to list_extend", #menu.items(), 0)
    t.eq("submenu: and no submenu entry at all, rather than an empty fly-out", menu.submenu(), nil)
  end)
  config.setup()

  -- ---------- submenu ----------
  with_menu(function(menu)
    local sub = menu.submenu()
    t.eq("submenu: has a default label", sub.name, "  Spotlight")
    t.eq("submenu: wrapping the full entry list", #sub.items, #menu.items())
    local named = menu.submenu("Highlights")
    t.eq("submenu: an explicit label is used", named.name, "Highlights")
  end)

  -- ---------- keymaps turned off entirely ----------
  -- `keymaps = false` is a legal way to say "bind nothing"; the entries must
  -- still be built, just without hint text.
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ keymaps = false })
  with_menu(function(menu)
    local real = entries_only(menu.items())
    t.eq("items: keymaps = false still produces every action", #real, 8)
    t.eq("items: with no hint text", real[1].rtxt, nil)
  end)
  config.setup()

  -- ---------- a user-moved keymap shows up in the hint ----------
  config.setup({ keymaps = { toggle = "<leader>xx" } })
  with_menu(function(menu)
    local real = entries_only(menu.items())
    t.eq("items: a moved keymap is reflected in the hint", real[2].rtxt, "<leader>xx")
  end)
  config.setup()

  registry.clear()
end

return M
