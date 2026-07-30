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
