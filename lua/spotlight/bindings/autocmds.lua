---@module 'spotlight.bindings.autocmds'
---@brief The autocommands that make window-local matches behave globally.
---@description
--- These are the ~30 lines of bookkeeping that `matchadd()` costs (see
--- `spotlight.core.match` for why that trade is worth making):
---
---   - `WinNew` / `BufWinEnter` / `TabNewEntered` — a new window starts with no
---     matches at all, so every active spotlight is applied to it. All three are
---     needed: `WinNew` catches a `:split`, `BufWinEnter` catches a buffer being
---     displayed in an existing window, and `TabNewEntered` catches a tab created
---     with its window already in place.
---   - `WinClosed` — drop the ledger entry. The matches died with the window, so
---     `matchdelete()` on those ids would only fail.
---   - `ColorScheme` / `OptionSet background` — redefine the `SpotlightN` groups.
---     A colorscheme clears highlight groups it does not know about, and the
---     background is what selects between the dark and light palettes.
---   - `VimEnter` — load the persisted snapshot, once.
---   - `VimLeavePre` — flush a pending debounced save, so the last toggle before
---     `:qa` is not the one that gets lost.
---
--- None of these fire per keystroke or per text change; that is the point. There
--- is deliberately no `TextChanged` or `CursorMoved` handler anywhere in this
--- plugin — a pattern-based highlight needs no invalidation when the text moves.

local lib = require("spotlight.util.lib")
local palette = require("spotlight.core.palette")
local persist = require("spotlight.persist")
local registry = require("spotlight.core.registry")

local M = {}

---@internal
--- Apply every active spotlight to the window an autocmd fired for. `WinClosed`
--- reports the window in `args.match` (a string), the others imply the current
--- window.
---@param win integer
---@return nil
local function fill_window(win)
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    return
  end
  registry.apply_to_window(win)
end

--- Register spotlight's autocommands. Idempotent: the augroups are cleared on
--- every setup.
---@param cfg Spotlight.Config
---@return nil
function M.setup(cfg)
  local win_group = lib.augroup("spotlight_windows")
  lib.autocmd({ "WinNew", "BufWinEnter", "TabNewEntered" }, function()
    -- Deferred one tick: on WinNew the new window is not yet the current one,
    -- and its id is not in the event args either. By the time the scheduled
    -- callback runs the window exists and is entered, so a plain "fill every
    -- eligible window" pass is both correct and idempotent (core.match skips
    -- windows that already carry the match).
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        fill_window(win)
      end
    end)
  end, {
    group = win_group,
    pattern = "*",
    desc = "spotlight: apply matches to new/changed windows",
  })

  lib.autocmd("WinClosed", function(args)
    local win = tonumber(args.match)
    if win then
      require("spotlight.core.match").forget_window(win)
    end
  end, {
    group = win_group,
    pattern = "*",
    desc = "spotlight: forget a closed window's matches",
  })

  local hl_group = lib.augroup("spotlight_highlights")
  if cfg.palette.reapply_on_colorscheme then
    lib.autocmd("ColorScheme", function()
      palette.apply()
    end, {
      group = hl_group,
      pattern = "*",
      desc = "spotlight: redefine the SpotlightN highlight groups",
    })
  end
  lib.autocmd("OptionSet", function()
    palette.apply()
  end, {
    group = hl_group,
    pattern = "background",
    desc = "spotlight: switch to the dark/light palette",
  })

  local persist_group = lib.augroup("spotlight_persist")
  if cfg.persist.enable then
    -- `VimEnter` rather than a direct call from setup(): a plugin manager may
    -- run setup() before the project's cwd is final (a session plugin, a
    -- `:cd`-ing autocmd), and the store is keyed by project root — loading too
    -- early would read the wrong project's snapshot.
    lib.autocmd("VimEnter", function()
      persist.load()
    end, {
      group = persist_group,
      pattern = "*",
      desc = "spotlight: restore the persisted spotlights",
    })
    -- Already inside a session (lazy-loaded well after VimEnter): load now, on
    -- the next tick so setup() has finished wiring everything first.
    if vim.v.vim_did_enter == 1 then
      vim.schedule(function()
        persist.load()
      end)
    end

    lib.autocmd("VimLeavePre", function()
      persist.flush()
    end, {
      group = persist_group,
      pattern = "*",
      desc = "spotlight: flush a pending state save",
    })
  end
end

return M
