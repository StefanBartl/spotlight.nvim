# hover.nvim integration

You are reading a log. A request id is spotlighted, so every occurrence is
coloured — but *how many*, and *is there another one below the fold*, is a
question the colours do not answer. Rest the cursor on it and
[hover.nvim](https://github.com/StefanBartl/hover.nvim) says.

```
req-42abc started
   └─ hover ─┘

┌ spotlight: req-42abc ─────────────────┐
│ 3 occurrences in this buffer          │
└───────────────────────────────────────┘
```

## The gate is the design

**It answers only for tokens that are already spotlighted**, and that is not a
limitation to be lifted later — it is what makes the feature acceptable at
all.

Every token in a log is a token. A preview that counted whatever the cursor
touched would fire on every word, which is precisely the unasked-float noise
hover.nvim's opt-in model is built to prevent. There is no shape heuristic
that could separate "a request id worth counting" from "a word", because the
difference is not in the text.

A spotlight *is* that signal. It is a decision the reader already made about
this token, and the only one available. So the gate is not a guess: is this
text in `spotlight.core.registry`? If not, nothing is said and hover.nvim
carries on to whatever else might answer.

## "We did not look" is not zero

`spotlight.core.count` refuses to scan a buffer past its ceiling and answers
`nil` rather than a wrong number — the same distinction the spotlight list
makes between "this token appears nowhere" and "we did not look". The float
repeats that instead of smoothing it into a `0`:

```
┌ spotlight: req-42abc ─────────────────┐
│ spotlighted                           │
│                                       │
│ too many lines to count here          │
└───────────────────────────────────────┘
```

Reporting a confident `0` there would be wrong about the one thing the reader
is asking.

## Scope

- **This buffer**, not the project. The count is what `core.count` can see in
  the buffer under the cursor. `:Spotlight qf` is what answers across files.
- **Exact text match.** The spotlight's `text` is compared to the token under
  the cursor as written. A spotlight created from `req-42abc` does not answer
  for `req-42abcd`.

## Soft in both directions

- **Without hover.nvim**, `setup()` looks for `hover.registry`, does not find
  it, and returns. Nothing registered, nothing errors.
- **Without spotlight**, hover.nvim is unaffected — it never names this
  plugin.
- **With an older hover.nvim** that has a registry but not `positions`, the
  integration declines rather than registering something that would be
  silently ignored.

## Turning it off

```lua
require("spotlight").setup({ hover = false })
```

Or from hover.nvim's side, which silences every registered position preview:

```vim
:Hover positions off
```
