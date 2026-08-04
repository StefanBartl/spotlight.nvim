---@module 'spotlight.bindings.usrcmds'
---@brief The `:Spotlight <subcommand>` verb, built via lib.nvim's composer.
---@description
--- One verb for the whole plugin (`:Spotlight toggle`, `:Spotlight persist off`,
--- …) rather than a family of `:SpotlightToggle` / `:SpotlightClear` commands:
--- the composer derives `<Tab>` completion, argument typing and validation, and
--- the Markdown docs from the same route tree, so the command surface cannot
--- drift out of sync with its own documentation.
---
--- `toggle` is range-aware so `:'<,'>Spotlight toggle` works from a visual
--- selection. It reads the selection from the `'<`/`'>` marks rather than from
--- the live cursor: by the time a `:` command runs, Visual mode has already
--- ended — which is precisely when those marks become valid, and precisely when
--- `spotlight.cursor.selection`'s live-position approach stops working.

local composer = require("lib.nvim.usercmd.composer")

local M = {}

---@internal
--- The literal text of a single-line range, from composer's `ctx.range`.
---
--- The columns come from `ctx.range.col1`/`col2`, which composer reads off the
--- `'<`/`'>` marks — the same source this used to query via `vim.fn.col()`
--- directly, now shared rather than re-derived. The route's `visual` allowlist
--- takes care of rejecting blockwise/linewise selections, so only the
--- single-line constraint is left to check here.
---@param r Lib.UserCmd.Composer.RangeInfo
---@return string|nil text, string|nil err
local function range_text(r)
  if not r.range or r.range == 0 then
    return nil, nil
  end
  if r.line1 ~= r.line2 then
    return nil, "spotlight a selection within a single line"
  end
  local line = vim.api.nvim_buf_get_lines(0, r.line1 - 1, r.line1, false)[1]
  if not line then
    return nil, "empty line"
  end
  local scol, ecol = r.col1, r.col2
  if type(scol) ~= "number" or type(ecol) ~= "number" or scol <= 0 then
    return nil, "no character-wise selection to read"
  end
  if scol > ecol then
    scol, ecol = ecol, scol
  end
  local text = line:sub(scol, math.min(ecol, #line))
  if text == "" then
    return nil, "empty selection"
  end
  return text, nil
end

--- Create the `:Spotlight` verb.
---@return nil
function M.setup()
  local api = require("spotlight")
  local lib = require("spotlight.util.lib")

  composer.verb("Spotlight", {
    desc = "Spotlight: persistent multi-token highlighting",
    -- Bare `:Spotlight` is the action reached most often, so it is the default
    -- rather than an error or a help dump.
    default = function()
      api.toggle()
    end,
    routes = {
      {
        path = { "toggle" },
        range = true,
        -- A spotlight is a piece of text within one line, so only a charwise
        -- selection carries usable geometry: linewise has no columns to read
        -- and blockwise spans several lines by definition.
        visual = { "charwise" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Toggle a spotlight (cursor token, range selection, or explicit TEXT)",
        run = function(ctx)
          if type(ctx.args.text) == "string" and ctx.args.text ~= "" then
            local existing = require("spotlight.core.registry").find_by_text(ctx.args.text)
            if existing then
              api.remove(ctx.args.text)
            else
              api.add(ctx.args.text)
            end
            return
          end
          local text, err = range_text(ctx.range)
          if err then
            lib.notify(err, vim.log.levels.WARN)
            return
          end
          if text then
            local existing = require("spotlight.core.registry").find_by_text(text)
            if existing then
              api.remove(text)
            else
              api.add(text)
            end
            return
          end
          api.toggle()
        end,
      },

      {
        path = { "add" },
        args = { { name = "text", type = "STRING" } },
        desc = "Add a spotlight for the literal TEXT",
        run = function(ctx)
          api.add(ctx.args.text)
        end,
      },

      {
        path = { "remove" },
        args = { { name = "text", type = "STRING" } },
        desc = "Remove the spotlight matching TEXT exactly",
        run = function(ctx)
          api.remove(ctx.args.text)
        end,
      },

      {
        path = { "clear" },
        desc = "Remove every spotlight",
        run = function()
          api.clear()
        end,
      },

      {
        path = { "list" },
        args = { { name = "action", type = "STRING", enum = { "jump", "remove" }, optional = true } },
        desc = "Open the spotlight list (swatch + pattern + match count)",
        run = function(ctx)
          if ctx.args.action == "remove" then
            api.list_remove()
          else
            api.list()
          end
        end,
      },

      {
        path = { "next" },
        desc = "Jump to the next spotlight occurrence",
        run = function()
          api.next()
        end,
      },

      {
        path = { "prev" },
        desc = "Jump to the previous spotlight occurrence",
        run = function()
          api.prev()
        end,
      },

      {
        path = { "qf" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Matching lines to the quickfix list (all spotlights, or just TEXT's)",
        run = function(ctx)
          api.quickfix(ctx.args.text)
        end,
      },

      {
        path = { "persist" },
        args = { { name = "state", type = "STRING", enum = { "on", "off", "default", "status" }, optional = true } },
        desc = "Per-file persistence: on / off / default (clear override) / status",
        run = function(ctx)
          local state = ctx.args.state or "status"
          if state == "on" then
            api.persist_set(true)
          elseif state == "off" then
            api.persist_set(false)
          elseif state == "default" then
            api.persist_set(nil)
          else
            api.persist_status()
          end
        end,
      },

      {
        path = { "refresh" },
        desc = "Re-apply every spotlight to every window (and redefine the palette)",
        run = function()
          api.refresh()
        end,
      },
    },
  })
end

return M
