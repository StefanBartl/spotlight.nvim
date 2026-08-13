---@module 'spotlight.health'
---@brief `:checkhealth spotlight` diagnostics.
---@description
--- Reports the Neovim version, `lib.nvim` availability per required module (each
--- one carries a distinct feature, so "lib.nvim missing" is not a useful answer),
--- 'termguicolors' — the one environment setting that silently ruins the palette
--- — the config issues `spotlight.config` collected while normalizing, and the
--- live registry / persistence state. Read-only: never mutates anything.

local M = {}

--- The lib.nvim modules spotlight genuinely needs, and what each one is for.
---@type { module: string, purpose: string, required: boolean }[]
local LIB_MODULES = {
  { module = "lib.nvim.usercmd.composer", purpose = "the :Spotlight verb", required = true },
  { module = "lib.nvim.ui.kit.select", purpose = "the spotlight list", required = true },
  { module = "lib.nvim.store.project", purpose = "per-project persistence", required = false },
  { module = "lib.nvim.debounce", purpose = "coalesced state saves", required = false },
  { module = "lib.nvim.notify", purpose = "namespaced notifications", required = false },
  { module = "lib.nvim.logger", purpose = "structured debug logs (spotlight.debug)", required = false },
  { module = "lib.nvim.map", purpose = "keymap registration", required = false },
  { module = "lib.nvim.dotrepeat", purpose = "`.` repeats the normal-mode toggle", required = false },
  { module = "lib.nvim.autocmd", purpose = "guarded autocommands", required = false },
  { module = "lib.nvim.ui.hl", purpose = "highlight definition", required = false },
}

--- Run the health check.
---@return nil
function M.check()
  local health = vim.health or require("health")
  local start = health.start or health.report_start
  local ok = health.ok or health.report_ok
  local warn = health.warn or health.report_warn
  local error_ = health.error or health.report_error
  local info = health.info or health.report_info

  start("spotlight.nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    warn("spotlight.nvim targets Neovim 0.9+")
  end

  -- ---------- environment ----------
  if vim.o.termguicolors then
    ok("'termguicolors' is on — the palette's hex colors render as configured")
  else
    warn(
      "'termguicolors' is off — the palette's #rrggbb values are approximated to the terminal's 256-color "
        .. "cube, so slots may become hard to tell apart. Set `vim.o.termguicolors = true`."
    )
  end

  -- ---------- lib.nvim ----------
  start("spotlight.nvim: lib.nvim")
  for _, entry in ipairs(LIB_MODULES) do
    if pcall(require, entry.module) then
      ok(("%s — %s"):format(entry.module, entry.purpose))
    elseif entry.required then
      error_(('%s missing — %s will not work; install "StefanBartl/lib.nvim"'):format(entry.module, entry.purpose))
    else
      info(("%s missing — %s falls back to a native equivalent"):format(entry.module, entry.purpose))
    end
  end

  if require("spotlight.bindings.which_key").available() then
    ok("which-key detected — the preset's prefix is labelled as a group")
  else
    info("which-key not found — mappings still carry their own descriptions")
  end

  -- ---------- config ----------
  start("spotlight.nvim: configuration")
  local cfg_ok, config = pcall(require, "spotlight.config")
  if not cfg_ok then
    error_("config module failed to load: " .. tostring(config))
    return
  end

  if #config.issues == 0 then
    ok("configuration validated cleanly")
  else
    for _, issue in ipairs(config.issues) do
      warn(issue)
    end
  end

  local palette = require("spotlight.core.palette")
  info(("palette: %d slot%s for &background=%s"):format(palette.size(), palette.size() == 1 and "" or "s", vim.o.background))

  local match_opts = config.get("match")
  info(
    ("match: priority %d (%s 'hlsearch'), %s, word boundaries %s, max %d"):format(
      match_opts.priority,
      match_opts.priority > 0 and "above" or "below",
      match_opts.ignore_case and "case-insensitive (\\c)" or "case-sensitive (\\C)",
      match_opts.word_boundaries and "on" or "off",
      match_opts.max
    )
  )
  info(
    ("cursor: %d resolver pattern%s, <cword> fallback %s"):format(
      #config.get("cursor.patterns"),
      #config.get("cursor.patterns") == 1 and "" or "s",
      config.get("cursor.fallback_cword") and "on" or "off"
    )
  )
  info(
    ("list: count %s (scope: %s, max %d lines)"):format(
      config.get("list.count") and "on" or "off",
      config.get("list.count_scope"),
      config.get("list.count_max_lines")
    )
  )
  -- One-shot only, not tracked here as live state — see spotlight.map's own
  -- module doc for why "which buffers currently have marks" is deliberately
  -- not session-global bookkeeping.
  info(("map: sign_text '%s', max %d entries"):format(config.get("map.sign_text"), config.get("map.max_entries")))

  -- Debug logging (resolver outcome, ledger apply/skip, snapshot filter, nav scope).
  if config.get("debug") == true then
    if require("spotlight.util.lib").has_logger() then
      ok("debug: on, lib.nvim.logger available (structured logs, inspect with :LibLogger)")
    else
      info("debug: on, lib.nvim.logger not found — falling back to vim.notify at DEBUG level")
    end
  else
    info("debug: off (set `debug = true` to log the resolver, ledger, persistence and nav decisions)")
  end

  local keymaps = config.get("keymaps")
  if keymaps.preset then
    local bound = {}
    for _, name in ipairs({ "toggle_here", "toggle", "list", "clear", "quickfix", "next", "prev" }) do
      if type(keymaps[name]) == "string" and keymaps[name] ~= "" then
        bound[#bound + 1] = ("%s = %s"):format(name, keymaps[name])
      end
    end
    ok("keymap preset: on (" .. table.concat(bound, ", ") .. ")")
  else
    info("keymap preset: off — use :Spotlight, or bind require('spotlight').<action> yourself")
  end

  -- ---------- runtime state ----------
  start("spotlight.nvim: state")
  local registry = require("spotlight.core.registry")
  local match = require("spotlight.core.match")
  info(
    ("%d active spotlight%s across %d tracked window%s"):format(
      registry.count(),
      registry.count() == 1 and "" or "s",
      match.tracked_windows(),
      match.tracked_windows() == 1 and "" or "s"
    )
  )
  for _, item in ipairs(registry.all()) do
    info(("  slot %d (%s): %s%s"):format(item.slot, item.hl, item.text, item.locked and " [locked]" or ""))
  end

  local persist = require("spotlight.persist")
  if config.get("persist.enable") then
    local path = require("spotlight.util.path")
    ok(("persistence: on (project root: %s)"):format(path.root()))
    info("  " .. persist.status(0))
    local n = 0
    for key, value in pairs(persist.exceptions()) do
      n = n + 1
      info(("  override: %s = %s"):format(key, value and "persist" or "do not persist"))
    end
    if n == 0 then
      info(("  no per-file overrides (global default: %s)"):format(config.get("persist.default") and "on" or "off"))
    end
  else
    info("persistence: off (persist.enable = false)")
  end

  local sets = require("spotlight.sets")
  local set_names = sets.names()
  if #set_names == 0 then
    info("sets: none saved")
  else
    local summaries = {}
    for i, name in ipairs(set_names) do
      summaries[i] = ("%s: %d"):format(name, sets.count(name) or 0)
    end
    info(("sets: %d saved (%s)"):format(#set_names, table.concat(summaries, ", ")))
  end

  require("lib.nvim.usercmd.composer").checkhealth("Spotlight")
end

return M
