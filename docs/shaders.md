# Shaders: Full-Screen Chains & Per-Object Effects

← Back to the [project README](../README.md)

`zed2love` embeds [vrld/moonshine](https://github.com/vrld/moonshine) inside [`src/moonshine/`](../src/moonshine/init.lua), updated for **LÖVE 11.5**. The update fixes LÖVE 0.10-era bugs in:

- `dmg.lua` — palette array uniform sending
- `filmgrain.lua` / `sketch.lua` — `0..1` `ImageData:mapPixel` ranges
- `glow.lua` — virtual canvas sizing
- `scanlines.lua` — 1-based color indexing

## Available Effects

All 17 built-in effects are available by name:

`boxblur`, `chromasep`, `colorgradesimple`, `crt`, `desaturate`, `dmg`, `fastgaussianblur`, `filmgrain`, `fog`, `gaussianblur`, `glow`, `godsray`, `pixelate`, `posterize`, `scanlines`, `sketch`, `vignette`.

## 1. Adding a Chain of Full-Screen Shaders

Call **`lovemap.setShaders(...)`** with any list of effect names. `lovemap` runs your entire `lovemap.draw()` scene through the shader chain at virtual resolution before scaling to the window:

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
end

function love.update(dt)
    -- You can also toggle effects on/off at runtime:
    -- screen_fx.disable("crt")
    -- screen_fx.enable("crt")
end

function lovemap.draw()
    love.graphics.circle("fill", 800, 450, 60)
end
```

## 2. Applying Parameterized Shaders to a Single Object or Group

Normally in `moonshine`, wrapping a single sprite in `effect(function() ... end)` clears the buffer to an opaque background color, wiping out everything drawn behind it.

`lovemap` solves this with **`lovemap.newEffect(...)`** and **`lovemap.withEffect(effect, params, draw_fn)`**. They clear the effect buffer with transparent alpha (`{0, 0, 0, 0}`) and let you pass dynamic per-draw parameters for a single object or group of objects:

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

> **Note:** `lovemap.withEffect(my_custom_love_shader, { my_uniform = 1.5 }, function() ... end)` also works with raw `love.graphics.newShader(...)` objects, as demonstrated in [`examples/train_ride/main.lua`](../examples/train_ride/main.lua).

## See Also

- [lovemap reference](./lovemap.md)
- [More code examples](./code_examples.md)
