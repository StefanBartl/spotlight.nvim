-- docs/TESTS/run.lua
-- Suite entry point. Run from the plugin root, with lib.nvim on the runtimepath:
--
--   nvim --headless -u NONE -c "set rtp+=.,../lib.nvim" -c "luafile docs/TESTS/run.lua" -c "qa!"
--
-- Exits non-zero on the first failing expectation so CI notices, and prints
-- every failure rather than only the first.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
package.path = ("%s/?.lua;%s"):format(root, package.path)

local t = require("harness")

local SPECS = {
  "cursor_spec",
  "registry_spec",
  "nav_spec",
  "persist_spec",
  "commands_spec",
}

-- Notifications are outcome reports, not test output: silence them so a failure
-- is visible in the noise a full suite would otherwise produce.
vim.notify = function() end

for _, name in ipairs(SPECS) do
  local ok, spec = pcall(require, name)
  if not ok then
    t.failures[#t.failures + 1] = ("%s: failed to load: %s"):format(name, spec)
  else
    local ran, err = pcall(spec.run)
    if not ran then
      t.failures[#t.failures + 1] = ("%s: crashed: %s"):format(name, err)
    end
  end
end

io.write(("\nspotlight.nvim: %d passed, %d failed\n"):format(t.passed, #t.failures))
for _, f in ipairs(t.failures) do
  io.write("  FAIL  " .. f .. "\n")
end

if #t.failures > 0 then
  vim.cmd("cquit 1")
end
