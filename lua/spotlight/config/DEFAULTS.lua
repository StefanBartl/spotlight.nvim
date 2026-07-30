---@module 'spotlight.config.DEFAULTS'
---@brief Immutable default configuration for spotlight.nvim.
---@description
--- Single source of truth for every configurable value. `spotlight.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.
---
--- Defaults are chosen so that `require("spotlight").setup()` with no arguments
--- is the intended everyday configuration: keymap preset on, persistence on,
--- match counts in the list on.

require("spotlight.@types")

---@type Spotlight.Config
local DEFAULTS = {
  -- ---------- colors ----------
  palette = {
    -- Eight slots, each with an explicit bg AND fg. Deriving only a background
    -- would leave the foreground to the colorscheme, which is exactly how
    -- "yellow on yellow" happens on a theme switch.
    --
    -- Dark themes get bright backgrounds with a near-black foreground; light
    -- themes get saturated dark backgrounds with white. Both sets are ordered
    -- so that consecutive round-robin slots are maximally distinguishable
    -- (warm/cool alternating), since the common case is 2-4 simultaneous
    -- spotlights taken in sequence.
    colors = {
      { bg = "#ffd75f", fg = "#1c1c1c" }, -- 1 yellow
      { bg = "#87d7ff", fg = "#1c1c1c" }, -- 2 cyan
      { bg = "#ff87d7", fg = "#1c1c1c" }, -- 3 pink
      { bg = "#a8e22e", fg = "#1c1c1c" }, -- 4 green
      { bg = "#ffaf5f", fg = "#1c1c1c" }, -- 5 orange
      { bg = "#b48eff", fg = "#ffffff" }, -- 6 purple
      { bg = "#5fd7af", fg = "#1c1c1c" }, -- 7 teal
      { bg = "#ff5f5f", fg = "#ffffff" }, -- 8 red
    },
    colors_light = {
      { bg = "#b58900", fg = "#ffffff" }, -- 1 yellow
      { bg = "#268bd2", fg = "#ffffff" }, -- 2 cyan
      { bg = "#d33682", fg = "#ffffff" }, -- 3 pink
      { bg = "#587a00", fg = "#ffffff" }, -- 4 green
      { bg = "#cb4b16", fg = "#ffffff" }, -- 5 orange
      { bg = "#6c4bb6", fg = "#ffffff" }, -- 6 purple
      { bg = "#2aa198", fg = "#ffffff" }, -- 7 teal
      { bg = "#dc322f", fg = "#ffffff" }, -- 8 red
    },
    bold = true,
    reapply_on_colorscheme = true,
  },

  -- ---------- matching ----------
  match = {
    -- matchadd()'s own default is 10, which already renders above 'hlsearch'
    -- (priority 0). That is deliberate: a spotlight is the long-lived marker,
    -- the search is transient, and losing the spotlight color while a search
    -- is active is the more confusing of the two. Lower this below 0 to invert.
    priority = 10,
    -- Logs are case-sensitive data (a request id, a hex address, a level).
    -- false pins `\C` into the pattern so the result does not silently change
    -- with the user's 'ignorecase'/'smartcase'.
    ignore_case = false,
    word_boundaries = true,
    -- A guard, not a design limit: matchadd() cost is per visible line, so
    -- hundreds of patterns would be felt. Eight is the palette size; the cap
    -- sits well above it so reuse of a slot is normal, exhaustion is not.
    max = 64,
  },

  -- ---------- token under the cursor ----------
  cursor = {
    -- Lua patterns, highest priority first. The first pattern with a match
    -- that *spans the cursor column* wins; `<cword>` is only the fallback,
    -- because it is blind to exactly the tokens that matter in a log (a UUID
    -- is five `<cword>`s, an IP is four).
    --
    -- Anchoring is deliberately absent: these are searched anywhere in the
    -- line and then filtered by "does this match contain the cursor".
    patterns = {
      "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", -- UUID
      "%d%d%d%d%-%d%d%-%d%d[T ]%d%d:%d%d:%d%d[%.%d]*[Zz%+%-:%d]*", -- ISO 8601 timestamp
      "%d%d:%d%d:%d%d[%.%d]*", -- bare clock time
      "%d+%.%d+%.%d+%.%d+:%d+", -- IPv4 + port
      "%d+%.%d+%.%d+%.%d+", -- IPv4
      "0[xX]%x+", -- hex literal / address
      "%x%x%x%x%x%x%x%x%x%x%x%x%x*", -- long bare hex blob (git sha, trace id)
      "[%w_%-%.]+@[%w_%-%.]+", -- email / user@host
      "[%w_]+%.[%w_%.]+", -- dotted identifier (a.b.c, package paths)
      "%-?%d+%.?%d*", -- number (int/float, signed)
      "[%w_%-]+", -- generic token incl. dashes (broader than <cword>)
    },
    fallback_cword = true,
  },

  -- ---------- navigation ----------
  nav = {
    scope = "auto",
    wrap = true,
    center = true,
  },

  -- ---------- the list ----------
  list = {
    count = true,
    -- Counting walks the buffer once per spotlight, which is the one O(file)
    -- operation in the plugin. It only ever runs when the list is opened, and
    -- not at all above this size — matching the "cost independent of file
    -- size" promise that picking matchadd() over extmarks is there to keep.
    count_max_lines = 200000,
    swatch = "  ",
  },

  -- ---------- quickfix ----------
  quickfix = {
    open = true,
    title = "Spotlight",
  },

  -- ---------- persistence ----------
  persist = {
    enable = true,
    -- Global per-file default. Set false to invert the whole model into
    -- opt-in: nothing is persisted unless a file is explicitly switched on
    -- with `:Spotlight persist on`.
    default = true,
    debounce_ms = 500,
  },

  -- ---------- keymaps ----------
  keymaps = {
    preset = true,
    -- `<leader>mk` / `<leader>mK` are the two keys the concept fixes. The rest
    -- deliberately avoid the `<leader>mk` prefix: a mapping that is also the
    -- prefix of a longer one costs a 'timeoutlen' pause on every press.
    toggle = "<leader>mk",
    list = "<leader>mK",
    clear = "<leader>m<C-k>",
    quickfix = "<leader>mq",
    next = "]k",
    prev = "[k",
  },

  notify = true,

  -- Structured debug logging at the plugin's decision points: which token the
  -- resolver picked and why, which windows the ledger applied to or skipped,
  -- what the snapshot filter kept, which pattern navigation searched with.
  --
  -- Those are the answers to "why did nothing light up", which is the only
  -- question this plugin ever really gets asked. Routed through
  -- `lib.nvim.logger` (inspectable with `:LibLogger`) when available.
  debug = false,
}

return DEFAULTS
