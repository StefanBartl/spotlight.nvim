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
keep them there. You are reading a log. You spot a request id, a PID, an IP, an
error code — and you want to see **every other occurrence, right now**.
Several tokens at once, and they have to stay put: through searches, through
scrolling, through a `:split`.

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
> **[my.nvim](https://github.com/StefanBartl/my.nvim)** — its
> `cword_occurrences` marks the word under the cursor as you move, which
> is the transient half of the same question. This plugin is the half you
> pin: several tokens at once, and they stay through searches and splits.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) and
> [ui.nvim](https://github.com/StefanBartl/ui.nvim) are the two real
> dependencies — see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at the [documentation index](docs/README.md), which says what is where
and which question each page answers.

**The Basics**

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — a spec for six package managers.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

**Configuration**

- [What you get with the defaults](docs/what-you-get.md) — the default keys at a glance.
- [All options](docs/configuration.md) — every `setup()` key with its default, plus the four topics worth reading before changing one.
- [Command reference](docs/commands.md) — every `:Spotlight` route: arguments, ranges, and what the non-obvious ones actually do.
- [Bindings](docs/BINDINGS.md) — the cheatsheet: keymaps, commands, autocommands and highlight groups at a glance.
- [Lua API](docs/api.md) — every action as a plain function, with signatures and return values.

**The Rest**

- [Features](docs/FEATURES/README.md) — everything the plugin does, one page per theme: [finding](docs/FEATURES/FINDING.md), [marking](docs/FEATURES/MARKING.md), [rendering](docs/FEATURES/RENDERING.md), [persistence](docs/FEATURES/PERSISTENCE.md), [diagnostics](docs/FEATURES/DIAGNOSTICS.md), [integrations](docs/FEATURES/INTEGRATIONS.md).
- [Workflow](docs/WORKFLOW.md) — how the features combine while you are actually reading a log.
- [hover.nvim integration](docs/hover.md) — what the hover says over a spotlighted token: the case this plugin was built for.
- [Troubleshooting](docs/troubleshooting.md) — "why did nothing light up", and the seven other symptoms that have a cause rather than a bug behind them.
- [Health check](docs/health.md) — what each line of `:checkhealth spotlight` means, section by section.
- [Architecture](docs/architecture.md) — the `matchadd()`-not-extmarks decision and the four limitations that follow, the module tree, and the security model.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and where a change belongs.
- [Feedback](https://github.com/StefanBartl/spotlight.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/spotlight.nvim/discussions).

`:help spotlight` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

spotlight.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
