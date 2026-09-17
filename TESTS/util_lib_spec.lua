-- Test code: when something here comes back nil -- a handle, a group id, a
-- captured message -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/util_lib_spec.lua
-- `spotlight.util.lib`: the soft bridge to lib.nvim. Every accessor there has
-- two arms — "lib.nvim answered" and "degrade to the native equivalent" — and
-- the second arm is the one that only runs on a machine where lib.nvim is
-- missing or broken, i.e. never in this suite unless it is driven deliberately.
--
-- So each accessor is driven through both, by replacing the specific lib.nvim
-- sub-module at the `package.loaded` seam (the module resolves them per call,
-- not at load time, which is exactly what makes this possible without reloading
-- anything). The third arm — lib.nvim present but *raising* — is driven too,
-- since a pcall that swallows the wrong thing looks identical to one that works.

local t = require("harness")

local M = {}

---@internal
--- Collect `vim.notify` calls made by `fn`.
---@param fn fun()
---@return { msg: string, level: integer|nil }[]
local function notices(fn)
  local seen = {}
  local saved = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    seen[#seen + 1] = { msg = tostring(msg), level = level }
  end
  local ok, err = pcall(fn)
  vim.notify = saved
  if not ok then
    error(err, 0)
  end
  return seen
end

function M.run()
  local config = require("spotlight.config")
  local lib = require("spotlight.util.lib")

  config.setup()

  -- ---------- try_require ----------
  t.eq("try_require: a table module comes back", type(lib.try_require("spotlight.config")), "table")
  t.eq("try_require: a function module comes back too", type(lib.try_require("lib.nvim.cross.platform.is_windows")), "function")
  t.eq("try_require: a module that does not exist is nil", lib.try_require("spotlight.no.such.module"), nil)
  t.with_modules({ ["spotlight.fake.string.module"] = "just a string" }, function()
    t.eq("try_require: a module returning a scalar is nil, not the scalar", lib.try_require("spotlight.fake.string.module"), nil)
  end)
  t.without_modules({ "spotlight.fake.raising" }, function()
    t.eq("try_require: a module that raises on load is nil", lib.try_require("spotlight.fake.raising"), nil)
  end)

  -- ---------- notify ----------
  local got_msg, got_level
  t.with_modules({
    ["lib.nvim.notify"] = {
      create = function(prefix)
        t.eq("notify: lib.nvim is asked for a '[spotlight]'-prefixed notifier", prefix, "[spotlight]")
        return {
          notify = function(msg, level)
            got_msg, got_level = msg, level
          end,
        }
      end,
    },
  }, function()
    local seen = notices(function()
      lib.notify("hello", vim.log.levels.WARN)
    end)
    t.eq("notify: lib.nvim's notifier is used when available", got_msg, "hello")
    t.eq("notify: with the level passed positionally, not as a method self", got_level, vim.log.levels.WARN)
    t.eq("notify: and vim.notify is not touched", #seen, 0)
  end)

  t.without_modules({ "lib.nvim.notify" }, function()
    local seen = notices(function()
      lib.notify("fallback message")
    end)
    t.eq("notify: without lib.nvim it degrades to vim.notify", #seen, 1)
    t.contains("notify: prefixing the plugin name itself", seen[1].msg, "[spotlight] fallback message")
    t.eq("notify: at INFO by default", seen[1].level, vim.log.levels.INFO)
  end)

  -- lib.nvim present but broken, in each of the three ways the guards allow for.
  t.with_modules({ ["lib.nvim.notify"] = {
    create = function()
      error("boom")
    end,
  } }, function()
    local seen = notices(function()
      lib.notify("still reported")
    end)
    t.eq("notify: a raising create() falls through to vim.notify", #seen, 1)
  end)
  t.with_modules({ ["lib.nvim.notify"] = {
    create = function()
      return "not a notifier"
    end,
  } }, function()
    local seen = notices(function()
      lib.notify("still reported")
    end)
    t.eq("notify: a create() returning the wrong shape falls through", #seen, 1)
  end)
  t.with_modules({
    ["lib.nvim.notify"] = {
      create = function()
        return {
          notify = function()
            error("notifier broke")
          end,
        }
      end,
    },
  }, function()
    local seen = notices(function()
      lib.notify("still reported")
    end)
    t.eq("notify: a raising notifier falls through as well", #seen, 1)
  end)

  -- ---------- debug ----------
  config.setup({ debug = false })
  local quiet = notices(function()
    lib.debug("should not appear", { a = 1 })
  end)
  t.eq("debug: silent while debug = false", #quiet, 0)

  config.setup({ debug = true })
  -- `_logger` is probed once per session and cached (including a cached "absent"),
  -- so a fresh module instance is required to drive the fallback arm. That
  -- caching is deliberate and pinned below.
  local saved_lib = package.loaded["spotlight.util.lib"]
  package.loaded["spotlight.util.lib"] = nil
  local logged = {}
  t.with_modules({
    ["lib.nvim.logger"] = {
      new = function(opts)
        t.eq("debug: the logger instance is named after the plugin", opts.name, "spotlight")
        return {
          debug = function(msg, ctx)
            logged[#logged + 1] = { msg = msg, ctx = ctx }
          end,
        }
      end,
    },
  }, function()
    local fresh = require("spotlight.util.lib")
    local seen = notices(function()
      fresh.debug("structured", { win = 3 })
    end)
    t.eq("debug: routed to lib.nvim.logger when available", #logged, 1)
    t.eq("debug: with the message", logged[1].msg, "structured")
    t.eq("debug: and the structured context", logged[1].ctx.win, 3)
    t.eq("debug: nothing goes to vim.notify", #seen, 0)
    t.eq("debug: has_logger() agrees", fresh.has_logger(), true)
  end)

  package.loaded["spotlight.util.lib"] = nil
  t.without_modules({ "lib.nvim.logger" }, function()
    local fresh = require("spotlight.util.lib")
    local seen = notices(function()
      fresh.debug("no logger here", { k = "v" })
    end)
    t.eq("debug: without a logger it degrades to vim.notify", #seen, 1)
    t.eq("debug: at DEBUG level", seen[1].level, vim.log.levels.DEBUG)
    t.contains("debug: with the context inlined", seen[1].msg, 'k = "v"')
    t.eq("debug: has_logger() says so", fresh.has_logger(), false)
    -- Probed once, never retried: re-installing the logger afterwards does not
    -- change the cached answer for this instance.
    t.with_modules(
      { ["lib.nvim.logger"] = {
        new = function()
          return { debug = function() end }
        end,
      } },
      function()
        t.eq("debug: an absent logger is cached, not re-probed", fresh.has_logger(), false)
      end
    )
  end)
  package.loaded["spotlight.util.lib"] = saved_lib
  config.setup()

  -- ---------- augroup ----------
  local gid = lib.augroup("spotlight_TEST_group")
  t.eq("augroup: returns a numeric id", type(gid), "number")
  vim.api.nvim_create_autocmd("User", { group = gid, pattern = "X", callback = function() end })
  t.eq("augroup: the autocmd landed in it", #vim.api.nvim_get_autocmds({ group = gid }), 1)
  local gid2 = lib.augroup("spotlight_TEST_group")
  t.eq("augroup: the same name resolves to the same group", gid2, gid)
  t.eq("augroup: and it was cleared, which is what makes setup() idempotent", #vim.api.nvim_get_autocmds({ group = gid }), 0)

  t.without_modules({ "lib.nvim.bindings.autocmd.augroup" }, function()
    local native = lib.augroup("spotlight_TEST_group_native")
    t.eq("augroup: falls back to nvim_create_augroup", type(native), "number")
    vim.api.nvim_create_autocmd("User", { group = native, pattern = "Y", callback = function() end })
    lib.augroup("spotlight_TEST_group_native")
    t.eq("augroup: the native fallback clears too", #vim.api.nvim_get_autocmds({ group = native }), 0)
  end)
  local wrong_augroup = { create = {
    clear = function()
      return "not a number"
    end,
  } }
  t.with_modules({ ["lib.nvim.bindings.autocmd.augroup"] = wrong_augroup }, function()
    t.eq("augroup: a lib.nvim answer of the wrong type falls back", type(lib.augroup("spotlight_TEST_group_wrong")), "number")
  end)

  -- ---------- autocmd ----------
  local fired = 0
  local g = lib.augroup("spotlight_TEST_autocmd")
  lib.autocmd("User", function()
    fired = fired + 1
  end, { group = g, pattern = "SpotlightTestEvent", desc = "test" })
  vim.api.nvim_exec_autocmds("User", { pattern = "SpotlightTestEvent" })
  t.eq("autocmd: the callback runs", fired, 1)

  -- The native fallback has to keep lib.nvim's own guarantee: a raising callback
  -- is reported, not propagated into whatever fired the event.
  t.without_modules({ "lib.nvim.bindings.autocmd" }, function()
    local g2 = lib.augroup("spotlight_TEST_autocmd_native")
    local ran = false
    lib.autocmd("User", function()
      ran = true
      error("callback exploded")
    end, { group = g2, pattern = "SpotlightTestRaise", desc = "test" })
    local ok = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "SpotlightTestRaise" })
    t.ok("autocmd: the native fallback registered the callback", ran)
    t.ok("autocmd: and a raising callback does not escape the event", ok)
  end)
  t.with_modules(
    { ["lib.nvim.bindings.autocmd"] = {
      create = function()
        error("lib.nvim broke")
      end,
    } },
    function()
      local g3 = lib.augroup("spotlight_TEST_autocmd_raise")
      local ran = false
      lib.autocmd("User", function()
        ran = true
      end, { group = g3, pattern = "SpotlightTestLibRaise", desc = "test" })
      vim.api.nvim_exec_autocmds("User", { pattern = "SpotlightTestLibRaise" })
      t.ok("autocmd: a raising lib.nvim create() still leaves a working autocmd", ran)
    end
  )

  -- ---------- hl ----------
  lib.hl("SpotlightTestGroup", { bg = "#123456", fg = "#abcdef" })
  t.eq("hl: the group exists", vim.fn.hlexists("SpotlightTestGroup"), 1)
  t.without_modules({ "lib.nvim.ui.hl" }, function()
    lib.hl("SpotlightTestGroupNative", { bg = "#654321", fg = "#fedcba" })
    t.eq("hl: the native fallback defines it too", vim.fn.hlexists("SpotlightTestGroupNative"), 1)
    local def = vim.api.nvim_get_hl(0, { name = "SpotlightTestGroupNative" })
    t.eq("hl: with the background it was given", def.bg, tonumber("654321", 16))
  end)
  t.with_modules({ ["lib.nvim.ui.hl"] = {
    set = function()
      error("hl broke")
    end,
  } }, function()
    lib.hl("SpotlightTestGroupRaise", { bg = "#111111", fg = "#222222" })
    t.eq("hl: a raising lib.nvim.ui.hl falls back to nvim_set_hl", vim.fn.hlexists("SpotlightTestGroupRaise"), 1)
  end)

  -- ---------- debounce ----------
  local handle = lib.debounce(function() end, 1)
  t.eq("debounce: lib.nvim's handle has call()", type(handle.call), "function")
  t.eq("debounce: and cancel()", type(handle.cancel), "function")

  t.without_modules({ "lib.nvim.debounce" }, function()
    local calls, last = 0, nil
    local native = lib.debounce(function(a, b)
      calls = calls + 1
      last = { a, b }
    end, 10)
    t.eq("debounce: the native fallback has the same contract", type(native.call), "function")
    native.call("x", "y")
    t.eq("debounce: nothing has run yet -- that is the point of the delay", calls, 0)
    vim.wait(300, function()
      return calls > 0
    end)
    t.eq("debounce: the callback runs after the delay", calls, 1)
    t.eq("debounce: with its arguments forwarded (1)", last[1], "x")
    t.eq("debounce: with its arguments forwarded (2)", last[2], "y")

    -- A burst coalesces into one call, which is the whole reason persistence
    -- goes through this.
    calls = 0
    native.call(1)
    native.call(2)
    native.call(3)
    vim.wait(300, function()
      return calls > 0
    end)
    t.eq("debounce: three calls in a burst fire once", calls, 1)
    t.eq("debounce: with the last call's arguments", last[1], 3)

    -- And cancel() really cancels.
    calls = 0
    native.call("dropped")
    native.cancel()
    vim.wait(120)
    t.eq("debounce: a cancelled call never runs", calls, 0)
    native.cancel()
    t.ok("debounce: cancelling twice is harmless", true)
  end)
  t.with_modules({ ["lib.nvim.debounce"] = {
    new = function()
      return { nope = true }
    end,
  } }, function()
    local h = lib.debounce(function() end, 1)
    t.eq("debounce: a lib.nvim handle without call() falls back to the native one", type(h.call), "function")
  end)

  -- ---------- dot-repeat ----------
  local target = function() end
  t.without_modules({ "lib.nvim.dotrepeat" }, function()
    t.eq("dot_repeatable: without lib.nvim the function is returned unchanged", lib.dot_repeatable(target), target)
    local ran = 0
    lib.dot_run(function()
      ran = ran + 1
    end)
    t.eq("dot_run: without lib.nvim the function is simply called, once", ran, 1)
  end)
  t.with_modules({ ["lib.nvim.dotrepeat"] = {
    repeatable = function()
      return "not a function"
    end,
  } }, function()
    t.eq("dot_repeatable: a wrong-shaped wrapper is discarded", lib.dot_repeatable(target), target)
  end)
  t.with_modules({ ["lib.nvim.dotrepeat"] = {
    run = function()
      error("dotrepeat broke")
    end,
  } }, function()
    local ran = 0
    lib.dot_run(function()
      ran = ran + 1
    end)
    t.eq("dot_run: a raising lib.nvim run() still runs the action", ran, 1)
  end)

  pcall(vim.api.nvim_del_augroup_by_name, "spotlight_TEST_group")
  pcall(vim.api.nvim_del_augroup_by_name, "spotlight_TEST_group_native")
  pcall(vim.api.nvim_del_augroup_by_name, "spotlight_TEST_group_wrong")
  pcall(vim.api.nvim_del_augroup_by_name, "spotlight_TEST_autocmd")
  pcall(vim.api.nvim_del_augroup_by_name, "spotlight_TEST_autocmd_native")
  pcall(vim.api.nvim_del_augroup_by_name, "spotlight_TEST_autocmd_raise")
  config.setup()
end

return M
