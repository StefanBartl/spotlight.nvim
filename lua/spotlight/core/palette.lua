---@module 'spotlight.core.palette'
---@brief The `Spotlight1..N` highlight groups and slot allocation.
---@description
--- Defines one highlight group per palette entry, each with an explicit `bg`
--- **and** `fg`. Setting only a background is the usual mistake: the foreground
--- then comes from whatever the colorscheme put there, which is how a perfectly
--- readable marker turns into yellow-on-yellow after `:colorscheme`. Both
--- channels are pinned, and both a dark and a light set exist, so contrast is a
--- property of the plugin rather than of the theme.
---
--- The groups are re-defined on `ColorScheme` (a colorscheme clears user
--- highlight groups it does not know about) and on `OptionSet background`, since
--- switching background is what selects the other palette. Definition is
--- idempotent, so re-running it is always safe. Users override a slot by simply
--- redefining `SpotlightN` after setup — but a `ColorScheme`-triggered reapply
--- would then overwrite it, so the supported way to change colors is
--- `palette.colors` / `palette.colors_light` in `setup()`.

local config = require("spotlight.config")
local lib = require("spotlight.util.lib")

local M = {}

--- Group name for slot `n`. Slots are 1-based to match the config list, so the
--- name a user sees in `:highlight` lines up with the index they configured.
---@param n integer
---@return string
function M.group(n)
  return ("Spotlight%d"):format(n)
end

--- The color list matching the current `&background`.
---@return Spotlight.Color[]
local function active_colors()
  local p = config.get("palette")
  if vim.o.background == "light" then
    return p.colors_light
  end
  return p.colors
end

--- How many slots the palette currently offers.
---@return integer
function M.size()
  return #active_colors()
end

--- (Re-)define every `SpotlightN` group from the active color list.
--- Idempotent; safe to call on every `ColorScheme`.
---@return nil
function M.apply()
  local p = config.get("palette")
  local colors = active_colors()
  for i, c in ipairs(colors) do
    lib.hl(M.group(i), { bg = c.bg, fg = c.fg, bold = p.bold == true })
  end
end

--- Round-robin cursor: the slot handed out last.
---@type integer
local last = 0

--- Pick the next palette slot, given the slots already in use.
---
--- Round-robin from the last handed-out slot, but skipping slots that are still
--- occupied as long as any slot is free. Plain round-robin would happily hand
--- out a color already on screen while three others sit unused — and two
--- same-colored spotlights are exactly the confusion the palette exists to
--- prevent. Once every slot is taken, reuse is unavoidable and the cursor just
--- advances.
---@param used table<integer, boolean> # Slots currently in use.
---@return integer slot
function M.next_slot(used)
  local n = M.size()
  if n == 0 then
    return 1
  end
  for i = 1, n do
    local slot = (last + i - 1) % n + 1
    if not used[slot] then
      last = slot
      return slot
    end
  end
  last = last % n + 1
  return last
end

--- Reset the round-robin cursor. Called on clear-all, so a fresh set of
--- spotlights starts from slot 1 again instead of wherever the previous set
--- happened to stop.
---@return nil
function M.reset()
  last = 0
end

--- Clamp a slot from an untrusted source (a restored snapshot, whose palette may
--- have been larger than the current one) into the valid range.
---@param slot any
---@return integer
function M.clamp(slot)
  local n = M.size()
  if type(slot) ~= "number" or n == 0 then
    return 1
  end
  return (math.floor(slot) - 1) % n + 1
end

return M
