---@module 'spotlight'
---@brief Public facade for spotlight.nvim: setup + the action surface.
---@description
--- One entry point that wires configuration and exposes every user-facing
--- action. Keymaps and the `:Spotlight` verb bind straight onto these functions,
--- so every feature is reachable both ways by construction — there is no action
--- that exists only as a keymap.
---
--- Each action is self-contained: it resolves what it needs, reports its own
--- outcome through `lib.nvim.notify`, and returns a plain boolean so a caller
--- (or a test) can tell whether anything happened.

require("spotlight.@types")

local config = require("spotlight.config")
local cursor = require("spotlight.cursor")
local lib = require("spotlight.util.lib")
local nav = require("spotlight.nav")
local palette = require("spotlight.core.palette")
local path = require("spotlight.util.path")
local persist = require("spotlight.persist")
local qf = require("spotlight.qf")
local registry = require("spotlight.core.registry")
local yank = require("spotlight.yank")

local M = {}

---@internal
--- Report `msg` unless the user turned notifications off.
---@param msg string
---@param level integer|nil
---@return nil
local function report(msg, level)
  if config.get("notify") == true or (level or vim.log.levels.INFO) >= vim.log.levels.WARN then
    lib.notify(msg, level)
  end
end

-- ---------- toggling ----------

--- Toggle a spotlight on the token under the cursor.
---@return boolean changed
function M.toggle()
  local token = cursor.token()
  if not token then
    report("no token under the cursor", vim.log.levels.WARN)
    return false
  end
  local action, item, err = registry.toggle(token)
  if action == "error" then
    report(err or "could not toggle spotlight", vim.log.levels.WARN)
    return false
  end
  if action == "added" and item then
    report(("spotlight %d: %s"):format(item.slot, item.text))
  elseif item then
    report(("removed spotlight: %s"):format(item.text))
  end
  return true
end

--- Toggle a spotlight on the current visual selection, taken literally.
---
--- Reads the selection while Visual mode is still active (see
--- `spotlight.cursor.selection`), then leaves it — a spotlight is not a text
--- edit, so there is nothing to reselect afterwards.
---@return boolean changed
function M.toggle_selection()
  local token, err = cursor.selection()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
  if not token then
    report(err or "no selection", vim.log.levels.WARN)
    return false
  end
  local action, item, add_err = registry.toggle(token)
  if action == "error" then
    report(add_err or "could not toggle spotlight", vim.log.levels.WARN)
    return false
  end
  if action == "added" and item then
    report(("spotlight %d: %s"):format(item.slot, item.text))
  elseif item then
    report(("removed spotlight: %s"):format(item.text))
  end
  return true
end

-- ---------- toggling: this occurrence only ----------

--- Toggle a spotlight on exactly the occurrence of the token under the
--- cursor — not on every occurrence of that text in the buffer, which is what
--- `M.toggle` does. Pinned to the line/column it was resolved at, and to the
--- windows currently showing this buffer (see `core/match.lua`).
---@return boolean changed
function M.toggle_here()
  local token, pos = cursor.token()
  if not token or not pos then
    report("no token under the cursor", vim.log.levels.WARN)
    return false
  end
  return M.toggle_here_at(token.text, { buf = vim.api.nvim_get_current_buf(), row1 = pos.row1, col1 = pos.col1 })
end

--- Toggle a spotlight on exactly the current visual selection's occurrence —
--- the visual-mode counterpart of `M.toggle_here`, the same way
--- `M.toggle_selection` is `M.toggle`'s.
---@return boolean changed
function M.toggle_here_selection()
  local token, err, pos = cursor.selection()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
  if not token or not pos then
    report(err or "no selection", vim.log.levels.WARN)
    return false
  end
  return M.toggle_here_at(token.text, { buf = vim.api.nvim_get_current_buf(), row1 = pos.row1, col1 = pos.col1 })
end

--- Toggle a spotlight for a literal `text` pinned to one exact buffer
--- position, rather than to whatever the cursor or selection currently
--- resolves to. The `:Spotlight here` range path uses this: by the time a `:`
--- command runs, Visual mode has already ended, so the position has to be
--- supplied rather than read live the way `M.toggle_here_selection` reads it.
---@param text string
---@param pos { buf: integer, row1: integer, col1: integer }
---@return boolean changed
function M.toggle_here_at(text, pos)
  if type(text) ~= "string" or text == "" then
    report("nothing to spotlight", vim.log.levels.WARN)
    return false
  end
  local action, item, err = registry.toggle_at({ text = text, kind = "literal" }, pos)
  if action == "error" then
    report(err or "could not toggle spotlight", vim.log.levels.WARN)
    return false
  end
  if action == "added" and item then
    report(("spotlight %d, this occurrence only: %s"):format(item.slot, item.text))
  elseif item then
    report(("removed spotlight: %s"):format(item.text))
  end
  return true
end

--- Add a spotlight for an explicit literal string. The `:Spotlight add` path,
--- for a token that is not conveniently under the cursor.
---
--- Literal, not shape-classified like the cursor resolver: text the user typed
--- out is an exact request, and silently wrapping `error` in `\<`/`\>` would make
--- it stop matching inside `errors` — which is very likely why they typed it.
---@param text string
---@return boolean added
function M.add(text)
  if type(text) ~= "string" or text == "" then
    report("nothing to add", vim.log.levels.WARN)
    return false
  end
  local item, err = registry.add({ text = text, kind = "literal" })
  if not item then
    report(err or "could not add spotlight", vim.log.levels.WARN)
    return false
  end
  report(("spotlight %d: %s"):format(item.slot, item.text))
  return true
end

--- Remove the spotlight matching `text` exactly.
---@param text string
---@return boolean removed
function M.remove(text)
  local item = registry.find_by_text(text)
  if not item then
    report(("no spotlight for: %s"):format(tostring(text)), vim.log.levels.WARN)
    return false
  end
  registry.remove(item.id)
  report(("removed spotlight: %s"):format(item.text))
  return true
end

--- Remove every spotlight.
---@return boolean changed
function M.clear()
  local n = registry.clear()
  if n == 0 then
    report("no active spotlights", vim.log.levels.INFO)
    return false
  end
  report(("cleared %d spotlight%s"):format(n, n == 1 and "" or "s"))
  return true
end

-- ---------- list ----------

--- Open the spotlight list; selecting an entry jumps to its first occurrence.
---@return nil
function M.list()
  require("spotlight.ui.list").open("jump")
end

--- Open the spotlight list in removal mode; selecting an entry removes it.
---@return nil
function M.list_remove()
  require("spotlight.ui.list").open("remove")
end

--- Open the spotlight list in lock mode; selecting an entry toggles whether
--- its palette slot is locked (see `M.lock_toggle`).
---@return nil
function M.list_lock()
  require("spotlight.ui.list").open("lock")
end

-- ---------- per-slot lock ----------

--- Set whether the spotlight matching `text` exactly keeps its palette slot
--- permanently, never handing it to a different spotlight even once the
--- palette fills up.
---@param text string
---@param value boolean
---@return boolean changed
function M.lock_set(text, value)
  local item = registry.find_by_text(text)
  if not item then
    report(("no spotlight for: %s"):format(tostring(text)), vim.log.levels.WARN)
    return false
  end
  registry.set_locked(item.id, value)
  report(("%s: %s"):format(value and "locked" or "unlocked", item.text))
  return true
end

--- Toggle the lock on the spotlight matching `text` exactly, or — with no
--- `text` — on whatever spotlight the cursor token resolves to, mirroring
--- `M.toggle`'s own resolution. Locking is only meaningful for a spotlight
--- that already exists, so an unresolved or not-yet-spotlighted token is
--- refused rather than silently doing nothing.
---@param text string|nil
---@return boolean changed
function M.lock_toggle(text)
  local item
  if type(text) == "string" and text ~= "" then
    item = registry.find_by_text(text)
  else
    local token = cursor.token()
    if not token then
      report("no token under the cursor", vim.log.levels.WARN)
      return false
    end
    item = registry.find_by_text(token.text)
  end
  if not item then
    report(("no spotlight for: %s"):format(tostring(text)), vim.log.levels.WARN)
    return false
  end
  return M.lock_set(item.text, not item.locked)
end

-- ---------- navigation ----------

--- Jump to the next spotlight occurrence. A count prefix (`3]k`) jumps that
--- many occurrences forward, `unimpaired`-style.
---@return boolean moved
function M.next()
  local moved, err = nav.next(vim.v.count1)
  if not moved then
    report(err or "no further occurrence", vim.log.levels.WARN)
  end
  return moved
end

--- Jump to the previous spotlight occurrence. A count prefix (`3[k`) jumps
--- that many occurrences backward, `unimpaired`-style.
---@return boolean moved
function M.prev()
  local moved, err = nav.prev(vim.v.count1)
  if not moved then
    report(err or "no further occurrence", vim.log.levels.WARN)
  end
  return moved
end

-- ---------- quickfix ----------

--- Send every line in the current buffer matching a spotlight to the quickfix
--- list. With `text`, only that spotlight's matches.
---@param text string|nil
---@return boolean filled
function M.quickfix(text)
  local item = nil
  if type(text) == "string" and text ~= "" then
    item = registry.find_by_text(text)
    if not item then
      report(("no spotlight for: %s"):format(text), vim.log.levels.WARN)
      return false
    end
  end
  local found, err, truncated = qf.fill(item)
  if found == 0 then
    report(err or "no matching lines", vim.log.levels.WARN)
    return false
  end
  if truncated then
    report(
      ("stopped at %d matching lines (quickfix.max_entries) — the list is truncated"):format(config.get("quickfix.max_entries")),
      vim.log.levels.WARN
    )
  end
  report(("%d matching line%s"):format(found, found == 1 and "" or "s"))
  return true
end

--- `M.quickfix`'s multi-buffer counterpart: every matching line in every
--- loaded, ordinary file buffer, merged into one quickfix list. With `text`,
--- only that spotlight's matches.
---@param text string|nil
---@return boolean filled
function M.quickfix_all(text)
  local item = nil
  if type(text) == "string" and text ~= "" then
    item = registry.find_by_text(text)
    if not item then
      report(("no spotlight for: %s"):format(text), vim.log.levels.WARN)
      return false
    end
  end
  local found, err, truncated = qf.fill_all(item)
  if found == 0 then
    report(err or "no matching lines", vim.log.levels.WARN)
    return false
  end
  if truncated then
    report(
      ("stopped at %d matching lines (quickfix.max_entries) — the list is truncated"):format(config.get("quickfix.max_entries")),
      vim.log.levels.WARN
    )
  end
  report(("%d matching line%s across all loaded buffers"):format(found, found == 1 and "" or "s"))
  return true
end

-- ---------- yank ----------

--- Yank every matching line in the current buffer into the unnamed register,
--- one per line. With `text`, only that spotlight's matches.
---@param text string|nil
---@return boolean yanked
function M.yank(text)
  local item = nil
  if type(text) == "string" and text ~= "" then
    item = registry.find_by_text(text)
    if not item then
      report(("no spotlight for: %s"):format(text), vim.log.levels.WARN)
      return false
    end
  end
  local found, err, truncated = yank.yank(item)
  if found == 0 then
    report(err or "no matching lines", vim.log.levels.WARN)
    return false
  end
  if truncated then
    report(
      ("stopped at %d matching lines (quickfix.max_entries) — the yank is truncated"):format(config.get("quickfix.max_entries")),
      vim.log.levels.WARN
    )
  end
  report(("yanked %d matching line%s"):format(found, found == 1 and "" or "s"))
  return true
end

-- ---------- persistence ----------

--- Set the persistence decision for the current file.
---@param value boolean|nil # nil clears the override, restoring `persist.default`.
---@return boolean ok
function M.persist_set(value)
  local key = path.buffer_key(0)
  if not key then
    report("this buffer has no file on disk — no per-file override possible", vim.log.levels.WARN)
    return false
  end
  persist.set_exception(key, value)
  report(persist.status(0))
  return true
end

--- Report the effective persistence status for the current file.
---@return nil
function M.persist_status()
  lib.notify(persist.status(0))
end

-- ---------- maintenance ----------

--- Re-apply every spotlight to every window from scratch. The escape hatch for
--- the one thing `matchadd()` cannot do: update in place. Also the fix if some
--- other plugin has cleared the current window's matches with `:call clearmatches()`.
---@return nil
function M.refresh()
  palette.apply()
  registry.rebuild()
end

--- Live access to the registry, for users scripting against the plugin.
---@return Spotlight.Item[]
function M.spotlights()
  return registry.all()
end

-- ---------- setup ----------

--- Configure spotlight.nvim, define the highlight groups, and wire every
--- binding (see `spotlight.bindings`).
---@param opts Spotlight.Config|nil
---@return nil
function M.setup(opts)
  config.setup(opts)
  palette.apply()
  persist.setup()
  require("spotlight.bindings").setup(config.options)
end

return M
