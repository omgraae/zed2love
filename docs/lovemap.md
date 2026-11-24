# `lovemap` — Virtual Coordinates, `lovemap.draw()` & Fullscreen

← Back to the [project README](../README.md)

One of the most common headaches in new LÖVE2D projects is mapping game coordinates to actual screen pixels across different window sizes, HiDPI displays, fullscreen modes, and shaders.

[`src/lovemap.lua`](../src/lovemap.lua) eliminates that boilerplate.

## 1. `lovemap.aspect(w, h, opts)`

Sets the game's aspect ratio where each unit maps to `* 100` virtual game coordinates, regardless of actual window pixel resolution:

- `lovemap.aspect(16, 9)` → **`1600 x 900`** virtual game coordinates
- `lovemap.aspect(4, 3)` → **`400 x 300`** virtual game coordinates
- Automatic letterbox/pillarbox scaling when the window is resized or fullscreened.

## 2. Zero-Boilerplate `function lovemap.draw()`

- Instead of writing `function love.draw()`, `function love.resize(w, h)`, and `function love.keypressed(key)` in [`main.lua`](../main.lua), simply define **`function lovemap.draw()`**.
- When `lovemap.aspect(...)` is called, `lovemap` automatically hooks LÖVE's drawing, window-resize, and key-press handlers (`F11` toggles fullscreen, `ESC` exits fullscreen) and runs `lovemap.draw()` inside your virtual coordinate canvas.

## 3. Mouse & Coordinate Conversion

- `lovemap.getMousePosition(clamp)` — returns `game_x, game_y, in_bounds` in virtual game coordinates.
- `lovemap.toGame(screen_x, screen_y, clamp)` — converts window pixel coordinates to virtual game coordinates.
- `lovemap.toScreen(game_x, game_y)` — converts virtual game coordinates to window pixel coordinates.

## 4. Shaders

`lovemap` also manages full-screen shader chains and per-object effects. See [Shaders](./shaders.md).
