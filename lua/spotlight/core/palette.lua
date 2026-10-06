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
local events = require("spotlight.core.events")
local lib = require("spotlight.util.lib")

local M = {}

--- Group name for slot `n`. Slots are 1-based to match the config list, so the
--- name a user sees in `:highlight` lines up with the index they configured.
---@param n integer
---@return string
function M.group(n)
  return ("Spotlight%d"):format(n)
end

---@internal
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

---@internal
--- A resolved `#rrggbb` channel of a highlight group, or nil when it has none.
---@param n any
---@return string|nil
local function hex(n)
  if type(n) ~= "number" then
    return nil
  end
  return ("#%06x"):format(n)
end

---@internal
--- What the editor currently has for highlight group `group`, links resolved.
--- `link = false` is Neovim 0.10; on 0.9 the plain call is the best available,
--- and a group that is only a link then reports no channels (the caller falls
--- back to the configured color).
---@param group string
---@return table|nil
local function get_hl(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if not ok then
    ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group })
  end
  if ok and type(hl) == "table" then
    return hl
  end
  return nil
end

---@internal
--- What the editor has for the first `n` palette groups, as one comparable
--- string. Only for telling whether `M.apply` actually changed anything.
---@param n integer
---@return string
local function signature(n)
  local parts = {}
  for i = 1, n do
    parts[i] = vim.inspect(get_hl(M.group(i)))
  end
  return table.concat(parts, "\n")
end

--- (Re-)define every `SpotlightN` group from the active color list.
--- Idempotent; safe to call on every `ColorScheme`. Announces itself as a
--- `colors` change (`core/events.lua`), the one place the group colors are set.
---
--- `opts.only_if_changed` announces only when a group came out different from
--- what the editor had, for a caller (`refresh`) that re-runs this on demand
--- rather than because the colors are known to have moved. The `ColorScheme` and
--- `background` handlers keep the plain form: whoever mirrors the colors wants
--- to hear that, even if the groups happen to read the same afterwards.
---@param opts? { only_if_changed?: boolean }
---@return boolean announced
function M.apply(opts)
  local p = config.get("palette")
  local colors = active_colors()
  local before = opts and opts.only_if_changed and signature(#colors) or nil
  for i, c in ipairs(colors) do
    lib.hl(M.group(i), { bg = c.bg, fg = c.fg, bold = p.bold == true })
  end
  if before and signature(#colors) == before then
    return false
  end
  events.changed("colors", true)
  return true
end

--- The palette as the editor currently renders it: one entry per slot, with
--- `fg`/`bg` resolved from the live `SpotlightN` group (so a user override or
--- a colorscheme that redefined it is what is reported). A channel the group
--- does not carry falls back to the configured color for that slot, so an entry
--- always has both. Read-only; for a consumer that mirrors the colors elsewhere.
---@return Spotlight.SlotColor[]
function M.colors()
  local out = {}
  for slot, c in ipairs(active_colors()) do
    local group = M.group(slot)
    local hl = get_hl(group) or {}
    out[slot] = {
      slot = slot,
      group = group,
      fg = hex(hl.fg) or c.fg,
      bg = hex(hl.bg) or c.bg,
      bold = hl.bold == true,
    }
  end
  return out
end

--- Round-robin cursor: the slot handed out last.
---@type integer
local last = 0

--- Pick the next palette slot, given the slots already in use and the slots a
--- `locked` item has claimed permanently.
---
--- Round-robin from the last handed-out slot, but skipping slots that are still
--- occupied as long as any slot is free. Plain round-robin would happily hand
--- out a color already on screen while three others sit unused — and two
--- same-colored spotlights are exactly the confusion the palette exists to
--- prevent. Once every unlocked slot is taken, reuse is unavoidable and the
--- cursor just advances — but a *locked* slot is never handed to a different
--- spotlight even then: locking exists precisely so a slot's color stops being
--- up for grabs, and a fallback that ignored locks would only honour that
--- promise until the palette filled up.
---
--- Bounded to `n` iterations in both scans, so an exhausted or even fully
--- locked palette still returns rather than looping — see the terminal case
--- below.
---@param used table<integer, boolean> # Slots currently in use.
---@param locked table<integer, boolean>|nil # Slots a locked item has claimed.
---@return integer slot
function M.next_slot(used, locked)
  locked = locked or {}
  local n = M.size()
  if n == 0 then
    return 1
  end

  -- Primary scan: first slot that is neither used nor locked.
  for i = 1, n do
    local slot = (last + i - 1) % n + 1
    if not used[slot] and not locked[slot] then
      last = slot
      return slot
    end
  end

  -- Every slot is occupied. Reuse an unlocked one rather than the plain
  -- "advance and return" the unlocked-only path used to do — that fallback
  -- carried no notion of locking and could hand out a locked slot the moment
  -- the palette filled up.
  for i = 1, n do
    local slot = (last + i - 1) % n + 1
    if not locked[slot] then
      last = slot
      return slot
    end
  end

  -- Every slot, without exception, is locked: nothing can be handed out
  -- without breaking some lock. Advance `last` anyway, so a later unlock
  -- resumes round-robin from a fresh point, and return it — a color, just
  -- not a promise, rather than hanging forever looking for one that cannot
  -- exist.
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
