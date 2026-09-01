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
---
--- `here` is `toggle`'s "this occurrence only" counterpart (see
--- `spotlight.M.toggle_here`), range-aware on the same terms.

local composer = require("lib.nvim.bindings.usercmd.composer")

local M = {}

---@internal
--- The literal text of a single-line range, from composer's `ctx.range`.
---
--- The columns come from `ctx.range.col1`/`col2`, which composer reads off the
--- `'<`/`'>` marks — the same source this used to query via `vim.fn.col()`
--- directly, now shared rather than re-derived. The route's `visual` allowlist
--- takes care of rejecting blockwise/linewise selections, so only the
--- single-line constraint is left to check here.
--- The third return value is the selection's own start column (1-based),
--- needed by the `here` route to pin a buffer-scoped spotlight — `toggle`'s
--- text-only routes ignore it, same as any Lua caller ignoring a trailing
--- return.
---@param r Lib.UserCmd.Composer.RangeInfo
---@return string|nil text, string|nil err, integer|nil start_col1
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
  local c1, c2 = r.col1, r.col2
  if type(c1) ~= "number" or type(c2) ~= "number" or c1 <= 0 then
    return nil, "no character-wise selection to read"
  end
  local scol, ecol = c1, c2
  if scol > ecol then
    scol, ecol = ecol, scol
  end
  local text = line:sub(scol, math.min(ecol, #line))
  if text == "" then
    return nil, "empty selection"
  end
  return text, nil, scol
end

--- Create the `:Spotlight` verb.
---@return nil
function M.setup()
  local api = require("spotlight")
  local lib = require("spotlight.util.lib")

  -- A custom arg type so `:Spotlight sets switch <Tab>` / `delete <Tab>`
  -- complete from whatever sets currently exist, read fresh on every press —
  -- `sets.names()` is cheap (session-cached) and this is the composer's own
  -- documented pattern for a dynamic completion source.
  composer.register_type("SPOTLIGHT_SET_NAME", {
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(arg_lead)
      return vim.tbl_filter(function(name)
        return name:sub(1, #arg_lead) == arg_lead
      end, require("spotlight.sets").names())
    end,
  })

  composer.verb("Spotlight", {
    desc = "Spotlight: persistent multi-token highlighting",
    -- Bare `:Spotlight` is the action reached most often, so it is the default
    -- rather than an error or a help dump. Routed through `dot_run` for the
    -- same reason as the `toggle` route's cursor-fallback branch below: `.`
    -- afterwards should re-toggle whatever the cursor is on then.
    default = function()
      lib.dot_run(api.toggle)
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
          -- No explicit text and no range: this resolves the cursor token,
          -- same as the bare `:Spotlight` default — dot-repeatable for the
          -- same reason.
          lib.dot_run(api.toggle)
        end,
      },

      {
        path = { "here" },
        range = true,
        visual = { "charwise" },
        desc = "Toggle a spotlight for only this occurrence (cursor token or range selection)",
        run = function(ctx)
          local text, err, scol = range_text(ctx.range)
          if err then
            lib.notify(err, vim.log.levels.WARN)
            return
          end
          if text and scol then
            api.toggle_here_at(text, { buf = vim.api.nvim_get_current_buf(), row1 = ctx.range.line1, col1 = scol })
            return
          end
          api.toggle_here()
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
        args = {
          { name = "action", type = "STRING", enum = { "jump", "remove", "lock", "line" }, optional = true },
          { name = "filter", type = "STRING", optional = true },
        },
        desc = "Open the spotlight list (swatch + pattern + match count)  [filter]",
        run = function(ctx)
          -- The filter matches slot / highlight group / origin / text, so one
          -- token answers both "which colour" and "from which file".
          local filter = ctx.args.filter
          if ctx.args.action == "remove" then
            api.list_remove(filter)
          elseif ctx.args.action == "lock" then
            api.list_lock(filter)
          elseif ctx.args.action == "line" then
            api.list_line(filter)
          else
            api.list(filter)
          end
        end,
      },

      {
        path = { "next" },
        bang = true,
        desc = "Jump to the next spotlight occurrence  (! ignores nav.scope)",
        run = function(ctx)
          api.next(ctx.bang)
        end,
      },

      {
        path = { "prev" },
        bang = true,
        desc = "Jump to the previous spotlight occurrence  (! ignores nav.scope)",
        run = function(ctx)
          api.prev(ctx.bang)
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
        path = { "qf", "all" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Matching lines across every loaded buffer to the quickfix list",
        run = function(ctx)
          api.quickfix_all(ctx.args.text)
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
        path = { "winopt" },
        args = { { name = "state", type = "STRING", enum = { "on", "off", "toggle", "status" }, optional = true } },
        desc = "Per-window opt-out: on / off / toggle (default) / status",
        run = function(ctx)
          local state = ctx.args.state or "toggle"
          if state == "on" then
            api.winopt_set(false)
          elseif state == "off" then
            api.winopt_set(true)
          elseif state == "status" then
            api.winopt_status()
          else
            api.winopt_toggle()
          end
        end,
      },

      {
        path = { "yank" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Yank matching lines to the unnamed register (all spotlights, or just TEXT's)",
        run = function(ctx)
          api.yank(ctx.args.text)
        end,
      },

      {
        path = { "lock" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Toggle whether a spotlight keeps its palette slot permanently (TEXT, or the cursor token)",
        run = function(ctx)
          api.lock_toggle(ctx.args.text)
        end,
      },

      {
        path = { "line" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Toggle whole-line rendering for a spotlight (TEXT, or the cursor token)",
        run = function(ctx)
          api.line_toggle(ctx.args.text)
        end,
      },

      {
        path = { "map" },
        args = { { name = "text", type = "STRING", optional = true } },
        desc = "Mark every matching line in the sign column (all spotlights, or just TEXT's)",
        run = function(ctx)
          api.map(ctx.args.text)
        end,
      },

      {
        path = { "map", "clear" },
        desc = "Clear the sign-column occurrence map in the current buffer",
        run = function()
          api.map_clear()
        end,
      },

      {
        path = { "sets", "save" },
        args = { { name = "name", type = "STRING" } },
        desc = "Save the active spotlights as a named set (overwrites if it already exists)",
        run = function(ctx)
          api.sets_save(ctx.args.name)
        end,
      },

      {
        path = { "sets", "switch" },
        args = { { name = "name", type = "SPOTLIGHT_SET_NAME" } },
        desc = "Clear the active spotlights and restore a saved set",
        run = function(ctx)
          api.sets_switch(ctx.args.name)
        end,
      },

      {
        path = { "sets", "delete" },
        args = { { name = "name", type = "SPOTLIGHT_SET_NAME" } },
        desc = "Delete a saved set (does not touch the active spotlights)",
        run = function(ctx)
          api.sets_delete(ctx.args.name)
        end,
      },

      {
        path = { "sets", "list" },
        desc = "List every saved set and how many spotlights it holds",
        run = function()
          api.sets_list()
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
