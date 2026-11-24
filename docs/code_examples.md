# Code Examples

← Back to the [project README](../README.md)

Short, copy-pasteable snippets using the `lovemap` API. For full shader walkthroughs see [Shaders](./shaders.md); for the API reference see [lovemap](./lovemap.md).

## Minimal game

```lua
local lovemap = require("src.lovemap")

function love.load()
    lovemap.aspect(16, 9) -- 1600x900 virtual coordinates
end

function lovemap.draw()
    love.graphics.print("Hello, zed2love!", 720, 440)
end
```

## Following the mouse in virtual coordinates

`lovemap.getMousePosition()` returns coordinates in the virtual game space, so the result is the same at any window size or in fullscreen:

```lua
local lovemap = require("src.lovemap")

function love.load()
    lovemap.aspect(16, 9)
end

function lovemap.draw()
    local mx, my, in_bounds = lovemap.getMousePosition(true) -- clamp to the game area
    love.graphics.setColor(in_bounds and 1 or 0.5, 1, 1)
    love.graphics.circle("fill", mx, my, 20)
end
```

## Full-screen chain plus a per-object effect

```lua
local lovemap = require("src.lovemap")

local screen_fx, glow_fx
local t = 0

function love.load()
    lovemap.aspect(16, 9)
    screen_fx = lovemap.setShaders("scanlines", "vignette")
    glow_fx = lovemap.newEffect("glow")
end

function love.update(dt)
    t = t + dt
end

function lovemap.draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Only the square glows", 60, 60)

    lovemap.withEffect(glow_fx, { glow = { strength = 4 + math.sin(t * 3) * 2 } }, function()
        love.graphics.setColor(1, 0.6, 0.2)
        love.graphics.rectangle("fill", 750, 400, 100, 100)
    end)
end
```

## Learning from the example games

Each example is a complete game using `lovemap.aspect(16, 9)` and `function lovemap.draw()`:

| Technique | Where to look |
| :--- | :--- |
| Per-object effect with a raw `love.graphics.newShader` | [`examples/train_ride`](../examples/train_ride/main.lua) |
| Full-screen `crt` + `scanlines` + `vignette` chain | [`examples/solitaire`](../examples/solitaire/main.lua) |
| Tile collision & platformer logic | [`examples/mario_clone`](../examples/mario_clone/main.lua) |
| Raycasting with PNG textures and billboard sprites | [`examples/wolfendoom`](../examples/wolfendoom/main.lua) |
| Isometric rendering & turn-based simulation | [`examples/utopia`](../examples/utopia/main.lua) |
| Full shader stack (`motionblur`, `screenshake`, `glow`, `chromasep`, `filmgrain`, …) | [`examples/shadermaxxing`](../examples/shadermaxxing/main.lua) |
