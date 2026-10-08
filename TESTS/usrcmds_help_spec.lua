-- TESTS/usrcmds_help_spec.lua
-- Every positional argument of `:Spotlight` has a line in the option float.
--
-- lib.nvim's help float (the option cheatsheet on the command line) shows one line for the next
-- positional argument, taken from the argument's own `desc`, from the text of its type
-- (`register_type`) or -- for a closed set -- from `enum_desc`. This pins that no route ships an
-- argument without one, and that the lines keep the float's house style: one short line, no
-- trailing full stop. A value text for a value the argument does not offer shows nowhere, so that
-- is pinned too.
--
-- Skipped on a lib.nvim without `help.undocumented` / `arg_desc` (older than the argument texts).

local t = require("harness")

local M = {}

--- The float's house style for one text.
---@param text any
---@return boolean
local function house_style(text)
  return type(text) == "string" and text ~= "" and not text:find("\n", 1, true) and #text <= 80 and not text:find("%.$")
end

function M.run()
  local composer = require("lib.nvim.bindings.usercmd.composer")
  local ok_entries, entries = pcall(require, "lib.nvim.bindings.usercmd.composer.help.entries")
  if
    not (
      type(composer.help) == "table"
      and type(composer.help.undocumented) == "function"
      and ok_entries
      and type(entries.arg_desc) == "function"
    )
  then
    print("  skip :Spotlight option float tests (lib.nvim has no argument texts)")
    return
  end

  require("spotlight").setup()

  local missing = {}
  for _, m in ipairs(composer.help.undocumented("Spotlight", { args = true })) do
    missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
  end
  t.eq("option float: every :Spotlight flag and argument has a text", table.concat(missing, ", "), "")

  local handle = composer.registry().Spotlight
  t.ok("option float: :Spotlight is registered", handle ~= nil)
  local walked, bad = 0, {}
  for _, route in ipairs(handle and handle:spec().routes or {}) do
    for _, arg in ipairs(route.args or {}) do
      walked = walked + 1
      local label = (":Spotlight %s {%s}"):format(table.concat(route.path, " "), arg.name)
      if not house_style(entries.arg_desc(arg)) then
        bad[#bad + 1] = label
      end
      for value, text in pairs(arg.enum_desc or {}) do
        if not house_style(text) then
          bad[#bad + 1] = label .. " = " .. value
        end
        if not vim.tbl_contains(arg.enum or arg.values or {}, value) then
          bad[#bad + 1] = label .. " = " .. value .. " (not one of its values)"
        end
      end
    end
  end
  t.ok("option float: the routes' arguments were walked", walked > 0)
  t.eq("option float: every :Spotlight argument text is one short line, no full stop", table.concat(bad, ", "), "")

  -- The set-name type says it once for both routes that take a saved set.
  local type_texts = {}
  for _, route in ipairs(handle and handle:spec().routes or {}) do
    for _, arg in ipairs(route.args or {}) do
      if arg.type == "SPOTLIGHT_SET_NAME" then
        type_texts[#type_texts + 1] = entries.arg_desc(arg)
      end
    end
  end
  t.eq("option float: sets switch and sets delete share the set-name text", #type_texts, 2)
  t.eq("option float: ... and it is the type's", type_texts[1], type_texts[2])
end

return M
