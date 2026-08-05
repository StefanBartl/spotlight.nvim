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
