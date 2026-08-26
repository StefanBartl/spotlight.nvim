---@module 'spotlight.core.count'
---@brief On-demand match counting, and the line scan the quickfix filter shares.
---@description
--- This is the one O(buffer) operation in the plugin, and it is deliberately
--- kept off every hot path. Counts are computed when the list is opened and
--- never maintained: keeping them current would mean re-scanning on every text
--- change, which is exactly the cost that choosing `matchadd()` over extmarks
--- exists to avoid (see `spotlight.core.match`). A count is a convenience; the
--- highlighting is the feature, and it must not pay for the convenience.
---
--- Above `list.count_max_lines` the scan is skipped entirely and the list shows
--- `?`, because "opening a list took eleven seconds" is a worse answer than "we
--- did not count this one".

local pattern = require("spotlight.core.pattern")

local M = {}

--- Is `item` a buffer-scoped spotlight pinned to `bufnr`?
---
--- **Why every scan in this module has to ask.** A buffer-scoped ("this
--- occurrence only", `core.registry.add_at`) item's pattern carries `\%l\%c`
--- position atoms. Those are evaluated by Vim's own search and render
--- machinery -- `search()`, `matchadd()` -- and by nothing else. In
--- particular `vim.regex:match_str`, which is the only engine the chunked
--- scans below can drive, does not evaluate them: it returns nil on *every*
--- line, the pinned one included. Verified, not assumed.
---
--- So such an item cannot be searched for; it can only be looked up. Its
--- match is a single point already recorded on the item (`buf`/`row1`/`col1`)
--- at the moment it was created. Left unhandled the effect is quiet and
--- confusing: the spotlight is plainly visible on screen, because `matchadd`
--- does understand the pattern, while every count reads 0 and every list
--- comes back empty.
---@param item Spotlight.Item
---@param bufnr integer
---@return boolean
local function pinned_to(item, bufnr)
  return item.scope == "buffer" and item.buf == bufnr
end

---@internal
--- Count matches of `re` in one line. Loops because a request id can appear
--- twice in the same log line, and `vim.regex:match_str` only reports the first.
---@param re vim.regex
---@param line string
---@return integer
local function count_in_line(re, line)
  local n, offset = 0, 0
  while offset <= #line do
    local s, e = re:match_str(line:sub(offset + 1))
    if not s then
      break
    end
    n = n + 1
    -- A zero-width match would otherwise spin here forever.
    offset = offset + (e > s and e or s + 1)
  end
  return n
end

--- Every loaded, ordinary file buffer eligible for a multi-buffer scan.
--- Terminal/quickfix/help/scratch buffers (`buftype ~= ""`) are excluded —
--- mirrors `spotlight.util.path`'s own buffer-key guard, since neither a
--- persistence key nor a cross-buffer count means anything for a buffer with
--- no stable file identity.
---@return integer[]
function M.scannable_buffers()
  return vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == ""
  end, vim.api.nvim_list_bufs())
end

--- Count how many times `item`'s pattern matches in `bufnr`.
---
--- Returns `nil` when the buffer is larger than `max_lines`, which callers must
--- render as "not counted" rather than as zero — the difference between "this
--- token appears nowhere" and "we did not look" is exactly what the user is
--- reading the list for.
---@param bufnr integer
---@param item Spotlight.Item
---@param max_lines integer
---@return integer|nil count, integer lines_scanned
function M.count(bufnr, item, max_lines)
  if item.scope == "buffer" then
    -- One known point, or nothing. No scan can answer this -- see `pinned_to`.
    -- `1` for lines_scanned rather than `0`: the caller distinguishes "we did
    -- not look" (nil) from a real count, and this is a real count.
    return pinned_to(item, bufnr) and 1 or 0, 1
  end
  local total = vim.api.nvim_buf_line_count(bufnr)
  if total > max_lines then
    return nil, 0
  end
  local re = pattern.compile(item.pattern)
  if not re then
    return 0, 0
  end
  local n = 0
  -- Fetched in chunks: one nvim_buf_get_lines call for a 200k-line buffer
  -- materializes the whole file as a Lua table before a single line is read.
  local CHUNK = 5000
  for start = 0, total - 1, CHUNK do
    local lines = vim.api.nvim_buf_get_lines(bufnr, start, math.min(start + CHUNK, total), false)
    for _, line in ipairs(lines) do
      n = n + count_in_line(re, line)
    end
  end
  return n, total
end

--- Sum `M.count` for `item` across every `M.scannable_buffers()` buffer.
---
--- A buffer over `max_lines` is skipped from the sum rather than making the
--- whole result `nil` — a lower bound across nine buffers is more useful than
--- refusing to answer because a tenth was too big to look at. `exact` tells
--- the caller which case happened, mirroring `M.count`'s own `nil`-vs-`0`
--- distinction one level up (the list renders this as `N+` instead of `N`).
---@param item Spotlight.Item
---@param max_lines integer
---@return integer total, boolean exact, integer scanned # `scanned` = buffers actually counted.
function M.count_loaded(item, max_lines)
  local total, exact, scanned = 0, true, 0
  for _, bufnr in ipairs(M.scannable_buffers()) do
    local n = M.count(bufnr, item, max_lines)
    if n == nil then
      exact = false
    else
      total = total + n
      scanned = scanned + 1
    end
  end
  return total, exact, scanned
end

--- Collect every line in `bufnr` matching any pattern in `patterns`, as
--- quickfix entries. One compiled regex per pattern, one pass over the buffer,
--- and a line is reported once even if several spotlights hit it — the question
--- being answered is "show me the lines involving this request id", not "show me
--- each highlight".
--- Unlike `M.count`, this *produces* memory proportional to the number of hits —
--- one entry per matching line, each holding that line's full text. On a large
--- log where the token is common, that is most of the file. So the result is
--- capped at `max_entries` and the caller is told it was truncated, rather than
--- silently building a list the size of the buffer.
---@param bufnr integer
---@param patterns string[]
---@param max_entries integer|nil # Defaults to `quickfix.max_entries`.
---@return table[] items # `{ bufnr, lnum, col, text }`, quickfix shaped.
---@return boolean truncated # True when the cap was reached and scanning stopped.
function M.matching_lines(bufnr, patterns, max_entries)
  -- Falls back to the configured cap rather than to "unbounded" if a caller
  -- omits it: a guard whose absence silently removes the guard is worse than no
  -- guard at all, since it fails only on the large inputs it existed for.
  if type(max_entries) ~= "number" or max_entries < 1 then
    max_entries = require("spotlight.config").get("quickfix.max_entries")
  end

  ---@type vim.regex[]
  local regexes = {}
  for _, p in ipairs(patterns) do
    local re = pattern.compile(p)
    if re then
      regexes[#regexes + 1] = re
    end
  end
  local out = {}
  if #regexes == 0 then
    return out, false
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  local CHUNK = 5000
  for start = 0, total - 1, CHUNK do
    local lines = vim.api.nvim_buf_get_lines(bufnr, start, math.min(start + CHUNK, total), false)
    for i, line in ipairs(lines) do
      local first = nil
      for _, re in ipairs(regexes) do
        local s = re:match_str(line)
        if s and (first == nil or s < first) then
          first = s
        end
      end
      if first then
        if #out >= max_entries then
          -- Stop scanning, not just appending: the remaining work is pure cost
          -- once the answer is already known to be truncated.
          return out, true
        end
        out[#out + 1] = {
          bufnr = bufnr,
          lnum = start + i,
          col = first + 1,
          text = line,
        }
      end
    end
  end
  return out, false
end

--- `M.matching_lines`'s item-aware counterpart, for `spotlight.qf`.
---
--- Same output and same cap as `M.matching_lines`, but takes items rather
--- than bare patterns, which is what it takes to notice a buffer-scoped one.
--- Global items still go through `M.matching_lines` unchanged -- one call,
--- one pass over the buffer; pinned items are resolved from their recorded
--- position afterwards (see `pinned_to`) and merged in.
---
--- "One entry per matching line" holds across the two sources, not only
--- within the regex pass: a pinned line that a global pattern already
--- reported is not repeated. The merged result is re-sorted because the
--- pinned entries are appended after the scan and a quickfix list reads
--- top-to-bottom like the buffer it came from.
---@param bufnr integer
---@param items Spotlight.Item[]
---@param max_entries integer|nil # Defaults to `quickfix.max_entries`.
---@return table[] entries # `{ bufnr, lnum, col, text }`, quickfix shaped.
---@return boolean truncated
function M.matching_lines_for(bufnr, items, max_entries)
  if type(max_entries) ~= "number" or max_entries < 1 then
    max_entries = require("spotlight.config").get("quickfix.max_entries")
  end

  local patterns = {}
  ---@type Spotlight.Item[]
  local pinned = {}
  for _, it in ipairs(items) do
    if it.scope == "buffer" then
      -- A spotlight pinned to another buffer can never match in this one --
      -- the same guard `core.match` applies when rendering.
      if pinned_to(it, bufnr) then
        pinned[#pinned + 1] = it
      end
    else
      patterns[#patterns + 1] = it.pattern
    end
  end

  local out, truncated = M.matching_lines(bufnr, patterns, max_entries)
  if truncated or #pinned == 0 then
    return out, truncated
  end

  local have = {}
  for _, e in ipairs(out) do
    have[e.lnum] = true
  end

  for _, it in ipairs(pinned) do
    if not have[it.row1] then
      if #out >= max_entries then
        return out, true
      end
      local line = vim.api.nvim_buf_get_lines(bufnr, it.row1 - 1, it.row1, false)[1] or ""
      out[#out + 1] = { bufnr = bufnr, lnum = it.row1, col = it.col1, text = line }
      have[it.row1] = true
    end
  end

  table.sort(out, function(a, b)
    return a.lnum < b.lnum
  end)

  return out, false
end

--- `M.matching_lines`'s sibling for `spotlight.map`: one shared buffer scan
--- (not one scan per `item`, which would multiply the cost by however many
--- spotlights are active) that additionally records *which* item's pattern
--- won each line — needed for a sign column painted in the matching
--- spotlight's own color, which `M.matching_lines`'s pattern-only output
--- cannot answer. Same chunked-read shape, same one-entry-per-line rule when
--- several items hit the same line (the earliest column wins, matching
--- `M.matching_lines`'s own tie-break).
---@param bufnr integer
---@param items Spotlight.Item[]
---@param max_entries integer|nil # Defaults to `map.max_entries`.
---@return { bufnr: integer, lnum: integer, col: integer, item: Spotlight.Item }[] entries
---@return boolean truncated
function M.matching_lines_by_item(bufnr, items, max_entries)
  if type(max_entries) ~= "number" or max_entries < 1 then
    max_entries = require("spotlight.config").get("map.max_entries")
  end

  ---@type { re: vim.regex, item: Spotlight.Item }[]
  local compiled = {}
  ---@type Spotlight.Item[]
  local pinned = {}
  for _, item in ipairs(items) do
    if item.scope == "buffer" then
      -- Not compilable into a working regex -- see `pinned_to`. Without this
      -- the map silently loses its sign for every "this occurrence only"
      -- spotlight, which is the same defect `M.matching_lines_for` exists to
      -- avoid one module over.
      if pinned_to(item, bufnr) then
        pinned[#pinned + 1] = item
      end
    else
      local re = pattern.compile(item.pattern)
      if re then
        compiled[#compiled + 1] = { re = re, item = item }
      end
    end
  end
  local out = {}
  if #compiled == 0 and #pinned == 0 then
    return out, false
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  local CHUNK = 5000
  for start = 0, total - 1, CHUNK do
    local lines = vim.api.nvim_buf_get_lines(bufnr, start, math.min(start + CHUNK, total), false)
    for i, line in ipairs(lines) do
      local first_col, first_item = nil, nil
      for _, c in ipairs(compiled) do
        local s = c.re:match_str(line)
        if s and (first_col == nil or s < first_col) then
          first_col, first_item = s, c.item
        end
      end
      if first_item then
        if #out >= max_entries then
          return out, true
        end
        out[#out + 1] = {
          bufnr = bufnr,
          lnum = start + i,
          col = first_col + 1,
          item = first_item,
        }
      end
    end
  end

  if #pinned > 0 then
    local have = {}
    for _, e in ipairs(out) do
      have[e.lnum] = true
    end
    for _, it in ipairs(pinned) do
      if not have[it.row1] then
        if #out >= max_entries then
          return out, true
        end
        out[#out + 1] = { bufnr = bufnr, lnum = it.row1, col = it.col1, item = it }
        have[it.row1] = true
      end
    end
    table.sort(out, function(a, b)
      return a.lnum < b.lnum
    end)
  end

  return out, false
end

return M
