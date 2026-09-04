# Features

`spotlight.nvim` marks tokens in a log — any number of them, in distinguishable
colors, applied in every window, and persisted per project. Everything on the
pages below is verified against `lua/spotlight/` as it stands.

| Page | What it covers |
| --- | --- |
| [MARKING.md](MARKING.md) | Making a spotlight: the two toggles, the log-aware cursor resolver, and the matching rules (`\C`, word boundaries) that decide what a spotlight actually hits |
| [RENDERING.md](RENDERING.md) | How a spotlight is shown: the eight-slot palette, slot locking, whole-line rendering, and what makes a window-local `matchadd()` look global |
| [FINDING.md](FINDING.md) | Getting from "it is marked" to "I am looking at it": the list, `]k`/`[k`, the sign-column occurrence map, the quickfix filter, and yank |
| [PERSISTENCE.md](PERSISTENCE.md) | What survives `:qa`: per-project state, named sets, the per-file opt-out, and why an exception is about a spotlight's origin rather than its appearances |
| [INTEGRATIONS.md](INTEGRATIONS.md) | The soft dependencies: hover.nvim, which-key, nvzone/menu, and the plain-function facade every one of them binds onto |
| [DIAGNOSTICS.md](DIAGNOSTICS.md) | When something looks wrong: `:checkhealth spotlight`, `debug = true`, `:Spotlight refresh`, and why an invalid config degrades instead of throwing |

Each entry names the module behind it, its keymap and `:Spotlight` route, and
the config keys that change it. The full reference for those lives in
[commands.md](../commands.md), [BINDINGS.md](../BINDINGS.md) and
[configuration.md](../configuration.md).

## Deliberately not here

Four things are plausible, are not planned, and each would double the command
surface: a regex mode, per-buffer or per-filetype scoping, automatic rules
(`ERROR`/`WARN` highlighted for you), and set export/import. They go in when a
real need shows up, not before.

Two further limits are consequences of choosing `matchadd()` over extmarks
rather than oversights — match counts are computed on demand and never
maintained, and a whole-line highlight ends where the line's text ends. Both
are explained in [architecture.md](../architecture.md).
