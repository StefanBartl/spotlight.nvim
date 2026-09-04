> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# spotlight.nvim

```
                    __  ___       __    __
   _________  ____  / /_/ (_)___ _/ /_  / /_
  / ___/ __ \/ __ \/ __/ / / __ `/ __ \/ __/
 (__  ) /_/ / /_/ / /_/ / / /_/ / / / / /_
/____/ .___/\____/\__/_/_/\__,_/_/ /_/\__/
    /_/      many tokens, many colors, one log
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-active%20development-blue)
[![CI](https://github.com/StefanBartl/spotlight.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/spotlight.nvim/actions/workflows/ci.yml)

> Pairs well with [buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim):
> its `:Mark` marks the *lines* you want to come back to, spotlight marks the
> *tokens* you are following through them — line context and token context side
> by side in the same log.
>
> And with [hover.nvim](https://github.com/StefanBartl/hover.nvim), which asks
> "what is this" about the thing under the cursor while spotlight answers "where
> else is it": spotlight registers a preview there, so resting on a spotlighted
> token reports how often it occurs in this buffer.

Mark any number of tokens in a log at once, in colors you can tell apart, and
keep them there.

You are reading a log. You spot a request id, a PID, an IP, an error code — and
you want to see **every other occurrence, right now**. Several tokens at once,
and they must stay put: through searches, through scrolling, through a
`:split`. `*` gives you one token and fights your real search. `:match` gives
you three slots and no management. `matchadd()` is the right primitive but is
window-local, so a split loses everything.

`spotlight.nvim` is that primitive with the bookkeeping done for you: any number
of tokens, eight distinguishable colors, applied in every window, persisted per
project, with a per-file opt-out. Because it stores *patterns* rather than
positions, cost is proportional to the window rather than to the file — which is
what keeps it usable on a log too big to open in anything else, and is the
decision the rest of the plugin follows from
([why](docs/architecture.md#why-matchadd-and-not-extmarks)).

---

## Table of contents

- [Quickstart](#quickstart)
- [What it does](#what-it-does)
- [Documentation](#documentation)
- [License](#license)

---

## Quickstart

Requires Neovim **0.9+** and
[lib.nvim](https://github.com/StefanBartl/lib.nvim). No Treesitter, no LSP, no
external binary.

```lua
{
  "StefanBartl/spotlight.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

Other package managers, and the reasoning behind `event = "VeryLazy"`, are in
[installation.md](docs/installation.md).

Open a log. Put the cursor on a request id and press `<leader>sK`: every other
occurrence lights up, in the whole buffer and in every window showing it.
`<leader>sk` (lowercase) does the narrower thing — only *this* occurrence,
pinned to this exact spot, for when the text is too common to light up
everywhere.

Point at a PID, press it again: a second color. An IP: a third.

- `]k` / `[k` — walk the occurrences of the token you are on.
- `<leader>sL` — the list: swatch, token, match count. Pick one to jump to it.
- `<leader>sq` — every line matching any spotlight, into the quickfix list.
- `<leader>sC` — clear them all.

Quit and come back tomorrow: they are still there.

Everything is reachable three ways — a preset keymap, a `:Spotlight`
subcommand, and a plain function on the `spotlight` module. Verify your setup
any time with:

```vim
:checkhealth spotlight
```

---

## What it does

- **Mark any number of tokens**, under the cursor or from a visual selection,
  either everywhere the text appears or pinned to one occurrence.
- **See the tokens `<cword>` cannot.** A configurable, ordered pattern list
  resolves UUIDs, ISO timestamps, `192.168.1.1:8080`, `0x1f4a`, git shas and
  `user@host` as single tokens.
- **Eight distinguishable colors**, handed out round-robin and skipping the
  ones already on screen, with dark and light palettes and an optional
  permanent lock per slot.
- **In every window** — new splits, new tabs and buffer switches fill
  themselves; a single window can opt out.
- **Find your way around:** the list with live match counts, `]k`/`[k`
  navigation, a sign-column occurrence map, whole-line rendering, and every
  matching line into the quickfix list or a register.
- **Still there tomorrow.** State is persisted per project, keyed by git root,
  with a per-file opt-out for the log you do not want written to disk — and
  named sets to switch between investigations.
- **Answers for itself.** `:checkhealth spotlight` reports every dependency,
  every rejected config value and the live state; `debug = true` logs the four
  decisions behind "why did nothing light up".

Each of these has its own page with the module, keymap, command and config keys
behind it: [docs/FEATURES/](docs/FEATURES/README.md).

---

## Documentation

Start at the [documentation index](docs/README.md), which says what is where
and which question each page answers.

- [Features](docs/FEATURES/README.md) — everything the plugin does, one page per theme.
- [Installation](docs/installation.md) — requirements and a spec for six package managers.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) — every `:Spotlight` route, with arguments and ranges.
- [Bindings](docs/BINDINGS.md) — the cheatsheet: keymaps, commands, autocommands, highlight groups.
- [Workflow](docs/WORKFLOW.md) — how the features combine while you are actually reading a log.
- [Troubleshooting](docs/troubleshooting.md) — the symptoms that have a cause rather than a bug behind them.
- [Architecture](docs/architecture.md) — the `matchadd()` decision, the module tree, the security model.

Also `:help spotlight` for the same material as Vim help.

## License

MIT — see [LICENSE](LICENSE).
