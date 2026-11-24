--- @class Lovemap
--- @field aspect_w number Aspect ratio width component (e.g. 16)
--- @field aspect_h number Aspect ratio height component (e.g. 9)
--- @field unit_scale number Multiplier per aspect unit (default: 100 -> 16:9 becomes 1600x900)
--- @field width number Virtual game width in game coordinates
--- @field height number Virtual game height in game coordinates
--- @field window_w number Actual window pixel width
--- @field window_h number Actual window pixel height
--- @field scale number Current uniform scale factor from virtual coordinates to window pixels
--- @field offset_x number Current horizontal letterbox/pillarbox offset in window pixels
--- @field offset_y number Current vertical letterbox/pillarbox offset in window pixels
--- @field use_canvas boolean Whether to render to an internal virtual-resolution Canvas
--- @field filter "linear"|"nearest" Texture filter mode when scaling the internal Canvas
--- @field canvas love.Canvas|nil Internal virtual-resolution Canvas (when use_canvas is true)
--- @field background number[] RGBA color for the game area background {r, g, b, a}
--- @field border_color number[] RGBA color for letterbox/pillarbox bars {r, g, b, a}
--- @field post_effect table|nil Active full-screen moonshine chain
--- @field draw? fun() User-defined drawing callback operating in virtual game coordinates (`function lovemap.draw()`)
--- @field moonshine table Embedded vrld/moonshine library (`src.moonshine`)
--- @field effects table Alias for `moonshine.effects`
local lovemap = {
    aspect_w = 16,
    aspect_h = 9,
    unit_scale = 100,
    width = 1600,
    height = 900,
    window_w = 800,
    window_h = 600,
    scale = 1,
    offset_x = 0,
    offset_y = 0,
    use_canvas = true,
    filter = "linear",
    canvas = nil,
    background = { 0.08, 0.08, 0.10, 1.0 },
    border_color = { 0.0, 0.0, 0.0, 1.0 },
    post_effect = nil,
    draw = nil,
    _active = false,
    _prev_canvas = nil,
    _prev_scissor = nil,
    _resize_listeners = {},
    _hooks_installed = false,
}

local ok_ms, moonshine = pcall(require, "src.moonshine")
if ok_ms and moonshine then
    lovemap.moonshine = moonshine
    lovemap.effects = moonshine.effects
end

--- Recomputes scale and letterbox/pillarbox offsets for the given window dimensions.
--- Automatically hooked into LÖVE's `resize` event handler.
--- @param win_w? number Actual window width in pixels (defaults to love.graphics.getDimensions())
--- @param win_h? number Actual window height in pixels
function lovemap.resize(win_w, win_h)
    if not win_w or not win_h then
        win_w, win_h = love.graphics.getDimensions()
    end
    lovemap.window_w = win_w
    lovemap.window_h = win_h

    local scale_x = win_w / lovemap.width
    local scale_y = win_h / lovemap.height
    lovemap.scale = math.min(scale_x, scale_y)

    lovemap.offset_x = math.floor((win_w - lovemap.width * lovemap.scale) * 0.5)
    lovemap.offset_y = math.floor((win_h - lovemap.height * lovemap.scale) * 0.5)

    for _, listener in ipairs(lovemap._resize_listeners) do
        listener(lovemap.width, lovemap.height, win_w, win_h)
    end
end

--- Rebuilds the internal virtual-resolution canvas if `use_canvas` is enabled.
local function rebuildCanvas()
    if not lovemap.use_canvas then
        if lovemap.canvas then
            lovemap.canvas:release()
            lovemap.canvas = nil
        end
        return
    end

    if lovemap.canvas then
        lovemap.canvas:release()
    end
    lovemap.canvas = love.graphics.newCanvas(lovemap.width, lovemap.height)
    lovemap.canvas:setFilter(lovemap.filter, lovemap.filter)
end

--- Temporarily overrides `love.graphics.getWidth/getHeight/getDimensions`, `love.window.getMode`,
--- and `love.graphics.newCanvas` (when called with no dimensions) to report the virtual resolution
--- (`lovemap.width`, `lovemap.height`) while running `fn(...)`.
--- This ensures plugins like `vrld/moonshine` (including `glow`, `scanlines`, `filmgrain`, `boxblur`, `chromasep`)
--- allocate internal canvases and compute shader uniforms at the virtual resolution rather than window resolution.
--- @param fn fun(...): any
--- @param ... any
--- @return any
function lovemap.withVirtualMetrics(fn, ...)
    local lg = love.graphics
    local lw = love.window
    local orig_getWidth = lg.getWidth
    local orig_getHeight = lg.getHeight
    local orig_getDimensions = lg.getDimensions
    local orig_newCanvas = lg.newCanvas
    local orig_getMode = lw.getMode

    --- @diagnostic disable: duplicate-set-field
    lg.getWidth = function() return lovemap.width end
    lg.getHeight = function() return lovemap.height end
    lg.getDimensions = function() return lovemap.width, lovemap.height end
    lg.newCanvas = function(w, h, ...)
        if w == nil and h == nil then
            return orig_newCanvas(lovemap.width, lovemap.height)
        end
        return orig_newCanvas(w, h, ...)
    end
    lw.getMode = function()
        local _, _, flags = orig_getMode()
        return lovemap.width, lovemap.height, flags
    end
    --- @diagnostic enable: duplicate-set-field

    local ok, res = pcall(fn, ...)

    lg.getWidth = orig_getWidth
    lg.getHeight = orig_getHeight
    lg.getDimensions = orig_getDimensions
    lg.newCanvas = orig_newCanvas
    lw.getMode = orig_getMode

    if not ok then
        error(res, 2)
    end
    return res
end

--- Resolves an effect name (e.g. `"crt"`), constructor (`moonshine.effects.crt`), or effect table.
--- @param eff string|function|table
--- @return function|table
local function resolveEffect(eff)
    if type(eff) == "string" then
        assert(lovemap.moonshine, "src.moonshine is not available")
        return lovemap.moonshine.effects[eff]
    end
    return eff
end

--- Creates a stand-alone `moonshine` shader chain sized to `lovemap`'s virtual canvas.
--- Can be used for full-screen post-processing or to apply shader effects to singular or groups of objects
--- via `lovemap.withEffect(effect, function() ... end)` or `effect(function() ... end)`.
--- Accepts effect names as strings (`"crt"`, `"glow"`, `"chromasep"`) or constructors (`lovemap.effects.crt`).
--- @param first_effect string|function|table First effect name or constructor
--- @param ... string|function|table Additional chained effects
--- @return table chain The configured moonshine chain (parameterizable via `chain.<effect>.<param> = value`)
function lovemap.newEffect(first_effect, ...)
    assert(lovemap.moonshine, "lovemap.newEffect requires src.moonshine")
    local extra_effects = { ... }
    return lovemap.withVirtualMetrics(function()
        local chain = lovemap.moonshine(lovemap.width, lovemap.height, resolveEffect(first_effect))
        for _, eff in ipairs(extra_effects) do
            chain = chain.chain(resolveEffect(eff))
        end
        lovemap.onResize(function(vw, vh)
            if chain and type(chain.resize) == "function" then
                lovemap.withVirtualMetrics(function()
                    chain.resize(vw, vh)
                end)
            end
        end)
        return chain
    end)
end

--- Sets (or clears) the full-screen post-processing shader chain applied automatically during `lovemap.draw()`.
--- Accepts effect names as strings (e.g. `lovemap.setShaders("crt", "scanlines", "vignette")`)
--- or `lovemap.effects.<name>` constructors. Pass `nil` to clear full-screen shaders.
--- @param first_effect? string|function|table First effect name or constructor (or `nil` to disable)
--- @param ... string|function|table Additional chained effects
--- @return table chain The active full-screen moonshine chain
function lovemap.setShaders(first_effect, ...)
    if not first_effect then
        lovemap.post_effect = nil
        --- @diagnostic disable-next-line: return-type-mismatch
        return nil
    end
    local chain = lovemap.newEffect(first_effect, ...)
    lovemap.post_effect = chain
    return chain
end

--- Applies a `moonshine` effect chain (or raw `love.Shader`) to a single object or group of objects
--- inside `lovemap.draw()`, optionally setting parameters before drawing.
--- Unlike raw `moonshine` calls (which clear the background to opaque RGB and overwrite previously drawn objects),
--- `lovemap.withEffect` clears the effect buffer to transparent `{0, 0, 0, 0}` so it composites cleanly over your scene!
--- @param effect table|love.Shader|fun(fn: fun()) A moonshine chain (from `lovemap.newEffect`) or a `love.Shader`
--- @param params_or_draw table|fun() Optional parameter table (e.g. `{ chromasep = { radius = 6, angle = t } }` or `{ radius = 6 }`) or the draw callback
--- @param draw_fn? fun() Draw callback if `params_or_draw` is a parameter table
function lovemap.withEffect(effect, params_or_draw, draw_fn)
    local params = nil
    if type(params_or_draw) == "function" then
        draw_fn = params_or_draw
    elseif type(params_or_draw) == "table" then
        params = params_or_draw
    end
    assert(type(draw_fn) == "function", "lovemap.withEffect requires a draw function")

    -- Case 1: Raw love.Shader
    if type(effect) == "userdata" then
        --- @cast effect love.Shader
        if effect.typeOf and effect:typeOf("Shader") then
            if params then
                for k, v in pairs(params) do
                    if effect:hasUniform(k) then
                        effect:send(k, v)
                    end
                end
            end
            local prev_shader = love.graphics.getShader()
            love.graphics.setShader(effect)
            draw_fn()
            love.graphics.setShader(prev_shader)
            return
        end
    end

    -- Case 2: Moonshine effect chain
    if params and type(effect) == "table" then
        -- Support both `{ chromasep = { radius = 4 } }` and flat `{ radius = 4 }` (for single-effect chains)
        local first_entry = rawget(effect, 1)
        for k, v in pairs(params) do
            if type(v) == "table" and first_entry and first_entry.setters and not first_entry.setters[k] then
                for param_name, param_val in pairs(v) do
                    effect[k][param_name] = param_val
                end
            elseif first_entry and first_entry.setters and first_entry.setters[k] then
                effect[first_entry.name][k] = v
            else
                effect[k] = v
            end
        end
    end

    lovemap.withVirtualMetrics(function()
        local prev_bg = { love.graphics.getBackgroundColor() }
        local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
        -- Clear moonshine buffer with alpha = 0 and ensure moonshine's internal pass tint is opaque white
        love.graphics.setBackgroundColor(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        effect(draw_fn)
        love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
        love.graphics.setBackgroundColor(prev_bg)
    end)
end

--- Installs automatic hooks into LÖVE (`love.draw`, `love.handlers.resize`, `love.handlers.keypressed`)
--- so `main.lua` only needs `function lovemap.draw()` without boilerplate `love.resize` or `love.keypressed`.
local function installHooks()
    if lovemap._hooks_installed then
        return
    end
    lovemap._hooks_installed = true

    local handlers = rawget(love, "handlers")
    if type(handlers) == "table" then
        local orig_resize = handlers.resize
        handlers.resize = function(w, h, ...)
            lovemap.resize(w, h)
            if orig_resize then
                return orig_resize(w, h, ...)
            end
        end

        local orig_keypressed = handlers.keypressed
        handlers.keypressed = function(key, scancode, isrepeat, ...)
            if lovemap.keypressed(key) then
                return
            end
            if orig_keypressed then
                return orig_keypressed(key, scancode, isrepeat, ...)
            end
        end
    end

    -- Automatically bridge `love.draw` -> `lovemap.draw` if the user hasn't defined a custom `love.draw`
    if not love.draw then
        --- @diagnostic disable-next-line: duplicate-set-field
        love.draw = function()
            if type(lovemap.draw) == "function" then
                lovemap.render(lovemap.draw, lovemap.post_effect)
            end
        end
    end
end

--- Sets the virtual aspect ratio (e.g. `lovemap.aspect(16, 9)` -> 1600x900 game coordinates)
--- and installs automatic LÖVE hooks for `lovemap.draw()`, window resizing, and `F11`/`ESC` fullscreen.
--- Each aspect number maps to `* 100` game coordinates by default (customizable via `opts.unit_scale`).
--- @param w number Aspect width (e.g. 16)
--- @param h number Aspect height (e.g. 9)
--- @param opts? { unit_scale?: number, use_canvas?: boolean, filter?: "linear"|"nearest", background?: number[], border_color?: number[] }
--- @return number width, number height The resulting virtual game dimensions
function lovemap.aspect(w, h, opts)
    assert(type(w) == "number" and w > 0, "lovemap.aspect: width must be a positive number")
    assert(type(h) == "number" and h > 0, "lovemap.aspect: height must be a positive number")

    if type(opts) == "table" then
        if opts.unit_scale then lovemap.unit_scale = opts.unit_scale end
        if opts.use_canvas ~= nil then lovemap.use_canvas = opts.use_canvas end
        if opts.filter then lovemap.filter = opts.filter end
        if opts.background then lovemap.background = opts.background end
        if opts.border_color then lovemap.border_color = opts.border_color end
    end

    lovemap.aspect_w = w
    lovemap.aspect_h = h
    lovemap.width = math.floor(w * lovemap.unit_scale)
    lovemap.height = math.floor(h * lovemap.unit_scale)

    rebuildCanvas()
    lovemap.resize()
    installHooks()

    return lovemap.width, lovemap.height
end

--- Registers a callback invoked whenever `lovemap.resize()` or `lovemap.aspect()` runs.
--- @param fn fun(virtual_w: number, virtual_h: number, window_w: number, window_h: number)
function lovemap.onResize(fn)
    table.insert(lovemap._resize_listeners, fn)
end

--- Returns the virtual game dimensions (e.g. 1600, 900 for 16:9).
--- @return number width, number height
function lovemap.getDimensions()
    return lovemap.width, lovemap.height
end

--- Returns the virtual game width.
--- @return number width
function lovemap.getWidth()
    return lovemap.width
end

--- Returns the virtual game height.
--- @return number height
function lovemap.getHeight()
    return lovemap.height
end

--- Converts window pixel coordinates (e.g. from `love.mouse.getPosition()`) into virtual game coordinates.
--- Also returns `in_bounds` (`true` if the point lies inside the active game area rather than the black bars).
--- @param screen_x number Window X coordinate in pixels
--- @param screen_y number Window Y coordinate in pixels
--- @param clamp? boolean If true, clamps the returned coordinates to `[0, width]` and `[0, height]`
--- @return number game_x, number game_y, boolean in_bounds
function lovemap.toGame(screen_x, screen_y, clamp)
    local gx = (screen_x - lovemap.offset_x) / lovemap.scale
    local gy = (screen_y - lovemap.offset_y) / lovemap.scale
    local in_bounds = gx >= 0 and gx <= lovemap.width and gy >= 0 and gy <= lovemap.height

    if clamp then
        gx = math.max(0, math.min(lovemap.width, gx))
        gy = math.max(0, math.min(lovemap.height, gy))
    end

    return gx, gy, in_bounds
end

--- Converts virtual game coordinates into actual window pixel coordinates.
--- @param game_x number Virtual game X coordinate
--- @param game_y number Virtual game Y coordinate
--- @return number screen_x, number screen_y
function lovemap.toScreen(game_x, game_y)
    local sx = game_x * lovemap.scale + lovemap.offset_x
    local sy = game_y * lovemap.scale + lovemap.offset_y
    return sx, sy
end

--- Returns the current mouse position in virtual game coordinates.
--- @param clamp? boolean If true, clamps coordinates to the virtual game bounds
--- @return number game_x, number game_y, boolean in_bounds
function lovemap.getMousePosition(clamp)
    local mx, my = love.mouse.getPosition()
    return lovemap.toGame(mx, my, clamp)
end

--- Begins drawing in virtual game coordinates.
--- Pair with `lovemap.finish()`.
function lovemap.start()
    assert(not lovemap._active, "lovemap.start() called while already active")
    lovemap._active = true

    if lovemap.use_canvas then
        if not lovemap.canvas then
            rebuildCanvas()
        end
        lovemap._prev_canvas = love.graphics.getCanvas()
        love.graphics.setCanvas(lovemap.canvas)
        love.graphics.clear(lovemap.background)
        love.graphics.push("all")
        love.graphics.origin()
    else
        lovemap._prev_scissor = { love.graphics.getScissor() }
        love.graphics.clear(lovemap.border_color)
        love.graphics.push("all")
        love.graphics.setScissor(
            lovemap.offset_x,
            lovemap.offset_y,
            math.floor(lovemap.width * lovemap.scale),
            math.floor(lovemap.height * lovemap.scale)
        )
        love.graphics.clear(lovemap.background)
        love.graphics.translate(lovemap.offset_x, lovemap.offset_y)
        love.graphics.scale(lovemap.scale, lovemap.scale)
    end
end

--- Finishes drawing in virtual game coordinates and presents the scaled game area to the window.
--- @param post_effect? fun(draw_fn: fun()) Optional post-processing wrapper applied at window presentation
function lovemap.finish(post_effect)
    assert(lovemap._active, "lovemap.finish() called without lovemap.start()")
    lovemap._active = false

    love.graphics.pop()

    if lovemap.use_canvas then
        love.graphics.setCanvas(lovemap._prev_canvas)
        lovemap._prev_canvas = nil

        -- Clear the window border area
        love.graphics.clear(lovemap.border_color)

        local function presentCanvas()
            love.graphics.push("all")
            love.graphics.origin()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setBlendMode("alpha", "premultiplied")
            love.graphics.draw(
                lovemap.canvas,
                lovemap.offset_x,
                lovemap.offset_y,
                0,
                lovemap.scale,
                lovemap.scale
            )
            love.graphics.pop()
        end

        if type(post_effect) == "function" then
            post_effect(presentCanvas)
        else
            presentCanvas()
        end
    else
        if lovemap._prev_scissor and #lovemap._prev_scissor == 4 then
            love.graphics.setScissor(
                lovemap._prev_scissor[1],
                lovemap._prev_scissor[2],
                lovemap._prev_scissor[3],
                lovemap._prev_scissor[4]
            )
        else
            love.graphics.setScissor()
        end
        lovemap._prev_scissor = nil
    end
end

--- Renders `draw_fn` inside virtual game coordinates, optionally wrapped in a full-screen `effect`.
--- Used automatically by `lovemap` to invoke `function lovemap.draw()`.
--- @param draw_fn fun() Drawing callback operating in virtual game coordinates
--- @param effect? fun(fn: fun())|table Optional full-screen post-processing effect (defaults to `lovemap.post_effect`)
function lovemap.render(draw_fn, effect)
    effect = effect or lovemap.post_effect
    lovemap.start()
    if effect then
        lovemap.withVirtualMetrics(function()
            local prev_bg = { love.graphics.getBackgroundColor() }
            love.graphics.setBackgroundColor(lovemap.background)
            love.graphics.setColor(1, 1, 1, 1)
            effect(draw_fn)
            love.graphics.setBackgroundColor(prev_bg)
        end)
    else
        draw_fn()
    end
    lovemap.finish()
end

--- Toggles fullscreen mode and updates the virtual viewport mapping.
--- @return boolean is_fullscreen The new fullscreen state
function lovemap.toggleFullscreen()
    local is_fs = love.window.getFullscreen()
    love.window.setFullscreen(not is_fs, "desktop")
    lovemap.resize()
    return not is_fs
end

--- Exits fullscreen mode if currently in fullscreen.
--- @return boolean exited True if fullscreen was active and has now been exited, false if already windowed
function lovemap.exitFullscreen()
    if love.window.getFullscreen() then
        love.window.setFullscreen(false)
        lovemap.resize()
        return true
    end
    return false
end

--- Handles standard `lovemap` hotkeys:
--- - `f11`: Toggles fullscreen
--- - `escape`: Exits fullscreen if currently fullscreen (or quits the game if `quit_on_escape` is true and already windowed)
--- Automatically hooked into `love.handlers.keypressed` when `lovemap.aspect(...)` is called.
--- @param key love.KeyConstant
--- @param opts? { quit_on_escape?: boolean }
--- @return boolean handled True if `lovemap` consumed the key event
function lovemap.keypressed(key, opts)
    if key == "f11" then
        lovemap.toggleFullscreen()
        return true
    elseif key == "escape" then
        if lovemap.exitFullscreen() then
            return true
        elseif opts and opts.quit_on_escape then
            love.event.quit()
            return true
        end
    end
    return false
end

return lovemap
