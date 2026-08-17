---@module 'spotlight.core.pattern'
---@brief Turns a raw token into the Vim regex `matchadd()` and `search()` use.
---@description
--- Every pattern this plugin hands to Vim is built here, so escaping and the
--- case/magic flags are decided exactly once. Two properties matter:
---
---   * **Literal by design.** Spotlights are "highlight this exact token", not
---     "run this regex" — a request id containing `[` or `.` must match itself.
---     `\V` (very nomagic, |/magic|) reduces the special characters to a single
---     one, the backslash, so escaping is one substitution instead of a
---     character class that has to be kept in sync with Vim's magic rules.
---   * **Case pinned explicitly.** `\C`/`\c` in the pattern beats 'ignorecase'
---     and 'smartcase', so a spotlight keeps matching the same text after the
---     user toggles either — the alternative is a highlight that silently
---     changes meaning between sessions.

local M = {}

--- Escape `text` for use inside a `\V` (very nomagic) pattern. There the
--- backslash is the only special character left, so escaping it is sufficient
--- and complete.
---@param text string
---@return string
function M.escape(text)
  return (text:gsub("\\", "\\\\"))
end

--- Build the complete Vim regex for `token`.
---
--- Word boundaries are applied for `word`-kind tokens only. A `<cword>` fallback
--- wants them (`error` should not light up inside `errors`), but a structured
--- token must never have them: `\<192.168.1.1\>` matches nothing at all, since
--- `.` is not a word character and `\<` only asserts at a word start.
---@param token Spotlight.Token
---@param opts Spotlight.MatchOpts
---@return string pattern # Complete Vim regex, ready for `matchadd()`.
function M.build(token, opts)
  local body = M.escape(token.text)
  if opts.word_boundaries and token.kind == "word" then
    body = "\\<" .. body .. "\\>"
  end
  return (opts.ignore_case and "\\c" or "\\C") .. "\\V" .. body
end

--- Build a Vim regex pinned to one exact buffer position: line `row1`, byte
--- column `col1` (both 1-based), followed by the literal text. Used for a
--- "this occurrence only" spotlight, where the point is that a duplicate of
--- the same text elsewhere must *not* light up.
---
--- `\%<row>l\%<col>c` are position atoms — special after a backslash
--- regardless of magic state, the same way `\<`/`\>` still work after `\V` in
--- `M.build`. They make the match require both "on this line" and "starting
--- at this column" before the literal body is even considered, so no repeat
--- of the same text elsewhere in the buffer (or in another buffer the pattern
--- is never applied to — see `spotlight.core.match`) can satisfy it.
---@param text string
---@param row1 integer # 1-based line.
---@param col1 integer # 1-based byte column.
---@param opts Spotlight.MatchOpts
---@return string pattern
function M.build_at(text, row1, col1, opts)
  local body = M.escape(text)
  local case = opts.ignore_case and "\\c" or "\\C"
  return case .. "\\%" .. tostring(row1) .. "l\\%" .. tostring(col1) .. "c\\V" .. body
end

--- Widen a complete pattern to the whole line it matches on, for a spotlight
--- rendered in line mode (`Spotlight.Item.line`).
---
--- Takes an already-built pattern rather than a token, so it works unchanged
--- for both `M.build` and `M.build_at` output — a position-anchored pattern
--- widened this way lights up the whole line of *that one* occurrence, because
--- `\%l`/`\%c` are zero-width assertions the leading `\.\*` simply walks up to.
---
--- `\_^`/`\_$` rather than plain `^`/`$`: those are special only at the very
--- start/end of a pattern, and here they sit next to the caller's own `\C\V`
--- prefix. The `\_` forms are position atoms — special after a backslash
--- regardless of magic state, the same way `\<`/`\>` still work after `\V`.
--- `\.\*` is "any character, any number of times" spelled for `\V`, where `.`
--- and `*` are ordinary characters. Re-stating `\C\V` in front is safe and
--- necessary for the same reason `M.alternation` re-states nothing: magic and
--- case are positional switches, and the input's own inner `\V` re-establishes
--- nomagic for its body.
---
--- What this does **not** do is fill the line to the window's right edge:
--- `matchadd()` colors text, and a short line simply stops where its text
--- stops. Painting to the edge needs `line_hl_group`, which is an extmark, and
--- an extmark is a position — the one thing `spotlight.core.match` exists to
--- not store.
---@param pat string # A complete pattern from `M.build`/`M.build_at`.
---@return string
function M.line(pat)
  return "\\C\\V\\_^\\.\\*" .. pat .. "\\.\\*\\_$"
end

--- Combine several complete patterns into one alternation, for a single
--- `search()` call over every spotlight at once.
---
--- Each input already carries its own `\C`/`\c` and `\V` prefix. Vim reads
--- magic and case atoms as *positional switches* rather than per-branch scopes,
--- so re-stating them mid-pattern is both legal and necessary: the inner `\V`
--- of branch two is what keeps branch two nomagic after branch one's `\<`.
--- The separator `\|` is spelled with a backslash, which is its `\V` form.
---@param patterns string[]
---@return string|nil # nil when `patterns` is empty (nothing to search for).
function M.alternation(patterns)
  if #patterns == 0 then
    return nil
  end
  if #patterns == 1 then
    return patterns[1]
  end
  return table.concat(patterns, "\\|")
end

--- Compile `pattern` into a `vim.regex` object, or nil if Vim rejects it.
--- Used by the counting and quickfix paths, which walk lines themselves rather
--- than going through the renderer.
---@param pattern string
---@return vim.regex|nil
function M.compile(pattern)
  local ok, re = pcall(vim.regex, pattern)
  if ok then
    return re
  end
  return nil
end

return M
