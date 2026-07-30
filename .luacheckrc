-- luacheck configuration for spotlight.nvim
std = "luajit"
-- `vim` is writable (we set vim.o.*, vim.w[win].* etc.); `read_globals` would
-- flag those field assignments as "setting a read-only field".
globals = { "vim" }
max_line_length = 130

-- docs/BINDINGS.md is a manually column-aligned data table (documentation),
-- not runtime code; its alignment intentionally exceeds the line limit.
exclude_files = { "docs/BINDINGS.md" }
