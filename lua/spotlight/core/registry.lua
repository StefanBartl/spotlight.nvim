---@module 'spotlight.core.registry'
---@brief The authoritative list of active spotlights.
---@description
--- One flat, session-global list of `Spotlight.Item`. Global is the model, not a
--- shortcut: a request id you spotted in `app.log` is the same request id in
--- `worker.log`, and scoping the highlight to a buffer would defeat the reason
--- for tracking it. `spotlight.core.match` makes that global list appear in
--- every window; this module owns *what* is in it.
---
--- Everything that changes the list funnels through here and ends with a single
--- `notify_change()`, which is what persistence subscribes to — so no caller has
--- to remember to trigger a save, and there is exactly one place where "the set
--- of spotlights changed" is defined.

require("spotlight.@types")

local config = require("spotlight.config")
local match = require("spotlight.core.match")
local palette = require("spotlight.core.palette")
local pattern = require("spotlight.core.pattern")
local path = require("spotlight.util.path")

local M = {}

---@type Spotlight.Item[]
local items = {}

--- Monotonic id source. Never reused within a session, so a stale ledger entry
--- in `core.match` can never be mistaken for a live spotlight.
---@type integer
local next_id = 0

---@type fun()[]
local listeners = {}

--- Register a callback fired after every change to the list.
---@param fn fun()
---@return nil
function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

---@internal
--- Fire the change listeners. Guarded individually: a failing persistence write
--- must not swallow the highlight the user just asked for.
---@return nil
local function notify_change()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

--- The active spotlights, in insertion order. The returned table is the live
--- list — read-only by contract; mutate it only through this module.
---@return Spotlight.Item[]
function M.all()
  return items
end

--- How many spotlights are active.
---@return integer
function M.count()
  return #items
end

--- Find the spotlight with the given id.
---@param id integer
---@return Spotlight.Item|nil item, integer|nil index
function M.get(id)
  for i, item in ipairs(items) do
    if item.id == id then
      return item, i
    end
  end
  return nil, nil
end

--- Find a spotlight by the raw text it was created from. This is the identity
--- used for toggling a **global** spotlight: pressing the key twice on the
--- same token removes it, because "the same token" is what the user
--- perceives — comparing the built regex instead would make `error`
--- (word-bounded) and a visually selected `error` (literal) two different
--- spotlights that look identical on screen.
---
--- Buffer-scoped items (see `M.add_at`) are skipped: their identity is
--- position, not text, since the whole point of one is to single out *this*
--- occurrence from every other one that shares its text.
---@param text string
---@return Spotlight.Item|nil item, integer|nil index
function M.find_by_text(text)
  for i, item in ipairs(items) do
    if item.scope ~= "buffer" and item.text == text then
      return item, i
    end
  end
  return nil, nil
end

--- Find a buffer-scoped spotlight by the exact position it was created at —
--- the toggle identity for `M.add_at`, mirroring what `M.find_by_text` is for
--- `M.add`.
---@param buf integer
---@param row1 integer
---@param col1 integer
---@return Spotlight.Item|nil item, integer|nil index
function M.find_at(buf, row1, col1)
  for i, item in ipairs(items) do
    if item.scope == "buffer" and item.buf == buf and item.row1 == row1 and item.col1 == col1 then
      return item, i
    end
  end
  return nil, nil
end

---@internal
--- Palette slots currently in use, for `palette.next_slot`.
---@return table<integer, boolean>
local function used_slots()
  local used = {}
  for _, item in ipairs(items) do
    used[item.slot] = true
  end
  return used
end

--- Add a spotlight for `token`. Returns the new item, or nil plus a reason when
--- it was refused (empty token, duplicate, or `match.max` reached).
---
--- `opts.origin` distinguishes three cases, which is why it is not a plain
--- `string|nil`: omitted means "derive it from the current buffer", a string
--- means "use this", and `false` means "this spotlight has no origin" — the
--- `and`/`or` shorthand cannot express the third, since it treats `false` and
--- `nil` alike.
---@param token Spotlight.Token
---@param opts? { slot?: integer, origin?: string|false }
---@return Spotlight.Item|nil item, string|nil err
function M.add(token, opts)
  opts = opts or {}
  if type(token.text) ~= "string" or token.text == "" then
    return nil, "nothing to highlight"
  end
  local max_len = config.get("match.max_text_len")
  if #token.text > max_len then
    return nil, ("token is %d bytes, over the %d-byte limit (match.max_text_len)"):format(#token.text, max_len)
  end
  local existing = M.find_by_text(token.text)
  if existing then
    return nil, ("already spotlighted: %s"):format(token.text)
  end
  local max = config.get("match.max")
  if #items >= max then
    return nil, ("spotlight limit reached (match.max = %d)"):format(max)
  end

  local slot = opts.slot and palette.clamp(opts.slot) or palette.next_slot(used_slots())

  -- Recorded even when persistence is off: turning it on later should not
  -- require re-creating the spotlights to know where they came from.
  local origin = opts.origin
  if origin == nil then
    origin = path.buffer_key(0)
  elseif origin == false then
    origin = nil
  end

  next_id = next_id + 1
  ---@type Spotlight.Item
  local item = {
    id = next_id,
    text = token.text,
    pattern = pattern.build(token, config.get("match")),
    slot = slot,
    hl = palette.group(slot),
    origin = origin,
  }
  items[#items + 1] = item
  match.apply_all({ item }, config.get("match.priority"))
  notify_change()
  return item, nil
end

--- Add a spotlight for exactly one buffer position — `token.text` highlighted
--- only where it sits at `pos.buf`/`pos.row1`/`pos.col1`, not every occurrence
--- of that text everywhere. This is `M.add`'s counterpart for "this occurrence
--- only" (`spotlight.M.toggle_here`): same guards (empty text, length cap,
--- `match.max`), same palette allocation, different identity and a pattern
--- pinned to a position instead of built from the token's shape.
---
--- Session-only by design: `M.snapshot` excludes buffer-scoped items, because
--- persisting a line/column only makes sense against the exact buffer state it
--- was recorded from, and that guarantee does not survive a restart the way a
--- text pattern's does.
---@param token Spotlight.Token
---@param pos { buf: integer, row1: integer, col1: integer }
---@param opts? { slot?: integer, origin?: string|false }
---@return Spotlight.Item|nil item, string|nil err
function M.add_at(token, pos, opts)
  opts = opts or {}
  if type(token.text) ~= "string" or token.text == "" then
    return nil, "nothing to highlight"
  end
  local max_len = config.get("match.max_text_len")
  if #token.text > max_len then
    return nil, ("token is %d bytes, over the %d-byte limit (match.max_text_len)"):format(#token.text, max_len)
  end
  local existing = M.find_at(pos.buf, pos.row1, pos.col1)
  if existing then
    return nil, ("already spotlighted here: %s"):format(token.text)
  end
  local max = config.get("match.max")
  if #items >= max then
    return nil, ("spotlight limit reached (match.max = %d)"):format(max)
  end

  local slot = opts.slot and palette.clamp(opts.slot) or palette.next_slot(used_slots())

  local origin = opts.origin
  if origin == nil then
    origin = path.buffer_key(pos.buf)
  elseif origin == false then
    origin = nil
  end

  next_id = next_id + 1
  ---@type Spotlight.Item
  local item = {
    id = next_id,
    text = token.text,
    pattern = pattern.build_at(token.text, pos.row1, pos.col1, config.get("match")),
    slot = slot,
    hl = palette.group(slot),
    origin = origin,
    scope = "buffer",
    buf = pos.buf,
    row1 = pos.row1,
    col1 = pos.col1,
  }
  items[#items + 1] = item
  match.apply_all({ item }, config.get("match.priority"))
  notify_change()
  return item, nil
end

--- Remove the spotlight with id `id`.
---@param id integer
---@return Spotlight.Item|nil removed
function M.remove(id)
  local item, index = M.get(id)
  if not item or not index then
    return nil
  end
  match.remove(id)
  table.remove(items, index)
  notify_change()
  return item
end

--- Toggle a spotlight for `token`: remove it if that exact text is already
--- spotlighted, otherwise add it.
---@param token Spotlight.Token
---@return "added"|"removed"|"error" action, Spotlight.Item|nil item, string|nil err
function M.toggle(token)
  if type(token.text) ~= "string" or token.text == "" then
    return "error", nil, "nothing under the cursor to spotlight"
  end
  local existing = M.find_by_text(token.text)
  if existing then
    return "removed", M.remove(existing.id), nil
  end
  local item, err = M.add(token)
  if not item then
    return "error", nil, err
  end
  return "added", item, nil
end

--- Toggle a buffer-scoped spotlight at `pos`: remove it if that exact position
--- is already spotlighted, otherwise add it. The `M.add_at` counterpart of
--- `M.toggle`.
---@param token Spotlight.Token
---@param pos { buf: integer, row1: integer, col1: integer }
---@return "added"|"removed"|"error" action, Spotlight.Item|nil item, string|nil err
function M.toggle_at(token, pos)
  if type(token.text) ~= "string" or token.text == "" then
    return "error", nil, "nothing under the cursor to spotlight"
  end
  local existing = M.find_at(pos.buf, pos.row1, pos.col1)
  if existing then
    return "removed", M.remove(existing.id), nil
  end
  local item, err = M.add_at(token, pos)
  if not item then
    return "error", nil, err
  end
  return "added", item, nil
end

--- Drop every buffer-scoped spotlight tied to `buf`. Called when a buffer is
--- wiped out from under a position-pinned spotlight — the position it was
--- pinned to no longer means anything, so nothing is served by keeping a
--- registry entry that can never render again.
---@param buf integer
---@return integer removed
function M.remove_for_buffer(buf)
  local n = 0
  for i = #items, 1, -1 do
    local item = items[i]
    if item.scope == "buffer" and item.buf == buf then
      match.remove(item.id)
      table.remove(items, i)
      n = n + 1
    end
  end
  if n > 0 then
    notify_change()
  end
  return n
end

--- Remove every spotlight. Returns how many there were.
---@return integer removed
function M.clear()
  local n = #items
  match.clear()
  items = {}
  palette.reset()
  if n > 0 then
    notify_change()
  end
  return n
end

--- Replace the whole list from a restored snapshot, without firing a change
--- notification — a load is not a user edit, and re-saving what was just read
--- would be pure churn (and would write back a snapshot filtered by exception
--- rules that were themselves only just loaded).
---@param stored Spotlight.StoredItem[]
---@return integer restored
function M.restore(stored)
  match.clear()
  items = {}
  palette.reset()
  local match_opts = config.get("match")
  local max = config.get("match.max")
  local max_len = config.get("match.max_text_len")
  local seen = {}
  for _, s in ipairs(stored) do
    -- Every field is re-validated, not trusted. The snapshot is a JSON file in
    -- the cache directory: writable by anything running as this user, and
    -- hand-editable. It is the plugin's only external input, so it gets the same
    -- treatment as one — type checks, the length cap, dedup, and the count cap.
    -- The regex is rebuilt from `text` rather than read from the file, which is
    -- what makes a crafted snapshot unable to inject a pattern.
    if
      type(s) == "table"
      and type(s.text) == "string"
      and s.text ~= ""
      and #s.text <= max_len
      and not seen[s.text]
      and #items < max
    then
      seen[s.text] = true
      local slot = palette.clamp(s.slot)
      next_id = next_id + 1
      items[#items + 1] = {
        id = next_id,
        text = s.text,
        -- Rebuilt rather than stored: a later change to the escaping or
        -- boundary policy then applies to restored spotlights too, instead of
        -- resurrecting a regex built by an older version of this plugin.
        pattern = pattern.build({ text = s.text, kind = s.kind == "word" and "word" or "literal" }, match_opts),
        slot = slot,
        hl = palette.group(slot),
        origin = type(s.origin) == "string" and s.origin or nil,
      }
    end
  end
  match.apply_all(items, config.get("match.priority"))
  return #items
end

--- Serialize the current list for persistence. `kind` is recovered from the
--- pattern's own boundary markers, so the round-trip does not need a separate
--- field on the runtime item that could drift out of sync with the regex.
---
--- Buffer-scoped items (`M.add_at`) are left out entirely — see `M.add_at`'s
--- doc comment for why a line/column pin is session-only rather than
--- persisted.
---@return Spotlight.StoredItem[]
function M.snapshot()
  local out = {}
  for _, item in ipairs(items) do
    if item.scope ~= "buffer" then
      out[#out + 1] = {
        text = item.text,
        slot = item.slot,
        kind = item.pattern:find("\\<", 1, true) and "word" or "literal",
        origin = item.origin,
      }
    end
  end
  return out
end

--- Apply every active spotlight to `win`. Called from the window autocmds that
--- compensate for `matchadd()` being window-local.
---@param win integer
---@return nil
function M.apply_to_window(win)
  if #items == 0 then
    return
  end
  match.apply_window(win, items, config.get("match.priority"))
end

--- Re-apply everything from scratch. Used after a config change that is baked
--- into the `matchadd()` call itself (priority, case flag, boundaries), which
--- has no in-place update form.
---@return nil
function M.rebuild()
  local match_opts = config.get("match")
  for _, item in ipairs(items) do
    if item.scope == "buffer" then
      item.pattern = pattern.build_at(item.text, item.row1, item.col1, match_opts)
    else
      local kind = item.pattern:find("\\<", 1, true) and "word" or "literal"
      item.pattern = pattern.build({ text = item.text, kind = kind }, match_opts)
    end
    item.slot = palette.clamp(item.slot)
    item.hl = palette.group(item.slot)
  end
  match.refresh(items, config.get("match.priority"))
end

return M
