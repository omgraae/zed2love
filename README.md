# zed2love

**zed2love** is a lean, MIT-licensed project starter for building [LÖVE2D](https://love2d.org/) (11.5) games in the [Zed](https://zed.dev/) editor. It gives you:

- **Zero-clutter type hints** — uses the LÖVE 11.5 definitions built into `lua-language-server`, so `src/` stays free for your game code.
- **One-key game launching** — every game and example is a pre-wired Zed task.
- **Virtual-resolution coordinates** — [`src/lovemap.lua`](./src/lovemap.lua) handles aspect ratio, letterboxing, fullscreen, and mouse mapping.
- **An embedded shader suite** — a LÖVE 11.5-updated [moonshine](https://github.com/vrld/moonshine) in [`src/moonshine/`](./src/moonshine/init.lua), for full-screen chains and per-object effects.
- **6 complete example games** in [`examples/`](./examples/).
- **A WebAssembly (WASM) build pipeline** to publish your game to the web.

```lua
local lovemap = require("src.lovemap")

function love.load()
    lovemap.aspect(16, 9) -- 1600x900 virtual game coordinates
end

function lovemap.draw()
    love.graphics.print("Hello, zed2love!", 720, 440)
end
```

## Quick Start

```sh
git clone <your-repo-url> my-love-game
cd my-love-game
zed .
```

Then press `Cmd+Shift+R` (macOS) or `Ctrl+Shift+R` (Linux/Windows) in Zed and run **`Run Game`**. See the [full getting started guide](./docs/getting_started.md).

## Documentation

| Guide | What's in it |
| :--- | :--- |
| [Getting Started](./docs/getting_started.md) | Setup, first game, running examples, dependencies |
| [lovemap](./docs/lovemap.md) | Virtual coordinates, `lovemap.draw()`, fullscreen, mouse conversion |
| [Shaders](./docs/shaders.md) | Full-screen shader chains and per-object effects, all 17 effects |
| [Code Examples](./docs/code_examples.md) | Copy-pasteable snippets and a map of techniques in the examples |
| [Zed Setup](./docs/zed_setup.md) | LÖVE binary path (macOS/Linux/Windows), keybindings, why `emmylua` is disabled |
| [Building & Tasks](./docs/building.md) | `.love` packaging, WASM builds, Zed task reference |

## Contributors & Attribution

- **[Ole Valente](mailto:ole@covalente.dk)** — creator and maintainer of zed2love: Zed integration, `lovemap`, the LÖVE 11.5 shader updates, the example games, and the WASM build pipeline.
- **[Alejandro Alzate](https://github.com/alejandro-alzate)** — author of [love2z](https://github.com/alejandro-alzate/love2z) (MIT), the inspiration for the type-hints and Zed setup. While `love2z` generates hundreds of kilobytes of local `@meta` stub files inside `src/`, modern `lua-language-server` ships with complete LÖVE 11.5 definitions (`${3rd}/love2d/library/`). zed2love uses that built-in library instead, so your `src/` folder and `main.lua` stay clean.
- **[Matthias Richter (vrld)](https://github.com/vrld)** — author of [moonshine](https://github.com/vrld/moonshine) (MIT), the post-processing shader library embedded in [`src/moonshine/`](./src/moonshine/init.lua). It has been updated for LÖVE 11.5 and integrated with `lovemap`.

Licensed under the [MIT License](./LICENSE).

## Project Assets

### Example games (`examples/`)

Every example uses `lovemap.aspect(16, 9)` + `function lovemap.draw()` and can be launched straight from Zed's Task Picker.

| # | Directory | Zed Task | Highlights |
| :- | :--- | :--- | :--- |
| **1** | [`examples/train_ride`](./examples/train_ride/main.lua) | **`Example 1: Train Ride`** | Side-scrolling vintage steam train with animated connecting rods and steam puffs, 2 fast foreground parallax layers, 5 background parallax layers (forests, hills with farms and windmills, mountain ranges), a twilight sky, and a depth-haze shader (`lovemap.withEffect`) that thickens atmospheric haze on deeper layers. |
| **2** | [`examples/mario_clone`](./examples/mario_clone/main.lua) | **`Example 2: Mario Clone`** | 3-level side-scrolling platformer (*Green Hills*, *Underground Cavern*, *Sunset Fortress*) with tile collision, breakable bricks, `?` coin blocks, pipes, Goomba stomping, hazards, lives, and flagpoles. |
| **3** | [`examples/solitaire`](./examples/solitaire/main.lua) | **`Example 3: Solitaire (CRT)`** | Klondike Solitaire where every card is a spring-damper object (velocity-based tilt, lift scale, drop shadow, flip impulse) under a full-screen `crt` + `scanlines` + `vignette` chain. Drag-and-drop stacks and right-click auto-foundation. |
| **4** | [`examples/wolfendoom`](./examples/wolfendoom/main.lua) | **`Example 4: Wolfendoom 3D`** | 3D DDA raycaster projecting PNG textures onto walls with distance shading, Z-buffered billboarded monster sprites that pursue the player and respawn, plasma blaster hitscan shooting, and a live mini-map. |
| **5** | [`examples/utopia`](./examples/utopia/main.lua) | **`Example 5: Utopia (Isometric)`** | Turn-based isometric civilization game on a 28x28 archipelago about mutual aid: trade routes with animated caravans, shared ecological knowledge, and relief convoys when floods, droughts, or landslides strike neighbors. No war. |
| **6** | [`examples/shadermaxxing`](./examples/shadermaxxing/main.lua) | **`Example 6: Shadermaxxing`** | Generated isometric maze showcasing the full shader stack: 3D rolling-sphere shader, 360° raytraced sight cone with fog-of-war desaturation, `motionblur`, `screenshake`, `glow`, `chromasep`, `vignette`, `filmgrain`, plus magma vent and exit portal shaders. |

### Core source (`src/`)

| Asset | Description |
| :--- | :--- |
| [`src/lovemap.lua`](./src/lovemap.lua) | Virtual-coordinate, aspect-ratio, fullscreen, and shader manager. |
| [`src/moonshine/`](./src/moonshine/init.lua) | Embedded vrld/moonshine library with 17 effects, updated for LÖVE 11.5. |

### Project files

| Asset | Description |
| :--- | :--- |
| [`main.lua`](./main.lua) | Lean entry point for your own game. |
| [`main.lua.example`](./main.lua.example) | Interactive playground: movement + full-screen and per-object shaders. |
| [`conf.lua`](./conf.lua) | LÖVE configuration (resizable 1280x720 window). |
| [`Makefile`](./Makefile) | Build automation for desktop (`.love`) and WebAssembly (`love.js`). |
| [`.zed/`](./.zed/) | Zed settings and tasks (Run Game, Examples 1–6, Build/Serve WASM, Package .love). |
| [`.luarc.json`](./.luarc.json) | LuaJIT + built-in LÖVE 11.5 type definitions. |
| [`skills/zed2love/SKILL.md`](./skills/zed2love/SKILL.md) | Agent skill describing zed2love workflows and conventions. |
| [`docs/`](./docs/) | Guides (see [Documentation](#documentation)). |

---

## Technical Details

### Dependencies

**Required (desktop development)**
- [Zed Editor](https://zed.dev/) with the **Lua** extension (`lua-language-server`)
- [LÖVE2D 11.5](https://love2d.org/)

**Optional (`.love` packaging & WASM builds)**
- `make` and `zip`
- [Node.js](https://nodejs.org/) and [`love.js`](https://github.com/Davidobot/love.js) (`npm install -g love.js`)
- `python3` (for `make serve`)

More detail in [Getting Started](./docs/getting_started.md#dependencies).

### `lovemap` at a glance

- `lovemap.aspect(w, h)` — each unit is 100 virtual coordinates (`16, 9` → `1600 x 900`), with automatic letterboxing.
- `function lovemap.draw()` — replaces `love.draw`/`love.resize`/`love.keypressed`; `F11` toggles fullscreen, `Escape` leaves it.
- `lovemap.getMousePosition()`, `lovemap.toGame()`, `lovemap.toScreen()` — coordinate conversion.
- `lovemap.setShaders(...)`, `lovemap.newEffect(...)`, `lovemap.withEffect(...)` — full-screen and per-object shaders.

Full reference: [lovemap](./docs/lovemap.md), [Shaders](./docs/shaders.md).

### Zed tasks & WASM

| Zed Task | CLI | Description |
| :--- | :--- | :--- |
| `Run Game` | `make run` | Run the root game |
| `Package .love` | `make love` | Package into `build/zed2love.love` |
| `Build WASM` | `make wasm` | Build the HTML5/WASM bundle into `build/web/` |
| `Serve WASM` | `make serve` | Build and serve at `http://localhost:8000` |
| `Clean Build` | `make clean` | Remove `build/` and `dist/` |

More in [Building & Tasks](./docs/building.md).

### Why `emmylua` is disabled

Zed launches every installed Lua language server. `emmylua_ls` lacks the LÖVE library and reports false `undefined global variable: love` errors, so [`.zed/settings.json`](./.zed/settings.json) pins `lua-language-server` and disables `emmylua`. Details in [Zed Setup](./docs/zed_setup.md#why-emmylua-is-explicitly-disabled-in-zedsettingsjson).

### Project layout

```text
.
├── .gitignore           # Ignores build/, dist/, *.love, and .DS_Store
├── .luarc.json          # LuaJIT + built-in LÖVE2D 11.5 type definitions
├── .zed/
│   ├── settings.json    # Enables lua-language-server and disables emmylua
│   └── tasks.json       # Zed tasks: Run Game, Examples 1-6, Build/Serve WASM, Package .love
├── LICENSE              # MIT License
├── Makefile             # Desktop (.love) and WebAssembly (love.js) builds
├── README.md            # This file
├── conf.lua             # LÖVE2D configuration (resizable 1280x720 window)
├── main.lua             # Lean entry point using lovemap
├── main.lua.example     # Interactive movement + shader playground
├── docs/
│   ├── getting_started.md
│   ├── lovemap.md
│   ├── shaders.md
│   ├── code_examples.md
│   ├── zed_setup.md
│   └── building.md
├── examples/
│   ├── train_ride/      # 1. Parallax steam train with depth-haze shaders
│   ├── mario_clone/     # 2. 3-level side-scrolling platformer
│   ├── solitaire/       # 3. Spring-damper Klondike Solitaire with CRT shader
│   ├── wolfendoom/      # 4. Texture-mapped 3D raycaster
│   ├── utopia/          # 5. Peaceful isometric civilization game
│   └── shadermaxxing/   # 6. Isometric 3D-ball maze with full shader showcase
├── src/
│   ├── lovemap.lua      # Virtual-coordinate, aspect-ratio, fullscreen & shader manager
│   └── moonshine/       # Embedded vrld/moonshine (updated for LÖVE 11.5)
└── skills/
    └── zed2love/
        └── SKILL.md     # Agent skill for zed2love workflows
```
