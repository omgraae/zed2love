# zed2love

Welcome to **zed2love** — a lean, MITMIT-licensedlicensed project stub for building [LÖVE2D](https://love2d.org/) (11.5) games in the [Zed](https://zed.dev/) editor, complete with zero-clutter type hints, one-key game launching, virtual-resolution coordinate mapping ([`src/lovemap.lua`](./src/lovemap.lua)), an embedded & LÖVE 11.5-updated shader suite ([`src/moonshine/`](./src/moonshine/init.lua)), an embedded & LÖVE 11.5-updated shader suite ([`src/moonshine/`](./src/moonshine/init.lua)), 5 complete example games ([`examples/`](./examples/)), and a WebAssembly (WASM) build pipeline.

> **Attribution, Inspiration & License (MIT):**
> - **Type Hints & Zed Setup:** Inspired by [love2z](https://github.com/alejandro-alzate/love2z) by Alejandro Alzate (MIT). While `love2z` originally generated hundreds of kilobytes of local `@meta` stub files inside `src/`, modern `lua-language-server` (bundled with Zed's Lua extension) now ships with complete, built-in LÖVE 11.5 definitions (`${3rd}/love2d/library/`). `zed2love` takes advantage of this built-in library so your project stays completely lean, your `src/` folder stays free for your actual game code, and your `main.lua` never gets polluted with broken `require("src.love")` statements.
> - **Post-Processing & Object Shaders:** Embeds an updated, LÖVE 11.5-compatible version of [vrld/moonshine](https://github.com/vrld/moonshine) by Matthias Richter (MIT) inside [`src/moonshine/`](./src/moonshine/init.lua), tightly integrated with [`src/lovemap.lua`](./src/lovemap.lua) for both full-screen shader chains and per-object/per-group parameterized effects.
> - Licensed under the [MIT License](./LICENSE).
> **Attribution, Inspiration & License (MIT):**
> - **Type Hints & Zed Setup:** Inspired by [love2z](https://github.com/alejandro-alzate/love2z) by Alejandro Alzate (MIT). While `love2z` originally generated hundreds of kilobytes of local `@meta` stub files inside `src/`, modern `lua-language-server` (bundled with Zed's Lua extension) now ships with complete, built-in LÖVE 11.5 definitions (`${3rd}/love2d/library/`). `zed2love` takes advantage of this built-in library so your project stays completely lean, your `src/` folder stays free for your actual game code, and your `main.lua` never gets polluted with broken `require("src.love")` statements.
> - **Post-Processing & Object Shaders:** Embeds an updated, LÖVE 11.5-compatible version of [vrld/moonshine](https://github.com/vrld/moonshine) by Matthias Richter (MIT) inside [`src/moonshine/`](./src/moonshine/init.lua), tightly integrated with [`src/lovemap.lua`](./src/lovemap.lua) for both full-screen shader chains and per-object/per-group parameterized effects.
> - Licensed under the [MIT License](./LICENSE).

---

## Friendly How-To: Getting Started in 2 Minutes

1. **Clone or copy this repo** as the starting point for your new LÖVE2D game:
   ```sh
   git clone <your-repo-url> my-love-game
   cd my-love-game
   zed .
   ```
2. **Verify your LÖVE binary path** in [`.zed/tasks.json`](./.zed/tasks.json) (it defaults to macOS `/Applications/love.app/Contents/MacOS/love` — see [Configuring the LÖVE Binary Path](#configuring-the-löve-binary-path) below for Linux and Windows).
3. **Start coding in [`main.lua`](./main.lua)** (or check out [`main.lua.example`](./main.lua.example) for a full interactive movement & shader playground). Notice how lean [`main.lua`](./main.lua) is:
   ```lua
   local lovemap = require("src.lovemap")

   function love.load()
       lovemap.aspect(16, 9) -- 1600x900 virtual game coordinates
   end

   function love.update(dt)
   end

   function lovemap.draw()
       love.graphics.print("Hello, zed2love!", 720, 440)
   end
   ```
3. **Start coding in [`main.lua`](./main.lua)** (or check out [`main.lua.example`](./main.lua.example) and the 5 complete games in [`examples/`](./examples/)). Notice how lean [`main.lua`](./main.lua) is:
   ```lua
   local lovemap = require("src.lovemap")

   function love.load()
       lovemap.aspect(16, 9) -- 1600x900 virtual game coordinates
   end

   function love.update(dt)
   end

   function lovemap.draw()
       love.graphics.print("Hello, zed2love!", 720, 440)
   end
   ```
4. **Run your game (or any of the 6 examples):**
   - Open the Zed Task Picker (`Cmd+Shift+R` on macOS / `Ctrl+Shift+R` on Linux & Windows) and select **`Run Game`** or **`Example 1..5`**, or bind `Run Game` directly to `Cmd+Return` (see [Recommended Zed Keybindings](#recommended-zed-keybindings)).
   - Press **`F11`** to toggle fullscreen, and **`Escape`** to exit fullscreen.
5. **Export to the Web (WASM):**
   - Run the **`Build WASM`** (or **`Serve WASM`**) task from Zed, or run `make wasm` / `make serve` in your terminal to compile your game to WebAssembly and play it at `http://localhost:8000`!

---

## 5 Included Example Games (`examples/`)

Every example game uses `src/lovemap.lua` (`lovemap.aspect(16, 9)` + `function lovemap.draw()`) and shaderscanbelaunchedstraightfrom Zed's Task Picker `Cmd+Shift+R`:

| # | Directory | Zed Task | Highlights |
| :- | :--- | :--- | :--- |
| **1** | [`examples/train_ride`](./examples/train_ride/main.lua) | **`Example 1: Train Ride`** | Side-scrolling vintage steam train bobbing on the track with animated connecting rods & steam puffs, 2 fast foreground parallax layers, 5 background parallax layers (near/mid forests, rolling hills with farms & windmills, 2 mountain ranges), stationary twilight sky, and a depth-haze shader (`lovemap.withEffect`) that increases atmospheric haze on deeper layers. |
| **2** | [`examples/mario_clone`](./examples/mario_clone/main.lua) | **`Example 2: Mario Clone`** | Pure 3-level side-scrolling platformer (*Green Hills*, *Underground Cavern*, *Sunset Fortress*) with tile collision, breakable bricks, `?` coin blocks, pipes, Goomba stomping, hazards, lives, and flagpoles. |
| **3** | [`examples/solitaire`](./examples/solitaire/main.lua) | **`Example 3: Solitaire (CRT)`** | Klondike Solitaire where every card is a physical spring-damper object (velocity-based tilt, lift scale, drop shadow, flip impulse) wrapped in a full-screen `crt` + `scanlines` + `vignette` shader chain. Supports drag-and-drop stacks and right-click auto-foundation. |
| **4** | [`examples/wolfendoom`](./examples/wolfendoom/main.lua) | **`Example 4: Wolfendoom 3D`** | 3D DDA raycaster that projects PNG textures (`assets/wall_brick.png`, `assets/wall_tech.png`) onto virtual 3D wall surfaces with distance shading, Z-buffered 3D billboarded monster sprites (`assets/monster.png`) that pursue the player and automatically respawn, plasma blaster hitscan shooting, and a live mini-map. |
| **5** | [`examples/utopia`](./examples/utopia/main.lua) | **`Example 5: Utopia (Isometric)`** | Turn-based isometric civilization game on a 28x28 archipelago focused purely on mutual aid, establishing trade routes with animated caravans, sharing ecological knowledge, and sending relief convoys when natural emergencies (floods, droughts, landslides) strike neighboring settlements. Zero war or strife. |
| **6** | [`examples/shadermaxxing`](./examples/shadermaxxing/main.lua) | **`Example 6: Shadermaxxing`** | Autogenerated top-down isometric maze showcasing the full shader stack: 3D rolling sphere shader, 360° raytraced 8-segment sight cone with fog-of-war mist desaturation, directional speed blur (`motionblur`), impact `screenshake`, `glow`, `chromasep`, `vignette`, `filmgrain`, plus magma vent and exit portal shaders. |

1. **`lovemap.aspect(w, h, opts)`**: Sets the game's aspect ratio where each unit maps to `* 100` virtual game coordinates regardless of actual window pixel resolution:
   - `lovemap.aspect(16, 9)` → **`1600 x 900`** virtual game coordinates
   - `lovemap.aspect(4, 3)` → **`400 x 300`** virtual game coordinates
   - Automatic letterbox/pillarbox scaling when the window is resized or fullscreened.
2. **Zero-Boilerplate `function lovemap.draw()`**:
   - Instead of writing `function love.draw()`, `function love.resize(w, h)`, and `function love.keypressed(key)` in [`main.lua`](./main.lua), simply define **`function lovemap.draw()`**!
   - When `lovemap.aspect(...)` is called, `lovemap` automatically hooks LÖVE's drawing, window-resize, and key-press handlers (`F11` toggles fullscreen, `ESC` exits fullscreen) and runs `lovemap.draw()` inside your virtual coordinate canvas.
3. **Mouse & Coordinate Conversion**:
   - `lovemap.getMousePosition(clamp)` — Returns `game_x, game_y, in_bounds` in virtual game coordinates.
   - `lovemap.toGame(screen_x, screen_y, clamp)` — Converts window pixel coordinates to virtual game coordinates.
   - `lovemap.toScreen(game_x, game_y)` — Converts virtual game coordinates to window pixel coordinates.
---

---

## Shaders: Full-Screen Chains & Per-Object Effects (`src/moonshine/`)

`zed2love` embeds [vrld/moonshine](https://github.com/vrld/moonshine) inside [`src/moonshine/`](./src/moonshine/init.lua), updated for **LÖVE 11.5** (fixing LÖVE 0.10-era bugs in `dmg.lua` palette array uniform sending, `filmgrain.lua` / `sketch.lua` `0..1` `ImageData:mapPixel` ranges, `glow.lua` virtual canvas sizing, and `scanlines.lua` 1-based color indexing).

All 17 built-in effects are available by name:
`boxblur`, `chromasep`, `colorgradesimple`, `crt`, `desaturate`, `dmg`, `fastgaussianblur`, `filmgrain`, `fog`, `gaussianblur`, `glow`, `godsray`, `pixelate`, `posterize`, `scanlines`, `sketch`, `vignette`.

### 1. Adding a Chain of Full-Screen Shaders

Call **`lovemap.setShaders(...)`** with any list of effect names. `lovemap` automatically runs your entire `lovemap.draw()` scene through the shader chain at virtual resolution before scaling to the window:

## `lovemap` — Virtual Coordinates, `lovemap.draw()`, & Fullscreen (`src/lovemap.lua`)

One of the most common headaches in new LÖVE2D projects is mapping game coordinates to actual screen pixels across different window sizes, HiDPI displays, fullscreen modes, and shaders.

[`src/lovemap.lua`](./src/lovemap.lua) eliminates all of that boilerplate:

1. **`lovemap.aspect(w, h, opts)`**: Sets the game's aspect ratio where each unit maps to `* 100` virtual game coordinates regardless of actual window pixel resolution:
   - `lovemap.aspect(16, 9)` → **`1600 x 900`** virtual game coordinates
   - `lovemap.aspect(4, 3)` → **`400 x 300`** virtual game coordinates
   - Automatic letterbox/pillarbox scaling when the window is resized or fullscreened.
2. **Zero-Boilerplate `function lovemap.draw()`**:
   - Instead of writing `function love.draw()`, `function love.resize(w, h)`, and `function love.keypressed(key)` in [`main.lua`](./main.lua), simply define **`function lovemap.draw()`**!
   - When `lovemap.aspect(...)` is called, `lovemap` automatically hooks LÖVE's drawing, window-resize, and key-press handlers (`F11` toggles fullscreen, `ESC` exits fullscreen) and runs `lovemap.draw()` inside your virtual coordinate canvas.
3. **Mouse & Coordinate Conversion**:
   - `lovemap.getMousePosition(clamp)` — Returns `game_x, game_y, in_bounds` in virtual game coordinates.
   - `lovemap.toGame(screen_x, screen_y, clamp)` — Converts window pixel coordinates to virtual game coordinates.
   - `lovemap.toScreen(game_x, game_y)` — Converts virtual game coordinates to window pixel coordinates.

---

## Shaders: Full-Screen Chains & Per-Object Effects (`src/moonshine/`)

`zed2love` embeds [vrld/moonshine](https://github.com/vrld/moonshine) inside [`src/moonshine/`](./src/moonshine/init.lua), updated for **LÖVE 11.5** (fixing LÖVE 0.10-era bugs in `dmg.lua` palette array uniform sending, `filmgrain.lua` / `sketch.lua` `0..1` `ImageData:mapPixel` ranges, `glow.lua` virtual canvas sizing, and `scanlines.lua` 1-based color indexing).

All 17 built-in effects are available by name:
`boxblur`, `chromasep`, `colorgradesimple`, `crt`, `desaturate`, `dmg`, `fastgaussianblur`, `filmgrain`, `fog`, `gaussianblur`, `glow`, `godsray`, `pixelate`, `posterize`, `scanlines`, `sketch`, `vignette`.

### 1. Adding a Chain of Full-Screen Shaders

Call **`lovemap.setShaders(...)`** with any list of effect names. `lovemap` automatically runs your entire `lovemap.draw()` scene through the shader chain at virtual resolution before scaling to the window:

```lua
local lovemap = require("src.lovemap")

local screen_fx

function love.load()
    lovemap.aspect(16, 9)

    -- Chain multiple full-screen effects in one line:
    screen_fx = lovemap.setShaders("crt", "scanlines", "vignette")

    -- Configure effect parameters at load time (or dynamically in love.update):
    screen_fx.scanlines.opacity = 0.25
    screen_fx.vignette.radius = 0.85
    screen_fx.vignette.opacity = 0.4
    lovemap.aspect(16, 9)

    -- Chain multiple full-screen effects in one line:
    screen_fx = lovemap.setShaders("crt", "scanlines", "vignette")

    -- Configure effect parameters at load time (or dynamically in love.update):
    screen_fx.scanlines.opacity = 0.25
    screen_fx.vignette.radius = 0.85
    screen_fx.vignette.opacity = 0.4
end

function love.updateupdate(dtdt)
    ---- You can also toggle effects on/off at runtime:
    -- screen_fx.disable("crt")
    -- screen_fx.enable("crt"You can also toggle effects on/off at runtime:
    -- screen_fx.disable("crt")
    -- screen_fx.enable("crt")
end

function lovemap.draw()
    love.graphics.circle("fill", 800, 450, 60)
end
```

### 2. Applying Parameterized Shaders to a Single Object or Group of Objects

Normally in `moonshine`, wrapping a single sprite in `effect(function() ... end)` clears the buffer to an opaque background color—wiping out everything drawn behind it!

`lovemap` solves this with **`lovemap.newEffect(...)`** and **`lovemap.withEffect(effect, params, draw_fn)`**, which clears the effect buffer with transparent alpha (`{0, 0, 0, 0}`) and lets you pass dynamic per-draw parameters for a single object or group of objects:

```lua
local lovemap = require("src.lovemap")

local player_fx
local time_elapsed = 0

function love.load()
    lovemap.aspect(16, 9)

    -- Create an effect chain specifically for a single object or group:
    player_fx = lovemap.newEffect("chromasep", "glow")
    player_fx.glow.min_luma = 0.3
end

function love.update(dt)
    time_elapsed = time_elapsed + dt
end

function lovemap.draw()
    -- 1. Draw normal background / HUD (unaffected by player_fx)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Normal unshaded HUD text", 60, 60)

    -- 2. Draw a single object (or group of objects) with dynamic shader parameters:
    lovemap.withEffect(player_fx, {
        chromasep = {
            angle = time_elapsed * 2,
            radius = 4 + math.sin(time_elapsed * 5) * 3,
        },
        glow = {
            strength = 6,
        },
    }, function()
        love.graphics.setColor(0.2, 0.7, 1.0, 1.0)
        love.graphics.rectangle("fill", 750, 400, 100, 100)
function lovemap.draw()
    love.graphics.circle("fill", 800, 450, 60)
end
```

### 2. Applying Parameterized Shaders to a Single Object or Group of Objects

Normally in `moonshine`, wrapping a single sprite in `effect(function() ... end)` clears the buffer to an opaque background color—wiping out everything drawn behind it!

`lovemap` solves this with **`lovemap.newEffect(...)`** and **`lovemap.withEffect(effect, params, draw_fn)`**, which clears the effect buffer with transparent alpha (`{0, 0, 0, 0}`) and lets you pass dynamic per-draw parameters for a single object or group of objects:

```lua
local lovemap = require("src.lovemap")

local player_fx
local time_elapsed = 0

function love.load()
    lovemap.aspect(16, 9)

    -- Create an effect chain specifically for a single object or group:
    player_fx = lovemap.newEffect("chromasep", "glow")
    player_fx.glow.min_luma = 0.3
end

function love.update(dt)
    time_elapsed = time_elapsed + dt
end

function lovemap.draw()
    -- 1. Draw normal background / HUD (unaffected by player_fx)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Normal unshaded HUD text", 60, 60)

    -- 2. Draw a single object (or group of objects) with dynamic shader parameters:
    lovemap.withEffect(player_fx, {
        chromasep = {
            angle = time_elapsed * 2,
            radius = 4 + math.sin(time_elapsed * 5) * 3,
        },
        glow = {
            strength = 6,
        },
    }, function()
        love.graphics.setColor(0.2, 0.7, 1.0, 1.0)
        love.graphics.rectangle("fill", 750, 400, 100, 100)
    end)
end
```
*(Note: `lovemap.withEffect(my_custom_love_shader, { my_uniform = 1.5 }, function() ... end)` also works with raw `love.graphics.newShader(...)` objects!)*
*(Note: `lovemap.withEffect(my_custom_love_shader, { my_uniform = 1.5 }, function() ... end)` also works with raw `love.graphics.newShader(...)` objects, as demonstrated in [`examples/train_ride/main.lua`](./examples/train_ride/main.lua)!)*

---

## Dependencies

### Required (Desktop Development)
- **[Zed Editor](https://zed.dev/)**
- **Zed `Lua` Extension** (`lua-language-server`): Install via Zed's Extensions panel (`Cmd+Shift+X`).
- **[LÖVE2D 11.5](https://love2d.org/)**: Installed on your system.

### Optional (For `.love` Packaging & WASM Web Builds)
- **`make`** and **`zip`**: Standard build utilities (pre-installed on macOS/Linux).
- **[Node.js](https://nodejs.org/)** (`npm` / `npx`) and **[`love.js`](https://github.com/Davidobot/love.js)**: Used by the `Makefile` to compile `.love` archives into a playable HTML5/WebAssembly bundle:
  ```sh
  npm install -g love.js
  ```
- **`python3`**: Used by `make serve` (`python3 -m http.server`) to host the WASM build locally.

---

## Why `emmylua` is Explicitly Disabled in `.zed/settings.json`

If you have both the **Lua** (`lua-language-server`) and **EmmyLua** (`emmylua_ls`) extensions installed in Zed, Zed will launch **both** language servers simultaneously for `.lua` files.

While `lua-language-server` reads [`.luarc.json`](./.luarc.json) and loads `${3rd}/love2d/library/`, `emmylua_ls` does not include that third-party library and will show false `undefined global variable: love` errors (or aggressively insert broken `local love = require(...)` lines on autocomplete).

To prevent this conflict, [`.zed/settings.json`](./.zed/settings.json) explicitly pins `lua-language-server` and disables `emmylua` for this workspace:

```json
{
  "languages": {
    "Lua": {
      "language_servers": ["lua-language-server", "!emmylua"]
    }
  }
}
```

---

## Configuring the LÖVE Binary Path

Before running the **`Run Game`** task, make sure the `"command"` field in [`.zed/tasks.json`](./.zed/tasks.json) matches where the LÖVE binary is installed on your operating system.

Here are the 3 typical configurations for **macOS**, **Linux**, and **Windows**:

### 1. macOS (Default in `.zed/tasks.json`)
```json
{
  "label": "Run Game",
  "command": "/Applications/love.app/Contents/MacOS/love",
  "args": ["."],
  "cwd": "$ZED_WORKTREE_ROOT"
}
```

### 2. Linux
```json
{
  "label": "Run Game",
  "command": "love",
  "args": ["."],
  "cwd": "$ZED_WORKTREE_ROOT"
}
```
*(Or `"/usr/bin/love"`, or `"/usr/games/love"` depending on your distro's package manager.)*

### 3. Windows
```json
{
  "label": "Run Game",
  "command": "C:\\Program Files\\LOVE\\love.exe",
  "args": ["."],
  "cwd": "$ZED_WORKTREE_ROOT"
}
```

---

## Building for WebAssembly (WASM) & Zed Tasks

[`Makefile`](./Makefile) provides targets for running, packaging, and compiling your game to WebAssembly using `love.js`, and every target is pre-wired as a Zed task in [`.zed/tasks.json`](./.zed/tasks.json):

| Zed Task Label | CLI Command | Description |
| :--- | :--- | :--- |
| **`Run Game`** | `make run` | Runs the root game locally using your LÖVE binary |
| **`Example 1..6: ...`** | `love examples/<name>` | Runs any of the 6 example games in `examples/` |
| **`Package .love`** | `make love` | Packages the project into `build/zed2love.love` |
| **`Build WASM`** | `make wasm` | Builds the `.love` file and compiles the HTML5/WASM bundle into `build/web/` |
| **`Serve WASM`** | `make serve` | Builds the WASM bundle and serves it at `http://localhost:8000` |
| **`Clean Build`** | `make clean` | Removes the `build/` and `dist/` directories |

You can customize the game name, browser tab title, and WASM memory allocation (in bytes) either in [`Makefile`](./Makefile) or via CLI overrides:
```sh
make wasm GAME_NAME=my_game TITLE="My Awesome Game" MEMORY=134217728
```

---

## Recommended Zed Keybindings

Add the following to your user keymap (`~/.config/zed/keymap.json`, accessible via `Cmd+K Cmd+S` in Zed) to launch your game with `Cmd+Return`, open the task modal with `Cmd+Shift+R`, and close the task terminal with `Cmd+.`:

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "cmd-shift-r": "task::Spawn",
      "cmd-return": ["task::Spawn", { "task_name": "Run Game" }]
    }
  },
  {
    "context": "Terminal",
    "bindings": {
      "cmd-.": "pane::CloseActiveItem"
    }
  }
]
```

---

## Project Layout

```text
.
├── .gitignore           # Ignores build/, dist/, *.love, and .DS_Store
├── .luarc.json          # LuaJIT + built-in LÖVE2D 11.5 type definitions
├── .zed/
│   ├── settings.json    # Enables lua-language-server and disables emmylua
│   └── tasks.json       # Zed tasks for Run Game, Examples 1-5, Build/Serve WASM, Package .love
├── LICENSE              # MIT License
├── LICENSE              # MIT License
├── Makefile             # Build automation for desktop (.love) and WebAssembly (love.js)
├── README.md            # Project documentation
├── conf.lua             # LÖVE2D configuration file (resizable 1280x720 window)
├── main.lua             # Lean entry point using lovemap.aspect(16, 9) and lovemap.draw()
├── main.lua.example     # Interactive playground demonstrating movement + full-screen & per-object shaders
├── examples/
│   ├── train_ride/      # 1. Parallax steam train with depth-haze shaders
│   ├── mario_clone/     # 2. Pure 3-level side-scrolling platformer
│   ├── solitaire/       # 3. Physical spring-damper Klondike Solitaire with CRT shader
│   ├── wolfendoom/      # 4. 3D texture-mapped raycaster with PNG textures & respawning monsters
│   ├── utopia/          # 5. Peaceful turn-based isometric civilization game of mutual aid & trade
│   └── shadermaxxing/   # 6. Isometric 3D-ball maze with 360° raytraced sight & full shader showcase
├── src/
│   ├├── lovemap.lua      # VirtualVirtual-coordinate, aspect-ratio, fullscreen & shadershader manager
│   └── moonshine/       # Embedded vrld/moonshine shader library (updated for LÖVE 11.5)
└── skills/
    └── zed2love/
        └── SKILL.md     # Agent skill describing zed2love workflows and conventions
```
