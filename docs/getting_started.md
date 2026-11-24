# Getting Started

← Back to the [project README](../README.md)

## Getting Started in 2 Minutes

1. **Clone or copy this repo** as the starting point for your new LÖVE2D game:
   ```sh
   git clone <your-repo-url> my-love-game
   cd my-love-game
   zed .
   ```
2. **Verify your LÖVE binary path** in [`.zed/tasks.json`](../.zed/tasks.json). It defaults to macOS (`/Applications/love.app/Contents/MacOS/love`). See [Zed Setup](./zed_setup.md#configuring-the-löve-binary-path) for Linux and Windows.
3. **Start coding in [`main.lua`](../main.lua)** (or check out [`main.lua.example`](../main.lua.example) and the 6 complete games in [`examples/`](../examples/)). Notice how lean `main.lua` is:
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
   - Open the Zed Task Picker (`Cmd+Shift+R` on macOS / `Ctrl+Shift+R` on Linux & Windows) and select **`Run Game`** or **`Example 1..6`**, or bind `Run Game` directly to `Cmd+Return` (see [Recommended Zed Keybindings](./zed_setup.md#recommended-zed-keybindings)).
   - Press **`F11`** to toggle fullscreen, and **`Escape`** to exit fullscreen.
5. **Export to the Web (WASM):**
   - Run the **`Build WASM`** (or **`Serve WASM`**) task from Zed, or run `make wasm` / `make serve` in your terminal to compile your game to WebAssembly and play it at `http://localhost:8000`. See [Building & Tasks](./building.md).

## Dependencies

### Required (Desktop Development)
- **[Zed Editor](https://zed.dev/)**
- **Zed `Lua` Extension** (`lua-language-server`): install via Zed's Extensions panel (`Cmd+Shift+X`).
- **[LÖVE2D 11.5](https://love2d.org/)**: installed on your system.

### Optional (For `.love` Packaging & WASM Web Builds)
- **`make`** and **`zip`**: standard build utilities (pre-installed on macOS/Linux).
- **[Node.js](https://nodejs.org/)** (`npm` / `npx`) and **[`love.js`](https://github.com/Davidobot/love.js)**: used by the `Makefile` to compile `.love` archives into a playable HTML5/WebAssembly bundle:
  ```sh
  npm install -g love.js
  ```
- **`python3`**: used by `make serve` (`python3 -m http.server`) to host the WASM build locally.

## Next Steps

- [lovemap: virtual coordinates & fullscreen](./lovemap.md)
- [Shaders: full-screen chains & per-object effects](./shaders.md)
- [Code examples](./code_examples.md)
