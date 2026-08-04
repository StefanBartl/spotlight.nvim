---@module 'spotlight.cursor'
---@brief Resolves what the user actually pointed at.
---@description
--- `<cword>` is the obvious answer and the wrong one for logs. It splits on
--- 'iskeyword', so `550e8400-e29b-41d4-a716-446655440000` is five separate
--- words, `192.168.1.1` is four, `0x1f4a` is two, and
--- `2026-07-27T14:03:11.482Z` is a fistful — the tokens worth tracking are
--- precisely the ones it cannot see.
---
--- So instead: a configurable list of Lua patterns in priority order, searched
--- across the whole cursor line, and the first pattern with a match that *spans
--- the cursor column* wins. Ordering matters and is the user's to control —
--- IPv4 before number, timestamp before clock time — because a broad pattern
--- placed early would otherwise shadow every specific one after it. `<cword>` is
--- kept as the last resort for plain identifiers.
---
--- A visual selection bypasses all of this: the user has already said exactly
--- what they mean, so the selected bytes are taken literally.

require("spotlight.@types")

local config = require("spotlight.config")
local lib = require("spotlight.util.lib")

local M = {}

---@internal
--- Find the first match of Lua pattern `pat` in `line` that contains byte
--- column `col0` (0-based). Iterates every match rather than stopping at the
--- first, since the cursor can sit on the third IP in a line.
---@param line string
---@param col0 integer
---@param pat string
---@return string|nil
local function match_spanning(line, col0, pat)
  local init = 1
  while init <= #line + 1 do
    local ok, s, e = pcall(string.find, line, pat, init)
    if not ok or not s then
      return nil
    end
    -- `s`/`e` are 1-based inclusive; `col0` is 0-based. The cursor is inside
    -- the match when s <= col0 + 1 <= e.
    if s <= col0 + 1 and col0 + 1 <= e then
      return line:sub(s, e)
    end
    -- Advance past this match; +1 guards against a zero-width match looping.
    init = (e >= s) and (e + 1) or (s + 1)
  end
  return nil
end

---@internal
--- Classify `text` by its own shape, not by which resolver branch produced it.
---
--- Doing it this way is what keeps `match.word_boundaries` meaningful. Deriving
--- the kind from the branch would tie it to pattern *ordering*: the broad
--- `[%w_%-]+` entry near the end of the default list matches almost every plain
--- identifier, so `<cword>` would practically never be reached and the `word`
--- kind — the only thing boundaries apply to — would be unreachable config.
---
--- Shape answers it exactly instead. A token made only of word characters can
--- carry `\<`/`\>` and wants them (`error` must not light up inside `errors`).
--- Anything else cannot: `\<192.168.1.1\>` matches nothing, because `\<` asserts
--- a word start and `1` after `.` is not one.
---@param text string
---@return Spotlight.TokenKind
local function kind_of(text)
  return text:match("^[%w_]+$") and "word" or "literal"
end

--- Resolve the token under the cursor in normal mode.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return Spotlight.Token|nil
function M.token(bufnr)
  bufnr = bufnr or 0
  local win = vim.api.nvim_get_current_win()
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok then
    return nil
  end
  local row0, col0 = pos[1] - 1, pos[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1]
  if not line or line == "" then
    return nil
  end

  local opts = config.get("cursor")

  -- Bail out of the pattern scan on a pathological line before doing any of it.
  -- The scan is O(line) per pattern and a user-supplied Lua pattern may
  -- backtrack; a minified single-line JSON log makes that product large enough
  -- to hang the editor on a keypress. `<cword>` is bounded by the token rather
  -- than the line, so it still answers usefully here.
  if #line > opts.max_line_len then
    lib.debug("cursor: line over cursor.max_line_len, skipping the pattern scan", {
      len = #line,
      limit = opts.max_line_len,
    })
    local cword = vim.fn.expand("<cword>")
    if opts.fallback_cword and type(cword) == "string" and cword ~= "" then
      return { text = cword, kind = kind_of(cword) }
    end
    return nil
  end

  for i, pat in ipairs(opts.patterns) do
    local text = match_spanning(line, col0, pat)
    if text and text ~= "" then
      -- Which pattern won is the single most useful debug fact here: a
      -- surprising token almost always means a broader pattern sits ahead of
      -- the specific one the user expected.
      lib.debug("cursor: resolved by pattern", { index = i, pattern = pat, text = text, kind = kind_of(text) })
      return { text = text, kind = kind_of(text) }
    end
  end

  if opts.fallback_cword then
    local cword = vim.fn.expand("<cword>")
    if type(cword) == "string" and cword ~= "" then
      lib.debug("cursor: no pattern matched, fell back to <cword>", { text = cword, kind = kind_of(cword) })
      return { text = cword, kind = kind_of(cword) }
    end
  end
  lib.debug("cursor: nothing resolved", { col = col0, patterns_tried = #opts.patterns })
  return nil
end

--- Resolve the current visual selection as a literal token.
---
--- Must run while Visual mode is still active — `'<`/`'>` are only written when
--- the mode ends, so the live `v`/`.` positions are the reliable source
--- mid-selection. Multi-line selections are refused rather than joined: a
--- pattern containing a newline cannot match anything `matchadd()` sees, so
--- silently accepting one would produce a spotlight that highlights nothing.
---@return Spotlight.Token|nil token, string|nil err
function M.selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil, "not in visual mode"
  end

  local row_v, col_v = vim.fn.line("v"), vim.fn.col("v")
  local row_c, col_c = vim.fn.line("."), vim.fn.col(".")
  if row_v ~= row_c then
    return nil, "select within a single line to spotlight it"
  end
  if mode == "V" then
    return nil, "select characters, not whole lines, to spotlight them"
  end

  local scol, ecol = col_v, col_c
  if scol > ecol then
    scol, ecol = ecol, scol
  end
  local line = vim.api.nvim_buf_get_lines(0, row_c - 1, row_c, false)[1] or ""
  -- `col()` is a 1-based byte column and 'selection' can put the end one past
  -- the last byte, so clamp before slicing.
  local text = line:sub(scol, math.min(ecol, #line))
  if text == "" then
    return nil, "empty selection"
  end
  -- Checked here as well as in the registry, so the message names the actual
  -- cause: a `v$` on a minified single-line file selects the whole file, and
  -- "selection is 4.2 MB" is a more useful answer than a generic refusal.
  local max_len = config.get("match.max_text_len")
  if #text > max_len then
    return nil, ("selection is %d bytes, over the %d-byte limit (match.max_text_len)"):format(#text, max_len)
  end
  -- Always literal, never shape-classified like `M.token`: selecting `err` out
  -- of `error` is an explicit request to match that substring, and adding word
  -- boundaries would turn it into a spotlight that highlights nothing.
  return { text = text, kind = "literal" }, nil
end

return M
