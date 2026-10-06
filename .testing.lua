-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "spotlight",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  -- ui.nvim is deliberately NOT a dependency here: health_spec.lua asserts that ui.kit.select is absent
  -- from the runtimepath (the required-and-missing arm of :checkhealth).
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- Child editors start like the old CI line (-c luafile): vim_did_enter == 0, <cfile>/<cword> work.
  host = "c",
  -- Guards (testing.nvim docs/GUARDS.md). The fleet measurement found nothing real here: with
  -- isolated = "file" the plugin store (lib.nvim cache) lives in the child sandbox and setup() state
  -- (autocmd groups, keymaps, mapleader) dies with the child, so every guard can be a hard error.
  -- No guard_allow entries are needed: the specs spawn no executables, use no network and write
  -- nothing outside the temp dir / child sandbox.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
}
