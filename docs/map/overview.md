# spotlight.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**3 modules** · 4 namespaces · 18 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["spotlight.nvim"]
  nlua_spotlight["spotlightbr/smallOne entry point that wires configuration…/small"]
  nlua_spotlight_bindings["bindingsbr/smallThe `:Spotlight` verb and the autocommands…/small"]
  nlua_spotlight_config["configbr/smallDeep-merges user options over…/small"]
  nlua_spotlight_core["core"]
  nlua_spotlight_ui["ui"]
  nlua_spotlight_util["util"]
  nlua --> nlua_spotlight
  nlua_spotlight --> nlua_spotlight_bindings
  nlua_spotlight --> nlua_spotlight_config
  nlua_spotlight --> nlua_spotlight_core
  nlua_spotlight --> nlua_spotlight_ui
  nlua_spotlight --> nlua_spotlight_util
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_spotlight_bindings["spotlight.bindings"]
  nlua_spotlight_config["spotlight.config"]
  nlua_spotlight_core["core"]
  nlua_spotlight_cursor_lua["spotlight.cursor"]
  nlua_spotlight_health_lua["spotlight.health"]
  nlua_spotlight_nav_lua["spotlight.nav"]
  nlua_spotlight_persist_lua["spotlight.persist"]
  nlua_spotlight_qf_lua["spotlight.qf"]
  nlua_spotlight_ui["ui"]
  nlua_spotlight_util["util"]
  nlua_spotlight_bindings --> nlua_spotlight_core
  nlua_spotlight_bindings --> nlua_spotlight_persist_lua
  nlua_spotlight_bindings --> nlua_spotlight_util
  nlua_spotlight_core --> nlua_spotlight_config
  nlua_spotlight_core --> nlua_spotlight_util
  nlua_spotlight_cursor_lua --> nlua_spotlight_config
  nlua_spotlight_cursor_lua --> nlua_spotlight_util
  nlua_spotlight_health_lua --> nlua_spotlight_bindings
  nlua_spotlight_health_lua --> nlua_spotlight_config
  nlua_spotlight_health_lua --> nlua_spotlight_core
  nlua_spotlight_health_lua --> nlua_spotlight_persist_lua
  nlua_spotlight_health_lua --> nlua_spotlight_util
  nlua_spotlight_nav_lua --> nlua_spotlight_config
  nlua_spotlight_nav_lua --> nlua_spotlight_core
  nlua_spotlight_nav_lua --> nlua_spotlight_util
  nlua_spotlight_persist_lua --> nlua_spotlight_config
  nlua_spotlight_persist_lua --> nlua_spotlight_core
  nlua_spotlight_persist_lua --> nlua_spotlight_util
  nlua_spotlight_qf_lua --> nlua_spotlight_config
  nlua_spotlight_qf_lua --> nlua_spotlight_core
  nlua_spotlight_ui --> nlua_spotlight_config
  nlua_spotlight_ui --> nlua_spotlight_core
  nlua_spotlight_ui --> nlua_spotlight_nav_lua
  nlua_spotlight_ui --> nlua_spotlight_util
  nlua_spotlight_util --> nlua_spotlight_config
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `spotlight` | One entry point that wires configuration and exposes every user-facing action. | 19 | [src](../../lua/spotlight/init.lua) |
| &nbsp;&nbsp;`spotlight.bindings` | The `:Spotlight` verb and the autocommands are always registered — the verb because it is the complete, keymap-independent interface to every action, and… | 1 | [src](../../lua/spotlight/bindings/init.lua) |
| &nbsp;&nbsp;`spotlight.config` | Deep-merges user options over `spotlight.config.DEFAULTS`, validates the handful of values that can break rendering or matching if wrong, and exposes a single… | 9 | [src](../../lua/spotlight/config/init.lua) |
| &nbsp;&nbsp;`core` |  |  |  |
| &nbsp;&nbsp;`ui` |  |  |  |
| &nbsp;&nbsp;`util` |  |  |  |

## Drift

0 errors · 0 warnings · 4 info

No errors or warnings.


<details>
<summary>4 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/spotlight has no README.md |
| `missing-readme` | lua/spotlight/bindings has no README.md |
| `missing-readme` | lua/spotlight/config has no README.md |
| `unreferenced-module` | spotlight.health is required by no other file in the tree |

</details>
