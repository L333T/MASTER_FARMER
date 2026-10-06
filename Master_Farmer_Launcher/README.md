# Master Farmer – Multi-Game Platform launcher (Sylvanas)

An in-game launcher. Pick a World of Warcraft version, then a product.
The product is downloaded from its GitHub repo and run **from memory only**.

> **This folder holds the ENCODED launcher** (`plugin/Master_Farmer`, built with `python tools/build_plugins.py --launcher`). Copy that folder into a Sylvanas `scripts` folder to use it. The readable source is kept off GitHub.

## Products

| Card | Product | Versions | GitHub repo | Source here |
|---|---|---|---|---|
| Master Farmer | **Questing & Grinding** | Forever, TBC Anniversary | `L333T/90123-12333-44a-asd32r1f324fg-3f3fqwf-mf` (public, readable) | its own repo |
| Route Maker | **Master Farmer Route Tool** | all versions (Forever, TBC, Classic, Retail) | `L333T/mf-route-tool` (public, obfuscated) | `products_src/mf_route_tool/` |
| Combat Rotations | **Slave Pens Mage Solo Pull** | TBC Anniversary | `L333T/sp-pull` (public, obfuscated) | `products_src/sp_pull/` |
| Utility Tools | – | – | – | Coming Soon |

**Questing & Grinding requires Ameisen Navigation**, available in the Master Farmer Discord.
If the AmeisenNav plugin isn't running when you press LOAD, the launcher shows a notice with
**Copy Discord**, **Load anyway** and **Cancel** buttons. Settings shows whether Ameisen is running.

Products, versions and repos are configured in `plugin/Master_Farmer/modules/config.lua`.

## How a product loads

1. The launcher resolves the repo's `main` branch to its latest commit.
   Files are downloaded from that commit, so a new push is picked up immediately.
2. It reads the repo's `manifest.lua` and downloads every file listed there, 8 at a time, with retries.
3. Every file is compiled. The source text is then discarded and nothing is written to disk.
   Loading needs internet; copies left on disk by launcher 1.1 or older are wiped at startup.
4. `header.lua` runs first. It is the product's own load check, for example "TBC/Forever only" or "player in world".
   Then `main.lua` runs, exactly as Sylvanas would start the plugin.
5. **UNLOAD** removes every callback the product registered.

## Updating Route Tool / SP Pull

```bash
python tools/build_plugins.py
```

This obfuscates `products_src/<product>/` into `repos/<repo>/` and writes `manifest.lua`.
It uses the **Bot** preset: renamed names, encrypted strings and constant arrays. There is no VM, so per-frame speed is unaffected.
Then push the repo:

```bash
git -C repos/sp-pull add -A
```

```bash
git -C repos/sp-pull commit -m "Update"
```

```bash
git -C repos/sp-pull push
```

Use `python tools/build_plugins.py sp_pull --no-obfuscate` while debugging. In-game errors then show real line numbers.
Obfuscated errors all point at line 1.

**Questing & Grinding** loads straight from its own repo. Push there as usual, keeping its `manifest.lua` current (`make_manifest.py`).

## Folder layout

| Path | What |
|---|---|
| `plugin/Master_Farmer/` | Launcher plugin. Installed at `Documents/a6bc008e/scripts/Master_Farmer/` |
| `plugin/scripts_data/master_farmer/gui/` | GUI textures. Installed at `Documents/a6bc008e/scripts_data/master_farmer/gui/` |
| `products_src/` | Readable product source. **Never push this** |
| `repos/` | Build output; each folder is a git clone of its GitHub repo |
| `tools/` | `build_plugins.py`, `obfuscate_bot.lua` (preset), `build_gui_assets.py`, `prometheus/` |
| `tests/` | LuaJIT tests with a mock Sylvanas API, listed below |

## Tests

```bash
luajit tests/test_loader.lua .
```

```bash
luajit tests/test_gui.lua .
```

```bash
luajit tests/test_real_products.lua .
```

`test_real_products` runs the real products up to `main.lua`. `main.lua` needs the live game API, so the final check is in game.

## Writing a product

A product is a normal Sylvanas plugin folder (`header.lua`, `main.lua`, modules). Under the launcher it also gets:

- `MASTER_FARMER.version_id`, `.product_id`, `.launcher_version`, `.data_dir`, `.source`
- Its own `require`, `package.loaded` and `package.preload`.
- Implicit globals stay private to the product. Use `_G.x` to share between plugins.
- `return { on_unload = function() ... end }` from `main.lua` for cleanup on UNLOAD.
