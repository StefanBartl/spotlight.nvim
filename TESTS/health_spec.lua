-- Test code: when something here comes back nil -- a collected report, a
-- registry item -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/health_spec.lua
-- `:checkhealth spotlight`. Nothing in the suite touched `spotlight.health`
-- before, which matters more than it sounds: a health check is the one function
-- a user runs *because* something is already broken, so its own failure arms are
-- exactly the ones that must not raise.
--
-- `vim.health` is replaced with a collector, so the report is asserted as data
-- rather than rendered, and the check can be driven against a machine that is
-- deliberately missing dependencies. That is also how the pinned defect at the
-- bottom is reached: the "lib.nvim is missing" arm ends by calling into the
-- missing lib.nvim unconditionally.

local t = require("harness")

local M = {}

local COMPOSER = "lib.nvim.bindings.usercmd.composer"
local SELECT = "ui.kit.select"

---@internal
--- Run `spotlight.health.check()` against a collector.
---
--- `legacy` swaps the modern `vim.health.start/ok/warn/...` names for the 0.9-era
--- `report_*` aliases, which is the other half of the accessor dance at the top
--- of `check()` and is otherwise unreachable.
---@param legacy boolean|nil
---@return { level: string, msg: string }[] reports, boolean ok, string|nil err
local function collect(legacy)
  local reports = {}
  local function sink(level)
    return function(msg)
      reports[#reports + 1] = { level = level, msg = tostring(msg) }
    end
  end
  local api = {}
  for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
    api[legacy and ("report_" .. level) or level] = sink(level)
  end
  local saved = vim.health
  ---@diagnostic disable-next-line: assign-type-mismatch
  vim.health = api
  local ok, err = pcall(function()
    require("spotlight.health").check()
  end)
  vim.health = saved
  return reports, ok, ok and nil or tostring(err)
end

---@internal
---@param reports { level: string, msg: string }[]
---@param level string
---@param needle string
---@return boolean
local function has(reports, level, needle)
  for _, r in ipairs(reports) do
    if r.level == level and r.msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

---@internal
---@param reports { level: string, msg: string }[]
---@param level string
---@return integer
local function count_at(reports, level)
  local n = 0
  for _, r in ipairs(reports) do
    if r.level == level then
      n = n + 1
    end
  end
  return n
end

function M.run()
  local api = require("spotlight")
  local config = require("spotlight.config")
  local registry = require("spotlight.core.registry")

  config.setup()
  api.setup()
  registry.clear()

  -- ---------- the ordinary report ----------
  local tgc = vim.o.termguicolors
  vim.o.termguicolors = true
  local reports = collect(false)
  t.ok("check: the report is not empty", #reports > 10)
  t.ok("check: it opens a section for the plugin", has(reports, "start", "spotlight.nvim"))
  t.ok("check: a lib.nvim section of its own", has(reports, "start", "spotlight.nvim: lib.nvim"))
  t.ok("check: a ui.nvim section of its own", has(reports, "start", "spotlight.nvim: ui.nvim"))
  t.ok("check: a configuration section", has(reports, "start", "spotlight.nvim: configuration"))
  t.ok("check: and a live-state section", has(reports, "start", "spotlight.nvim: state"))
  t.ok("check: the Neovim version is reported ok", has(reports, "ok", "Neovim"))
  t.ok("check: 'termguicolors' on is reported ok", has(reports, "ok", "'termguicolors' is on"))
  t.ok("check: every required lib.nvim module was found", has(reports, "ok", COMPOSER))
  t.ok("check: including the keymap registry", has(reports, "ok", "lib.nvim.bindings.keymap"))
  t.ok("check: the configuration validated cleanly", has(reports, "ok", "configuration validated cleanly"))
  t.ok("check: the palette size is reported", has(reports, "info", "palette: 8 slot"))
  t.ok("check: the match settings are spelled out", has(reports, "info", "word boundaries on"))
  t.ok("check: including which side of 'hlsearch' the priority falls on", has(reports, "info", "above 'hlsearch'"))
  t.ok("check: the resolver pattern count", has(reports, "info", "resolver pattern"))
  t.ok("check: the list's counting settings", has(reports, "info", "list: count on"))
  t.ok("check: the sign-column settings", has(reports, "info", "map: sign_text"))
  t.ok("check: debug logging is reported off by default", has(reports, "info", "debug: off"))
  t.ok("check: the keymap preset is reported on", has(reports, "ok", "keymap preset: on"))
  t.ok("check: with the keys it bound", has(reports, "ok", "toggle_here ="))
  t.ok("check: the active spotlight count", has(reports, "info", "0 active spotlights"))
  t.ok("check: persistence is reported on, with the project root", has(reports, "ok", "persistence: on"))
  t.ok("check: sets are reported", has(reports, "info", "sets:"))

  -- The legacy 0.9 accessor names work too.
  local legacy = collect(true)
  t.ok("check: the report_* aliases are honoured for Neovim 0.9", #legacy > 10)
  t.ok("check: with the same content", has(legacy, "ok", "Neovim"))

  -- ---------- 'termguicolors' off ----------
  vim.o.termguicolors = false
  local no_tgc = collect(false)
  t.ok("check: 'termguicolors' off is a warning, not an error", has(no_tgc, "warn", "'termguicolors' is off"))
  t.ok("check: naming the consequence", has(no_tgc, "warn", "256-color"))
  vim.o.termguicolors = tgc

  -- ---------- what the state section reports ----------
  local bufnr = t.fixture({ "req=aaa one", "req=bbb two" })
  registry.add({ text = "req=aaa", kind = "literal" }, { origin = "logs/h.log" })
  local locked = registry.add({ text = "req=bbb", kind = "literal" }, { origin = "logs/h.log" })
  registry.set_locked(locked.id, true)
  registry.set_line(locked.id, true)
  registry.add_at({ text = "req=aaa", kind = "literal" }, { buf = bufnr, row1 = 1, col1 = 5 })
  vim.w[vim.api.nvim_get_current_win()].spotlight_disabled = true

  local stateful = collect(false)
  t.ok("state: the spotlight count", has(stateful, "info", "3 active spotlights"))
  t.ok("state: each spotlight is listed with its slot and group", has(stateful, "info", "slot 1 (Spotlight1)"))
  t.ok("state: a locked one is tagged", has(stateful, "info", "[locked]"))
  t.ok("state: a line-mode one reports the priority it renders at", has(stateful, "info", "[whole line, priority 9]"))
  t.ok("state: an opted-out window is counted", has(stateful, "info", "window"))
  t.ok("state: ...and named as opted out", has(stateful, "info", "opted out of spotlighting"))
  vim.w[vim.api.nvim_get_current_win()].spotlight_disabled = nil
  registry.clear()

  -- ---------- config issues surface as warnings ----------
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ nav = { scope = "sideways" }, map = { sign_text = "much too wide" } })
  local with_issues = collect(false)
  t.ok("config: a normalization issue is reported as a warning", has(with_issues, "warn", "nav.scope"))
  t.ok("config: every issue gets its own line", has(with_issues, "warn", "map.sign_text"))
  t.eq("config: and the clean-configuration ok line is gone", has(with_issues, "ok", "configuration validated cleanly"), false)
  config.setup()
  api.setup()

  -- ---------- the reporting switches ----------
  config.setup({ debug = true })
  local dbg = collect(false)
  t.ok("config: debug on is reported, either way round", has(dbg, "ok", "debug: on") or has(dbg, "info", "debug: on"))
  config.setup({ keymaps = { preset = false } })
  local nopreset = collect(false)
  t.ok("config: the preset being off is reported as info, not a problem", has(nopreset, "info", "keymap preset: off"))
  config.setup({ persist = { enable = false } })
  local nopersist = collect(false)
  t.ok("config: persistence off is reported", has(nopersist, "info", "persistence: off"))
  config.setup()

  -- Per-file overrides are listed one by one.
  local persist = require("spotlight.persist")
  persist.set_exception("logs/secret.log", false)
  local overrides = collect(false)
  t.ok("persist: an override is listed", has(overrides, "info", "override: logs/secret.log"))
  t.ok("persist: with its decision spelled out", has(overrides, "info", "do not persist"))
  persist.set_exception("logs/secret.log", nil)
  local no_overrides = collect(false)
  t.ok("persist: with none, the global default is reported instead", has(no_overrides, "info", "no per-file overrides"))

  -- ---------- ui.nvim and which-key ----------
  -- ui.kit.select is genuinely absent from this suite's runtimepath, which is
  -- the required-and-missing arm; installing a double gives the other one.
  t.ok("ui.nvim: a missing ui.kit.select is an error, since the list needs it", has(reports, "error", SELECT))
  t.ok("ui.nvim: with an install hint", has(reports, "error", "the spotlight list will not work"))
  t.with_modules({ [SELECT] = { open = function() end } }, function()
    local with_ui = collect(false)
    t.ok("ui.nvim: with ui.kit.select present it is reported ok", has(with_ui, "ok", SELECT))
    t.eq("ui.nvim: and no longer as an error", has(with_ui, "error", SELECT), false)
  end)

  t.ok("which-key: absent is info, not a problem", has(reports, "info", "which-key not found"))
  t.with_modules({ ["which-key"] = {} }, function()
    local wk = collect(false)
    t.ok("which-key: present is reported ok", has(wk, "ok", "which-key detected"))
  end)

  -- ---------- an optional lib.nvim module missing is info, not an error ----------
  t.without_modules({ "lib.nvim.logger" }, function()
    local no_logger = collect(false)
    t.ok("lib.nvim: an optional module is reported as info", has(no_logger, "info", "lib.nvim.logger missing"))
    t.ok("lib.nvim: naming the native fallback", has(no_logger, "info", "falls back to a native equivalent"))
    t.eq("lib.nvim: and not as an error", has(no_logger, "error", "lib.nvim.logger"), false)
  end)

  -- ---------- BUG: the "lib.nvim is missing" arm calls into lib.nvim ----------
  --
  -- `check()` reports a missing `usercmd.composer` as an error -- correctly, the
  -- `:Spotlight` verb cannot exist without it -- and then, as its very last
  -- statement, calls `require("lib.nvim.bindings.usercmd.composer").checkhealth
  -- ("Spotlight")` with no guard at all. On the one machine the error arm exists
  -- for, `:checkhealth spotlight` therefore dies with a stack trace instead of
  -- finishing its report: the user is shown some of the diagnosis and then the
  -- failure of the tool that was supposed to diagnose it.
  --
  -- This is the fourth repo in this campaign with the same shape (emojis.nvim,
  -- gopath.nvim, diff.nvim). Fix: `pcall` the trailing call, or gate it on the
  -- same probe the LIB_MODULES loop already performed. Pinned rather than fixed
  -- because it changes what `:checkhealth` prints.
  t.without_modules({ COMPOSER }, function()
    local broken, ok, err = collect(false)
    t.ok("BUG: the missing composer IS reported first", has(broken, "error", COMPOSER))
    t.ok("BUG: and a good deal of the report was produced", #broken > 20)
    t.eq("BUG: but check() then raises instead of returning", ok, false)
    t.contains("BUG: at the unguarded trailing composer call", err, "health.lua")
    t.contains("BUG: naming the module it just reported as missing", err, COMPOSER)
    -- The raise comes *after* health's own last line, which is what makes it
    -- look like a complete report followed by an unexplained stack trace: the
    -- composer's own `:checkhealth` section is simply missing.
    t.ok("BUG: health's own report ran to its last line first", has(broken, "info", "sets:"))
    t.contains("BUG: and nothing from the composer followed it", broken[#broken].msg, "sets:")
  end)

  -- Everything else missing at once is survivable -- it is only that one
  -- trailing call that is not guarded.
  t.without_modules({
    "lib.nvim.ui.list",
    "lib.nvim.store.project",
    "lib.nvim.debounce",
    "lib.nvim.notify",
    "lib.nvim.logger",
    "lib.nvim.bindings.keymap",
    "lib.nvim.dotrepeat",
    "lib.nvim.bindings.autocmd",
    "lib.nvim.ui.hl",
  }, function()
    local bare, ok = collect(false)
    t.ok("check: with every other lib.nvim module gone the report still completes", ok)
    t.ok("check: reaching its last section", has(bare, "info", "sets:"))
    t.ok("check: and reporting the required ones as errors", count_at(bare, "error") >= 2)
  end)

  -- ---------- a config module that will not load ----------
  -- The early return exists so `:checkhealth` says *that* rather than dying on
  -- the next line, which is exactly the guard the pinned defect above is missing.
  t.without_modules({ "spotlight.config" }, function()
    local broken_cfg, ok = collect(false)
    t.ok("check: a config module that fails to load does not take the report with it", ok)
    t.ok("check: it is reported as an error", has(broken_cfg, "error", "config module failed to load"))
    t.eq("check: and the check returns there rather than continuing", has(broken_cfg, "start", "spotlight.nvim: state"), false)
  end)

  registry.clear()
  config.setup()
  api.setup()
end

return M
