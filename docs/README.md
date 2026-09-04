# spotlight.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | Requirements, the dependency on `lib.nvim`, and a spec for lazy.nvim, packer, mini.deps, vim-plug, paq and `vim.pack` |
| [configuration.md](configuration.md) | Every `setup()` key with its default, plus the four topics worth reading before changing one: token resolution, colors, persistence, keymaps |

## Using it

| Page | Answers |
| --- | --- |
| [FEATURES/](FEATURES/README.md) | Everything the plugin does, one page per theme, each naming the module, keymap, command and config keys behind it |
| [commands.md](commands.md) | Every `:Spotlight` route: arguments, ranges, and what the non-obvious ones actually do |
| [BINDINGS.md](BINDINGS.md) | The cheatsheet — every keymap, command, autocommand and highlight group at a glance |
| [api.md](api.md) | The Lua facade: every action as a plain function, with signatures and return values |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each feature does, but how they combine while you are actually reading a log |
| [hover.md](hover.md) | What the hover says over a spotlighted token — the case this plugin was built for: a request id marked everywhere it appears |

## When something looks wrong

| Page | Answers |
| --- | --- |
| [troubleshooting.md](troubleshooting.md) | "Why did nothing light up", and the seven other symptoms that have a cause rather than a bug behind them |
| [health.md](health.md) | What each line of `:checkhealth spotlight` means, section by section |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [architecture.md](architecture.md) | The `matchadd()`-not-extmarks decision and the four limitations that follow from it; the module tree; the security model and the three bounded inputs |

## Also in the repository

`:help spotlight` — the same material as Vim help, in `doc/spotlight.txt`.

`docs/map/` is not in the repository: `:DocMap` generates it from the current
tree in seconds, it is stale the moment it is written, and it is ~40 MB of
artefacts. Run the command rather than looking for the folder.
