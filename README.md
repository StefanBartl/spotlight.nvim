> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# spotlight.nvim

```
                     __  ___       __    __
   _________  ____  / /_/ (_)___ _/ /_  / /_
  / ___/ __ \/ __ \/ __/ / / __ `/ __ \/ __/
 (__  ) /_/ / /_/ / /_/ / / /_/ / / / / /_
/____/ .___/\____/\__/_/_/\__, /_/ /_/\__/
    /_/                  /____/       .nvim
       many tokens, many colors, one log
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/spotlight.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/spotlight.nvim/actions/workflows/ci.yml)

Mark any number of tokens in a log at once, in colors you can tell apart, and
keep them there.

You are reading a log. You spot a request id, a PID, an IP, an error code — and
you want to see **every other occurrence, right now**. Several tokens at once,
and they have to stay put: through searches, through scrolling, through a
`:split`.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Integrations](#integrations)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at the [documentation index](docs/README.md), which says what is where
and which question each page answers.

- [Features](docs/FEATURES/README.md) — everything the plugin does, one page per theme: [finding](docs/FEATURES/FINDING.md), [marking](docs/FEATURES/MARKING.md), [rendering](docs/FEATURES/RENDERING.md), [persistence](docs/FEATURES/PERSISTENCE.md), [diagnostics](docs/FEATURES/DIAGNOSTICS.md), [integrations](docs/FEATURES/INTEGRATIONS.md).
- [Installation](docs/installation.md) — requirements and a spec for six package managers.
- [Configuration](docs/configuration.md) — every `setup()` key with its default, plus the four topics worth reading before changing one.
- [Command reference](docs/commands.md) — every `:Spotlight` route: arguments, ranges, and what the non-obvious ones actually do.
- [Bindings](docs/BINDINGS.md) — the cheatsheet: keymaps, commands, autocommands and highlight groups at a glance.
- [Lua API](docs/api.md) — every action as a plain function, with signatures and return values.
- [Workflow](docs/WORKFLOW.md) — how the features combine while you are actually reading a log.
- [hover.nvim integration](docs/hover.md) — what the hover says over a spotlighted token: the case this plugin was built for.
- [Troubleshooting](docs/troubleshooting.md) — "why did nothing light up", and the seven other symptoms that have a cause rather than a bug behind them.
- [Health](docs/health.md) — what each line of `:checkhealth spotlight` means, section by section.
- [Architecture](docs/architecture.md) — the `matchadd()`-not-extmarks decision and the four limitations that follow, the module tree, and the security model.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and where a change belongs.

`:help spotlight` is the same reference inside the editor.

---

## What it does

`*` gives you one token and fights your real search. `:match` gives you three
slots and no management. `matchadd()` is the right primitive but is
window-local, so a split loses everything.

This is that primitive with the bookkeeping done for you. Because it stores
*patterns* rather than positions, cost is proportional to the window rather
than to the file — which is what keeps it usable on a log too big to open in
anything else, and is the decision the rest of the plugin follows from
([why](docs/architecture.md#why-matchadd-and-not-extmarks)).

| Area | Does |
| --- | --- |
| **Marking** | Any number of tokens, under the cursor or from a visual selection, either everywhere the text appears or pinned to one occurrence |
| **Token resolution** | A configurable, ordered pattern list that sees what `<cword>` cannot: UUIDs, ISO timestamps, `192.168.1.1:8080`, `0x1f4a`, git shas, `user@host` |
| **Colors** | Eight distinguishable ones, handed out round-robin and skipping the ones already on screen, with dark and light palettes and an optional permanent lock per slot |
| **Every window** | New splits, new tabs and buffer switches fill themselves; a single window can opt out |
| **Finding your way** | The list with live match counts, `]k` / `[k` navigation, a sign-column occurrence map, whole-line rendering, and every matching line into the quickfix list or a register |
| **Persistence** | State per project, keyed by git root, with a per-file opt-out for the log you do not want written to disk — and named sets to switch between investigations |
| **Diagnostics** | `:checkhealth spotlight` reports every dependency, every rejected config value and the live state; `debug = true` logs the four decisions behind "why did nothing light up" |

Each of these has its own page with the module, keymap, command and config keys
behind it: [docs/FEATURES/](docs/FEATURES/README.md).

---

## Around it

> **[buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim)** — its
> `:Mark` marks the *lines* you want to come back to; spotlight marks the
> *tokens* you are following through them. Line context and token context side
> by side in the same log.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** — asks "what is
> this" about the thing under the cursor while spotlight answers "where else is
> it". Resting on a spotlighted token reports how often it occurs in this
> buffer — see [docs/hover.md](docs/hover.md).
>
> **[cmdlog.nvim](https://github.com/StefanBartl/cmdlog.nvim)** — the other
> half of reading output in the editor: the command that produced the log.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Spotlight` command layer and the shared helpers |

No Treesitter, no LSP, no external binary. Optional, each detected at runtime
and degrading to nothing when absent:

| | |
| --- | --- |
| `git` | Persistence keyed by git root. Without it, state falls back to the working directory |
| [hover.nvim](https://github.com/StefanBartl/hover.nvim) | The occurrence count over a spotlighted token |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [Integrations](#integrations) |

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/spotlight.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

`event = "VeryLazy"` rather than a command trigger: the persisted state has to
be restored and the window autocommands armed before you open the log, not
after you first type `:Spotlight`. Six package managers, and the reasoning in
full, are in [docs/installation.md](docs/installation.md).

---

## Quickstart

Open a log. Put the cursor on a request id and press `<leader>sK`: every other
occurrence lights up, in the whole buffer and in every window showing it.

`<leader>sk` — lowercase — does the narrower thing: only *this* occurrence,
pinned to this exact spot, for when the text is too common to light up
everywhere.

Point at a PID, press it again: a second color. An IP: a third. Then:

```
]k / [k          walk the occurrences of the token you are on
<leader>sL       the list: swatch, token, match count — pick one to jump to it
<leader>sq       every line matching any spotlight, into the quickfix list
<leader>sC       clear them all
```

Quit and come back tomorrow: they are still there.

Verify your setup any time with:

```vim
:checkhealth spotlight
```

---

## What you get with the defaults

| Key | Does |
| --- | --- |
| `<leader>sK` | Spotlight the token under the cursor, everywhere it appears |
| `<leader>sk` | Spotlight only this occurrence, pinned to this position |
| `]k` / `[k` | Next and previous occurrence of the token you are on |
| `<leader>sL` | The list: swatch, token, match count; pick one to jump to it |
| `<leader>sq` | Every matching line into the quickfix list |
| `<leader>sC` | Clear every spotlight |

Everything is reachable three ways — a preset keymap, a `:Spotlight`
subcommand, and a plain function on the `spotlight` module — so nothing here
forces you to keep the keys. The full set is
[docs/BINDINGS.md](docs/BINDINGS.md), the routes are
[docs/commands.md](docs/commands.md), and the functions are
[docs/api.md](docs/api.md).

---

## Integrations

### Context menu

`spotlight.integrations.menu` contributes context-aware entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects. spotlight.nvim has **no**
dependency on `menu` and never opens a context menu itself; a host — typically
your own `<RightMouse>` dispatcher — composes these entries into its own menu.

The entries mirror the normal-mode actions only. nvzone/menu closes the menu
and restores the triggering window before running a callback, so there is no
active Visual selection left by the time one fires — which is why the
`_selection` variants are left out, the same reason they have no Ex-command
equivalent. Opt out with `menu.enable = false`.

### hover.nvim

Resting on a spotlighted token reports how often it occurs in this buffer.
spotlight registers the preview; it does not open a float itself.
[docs/hover.md](docs/hover.md) is the case the plugin was built for — a request
id marked everywhere it appears.

---

## Health check

```vim
:checkhealth spotlight
```

Four sections: the environment, lib.nvim, the configuration — including every
value that was rejected and why — and the live state. It is the first place to
look when nothing lights up; `debug = true` logs the four decisions behind that
same question, and [docs/troubleshooting.md](docs/troubleshooting.md) reads the
symptoms back to their causes.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
project layout; [docs/architecture.md](docs/architecture.md) has the
`matchadd()` decision and the four limitations that follow from it, which is
what a change here has to stay inside.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/spotlight.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/spotlight.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
