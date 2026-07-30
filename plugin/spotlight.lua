-- plugin/spotlight.lua
-- Load guard. Keeps the plugin from initializing twice and lets users disable
-- it entirely via `vim.g.loaded_spotlight = 1` before it is sourced.

if vim.g.loaded_spotlight then
  return
end
vim.g.loaded_spotlight = 1
