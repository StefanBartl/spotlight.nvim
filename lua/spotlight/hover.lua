---@module 'spotlight.hover'
---@brief How often the spotlighted token under the cursor occurs.
---@description
--- You are reading a log. A request id is spotlighted, so every occurrence is
--- coloured — but "how many, and is there another one below the fold" is a
--- question the colours do not answer. This puts it in
--- [hover.nvim](https://github.com/StefanBartl/hover.nvim)'s float, for the
--- token the cursor is on.
---
--- **It answers only for tokens that are already spotlighted, and that
--- restriction is the whole design rather than a limitation.** Every token in
--- a log is a token; a preview that counted whatever the cursor touched would
--- fire on every word and be exactly the noise hover.nvim's opt-in model
--- exists to prevent. A spotlight is a decision the reader already made about
--- *this* token, and it is the only signal available that says "this one
--- matters to me".
---
--- So the gate is not a heuristic. It is: is this text in
--- `spotlight.core.registry`? If not, nothing is said, and hover.nvim carries
--- on to whatever else might answer.
---
--- **The count is bounded, and says so when it gave up.** `core.count`
--- refuses to scan a buffer past `max_lines` and answers nil rather than a
--- wrong number — the same distinction the spotlight list makes between "this
--- token appears nowhere" and "we did not look". The float repeats that
--- rather than smoothing it into a zero.
---
---@see spotlight.core.registry
---@see spotlight.core.count

local M = {}

local api = vim.api

---@type boolean
local _registered = false

--- How many lines a buffer may have before the count declines. Matches the
--- ceiling the spotlight list uses, so the two never disagree about whether a
--- buffer was scanned.
local MAX_LINES = 20000

---@internal
--- The word-ish run the cursor is inside, or nil.
---
--- Deliberately generous about what a token is -- a request id, a PID, an IP,
--- an error code are all shaped differently -- because the *gate* is the
--- spotlight registry, not this. Anything not spotlighted is declined a
--- moment later regardless of its shape.
---@param line string
---@param col integer 0-based
---@return string|nil
local function token_at(line, col)
  if type(line) ~= "string" or line == "" then
    return nil
  end
  local allowed = "[%w_%.%-:]"
  if not line:sub(col + 1, col + 1):match(allowed) then
    return nil
  end

  local first = col + 1
  while first > 1 and line:sub(first - 1, first - 1):match(allowed) do
    first = first - 1
  end
  local last = col + 1
  while last < #line and line:sub(last + 1, last + 1):match(allowed) do
    last = last + 1
  end

  local run = line:sub(first, last)
  return run ~= "" and run or nil
end

---@internal
--- The active spotlight whose text is exactly `token`, or nil.
---@param token string
---@return Spotlight.Item|nil
local function spotlight_for(token)
  local ok, registry = pcall(require, "spotlight.core.registry")
  if not ok or type(registry.all) ~= "function" then
    return nil
  end
  local ok_all, items = pcall(registry.all)
  if not ok_all or type(items) ~= "table" then
    return nil
  end
  for _, item in ipairs(items) do
    if type(item) == "table" and item.text == token then
      return item
    end
  end
  return nil
end

--- Register the position preview with hover.nvim, if it is installed.
---@return boolean registered
function M.setup()
  if _registered then
    return true
  end

  local ok, registry = pcall(require, "hover.registry")
  if not ok or type(registry) ~= "table" or type(registry.register) ~= "function" then
    return false
  end
  if type(registry.position_at) ~= "function" then
    return false
  end

  registry.register("spotlight.nvim", {
    positions = {
      ---@param bufnr integer
      ---@param row integer 1-based
      ---@param col integer 0-based
      ---@return table|nil
      function(bufnr, row, col)
        if not api.nvim_buf_is_valid(bufnr) then
          return nil
        end
        local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        local token = token_at(line, col)
        if not token then
          return nil
        end

        local item = spotlight_for(token)
        if not item then
          return nil
        end

        local ok_count, count = pcall(function()
          return (require("spotlight.core.count").count(bufnr, item, MAX_LINES))
        end)

        local lines
        if not ok_count then
          lines = { "spotlighted" }
        elseif count == nil then
          -- Not "0". `core.count` declines on a buffer past its ceiling, and
          -- reporting that as zero would be a confident wrong answer about
          -- the one thing the reader is asking.
          lines = { "spotlighted", "", "too many lines to count here" }
        else
          lines = {
            ("%d occurrence%s in this buffer"):format(count, count == 1 and "" or "s"),
          }
        end

        return { lines = lines, title = "spotlight: " .. token }
      end,
    },
  })

  _registered = true
  return true
end

---@internal
--- The token test on its own, for the spec suite.
---@param line string
---@param col integer
---@return string|nil
function M.token_at(line, col)
  return token_at(line, col)
end

---@internal
--- Forget the registration. Tests only.
---@return nil
function M._reset()
  _registered = false
end

return M
