-- Make root `src/` available when running `love examples/train_ride`
love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";../../?.lua;../../?/init.lua")
package.path = "../../?.lua;../../?/init.lua;" .. package.path

local lovemap = require("src.lovemap")

local t = 0
local speed = 320
local haze_shader
local smoke = {}
local stars = {}

-- Procedural deterministic pseudo-random helper
local function hash(n)
    return (math.sin(n * 12.9898 + 78.233) * 43758.5453) % 1
end

function love.load()
    lovemap.aspect(16, 9)

    -- Soft warm cinema vignette + glow on the sun and locomotive headlamp
    local fx = lovemap.setShaders("glow", "vignette")
    fx.glow.min_luma = 0.78
    fx.glow.strength = 6
    fx.vignette.radius = 0.95
    fx.vignette.opacity = 0.32

    -- Atmospheric depth-haze shader: blends distant layers toward the horizon haze color
    haze_shader = love.graphics.newShader([[
        extern number depth;
        extern vec3 haze_color;
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
            vec4 pixel = Texel(tex, uv) * color;
            vec3 blended = mix(pixel.rgb, haze_color, clamp(depth, 0.0, 0.92));
            return vec4(blended, pixel.a);
        }
    ]])
    haze_shader:send("haze_color", { 0.95, 0.68, 0.52 })

    for i = 1, 45 do
        stars[i] = { x = hash(i) * 1600, y = hash(i + 100) * 340, r = 1 + hash(i + 200) * 1.5 }
    end
end

function love.update(dt)
    if love.keyboard.isDown("right", "d") then
        speed = math.min(700, speed + 220 * dt)
    elseif love.keyboard.isDown("left", "a") then
        speed = math.max(80, speed - 220 * dt)
    end

    t = t + dt * (speed / 320)

    -- Spawn chugging steam puffs from the smokestack
    if math.random() < dt * (speed / 28) then
        table.insert(smoke, {
            x = 918,
            y = 620,
            vx = -speed * (0.55 + math.random() * 0.25),
            vy = -70 - math.random() * 45,
            r = 10 + math.random() * 8,
            age = 0,
            life = 2.4 + math.random() * 0.8,
        })
    end

    for i = #smoke, 1, -1 do
        local p = smoke[i]
        p.age = p.age + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy * (1 - 0.7 * dt)
        p.r = p.r + 24 * dt
        if p.age >= p.life then
            table.remove(smoke, i)
        end
    end
end

local function drawMountainLayer(scroll, base_y, amp, freq, col, seed)
    love.graphics.setColor(col)
    local step = 20
    local prev_x = 0
    local prev_y = base_y - math.abs(math.sin(scroll * freq + seed) * amp)
    for x = step, 1600, step do
        local wx = x + scroll
        local h = math.sin(wx * freq + seed) * amp
            + math.sin(wx * freq * 2.3 + seed * 2) * (amp * 0.42)
            + math.cos(wx * freq * 5.1 + seed * 3) * (amp * 0.16)
        local cur_y = base_y - math.abs(h)
        love.graphics.polygon("fill", prev_x, 900, prev_x, prev_y, x, cur_y, x, 900)
        prev_x, prev_y = x, cur_y
    end
end

local function drawFarmsAndHills(scroll)
    -- Rolling hills
    drawMountainLayer(scroll, 665, 65, 0.0028, { 0.24, 0.42, 0.28, 1.0 }, 4.2)

    -- Little farmhouses, barns, and windmills tucked into the hills
    local spacing = 420
    local first_i = math.floor(scroll / spacing) - 1
    for i = first_i, first_i + 6 do
        local wx = i * spacing
        local sx = wx - scroll
        local hy = 640 - math.abs(math.sin(wx * 0.0028 + 4.2) * 45)

        -- Red barn with pitched roof
        love.graphics.setColor(0.58, 0.22, 0.20, 1)
        love.graphics.rectangle("fill", sx, hy - 26, 46, 26)
        love.graphics.setColor(0.35, 0.16, 0.16, 1)
        love.graphics.polygon("fill", sx - 4, hy - 26, sx + 23, hy - 44, sx + 50, hy - 26)

        -- Warm glowing barn window
        love.graphics.setColor(1.0, 0.88, 0.48, 1)
        love.graphics.rectangle("fill", sx + 18, hy - 18, 10, 10)

        -- Silo & spinning windmill
        love.graphics.setColor(0.72, 0.70, 0.68, 1)
        love.graphics.rectangle("fill", sx + 52, hy - 42, 14, 42, 5, 5)
        local mx, my = sx - 38, hy - 38
        love.graphics.setLineWidth(2)
        love.graphics.line(mx - 8, hy, mx, my, mx + 8, hy)
        for b = 0, 3 do
            local ang = t * 1.4 + i + b * (math.pi * 0.5)
            love.graphics.line(mx, my, mx + math.cos(ang) * 18, my + math.sin(ang) * 18)
        end
    end
end

local function drawTreeLayer(scroll, base_y, spacing, scale, col)
    love.graphics.setColor(col)
    love.graphics.rectangle("fill", 0, base_y, 1600, 900 - base_y)
    local first_i = math.floor(scroll / spacing) - 1
    local count = math.ceil(1600 / spacing) + 3
    for i = first_i, first_i + count do
        local jitter = (hash(i * 17) - 0.5) * spacing * 0.55
        local sx = i * spacing + jitter - scroll
        local h = (58 + hash(i * 31) * 45) * scale
        local w = (24 + hash(i * 47) * 14) * scale

        -- Trunk
        love.graphics.setColor(col[1] * 0.55, col[2] * 0.45, col[3] * 0.4, 1)
        love.graphics.rectangle("fill", sx - 3 * scale, base_y - h * 0.25, 6 * scale, h * 0.28)

        -- Layered pine / deciduous canopy
        love.graphics.setColor(col)
        love.graphics.polygon("fill", sx - w, base_y - h * 0.2, sx, base_y - h * 0.75, sx + w, base_y - h * 0.2)
        love.graphics.polygon("fill", sx - w * 0.8, base_y - h * 0.5, sx, base_y - h, sx + w * 0.8, base_y - h * 0.5)
    end
end

local function drawSteamTrain(x, y, phase)
    local bob = math.sin(phase * 14) * 2.2
    local pitch = math.cos(phase * 14) * 0.006

    love.graphics.push()
    love.graphics.translate(x, y + bob)
    love.graphics.rotate(pitch)

    -- 2 Passenger Coaches + Tender + Locomotive
    for c = 0, 1 do
        local cx = -510 + c * 195
        love.graphics.setColor(0.34, 0.16, 0.15, 1)
        love.graphics.rectangle("fill", cx, -78, 175, 58, 6, 6)
        love.graphics.setColor(0.22, 0.11, 0.11, 1)
        love.graphics.rectangle("fill", cx - 6, -84, 187, 10, 4, 4)

        -- Warm illuminated coach windows
        love.graphics.setColor(1.0, 0.90, 0.55, 1)
        for w = 0, 4 do
            love.graphics.rectangle("fill", cx + 14 + w * 31, -66, 20, 22, 3, 3)
        end
        -- Coupler & wheels
        love.graphics.setColor(0.15, 0.15, 0.18, 1)
        love.graphics.rectangle("fill", cx + 175, -34, 20, 6)
        for _, wx in ipairs({ cx + 28, cx + 62, cx + 115, cx + 148 }) do
            love.graphics.circle("fill", wx, -14, 14)
            love.graphics.setColor(0.55, 0.52, 0.48, 1)
            love.graphics.circle("line", wx, -14, 14)
            love.graphics.setColor(0.15, 0.15, 0.18, 1)
        end
    end

    -- Coal Tender
    love.graphics.setColor(0.16, 0.17, 0.21, 1)
    love.graphics.polygon("fill", -110, -72, -30, -82, -20, -68, -115, -68)
    love.graphics.setColor(0.22, 0.24, 0.29, 1)
    love.graphics.rectangle("fill", -120, -70, 98, 50, 4, 4)
    love.graphics.setColor(0.78, 0.62, 0.26, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", -114, -64, 86, 38)

    -- Locomotive Cab, Boiler, Smokestack & Brass Domes
    love.graphics.setColor(0.20, 0.22, 0.27, 1)
    love.graphics.rectangle("fill", -10, -96, 68, 76, 4, 4) -- Cab
    love.graphics.setColor(0.14, 0.15, 0.18, 1)
    love.graphics.rectangle("fill", -16, -102, 80, 8, 3, 3) -- Cab Roof
    love.graphics.setColor(1.0, 0.85, 0.45, 1)
    love.graphics.rectangle("fill", 8, -84, 32, 26, 3, 3) -- Cab Firebox glow

    -- Boiler
    love.graphics.setColor(0.24, 0.26, 0.31, 1)
    love.graphics.rectangle("fill", 56, -78, 132, 54, 6, 6)
    love.graphics.setColor(0.78, 0.62, 0.26, 1) -- Brass bands & steam dome
    love.graphics.rectangle("fill", 85, -78, 5, 54)
    love.graphics.rectangle("fill", 135, -78, 5, 54)
    love.graphics.arc("fill", 110, -78, 16, math.pi, math.pi * 2)

    -- Smokestack
    love.graphics.setColor(0.18, 0.19, 0.23, 1)
    love.graphics.polygon("fill", 156, -78, 150, -118, 176, -118, 170, -78)

    -- Cowcatcher & Glowing Headlamp Beam
    love.graphics.setColor(0.35, 0.36, 0.40, 1)
    love.graphics.polygon("fill", 188, -24, 218, -8, 188, -8)
    love.graphics.setColor(1.0, 0.96, 0.78, 1)
    love.graphics.circle("fill", 190, -64, 8)
    love.graphics.setColor(1.0, 0.94, 0.68, 0.18)
    love.graphics.polygon("fill", 194, -68, 560, -155, 560, 15, 194, -60)

    -- Tender & Driving Wheels + Animated Connecting Rod
    local wheel_angle = phase * 14
    for _, wx in ipairs({ -94, -50 }) do
        love.graphics.setColor(0.18, 0.18, 0.22, 1)
        love.graphics.circle("fill", wx, -14, 14)
        love.graphics.setColor(0.65, 0.55, 0.35, 1)
        love.graphics.circle("line", wx, -14, 14)
    end

    local drivers = { 26, 76, 126 }
    local rod_x = math.cos(wheel_angle) * 13
    local rod_y = math.sin(wheel_angle) * 13
    for _, wx in ipairs(drivers) do
        love.graphics.setColor(0.18, 0.16, 0.18, 1)
        love.graphics.circle("fill", wx, -22, 22)
        love.graphics.setColor(0.82, 0.32, 0.24, 1)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", wx, -22, 22)
        love.graphics.line(wx, -22, wx + rod_x, -22 + rod_y)
    end
    love.graphics.setColor(0.82, 0.84, 0.88, 1)
    love.graphics.setLineWidth(5)
    love.graphics.line(drivers[1] + rod_x, -22 + rod_y, drivers[3] + rod_x, -22 + rod_y)

    love.graphics.pop()
end

function lovemap.draw()
    local dist = t * 320

    -- 0. Stationary twilight sky gradient, stars, and glowing setting sun (furthest back)
    for y = 0, 720, 8 do
        local k = y / 720
        love.graphics.setColor(
            0.14 + k * 0.82,
            0.16 + k * 0.48,
            0.34 + (1 - k) * 0.18,
            1.0
        )
        love.graphics.rectangle("fill", 0, y, 1600, 8)
    end
    love.graphics.setColor(1, 0.98, 0.9, 0.65)
    for _, s in ipairs(stars) do
        love.graphics.circle("fill", s.x, s.y, s.r)
    end
    -- Glowing sun disc (picked up by moonshine glow shader)
    love.graphics.setColor(1.0, 0.88, 0.58, 1.0)
    love.graphics.circle("fill", 1240, 340, 88)

    -- 5 Background Parallax Layers with progressive atmospheric haze shader (depth: 0.78 -> 0.10)
    lovemap.withEffect(haze_shader, { depth = 0.78 }, function()
        drawMountainLayer(dist * 0.04, 540, 210, 0.0018, { 0.22, 0.20, 0.36, 1.0 }, 1.1)
    end)
    lovemap.withEffect(haze_shader, { depth = 0.56 }, function()
        drawMountainLayer(dist * 0.10, 595, 155, 0.0024, { 0.25, 0.24, 0.38, 1.0 }, 2.7)
    end)
    lovemap.withEffect(haze_shader, { depth = 0.36 }, function()
        drawFarmsAndHills(dist * 0.22)
    end)
    lovemap.withEffect(haze_shader, { depth = 0.22 }, function()
        drawTreeLayer(dist * 0.42, 680, 78, 0.85, { 0.16, 0.30, 0.22, 1.0 })
    end)
    lovemap.withEffect(haze_shader, { depth = 0.10 }, function()
        drawTreeLayer(dist * 0.68, 725, 115, 1.15, { 0.11, 0.22, 0.16, 1.0 })
    end)

    -- Ballast embankment, sleepers & steel rails (1.0x reference speed)
    love.graphics.setColor(0.20, 0.18, 0.17, 1)
    love.graphics.rectangle("fill", 0, 750, 1600, 150)
    local tie_offset = (dist * 1.0) % 28
    love.graphics.setColor(0.32, 0.22, 0.15, 1)
    for x = -tie_offset, 1620, 28 do
        love.graphics.rectangle("fill", x, 748, 14, 10)
    end
    love.graphics.setColor(0.72, 0.74, 0.78, 1)
    love.graphics.rectangle("fill", 0, 743, 1600, 5)

    -- Steam Puffs
    for _, p in ipairs(smoke) do
        local alpha = (1 - p.age / p.life) * 0.55
        love.graphics.setColor(0.94, 0.88, 0.84, alpha)
        love.graphics.circle("fill", p.x, p.y, p.r)
    end

    -- Stationary (screen-relative) bobbing steam train
    drawSteamTrain(760, 743, t)

    -- Foreground Parallax Layer 1 (1.35x speed): Telegraph poles & sagging wires
    local pole_spacing = 520
    local pole_scroll = dist * 1.35
    local first_p = math.floor(pole_scroll / pole_spacing) - 1
    love.graphics.setColor(0.08, 0.07, 0.09, 1)
    for i = first_p, first_p + 5 do
        local px = i * pole_spacing - pole_scroll
        local nx = (i + 1) * pole_spacing - pole_scroll
        love.graphics.rectangle("fill", px - 5, 410, 10, 490)
        love.graphics.rectangle("fill", px - 28, 435, 56, 7)
        love.graphics.rectangle("fill", px - 22, 465, 44, 6)
        love.graphics.setLineWidth(2)
        for _, wy in ipairs({ 435, 465 }) do
            local mx = (px + nx) * 0.5
            love.graphics.line(px, wy, mx, wy + 22, nx, wy)
        end
    end

    -- Foreground Parallax Layer 2 (2.15x speed): Silhouetted bushes & milepost markers rushing past
    local fg_spacing = 260
    local fg_scroll = dist * 2.15
    local first_f = math.floor(fg_scroll / fg_spacing) - 1
    love.graphics.setColor(0.04, 0.05, 0.07, 1)
    love.graphics.rectangle("fill", 0, 845, 1600, 55)
    for i = first_f, first_f + 8 do
        local fx = i * fg_spacing - fg_scroll
        love.graphics.circle("fill", fx, 850, 38 + (i % 3) * 14)
        love.graphics.circle("fill", fx + 34, 858, 28)
    end

    -- Minimal HUD
    love.graphics.setColor(1, 0.95, 0.85, 0.85)
    love.graphics.print(
        string.format("Train Ride | Speed: %.0f km/h (Left/Right Arrows to adjust) | F11: Fullscreen", speed * 0.25),
        28,
        24
    )
end
