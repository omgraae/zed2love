-- Example 6: Shadermaxxing — Isometric 3D Ball Maze Showcase
-- Demonstrates lovemap + embedded Moonshine full-screen shader chain (glow, motionblur,
-- screenshake, chromasep, vignette, filmgrain) + per-object custom GLSL shaders
-- (3D rolling sphere, fog-of-war mist desaturation, 360° raytraced 8-segment light cone,
-- molten magma vents, swirling dimensional exit portal).

love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";../../?.lua;../../?/init.lua")
package.path = "../../?.lua;../../?/init.lua;" .. package.path

local lovemap = require("src.lovemap")

-- Virtual screen center: the ball is ALWAYS fixed at the middle of the screen
local CENTER_X = 800
local CENTER_Y = 450

-- Top-down isometric tile geometry
local ISO_W = 112
local ISO_H = 56
local WALL_H = 38

-- 360° Raytraced Visibility Constants
local MAX_SIGHT = 8.0   -- Strictly capped at 8 maze segments
local NUM_RAYS = 288    -- Smooth 360° visibility fan

-- Ball physics constants
local BALL_R = 0.27
local BALL_ACCEL = 11.5
local BALL_BRAKE = 7.5
local BALL_DRAG = 0.55      -- Low rolling drag so the ball picks up speed down corridors
local BALL_MAX_SPEED = 9.5

-- Game State
local level = 1
local maze_w, maze_h = 23, 23
local maze = {}           -- 1 = wall, 0 = open corridor
local explored = {}       -- true once ever seen within 8 segments
local vis_light = {}      -- 0..1 live visibility intensity this frame
local hazards = {}        -- keyed by "cx,cy" -> hazard table
local pickups = {}        -- shield energy orbs keyed by "cx,cy"
local start_gx, start_gy = 2, 2
local exit_gx, exit_gy = 2, 2

local ball = {
    x = 2.5,
    y = 2.5,
    vx = 0,
    vy = 0,
    speed = 0,
    hp = 5,
    max_hp = 5,
    invuln = 0,
    hit_flash = 0,
    -- 3D orthonormal orientation basis for true rolling sphere rendering
    ux = { 1, 0, 0 },
    uy = { 0, 1, 0 },
    uz = { 0, 0, 1 },
}

-- Dynamic shader feedback state
local shake_intensity = 0
local chroma_intensity = 0
local blur_dir_x, blur_dir_y = 0, 0
local blur_strength = 0
local damage_vignette = 0
local level_clear_timer = 0
local game_state = "playing" -- "playing" | "gameover"
local show_telemetry = true
local run_time = 0
local orbs_collected = 0
local total_explored = 0
local total_floor_tiles = 1

-- Visual particles (sparks, trail embers, shield bursts)
local particles = {}

-- Shaders, textures, meshes, fonts
local post_fx
local white_tex
local ball_shader
local fog_tile_shader
local magma_shader
local portal_shader
local light_cone_shader
local light_mesh
local ray_pts = {}

local font_sm, font_md, font_lg, font_xl

-- ============================================================================
-- Helpers & Isometric Math
-- ============================================================================

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function tileKey(cx, cy)
    return cx .. "," .. cy
end

--- Project world grid position (wx, wy, wz) into screen space with the ball locked at center.
local function worldToScreen(wx, wy, wz)
    local dx = wx - ball.x
    local dy = wy - ball.y
    local sx = CENTER_X + (dx - dy) * (ISO_W * 0.5)
    local sy = CENTER_Y + (dx + dy) * (ISO_H * 0.5) - (wz or 0)
    return sx, sy
end

--- Project world velocity (vx, vy) into screen-space velocity (svx, svy).
local function worldVelToScreen(vx, vy)
    return (vx - vy) * (ISO_W * 0.5), (vx + vy) * (ISO_H * 0.5)
end

--- Rotate a 3D vector v around unit axis k by angle theta (Rodrigues' formula).
local function rotateVec3(v, kx, ky, kz, theta)
    local c = math.cos(theta)
    local s = math.sin(theta)
    local vx, vy, vz = v[1], v[2], v[3]
    local dot = kx * vx + ky * vy + kz * vz
    local cx = ky * vz - kz * vy
    local cy = kz * vx - kx * vz
    local cz = kx * vy - ky * vx
    local omc = 1 - c
    return {
        vx * c + cx * s + kx * dot * omc,
        vy * c + cy * s + ky * dot * omc,
        vz * c + cz * s + kz * dot * omc,
    }
end

local function norm3(v)
    local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    if l < 1e-6 then return { 1, 0, 0 } end
    return { v[1] / l, v[2] / l, v[3] / l }
end

local function cross3(a, b)
    return {
        a[2] * b[3] - a[3] * b[2],
        a[3] * b[1] - a[1] * b[3],
        a[1] * b[2] - a[2] * b[1],
    }
end

local function spawnSparks(wx, wy, count, r, g, b, spd_scale)
    spd_scale = spd_scale or 1.0
    for _ = 1, count do
        local ang = love.math.random() * math.pi * 2
        local spd = (1.8 + love.math.random() * 4.2) * spd_scale
        table.insert(particles, {
            x = wx,
            y = wy,
            z = 8 + love.math.random() * 14,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd,
            vz = 30 + love.math.random() * 65,
            life = 0.25 + love.math.random() * 0.35,
            max_life = 0.6,
            r = r,
            g = g,
            b = b,
            size = 2.5 + love.math.random() * 3.0,
        })
    end
end

-- ============================================================================
-- Autogenerated Guaranteed-Completable Maze + Hazards
-- ============================================================================

local function isWall(cx, cy)
    if cx < 1 or cy < 1 or cx > maze_w or cy > maze_h then
        return true
    end
    return maze[cx][cy] == 1
end

local function bfsDistances(sx, sy)
    local dist = {}
    for x = 1, maze_w do
        dist[x] = {}
    end
    local qx, qy = { sx }, { sy }
    local head = 1
    dist[sx][sy] = 0
    local farthest_x, farthest_y, farthest_d = sx, sy, 0
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

    while head <= #qx do
        local cx, cy = qx[head], qy[head]
        head = head + 1
        local d = dist[cx][cy]
        if d > farthest_d then
            farthest_d = d
            farthest_x, farthest_y = cx, cy
        end
        for _, dir in ipairs(dirs) do
            local nx, ny = cx + dir[1], cy + dir[2]
            if not isWall(nx, ny) and not dist[nx][ny] then
                dist[nx][ny] = d + 1
                qx[#qx + 1] = nx
                qy[#qy + 1] = ny
            end
        end
    end

    return dist, farthest_x, farthest_y, farthest_d
end

local function generateMaze(lvl)
    -- Scale maze cleanly per level (always odd dimensions)
    maze_w = math.min(35, 21 + (lvl - 1) * 4)
    maze_h = maze_w
    if maze_w % 2 == 0 then
        maze_w = maze_w + 1
        maze_h = maze_w
    end

    maze = {}
    explored = {}
    vis_light = {}
    hazards = {}
    pickups = {}
    particles = {}

    for x = 1, maze_w do
        maze[x] = {}
        explored[x] = {}
        vis_light[x] = {}
        for y = 1, maze_h do
            maze[x][y] = 1
            explored[x][y] = false
            vis_light[x][y] = 0
        end
    end

    -- Iterative Randomized Depth-First Search (Recursive Backtracker)
    -- Guarantees a spanning tree connecting every odd cell (100% reachable).
    start_gx, start_gy = 2, 2
    maze[start_gx][start_gy] = 0
    local stack = { { start_gx, start_gy, 0 } } -- x, y, last_dir_idx
    local dirs = { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }

    while #stack > 0 do
        local top = stack[#stack]
        local cx, cy, last_d = top[1], top[2], top[3]
        local candidates = {}

        for i = 1, 4 do
            local nx = cx + dirs[i][1]
            local ny = cy + dirs[i][2]
            if nx >= 2 and ny >= 2 and nx <= maze_w - 1 and ny <= maze_h - 1 and maze[nx][ny] == 1 then
                candidates[#candidates + 1] = i
                -- Slight bias to keep going straight to create thrilling >8-segment corridors!
                if i == last_d and love.math.random() < 0.55 then
                    candidates[#candidates + 1] = i
                    candidates[#candidates + 1] = i
                end
            end
        end

        if #candidates > 0 then
            local pick = candidates[love.math.random(#candidates)]
            local dx, dy = dirs[pick][1], dirs[pick][2]
            maze[cx + dx * 0.5][cy + dy * 0.5] = 0
            maze[cx + dx][cy + dy] = 0
            stack[#stack + 1] = { cx + dx, cy + dy, pick }
        else
            stack[#stack] = nil
        end
    end

    -- Carve a controlled percentage of braided loops so rolling at speed has alternate routes
    local extra_openings = math.floor(maze_w * maze_h * 0.045)
    for _ = 1, extra_openings do
        local x = love.math.random(2, maze_w - 1)
        local y = love.math.random(2, maze_h - 1)
        if maze[x][y] == 1 then
            local horiz = (maze[x - 1][y] == 0 and maze[x + 1][y] == 0 and maze[x][y - 1] == 1 and maze[x][y + 1] == 1)
            local vert  = (maze[x][y - 1] == 0 and maze[x][y + 1] == 0 and maze[x - 1][y] == 1 and maze[x + 1][y] == 1)
            if horiz or vert then
                maze[x][y] = 0
            end
        end
    end

    -- Verify connectivity via BFS and place Exit at the farthest reachable cell
    local dist, fx, fy = bfsDistances(start_gx, start_gy)
    exit_gx, exit_gy = fx, fy

    -- Fallback safety assertion: exit must be reachable (guaranteed by spanning tree)
    assert(dist[exit_gx][exit_gy] ~= nil, "Generated maze failed reachability check")

    -- Count floor tiles and populate passable/timed hazards & traps
    total_floor_tiles = 0
    total_explored = 0

    for x = 2, maze_w - 1 do
        for y = 2, maze_h - 1 do
            if maze[x][y] == 0 then
                total_floor_tiles = total_floor_tiles + 1
                local d = dist[x][y] or 0
                local is_start_zone = (d <= 2)
                local is_exit_zone = (math.abs(x - exit_gx) + math.abs(y - exit_gy) <= 1)

                if not is_start_zone and not is_exit_zone then
                    local open_n = (maze[x + 1][y] == 0 and 1 or 0)
                                 + (maze[x - 1][y] == 0 and 1 or 0)
                                 + (maze[x][y + 1] == 0 and 1 or 0)
                                 + (maze[x][y - 1] == 0 and 1 or 0)

                    local roll = love.math.random()
                    local key = tileKey(x, y)

                    if open_n == 1 and roll < 0.42 then
                        -- Dead-end reward: glowing shield recharge orb
                        pickups[key] = { x = x, y = y, phase = love.math.random() * 6.28, taken = false }
                    elseif open_n >= 3 and roll < 0.24 then
                        -- Junction repulsor bumper (small kinetic orb in junction center, never blocks passage)
                        hazards[key] = {
                            kind = "bumper",
                            x = x,
                            y = y,
                            phase = love.math.random() * 6.28,
                            pulse = 0,
                        }
                    elseif open_n == 2 then
                        local horiz = (maze[x - 1][y] == 0 and maze[x + 1][y] == 0)
                        local vert  = (maze[x][y - 1] == 0 and maze[x][y + 1] == 0)
                        if (horiz or vert) and roll < (0.14 + math.min(0.08, lvl * 0.015)) then
                            local pick_h = love.math.random()
                            if pick_h < 0.30 then
                                -- Timed retractable spikes
                                hazards[key] = {
                                    kind = "spikes",
                                    x = x,
                                    y = y,
                                    period = 2.6 + love.math.random() * 0.8,
                                    phase = love.math.random() * 6.28,
                                }
                            elseif pick_h < 0.56 then
                                -- Pulsing laser barrier (always cycles OFF so path stays completable)
                                hazards[key] = {
                                    kind = "laser",
                                    x = x,
                                    y = y,
                                    axis = horiz and "y" or "x",
                                    period = 3.2 + love.math.random() * 0.9,
                                    phase = love.math.random() * 6.28,
                                }
                            elseif pick_h < 0.80 then
                                -- Molten plasma / magma vent (shader-rendered, cycles safe/active)
                                hazards[key] = {
                                    kind = "magma",
                                    x = x,
                                    y = y,
                                    period = 3.6 + love.math.random() * 1.0,
                                    phase = love.math.random() * 6.28,
                                }
                            else
                                -- Turbo boost pad! Accelerates ball down the straightaway
                                local bdx, bdy = 0, 0
                                if horiz then
                                    bdx = (love.math.random() < 0.5) and 1 or -1
                                else
                                    bdy = (love.math.random() < 0.5) and 1 or -1
                                end
                                hazards[key] = {
                                    kind = "boost",
                                    x = x,
                                    y = y,
                                    dx = bdx,
                                    dy = bdy,
                                    phase = love.math.random() * 6.28,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Place ball cleanly at center of start cell
    ball.x = start_gx + 0.5
    ball.y = start_gy + 0.5
    ball.vx = 0
    ball.vy = 0
    ball.speed = 0
    ball.invuln = 0.8
    ball.hit_flash = 0
    ball.ux = { 1, 0, 0 }
    ball.uy = { 0, 1, 0 }
    ball.uz = { 0, 0, 1 }

    shake_intensity = 0
    chroma_intensity = 0
    blur_strength = 0
    damage_vignette = 0
    level_clear_timer = 0
end

local function restartGame()
    level = 1
    ball.hp = ball.max_hp
    run_time = 0
    orbs_collected = 0
    game_state = "playing"
    generateMaze(level)
end

-- ============================================================================
-- 360° DDA Raytraced Visibility (Clamped to MAX_SIGHT = 8.0 Segments)
-- ============================================================================

local function sightFalloff(dist)
    if dist >= MAX_SIGHT then return 0 end
    local u = dist / MAX_SIGHT
    -- Bright & crisp up close, falling smoothly into deep shadow right at 8 segments
    return clamp(1.0 - math.pow(u, 2.2), 0, 1)
end

local function computeVisibility()
    -- Clear previous frame's live visibility in the local window around the ball
    local bx = math.floor(ball.x)
    local by = math.floor(ball.y)
    local rad = math.ceil(MAX_SIGHT) + 2
    local x0 = math.max(1, bx - rad)
    local x1 = math.min(maze_w, bx + rad)
    local y0 = math.max(1, by - rad)
    local y1 = math.min(maze_h, by + rad)

    for x = x0, x1 do
        local col = vis_light[x]
        for y = y0, y1 do
            col[y] = 0
        end
    end

    local function markCell(cx, cy, dist)
        if cx < 1 or cy < 1 or cx > maze_w or cy > maze_h then return end
        local f = sightFalloff(dist)
        if f > vis_light[cx][cy] then
            vis_light[cx][cy] = f
        end
        -- Reveal into permanent explored memory once clearly glimpsed (keeps the 7..8 tip dark until approached)
        if f > 0.24 and not explored[cx][cy] then
            explored[cx][cy] = true
            if maze[cx][cy] == 0 then
                total_explored = total_explored + 1
            end
        end
    end

    markCell(bx, by, 0)

    -- 288-ray 360° Amanatides-Woo DDA grid traversal
    for i = 1, NUM_RAYS do
        local ang = ((i - 1) / NUM_RAYS) * math.pi * 2
        local rdx = math.cos(ang)
        local rdy = math.sin(ang)

        local cx, cy = bx, by
        local step_x = rdx >= 0 and 1 or -1
        local step_y = rdy >= 0 and 1 or -1

        local delta_x = (math.abs(rdx) < 1e-6) and 1e9 or math.abs(1.0 / rdx)
        local delta_y = (math.abs(rdy) < 1e-6) and 1e9 or math.abs(1.0 / rdy)

        local t_max_x = (rdx >= 0) and ((cx + 1.0 - ball.x) * delta_x) or ((ball.x - cx) * delta_x)
        local t_max_y = (rdy >= 0) and ((cy + 1.0 - ball.y) * delta_y) or ((ball.y - cy) * delta_y)

        local hit_dist = MAX_SIGHT
        local t = 0

        for _ = 1, 24 do
            if t_max_x < t_max_y then
                t = t_max_x
                t_max_x = t_max_x + delta_x
                cx = cx + step_x
            else
                t = t_max_y
                t_max_y = t_max_y + delta_y
                cy = cy + step_y
            end

            if t >= MAX_SIGHT then
                hit_dist = MAX_SIGHT
                break
            end

            markCell(cx, cy, t)

            if isWall(cx, cy) then
                hit_dist = t
                break
            end
        end

        ray_pts[i] = {
            wx = ball.x + rdx * hit_dist,
            wy = ball.y + rdy * hit_dist,
            frac = hit_dist / MAX_SIGHT,
        }
    end
end

-- ============================================================================
-- Hazard Cycle Evaluation & Damage Handling
-- ============================================================================

--- Returns state ("off" | "warn" | "active") and 0..1 intensity for a cyclic hazard.
local function getHazardState(h, now)
    if h.kind == "bumper" or h.kind == "boost" then
        return "active", 1.0
    end
    local p = h.period or 3.0
    local cyc = ((now + h.phase) % p) / p
    if h.kind == "spikes" then
        if cyc < 0.52 then return "off", 0.0
        elseif cyc < 0.68 then return "warn", (cyc - 0.52) / 0.16
        else return "active", 1.0 end
    elseif h.kind == "laser" then
        if cyc < 0.50 then return "off", 0.0
        elseif cyc < 0.66 then return "warn", (cyc - 0.50) / 0.16
        else return "active", 1.0 end
    elseif h.kind == "magma" then
        if cyc < 0.48 then return "off", 0.0
        elseif cyc < 0.68 then return "warn", (cyc - 0.48) / 0.20
        else return "active", 1.0 end
    end
    return "off", 0.0
end

local function triggerImpact(strength, r, g, b)
    -- Subtle scaled screen shake + chromatic split on high-speed impacts
    shake_intensity = math.min(18, math.max(shake_intensity, strength * 1.45))
    chroma_intensity = math.min(12, math.max(chroma_intensity, strength * 0.95))
    spawnSparks(ball.x, ball.y, math.floor(8 + strength * 2.2), r or 1.0, g or 0.78, b or 0.35, 0.7 + strength * 0.1)
end

local function hurtBall(knock_vx, knock_vy)
    if ball.invuln > 0 or game_state ~= "playing" then return end
    ball.hp = math.max(0, ball.hp - 1)
    ball.invuln = 1.15
    ball.hit_flash = 1.0
    damage_vignette = 1.0
    ball.vx = knock_vx
    ball.vy = knock_vy
    triggerImpact(10.5, 1.0, 0.25, 0.22)
    if ball.hp <= 0 then
        game_state = "gameover"
        ball.vx = 0
        ball.vy = 0
    end
end

-- ============================================================================
-- Ball Physics & Wall Circle-vs-AABB Collision
-- ============================================================================

local function resolveWallCollisions()
    local bx = math.floor(ball.x)
    local by = math.floor(ball.y)
    local max_impact = 0

    for cx = bx - 1, bx + 1 do
        for cy = by - 1, by + 1 do
            if isWall(cx, cy) then
                local closest_x = clamp(ball.x, cx, cx + 1)
                local closest_y = clamp(ball.y, cy, cy + 1)
                local dx = ball.x - closest_x
                local dy = ball.y - closest_y
                local dist2 = dx * dx + dy * dy

                if dist2 < BALL_R * BALL_R then
                    local dist = math.sqrt(dist2)
                    local nx, ny
                    if dist > 1e-5 then
                        nx, ny = dx / dist, dy / dist
                    else
                        nx, ny = 0, -1
                    end
                    local pen = BALL_R - dist
                    ball.x = ball.x + nx * pen
                    ball.y = ball.y + ny * pen

                    local vn = ball.vx * nx + ball.vy * ny
                    if vn < 0 then
                        local impact_speed = -vn
                        if impact_speed > max_impact then
                            max_impact = impact_speed
                        end
                        -- Elastic-ish bounce off walls; grazing walls preserves tangential speed
                        local restitution = impact_speed > 2.0 and 0.58 or 0.25
                        ball.vx = ball.vx - (1 + restitution) * vn * nx
                        ball.vy = ball.vy - (1 + restitution) * vn * ny
                    end
                end
            end
        end
    end

    -- Trigger subtle screen shake shader when hitting an obstacle at speed!
    if max_impact > 1.85 then
        local shake_mag = clamp((max_impact - 1.5) * 1.15, 0.8, 10.5)
        triggerImpact(shake_mag, 0.45, 0.88, 1.0)
    end
end

-- ============================================================================
-- LÖVE Lifecycle & Shader Compilation
-- ============================================================================

function love.load()
    lovemap.aspect(16, 9, {
        title = "zed2love — 6. Shadermaxxing",
        background = { 0.02, 0.025, 0.04, 1 },
    })

    font_sm = love.graphics.newFont(15)
    font_md = love.graphics.newFont(19)
    font_lg = love.graphics.newFont(28)
    font_xl = love.graphics.newFont(44)

    -- 2x2 white texture for clean 0..1 UVs on custom fragment shaders
    local id = love.image.newImageData(2, 2)
    id:mapPixel(function() return 1, 1, 1, 1 end)
    white_tex = love.graphics.newImage(id)

    -- Full-screen Moonshine shader chain showcasing our embedded shaders + new screenshake & motionblur!
    post_fx = lovemap.setShaders(
        "glow",
        "motionblur",
        "screenshake",
        "chromasep",
        "vignette",
        "filmgrain"
    )
    post_fx.glow.min_luma = 0.62
    post_fx.glow.strength = 4.0
    post_fx.motionblur.strength = 0
    post_fx.motionblur.center_protect = 0.22
    post_fx.screenshake.intensity = 0
    post_fx.screenshake.frequency = 44
    post_fx.chromasep.radius = 0
    post_fx.vignette.radius = 0.88
    post_fx.vignette.softness = 0.48
    post_fx.vignette.opacity = 0.52
    post_fx.vignette.color = { 0.02, 0.03, 0.06 }
    post_fx.filmgrain.opacity = 0.055
    post_fx.filmgrain.size = 1.5

    -- 1. Custom GLSL 3D Rolling Sphere Shader (procedural metallic/energy orb with true 3D roll)
    ball_shader = love.graphics.newShader([[
        extern vec3 u_x;
        extern vec3 u_y;
        extern vec3 u_z;
        extern number time;
        extern number speed_norm;
        extern number hit_flash;

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
            vec2 p = (tc - vec2(0.5)) * 2.0;
            number r2 = dot(p, p);
            if (r2 > 1.0) { discard; }

            number z = sqrt(max(0.0, 1.0 - r2));
            // Flip y so screen-up is +y on sphere surface
            vec3 N = normalize(vec3(p.x, -p.y, z));

            // Transform normal into ball's 3D rolling local frame
            vec3 L = normalize(vec3(dot(N, u_x), dot(N, u_y), dot(N, u_z)));

            // Procedural 3D globe/energy bands so rotation in every axis is unmistakable
            number band_x = smoothstep(0.90, 0.96, 1.0 - abs(L.x));
            number band_y = smoothstep(0.90, 0.96, 1.0 - abs(L.y));
            number band_z = smoothstep(0.90, 0.96, 1.0 - abs(L.z));
            number energy_ring = max(max(band_x, band_y), band_z);

            // Subtle faceted panel pattern on the sphere shell
            number panel = 0.5 + 0.5 * sin(L.x * 12.0) * sin(L.y * 12.0) * sin(L.z * 12.0);
            number pole_dot = smoothstep(0.86, 0.94, max(max(abs(L.x), abs(L.y)), abs(L.z)));

            vec3 shell_base = mix(vec3(0.11, 0.16, 0.25), vec3(0.24, 0.34, 0.48), panel);
            vec3 energy_col = mix(vec3(0.18, 0.92, 1.0), vec3(1.0, 0.58, 0.16), clamp(speed_norm, 0.0, 1.0));
            vec3 albedo = mix(shell_base, energy_col, energy_ring * 0.85);
            albedo = mix(albedo, vec3(1.0, 0.95, 0.72), pole_dot * 0.65);

            // 3D Lighting: warm key light + cool fill + crisp specular + Fresnel rim
            vec3 light_dir = normalize(vec3(-0.52, 0.62, 0.58));
            vec3 view_dir  = vec3(0.0, 0.0, 1.0);
            vec3 half_vec  = normalize(light_dir + view_dir);

            number diff = max(dot(N, light_dir), 0.0);
            number spec = pow(max(dot(N, half_vec), 0.0), 42.0);
            number rim  = pow(1.0 - clamp(N.z, 0.0, 1.0), 2.8);

            vec3 lit = albedo * (0.28 + 0.78 * diff);
            lit += energy_col * energy_ring * (0.55 + 0.45 * speed_norm);
            lit += vec3(0.95, 0.98, 1.0) * spec * 0.95;
            lit += energy_col * rim * (0.65 + 0.5 * speed_norm);

            // Crimson flash when taking damage
            lit = mix(lit, vec3(1.0, 0.25, 0.2), clamp(hit_flash, 0.0, 1.0) * 0.8);

            // Crisp anti-aliased sphere silhouette
            number aa = 1.0 - smoothstep(0.94, 1.0, sqrt(r2));
            return vec4(lit, aa * color.a);
        }
    ]])

    -- 2. Custom GLSL Fog-of-War Shader for previously explored (out-of-sight) maze geometry
    fog_tile_shader = love.graphics.newShader([[
        extern number time;
        extern vec2 cam_scroll;

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 c = Texel(tex, tc) * color;
            number luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
            vec2 p = (sc + cam_scroll) * 0.007;
            number mist1 = sin(p.x * 2.3 + time * 0.55 + cos(p.y * 1.8 - time * 0.35));
            number mist2 = cos(p.x * 4.1 - p.y * 3.2 - time * 0.4);
            number mist = 0.5 + 0.28 * mist1 + 0.22 * mist2;
            vec3 gray = vec3(luma * 0.42 + 0.06);
            vec3 fog_tint = vec3(0.14, 0.16, 0.20) * (0.8 + 0.45 * mist);
            vec3 final_col = mix(gray, fog_tint, 0.48);
            return vec4(final_col, c.a);
        }
    ]])

    -- 3. Custom GLSL Molten Magma / Plasma Vent Shader
    magma_shader = love.graphics.newShader([[
        extern number time;
        extern number heat;
        extern number seed;

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
            // Map square UV into an isometric diamond mask
            vec2 p = abs(tc - vec2(0.5)) * 2.0;
            number dia = p.x + p.y;
            if (dia > 0.92) { discard; }

            vec2 uv = tc * 6.5 + vec2(seed, seed * 0.7);
            number w = sin(uv.x + time * 2.2) * cos(uv.y - time * 1.8)
                     + 0.5 * sin(uv.x * 2.1 - uv.y * 1.9 + time * 3.1);
            number veins = smoothstep(0.15, 0.85, 0.5 + 0.5 * w);

            vec3 crust = vec3(0.14, 0.10, 0.12);
            vec3 ember = mix(vec3(0.85, 0.20, 0.04), vec3(1.0, 0.86, 0.28), veins);
            vec3 col = mix(crust, ember, clamp(heat * (0.45 + 0.75 * veins), 0.0, 1.0));

            number edge = 1.0 - smoothstep(0.76, 0.92, dia);
            return vec4(col * color.rgb, edge * color.a);
        }
    ]])

    -- 4. Custom GLSL Dimensional Exit Portal Vortex Shader
    portal_shader = love.graphics.newShader([[
        extern number time;

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
            vec2 p = (tc - vec2(0.5)) * 2.0;
            number r = length(p);
            if (r > 1.0) { discard; }

            number ang = atan(p.y, p.x + 0.0001);
            number swirl = sin(ang * 5.0 - time * 4.5 + r * 10.0) * 0.5 + 0.5;
            number rings = sin(r * 16.0 - time * 6.0) * 0.5 + 0.5;

            vec3 inner = vec3(0.88, 1.0, 0.96);
            vec3 mid   = vec3(0.12, 0.92, 0.78);
            vec3 outer = vec3(0.28, 0.35, 0.98);

            vec3 col = mix(outer, mid, swirl);
            col = mix(col, inner, pow(1.0 - r, 2.2) + rings * 0.25);

            number alpha = (1.0 - smoothstep(0.72, 1.0, r)) * (0.78 + 0.22 * swirl);
            return vec4(col * color.rgb, alpha * color.a);
        }
    ]])

    -- 5. Custom GLSL 360° Raytraced 8-Segment Volumetric Light Cone Shader
    light_cone_shader = love.graphics.newShader([[
        extern number time;
        extern number speed_norm;

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
            // tc.x stores normalized ray distance (0 at ball center -> 1 at 8-segment max range)
            number d = clamp(tc.x, 0.0, 1.0);
            number falloff = pow(1.0 - d, 2.1);
            number pulse = 0.93 + 0.07 * sin(time * 3.8);
            vec3 glow_col = mix(vec3(0.24, 0.78, 1.0), vec3(1.0, 0.68, 0.28), speed_norm * 0.65);
            return vec4(glow_col, falloff * 0.20 * pulse) * color;
        }
    ]])

    -- Reusable triangle-fan mesh for the 360° raytraced visibility polygon (zero per-frame allocs)
    light_mesh = love.graphics.newMesh(NUM_RAYS + 2, "fan", "stream")
    light_mesh:setTexture(white_tex)

    generateMaze(level)
    computeVisibility()
end

function love.update(dt)
    dt = math.min(dt, 0.05)
    local now = love.timer.getTime()

    -- Handle gameover Y/N polling too for rock-solid WASM keyboard responsiveness
    if game_state == "gameover" then
        if love.keyboard.isDown("y", "r") then
            restartGame()
            return
        elseif love.keyboard.isDown("n") then
            love.event.quit()
            return
        end
    end

    if game_state == "playing" then
        run_time = run_time + dt

        -- 1. Screen-aligned controls mapped smoothly into isometric world axes
        local ix, iy = 0, 0
        if love.keyboard.isDown("right", "d") then ix = ix + 1 end
        if love.keyboard.isDown("left",  "a") then ix = ix - 1 end
        if love.keyboard.isDown("down",  "s") then iy = iy + 1 end
        if love.keyboard.isDown("up",    "w") then iy = iy - 1 end

        -- Optional mouse steering (hold left button to roll toward cursor)
        if ix == 0 and iy == 0 and love.mouse.isDown(1) then
            local mx, my = lovemap.getMousePosition(true)
            local mdx = mx - CENTER_X
            local mdy = my - CENTER_Y
            if mdx * mdx + mdy * mdy > 144 then
                ix = mdx
                iy = mdy
            end
        end

        if ix ~= 0 or iy ~= 0 then
            -- Inverse isometric mapping: screen (ix, iy) -> world (wx, wy)
            -- Right (+ix) => (+1, -1); Down (+iy) => (+1, +1)
            local ax = ix / ISO_W + iy / ISO_H
            local ay = iy / ISO_H - ix / ISO_W
            local alen = math.sqrt(ax * ax + ay * ay)
            if alen > 1e-5 then
                ax, ay = ax / alen, ay / alen
                ball.vx = ball.vx + ax * BALL_ACCEL * dt
                ball.vy = ball.vy + ay * BALL_ACCEL * dt
            end
        end

        -- Space acts as a grip brake if hurtling too fast toward a trap
        local drag = love.keyboard.isDown("space") and BALL_BRAKE or BALL_DRAG
        local damp = math.exp(-drag * dt)
        ball.vx = ball.vx * damp
        ball.vy = ball.vy * damp

        -- Speed cap
        local spd = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
        if spd > BALL_MAX_SPEED then
            ball.vx = (ball.vx / spd) * BALL_MAX_SPEED
            ball.vy = (ball.vy / spd) * BALL_MAX_SPEED
            spd = BALL_MAX_SPEED
        end
        ball.speed = spd

        -- Sub-stepped movement so high-speed rolling never tunnels through maze walls
        local substeps = math.max(1, math.ceil((spd * dt) / 0.08))
        local sub_dt = dt / substeps
        local prev_x, prev_y = ball.x, ball.y
        for _ = 1, substeps do
            ball.x = ball.x + ball.vx * sub_dt
            ball.y = ball.y + ball.vy * sub_dt
            resolveWallCollisions()
        end

        -- Update 3D rolling orientation matrix based on actual screen-projected travel
        local moved_x = ball.x - prev_x
        local moved_y = ball.y - prev_y
        local smx, smy = worldVelToScreen(moved_x, moved_y)
        local screen_dist = math.sqrt(smx * smx + smy * smy)
        if screen_dist > 1e-4 then
            -- Roll axis is perpendicular to screen travel (note +Y is screen-down -> -Y in shader 3D)
            local tx = smx / screen_dist
            local ty = -smy / screen_dist
            local kx, ky, kz = -ty, tx, 0
            local roll_angle = screen_dist / 22.0 -- matches 22px visual ball radius
            ball.ux = rotateVec3(ball.ux, kx, ky, kz, roll_angle)
            ball.uy = rotateVec3(ball.uy, kx, ky, kz, roll_angle)
            ball.uz = cross3(ball.ux, ball.uy)
            ball.ux = norm3(ball.ux)
            ball.uz = norm3(ball.uz)
            ball.uy = norm3(cross3(ball.uz, ball.ux))
        end

        -- Trail sparks at high speed
        if ball.speed > 5.0 and love.math.random() < (ball.speed / BALL_MAX_SPEED) * 0.55 then
            spawnSparks(ball.x, ball.y, 1, 1.0, 0.65, 0.2, 0.35)
        end

        -- Check interactions with hazards, pickups, and exit portal
        local cx, cy = math.floor(ball.x), math.floor(ball.y)
        local key = tileKey(cx, cy)

        -- Shield orb pickup
        local orb = pickups[key]
        if orb and not orb.taken then
            local dx = ball.x - (orb.x + 0.5)
            local dy = ball.y - (orb.y + 0.5)
            if dx * dx + dy * dy < 0.34 * 0.34 then
                orb.taken = true
                orbs_collected = orbs_collected + 1
                ball.hp = math.min(ball.max_hp, ball.hp + 1)
                spawnSparks(orb.x + 0.5, orb.y + 0.5, 18, 0.25, 1.0, 0.62, 1.0)
            end
        end

        -- Hazards in current cell (and nearby junction bumpers)
        for hx = cx - 1, cx + 1 do
            for hy = cy - 1, cy + 1 do
                local h = hazards[tileKey(hx, hy)]
                if h then
                    local hcx, hcy = h.x + 0.5, h.y + 0.5
                    local dx = ball.x - hcx
                    local dy = ball.y - hcy
                    local d2 = dx * dx + dy * dy

                    if h.kind == "bumper" then
                        h.pulse = math.max(0, h.pulse - dt * 3.5)
                        local min_r = BALL_R + 0.16
                        if d2 < min_r * min_r then
                            local d = math.max(1e-4, math.sqrt(d2))
                            local nx, ny = dx / d, dy / d
                            ball.x = hcx + nx * min_r
                            ball.y = hcy + ny * min_r
                            local launch = math.max(6.8, ball.speed * 1.35)
                            ball.vx = nx * launch
                            ball.vy = ny * launch
                            h.pulse = 1.0
                            triggerImpact(8.0, 1.0, 0.62, 0.15)
                        end
                    elseif hx == cx and hy == cy then
                        local state = getHazardState(h, now)
                        if h.kind == "boost" and d2 < 0.42 * 0.42 then
                            ball.vx = ball.vx + h.dx * 26.0 * dt
                            ball.vy = ball.vy + h.dy * 26.0 * dt
                            if love.math.random() < 0.45 then
                                spawnSparks(ball.x, ball.y, 1, 0.2, 0.95, 1.0, 0.6)
                            end
                        elseif h.kind == "spikes" and state == "active" and d2 < 0.36 * 0.36 then
                            hurtBall(-ball.vx * 0.6, -ball.vy * 0.6)
                        elseif h.kind == "magma" and state == "active" and d2 < 0.40 * 0.40 then
                            hurtBall(-ball.vx * 0.45, -ball.vy * 0.45)
                        elseif h.kind == "laser" and state == "active" then
                            local beam_dist = (h.axis == "y") and math.abs(dx) or math.abs(dy)
                            if beam_dist < 0.22 then
                                local push_x = (h.axis == "y") and ((dx >= 0 and 1 or -1) * 5.0) or (-ball.vx * 0.5)
                                local push_y = (h.axis == "x") and ((dy >= 0 and 1 or -1) * 5.0) or (-ball.vy * 0.5)
                                hurtBall(push_x, push_y)
                            end
                        end
                    end
                end
            end
        end

        -- Exit Portal reached -> advance to next autogenerated maze!
        local ex = ball.x - (exit_gx + 0.5)
        local ey = ball.y - (exit_gy + 0.5)
        if ex * ex + ey * ey < 0.38 * 0.38 then
            level = level + 1
            ball.hp = math.min(ball.max_hp, ball.hp + 1)
            generateMaze(level)
            level_clear_timer = 2.4
            triggerImpact(5.5, 0.2, 1.0, 0.85)
        end

        -- Update timers
        ball.invuln = math.max(0, ball.invuln - dt)
        ball.hit_flash = math.max(0, ball.hit_flash - dt * 3.5)
        level_clear_timer = math.max(0, level_clear_timer - dt)
    end

    -- 2. Recompute 360° Raytraced Visibility (max 8 segments)
    computeVisibility()

    -- 3. Update Sparks / Particles
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.z = math.max(0, p.z + p.vz * dt)
            p.vz = p.vz - 190 * dt
        end
    end

    -- 4. Drive Moonshine Post-Processing Shaders Intelligently from Live Game Physics!
    -- Directional Speed Blur COUNTER to the ball's screen movement vector
    local svx, svy = worldVelToScreen(ball.vx, ball.vy)
    local screen_spd = math.sqrt(svx * svx + svy * svy)
    local target_blur = 0
    if screen_spd > 95 then
        local norm = clamp((screen_spd - 95) / 380, 0, 1)
        target_blur = norm * norm * 22.0
        -- Counter to ball's movement direction: (-svx, -svy)
        local tdx = -svx / screen_spd
        local tdy = -svy / screen_spd
        blur_dir_x = blur_dir_x + (tdx - blur_dir_x) * math.min(1, dt * 14)
        blur_dir_y = blur_dir_y + (tdy - blur_dir_y) * math.min(1, dt * 14)
    end
    blur_strength = blur_strength + (target_blur - blur_strength) * math.min(1, dt * 10)

    -- Smooth exponential decay for impact screen shake, chromasep, and damage vignette
    shake_intensity = shake_intensity * math.exp(-9.5 * dt)
    if shake_intensity < 0.08 then shake_intensity = 0 end

    chroma_intensity = chroma_intensity * math.exp(-8.0 * dt)
    local speed_chroma = clamp((ball.speed - 6.0) / 3.5, 0, 1) * 1.8
    local total_chroma = chroma_intensity + speed_chroma

    damage_vignette = damage_vignette * math.exp(-4.0 * dt)

    -- Push live uniforms into the Moonshine shader chain
    post_fx.motionblur.direction = { blur_dir_x, blur_dir_y }
    post_fx.motionblur.strength = blur_strength
    post_fx.screenshake.intensity = shake_intensity
    post_fx.chromasep.radius = total_chroma
    post_fx.chromasep.angle = now * 4.0 + math.atan2(blur_dir_y, blur_dir_x)

    -- Tint vignette crimson on damage, or soft cyan when near the exit portal
    local exit_dist = math.sqrt((ball.x - (exit_gx + 0.5)) ^ 2 + (ball.y - (exit_gy + 0.5)) ^ 2)
    local near_exit = clamp(1.0 - exit_dist / 5.5, 0, 1)
    post_fx.vignette.opacity = 0.48 + damage_vignette * 0.34
    post_fx.vignette.color = {
        0.02 + damage_vignette * 0.65,
        0.03 + near_exit * 0.14 * (1 - damage_vignette),
        0.06 + near_exit * 0.20 * (1 - damage_vignette),
    }
    post_fx.glow.strength = 3.8 + clamp(ball.speed / BALL_MAX_SPEED, 0, 1) * 2.2
end

function love.keypressed(key, scancode)
    if game_state == "gameover" then
        if key == "y" or scancode == "y" or key == "r" or scancode == "r" or key == "return" then
            restartGame()
        elseif key == "n" or scancode == "n" then
            love.event.quit()
        end
        return
    end

    if key == "r" then
        generateMaze(level)
    elseif key == "tab" then
        show_telemetry = not show_telemetry
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if game_state == "gameover" then
        local gx, gy = lovemap.toGame(x, y)
        if gy >= 505 and gy <= 565 then
            if gx >= 515 and gx <= 775 then
                restartGame()
            elseif gx >= 825 and gx <= 1085 then
                love.event.quit()
            end
        end
    end
end

-- ============================================================================
-- Isometric Tile, Wall, Hazard, and 3D Ball Rendering
-- ============================================================================

local function drawIsoFloor(cx, cy, vis, in_fog)
    local x0, y0 = worldToScreen(cx,     cy,     0)
    local x1, y1 = worldToScreen(cx + 1, cy,     0)
    local x2, y2 = worldToScreen(cx + 1, cy + 1, 0)
    local x3, y3 = worldToScreen(cx,     cy + 1, 0)

    local checker = ((cx + cy) % 2 == 0)
    if in_fog then
        local b = checker and 0.46 or 0.38
        love.graphics.setColor(b, b * 1.03, b * 1.12, 1)
        love.graphics.polygon("fill", x0, y0, x1, y1, x2, y2, x3, y3)
        love.graphics.setColor(0.24, 0.27, 0.34, 0.7)
        love.graphics.polygon("line", x0, y0, x1, y1, x2, y2, x3, y3)
    else
        -- Smooth 8-segment shadow falloff (fades to dark shadow if fresh, or seamlessly into fog gray if explored)
        local is_exp = explored[cx][cy]
        local base_r = checker and 0.16 or 0.13
        local base_g = checker and 0.22 or 0.18
        local base_b = checker and 0.32 or 0.26
        local l = is_exp and (0.22 + vis * 0.78) or vis
        if is_exp then
            local fog_mix = clamp(1.0 - vis * 1.4, 0, 1)
            love.graphics.setColor(
                base_r * l * (1 - fog_mix) + 0.16 * fog_mix,
                base_g * l * (1 - fog_mix) + 0.18 * fog_mix,
                base_b * l * (1 - fog_mix) + 0.22 * fog_mix,
                1
            )
        else
            love.graphics.setColor(base_r * l, base_g * l, base_b * l, 1)
        end
        love.graphics.polygon("fill", x0, y0, x1, y1, x2, y2, x3, y3)

        -- Crisp architectural bevel lines on visible floor tiles
        love.graphics.setColor(0.28 * l, 0.44 * l, 0.62 * l, 0.45 * vis)
        love.graphics.polygon("line", x0, y0, x1, y1, x2, y2, x3, y3)
    end
end

local function drawIsoWall(cx, cy, vis, in_fog)
    local bx0, by0 = worldToScreen(cx,     cy,     0)
    local bx1, by1 = worldToScreen(cx + 1, cy,     0)
    local bx2, by2 = worldToScreen(cx + 1, cy + 1, 0)
    local bx3, by3 = worldToScreen(cx,     cy + 1, 0)

    local tx0, ty0 = bx0, by0 - WALL_H
    local tx1, ty1 = bx1, by1 - WALL_H
    local tx2, ty2 = bx2, by2 - WALL_H
    local tx3, ty3 = bx3, by3 - WALL_H

    if in_fog then
        -- Top face
        love.graphics.setColor(0.54, 0.56, 0.62, 1)
        love.graphics.polygon("fill", tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3)
        -- Left front face (cx..cx+1 along cy+1)
        love.graphics.setColor(0.36, 0.38, 0.44, 1)
        love.graphics.polygon("fill", tx3, ty3, tx2, ty2, bx2, by2, bx3, by3)
        -- Right front face (cy..cy+1 along cx+1)
        love.graphics.setColor(0.26, 0.28, 0.34, 1)
        love.graphics.polygon("fill", tx2, ty2, tx1, ty1, bx1, by1, bx2, by2)
        -- Subtle wireframe rim
        love.graphics.setColor(0.45, 0.48, 0.55, 0.5)
        love.graphics.polygon("line", tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3)
    else
        local is_exp = explored[cx][cy]
        local l = is_exp and (0.20 + vis * 0.80) or vis
        local fm = is_exp and clamp(1.0 - vis * 1.4, 0, 1) or 0
        -- Subtle cyan-slate architectural palette with directional lighting
        -- Top cap
        love.graphics.setColor(0.26 * l * (1 - fm) + 0.22 * fm, 0.35 * l * (1 - fm) + 0.24 * fm, 0.48 * l * (1 - fm) + 0.28 * fm, 1)
        love.graphics.polygon("fill", tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3)
        -- Left face (facing warm key light)
        love.graphics.setColor(0.19 * l * (1 - fm) + 0.16 * fm, 0.26 * l * (1 - fm) + 0.18 * fm, 0.38 * l * (1 - fm) + 0.21 * fm, 1)
        love.graphics.polygon("fill", tx3, ty3, tx2, ty2, bx2, by2, bx3, by3)
        -- Right face (cooler shadow side)
        love.graphics.setColor(0.11 * l * (1 - fm) + 0.12 * fm, 0.16 * l * (1 - fm) + 0.13 * fm, 0.25 * l * (1 - fm) + 0.16 * fm, 1)
        love.graphics.polygon("fill", tx2, ty2, tx1, ty1, bx1, by1, bx2, by2)

        -- Glowing tech bevel along top edge near the ball
        love.graphics.setColor(0.32 * l, 0.72 * l, 0.92 * l, 0.48 * vis)
        love.graphics.polygon("line", tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3)
    end
end

local function drawHazard(h, vis, now)
    local cx, cy = h.x + 0.5, h.y + 0.5
    local sx, sy = worldToScreen(cx, cy, 0)
    local state, prog = getHazardState(h, now)

    if h.kind == "magma" then
        local heat = 0.12
        if state == "warn" then heat = 0.2 + prog * 0.55
        elseif state == "active" then heat = 0.95 end

        lovemap.withEffect(magma_shader, {
            time = now,
            heat = heat,
            seed = h.phase,
        }, function()
            love.graphics.setColor(vis, vis, vis, 1)
            love.graphics.draw(white_tex, sx - ISO_W * 0.48, sy - ISO_H * 0.48, 0, ISO_W * 0.48, ISO_H * 0.48)
        end)

    elseif h.kind == "spikes" then
        -- Floor plate
        love.graphics.setColor(0.18 * vis, 0.14 * vis, 0.18 * vis, 0.95)
        love.graphics.ellipse("fill", sx, sy, 26, 13)

        if state == "warn" then
            love.graphics.setColor(1.0 * vis, 0.55 * vis, 0.12 * vis, 0.5 + 0.5 * prog)
            love.graphics.setLineWidth(2)
            love.graphics.ellipse("line", sx, sy, 26, 13)
            love.graphics.setLineWidth(1)
        end

        local spike_h = 0
        if state == "warn" then spike_h = 4 + prog * 6
        elseif state == "active" then spike_h = 24 end

        if spike_h > 0 then
            local offsets = {
                { -12, -3 }, { 12, -3 }, { 0, -7 }, { 0, 5 }, { -10, 4 }, { 10, 4 },
            }
            for _, o in ipairs(offsets) do
                local px, py = sx + o[1], sy + o[2]
                love.graphics.setColor(0.88 * vis, 0.22 * vis, 0.28 * vis, 1)
                love.graphics.polygon("fill", px - 4, py, px + 4, py, px, py - spike_h)
                love.graphics.setColor(1.0 * vis, 0.85 * vis, 0.72 * vis, 0.9)
                love.graphics.polygon("fill", px - 1.5, py - 2, px + 1.5, py - 2, px, py - spike_h)
            end
        end

    elseif h.kind == "laser" then
        local ax1, ay1, ax2, ay2
        if h.axis == "y" then
            ax1, ay1 = worldToScreen(h.x + 0.5, h.y + 0.05, 16)
            ax2, ay2 = worldToScreen(h.x + 0.5, h.y + 0.95, 16)
        else
            ax1, ay1 = worldToScreen(h.x + 0.05, h.y + 0.5, 16)
            ax2, ay2 = worldToScreen(h.x + 0.95, h.y + 0.5, 16)
        end
        -- Emitter posts
        love.graphics.setColor(0.45 * vis, 0.5 * vis, 0.6 * vis, 1)
        love.graphics.circle("fill", ax1, ay1, 5)
        love.graphics.circle("fill", ax2, ay2, 5)

        if state == "warn" then
            love.graphics.setColor(1.0 * vis, 0.45 * vis, 0.85 * vis, 0.35 + 0.45 * prog)
            love.graphics.setLineWidth(2)
            love.graphics.line(ax1, ay1, ax2, ay2)
            love.graphics.setLineWidth(1)
        elseif state == "active" then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(1.0 * vis, 0.18 * vis, 0.65 * vis, 0.55)
            love.graphics.setLineWidth(11)
            love.graphics.line(ax1, ay1, ax2, ay2)
            love.graphics.setColor(1.0 * vis, 0.82 * vis, 0.98 * vis, 0.95)
            love.graphics.setLineWidth(3.5)
            love.graphics.line(ax1, ay1, ax2, ay2)
            love.graphics.setLineWidth(1)
            love.graphics.setBlendMode("alpha")
        end

    elseif h.kind == "bumper" then
        local p = 1.0 + h.pulse * 0.38
        love.graphics.setColor(0, 0, 0, 0.42 * vis)
        love.graphics.ellipse("fill", sx, sy + 2, 16 * p, 9 * p)
        love.graphics.setColor(0.95 * vis, 0.45 * vis, 0.10 * vis, 1)
        love.graphics.circle("fill", sx, sy - 11, 13 * p)
        love.graphics.setColor(1.0 * vis, 0.90 * vis, 0.42 * vis, 1)
        love.graphics.circle("fill", sx - 3, sy - 14, 6 * p)
        love.graphics.setColor(1.0 * vis, 0.72 * vis, 0.22 * vis, 0.75)
        love.graphics.setLineWidth(2.5)
        love.graphics.circle("line", sx, sy - 11, (16 + math.sin(now * 6 + h.phase) * 2) * p)
        love.graphics.setLineWidth(1)

    elseif h.kind == "boost" then
        -- Glowing directional cyan boost chevrons
        local t = (now * 2.8 + h.phase) % 1
        for k = -1, 1 do
            local off = ((k * 0.33 + t) % 1) - 0.5
            local px, py = worldToScreen(cx + h.dx * off * 0.7, cy + h.dy * off * 0.7, 2)
            local tipx, tipy = worldToScreen(cx + h.dx * (off * 0.7 + 0.22), cy + h.dy * (off * 0.7 + 0.22), 2)
            local side_x, side_y = -h.dy * 0.22, h.dx * 0.22
            local lx, ly = worldToScreen(cx + h.dx * off * 0.7 + side_x, cy + h.dy * off * 0.7 + side_y, 2)
            local rx, ry = worldToScreen(cx + h.dx * off * 0.7 - side_x, cy + h.dy * off * 0.7 - side_y, 2)
            love.graphics.setColor(0.15 * vis, 0.95 * vis, 1.0 * vis, 0.85)
            love.graphics.setLineWidth(3)
            love.graphics.line(lx, ly, tipx, tipy, rx, ry)
            love.graphics.setLineWidth(1)
        end
    end
end

local function drawExitPortal(vis, now)
    local sx, sy = worldToScreen(exit_gx + 0.5, exit_gy + 0.5, 4)
    lovemap.withEffect(portal_shader, { time = now }, function()
        love.graphics.setColor(vis, vis, vis, 1)
        love.graphics.draw(white_tex, sx - 44, sy - 26, 0, 44, 26)
    end)
    -- Rising energy beacon ring
    local lift = (now * 28) % 34
    love.graphics.setColor(0.25 * vis, 1.0 * vis, 0.88 * vis, (1 - lift / 34) * 0.75)
    love.graphics.setLineWidth(2)
    love.graphics.ellipse("line", sx, sy - lift, 28, 14)
    love.graphics.setLineWidth(1)
end

local function drawPickupOrb(orb, vis, now)
    local bob = math.sin(now * 4.5 + orb.phase) * 5
    local sx, sy = worldToScreen(orb.x + 0.5, orb.y + 0.5, 16 + bob)
    love.graphics.setColor(0, 0, 0, 0.35 * vis)
    love.graphics.ellipse("fill", sx, sy + 16 + bob, 10, 5)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.18 * vis, 1.0 * vis, 0.58 * vis, 0.45)
    love.graphics.circle("fill", sx, sy, 14)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(0.32 * vis, 1.0 * vis, 0.68 * vis, 1)
    love.graphics.circle("fill", sx, sy, 8)
    love.graphics.setColor(0.92 * vis, 1.0 * vis, 0.95 * vis, 1)
    love.graphics.circle("fill", sx - 2.5, sy - 2.5, 3)
end

local function draw3DBall(now)
    -- Soft ground contact shadow directly under screen center
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.ellipse("fill", CENTER_X, CENTER_Y + 4, 24, 12)

    -- Subtle cyan/gold floor glow right beneath the rolling orb
    local spd_norm = clamp(ball.speed / BALL_MAX_SPEED, 0, 1)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.18 + 0.7 * spd_norm, 0.85 - 0.25 * spd_norm, 1.0 - 0.7 * spd_norm, 0.22)
    love.graphics.ellipse("fill", CENTER_X, CENTER_Y + 2, 34, 17)
    love.graphics.setBlendMode("alpha")

    -- Invulnerability blink
    local alpha = 1.0
    if ball.invuln > 0 and math.floor(now * 16) % 2 == 0 then
        alpha = 0.55
    end

    -- Render true 3D rolling sphere via custom analytic ray-sphere fragment shader
    local r = 22
    lovemap.withEffect(ball_shader, {
        u_x = ball.ux,
        u_y = ball.uy,
        u_z = ball.uz,
        time = now,
        speed_norm = spd_norm,
        hit_flash = ball.hit_flash,
    }, function()
        love.graphics.setColor(1, 1, 1, alpha)
        -- white_tex is 2x2, so scale r yields 2*r = 44x44 quad centered at (CENTER_X, CENTER_Y - 17)
        love.graphics.draw(white_tex, CENTER_X - r, CENTER_Y - 17 - r, 0, r, r)
    end)
end

local function drawRaytracedLightCone(now)
    -- Build vertex fan: center at ball + 288 exact raycast hit points (clamped at 8 segments)
    light_mesh:setVertex(1, CENTER_X, CENTER_Y - 4, 0, 0, 1, 1, 1, 1)
    for i = 1, NUM_RAYS do
        local rp = ray_pts[i]
        local sx, sy = worldToScreen(rp.wx, rp.wy, 4)
        light_mesh:setVertex(i + 1, sx, sy, rp.frac, 0, 1, 1, 1, 1)
    end
    -- Close the 360° fan cleanly
    local first = ray_pts[1]
    local fx, fy = worldToScreen(first.wx, first.wy, 4)
    light_mesh:setVertex(NUM_RAYS + 2, fx, fy, first.frac, 0, 1, 1, 1, 1)

    local spd_norm = clamp(ball.speed / BALL_MAX_SPEED, 0, 1)
    love.graphics.setBlendMode("add")
    lovemap.withEffect(light_cone_shader, {
        time = now,
        speed_norm = spd_norm,
    }, function()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(light_mesh)
    end)
    love.graphics.setBlendMode("alpha")
end

-- ============================================================================
-- HUD & Explored-Only Corner Minimap
-- ============================================================================

local function drawMinimap()
    local map_size = 172
    local mx, my = 1600 - map_size - 24, 20
    local cell_px = map_size / maze_w

    love.graphics.setColor(0.04, 0.06, 0.10, 0.84)
    love.graphics.rectangle("fill", mx - 6, my - 6, map_size + 12, map_size + 12, 8, 8)
    love.graphics.setColor(0.28, 0.52, 0.74, 0.6)
    love.graphics.rectangle("line", mx - 6, my - 6, map_size + 12, map_size + 12, 8, 8)

    for x = 1, maze_w do
        for y = 1, maze_h do
            local vis = vis_light[x][y]
            if vis > 0.02 then
                if maze[x][y] == 1 then
                    love.graphics.setColor(0.32 * vis + 0.12, 0.56 * vis + 0.16, 0.78 * vis + 0.22, 1)
                else
                    love.graphics.setColor(0.14 * vis + 0.08, 0.30 * vis + 0.12, 0.44 * vis + 0.16, 1)
                end
                love.graphics.rectangle("fill", mx + (x - 1) * cell_px, my + (y - 1) * cell_px, cell_px, cell_px)
            elseif explored[x][y] then
                -- Explored fog: grayed out, no hazards shown
                if maze[x][y] == 1 then
                    love.graphics.setColor(0.28, 0.30, 0.35, 0.9)
                else
                    love.graphics.setColor(0.14, 0.15, 0.18, 0.9)
                end
                love.graphics.rectangle("fill", mx + (x - 1) * cell_px, my + (y - 1) * cell_px, cell_px, cell_px)
            end
        end
    end

    -- Show exit dot ONLY if currently in sight or already explored
    if vis_light[exit_gx][exit_gy] > 0.02 then
        love.graphics.setColor(0.2, 1.0, 0.82, 1)
        love.graphics.circle("fill", mx + (exit_gx - 0.5) * cell_px, my + (exit_gy - 0.5) * cell_px, 4)
    elseif explored[exit_gx][exit_gy] then
        love.graphics.setColor(0.45, 0.65, 0.60, 0.85)
        love.graphics.circle("fill", mx + (exit_gx - 0.5) * cell_px, my + (exit_gy - 0.5) * cell_px, 3)
    end

    -- Ball position dot
    love.graphics.setColor(1.0, 0.92, 0.35, 1)
    love.graphics.circle("fill", mx + (ball.x - 1) * cell_px, my + (ball.y - 1) * cell_px, 3.8)
end

local function drawHUD()
    -- Top-left status bar
    love.graphics.setColor(0.05, 0.08, 0.13, 0.84)
    love.graphics.rectangle("fill", 20, 18, 535, 96, 10, 10)
    love.graphics.setColor(0.28, 0.68, 0.95, 0.55)
    love.graphics.rectangle("line", 20, 18, 535, 96, 10, 10)

    love.graphics.setFont(font_lg)
    love.graphics.setColor(0.92, 0.98, 1.0, 1)
    love.graphics.print(string.format("SHADERMAXXING  •  MAZE %d (%dx%d)", level, maze_w, maze_h), 36, 26)

    -- Shields bar
    love.graphics.setFont(font_md)
    love.graphics.setColor(0.75, 0.86, 0.96, 1)
    love.graphics.print("Shields:", 36, 66)
    for i = 1, ball.max_hp do
        local sx = 122 + (i - 1) * 28
        if i <= ball.hp then
            love.graphics.setColor(0.22, 0.92, 0.72, 1)
        else
            love.graphics.setColor(0.22, 0.26, 0.32, 0.85)
        end
        love.graphics.rectangle("fill", sx, 68, 22, 18, 4, 4)
    end

    -- Speed & Exploration readout
    local pct = math.floor((total_explored / math.max(1, total_floor_tiles)) * 100)
    love.graphics.setColor(1.0, 0.84, 0.36, 1)
    love.graphics.print(string.format("Speed: %.1f", ball.speed), 282, 66)
    love.graphics.setColor(0.65, 0.82, 0.98, 1)
    love.graphics.print(string.format("Mapped: %d%%", pct), 412, 66)

    -- Minimap
    drawMinimap()

    -- Bottom-left live shader telemetry panel (toggleable with Tab)
    if show_telemetry then
        local px, py, pw, ph = 20, 742, 430, 138
        love.graphics.setColor(0.05, 0.08, 0.13, 0.80)
        love.graphics.rectangle("fill", px, py, pw, ph, 10, 10)
        love.graphics.setColor(0.30, 0.58, 0.88, 0.45)
        love.graphics.rectangle("line", px, py, pw, ph, 10, 10)

        love.graphics.setFont(font_sm)
        love.graphics.setColor(0.45, 0.88, 1.0, 1)
        love.graphics.print("ACTIVE SHADERS  [Tab: toggle]", px + 14, py + 10)

        local function meter(label, val, maxv, y_off, r, g, b)
            love.graphics.setColor(0.80, 0.88, 0.95, 1)
            love.graphics.print(label, px + 14, py + y_off)
            local bx, bw = px + 168, 236
            love.graphics.setColor(0.14, 0.18, 0.25, 1)
            love.graphics.rectangle("fill", bx, py + y_off + 3, bw, 11, 3, 3)
            local fill = clamp(val / maxv, 0, 1) * bw
            love.graphics.setColor(r, g, b, 1)
            love.graphics.rectangle("fill", bx, py + y_off + 3, fill, 11, 3, 3)
        end

        meter("Motion Blur (dir)",  blur_strength,   22.0, 34, 0.25, 0.88, 1.0)
        meter("Screen Shake",       shake_intensity, 12.0, 54, 1.00, 0.55, 0.20)
        meter("Chroma Split",       chroma_intensity + clamp((ball.speed - 6) / 3.5, 0, 1) * 1.8, 10.0, 74, 0.92, 0.35, 0.95)
        love.graphics.setColor(0.68, 0.78, 0.88, 1)
        love.graphics.print("360° Raycast: 8.0 seg  |  3D Sphere  |  Fog Mist  |  Glow", px + 14, py + 96)
        love.graphics.setColor(0.55, 0.66, 0.78, 1)
        love.graphics.print("Magma Vent  |  Portal Vortex  |  Vignette  |  Film Grain", px + 14, py + 115)
    end

    -- Bottom-right concise controls hint
    love.graphics.setFont(font_sm)
    love.graphics.setColor(0.75, 0.84, 0.94, 0.88)
    love.graphics.printf(
        "WASD / Arrows / Mouse: Roll   •   Space: Brake   •   R: New Maze   •   F11: Fullscreen",
        740, 864, 836, "right"
    )

    -- Level clear banner
    if level_clear_timer > 0 then
        local a = math.min(1, level_clear_timer)
        love.graphics.setColor(0.05, 0.16, 0.20, 0.88 * a)
        love.graphics.rectangle("fill", 520, 130, 560, 62, 12, 12)
        love.graphics.setColor(0.25, 1.0, 0.82, a)
        love.graphics.rectangle("line", 520, 130, 560, 62, 12, 12)
        love.graphics.setFont(font_lg)
        love.graphics.printf(string.format("PORTAL REACHED!  ENTERING MAZE %d", level), 520, 145, 560, "center")
    end

    -- Game Over modal
    if game_state == "gameover" then
        love.graphics.setColor(0.32, 0.02, 0.04, 0.72)
        love.graphics.rectangle("fill", 0, 0, 1600, 900)

        love.graphics.setColor(0.08, 0.05, 0.08, 0.95)
        love.graphics.rectangle("fill", 380, 270, 840, 340, 16, 16)
        love.graphics.setColor(1.0, 0.28, 0.30, 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", 380, 270, 840, 340, 16, 16)
        love.graphics.setLineWidth(1)

        love.graphics.setFont(font_xl)
        love.graphics.setColor(1.0, 0.36, 0.36, 1)
        love.graphics.printf("SHIELD SHATTERED!", 380, 315, 840, "center")

        love.graphics.setFont(font_lg)
        love.graphics.setColor(0.92, 0.95, 1.0, 1)
        love.graphics.printf(string.format("Reached Maze %d   •   Time: %.1fs   •   Orbs: %d", level, run_time, orbs_collected), 380, 392, 840, "center")

        love.graphics.setFont(font_md)
        love.graphics.setColor(0.80, 0.86, 0.94, 1)
        love.graphics.printf("Generate a fresh maze and try again?", 380, 448, 840, "center")

        -- Clickable [Y] Restart and [N] Quit buttons
        love.graphics.setColor(0.14, 0.62, 0.46, 1)
        love.graphics.rectangle("fill", 515, 505, 260, 60, 10, 10)
        love.graphics.setColor(0.55, 1.0, 0.85, 1)
        love.graphics.rectangle("line", 515, 505, 260, 60, 10, 10)
        love.graphics.setFont(font_lg)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("[Y] Restart", 515, 519, 260, "center")

        love.graphics.setColor(0.56, 0.16, 0.20, 1)
        love.graphics.rectangle("fill", 825, 505, 260, 60, 10, 10)
        love.graphics.setColor(1.0, 0.55, 0.58, 1)
        love.graphics.rectangle("line", 825, 505, 260, 60, 10, 10)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("[N] Quit", 825, 519, 260, "center")
    end
end

-- ============================================================================
-- Main Draw Loop via lovemap.draw()
-- ============================================================================

function lovemap.draw()
    local now = love.timer.getTime()

    -- Deep shadowed void backdrop
    love.graphics.setColor(0.018, 0.022, 0.035, 1)
    love.graphics.rectangle("fill", 0, 0, 1600, 900)

    -- Compute world-space camera scroll offset for mist coherence in fog_tile_shader
    local cam_scroll_x = (ball.x - ball.y) * (ISO_W * 0.5)
    local cam_scroll_y = (ball.x + ball.y) * (ISO_H * 0.5)

    -- Painter's order isometric traversal strictly around camera bounds
    local bx_cell = math.floor(ball.x)
    local by_cell = math.floor(ball.y)
    local ball_diag = bx_cell + by_cell

    local range = 14
    local min_x = math.max(1, bx_cell - range)
    local max_x = math.min(maze_w, bx_cell + range)
    local min_y = math.max(1, by_cell - range)
    local max_y = math.min(maze_h, by_cell + range)

    local min_d = min_x + min_y
    local max_d = max_x + max_y

    for d = min_d, max_d do
        -- Pass A: Floor tiles + floor hazards/portal on diagonal d
        for cx = min_x, max_x do
            local cy = d - cx
            if cy >= min_y and cy <= max_y then
                local vis = vis_light[cx][cy]
                local exp = explored[cx][cy]
                if maze[cx][cy] == 0 then
                    if vis > 0.01 then
                        drawIsoFloor(cx, cy, vis, false)
                        -- Hazards, pickups, and exit portal are ONLY rendered when inside 360° sight!
                        local h = hazards[tileKey(cx, cy)]
                        if h and h.kind ~= "bumper" then
                            drawHazard(h, vis, now)
                        end
                        if cx == exit_gx and cy == exit_gy then
                            drawExitPortal(vis, now)
                        end
                    elseif exp then
                        -- Previously revealed, now out of sight: grayed out in fog, NO hazards shown!
                        lovemap.withEffect(fog_tile_shader, {
                            time = now,
                            cam_scroll = { cam_scroll_x, cam_scroll_y },
                        }, function()
                            drawIsoFloor(cx, cy, 0, true)
                        end)
                    end
                end
            end
        end

        -- Pass B: Tall elements (walls, bumpers, shield orbs) on diagonal d
        for cx = min_x, max_x do
            local cy = d - cx
            if cy >= min_y and cy <= max_y then
                local vis = vis_light[cx][cy]
                local exp = explored[cx][cy]
                if maze[cx][cy] == 1 then
                    if vis > 0.01 then
                        drawIsoWall(cx, cy, vis, false)
                    elseif exp then
                        lovemap.withEffect(fog_tile_shader, {
                            time = now,
                            cam_scroll = { cam_scroll_x, cam_scroll_y },
                        }, function()
                            drawIsoWall(cx, cy, 0, true)
                        end)
                    end
                elseif vis > 0.01 then
                    local h = hazards[tileKey(cx, cy)]
                    if h and h.kind == "bumper" then
                        drawHazard(h, vis, now)
                    end
                    local orb = pickups[tileKey(cx, cy)]
                    if orb and not orb.taken then
                        drawPickupOrb(orb, vis, now)
                    end
                end
            end
        end

        -- Draw the 3D Ball right on its exact isometric depth diagonal (behind walls in front, in front of walls behind!)
        if d == ball_diag then
            draw3DBall(now)
        end
    end

    -- Subtle translucent rim indicator if a front wall partially overlaps the ball
    if isWall(bx_cell + 1, by_cell) or isWall(bx_cell, by_cell + 1) or isWall(bx_cell + 1, by_cell + 1) then
        love.graphics.setColor(0.32, 0.92, 1.0, 0.24)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", CENTER_X, CENTER_Y - 17, 22)
        love.graphics.setLineWidth(1)
    end

    -- 360° Raytraced 8-Segment Volumetric Light Cone Overlay
    drawRaytracedLightCone(now)

    -- Sparks & impact particles (only drawn if inside currently visible cell)
    love.graphics.setBlendMode("add")
    for _, p in ipairs(particles) do
        local px, py = math.floor(p.x), math.floor(p.y)
        local pvis = (px >= 1 and py >= 1 and px <= maze_w and py <= maze_h) and vis_light[px][py] or 0
        if pvis > 0.02 then
            local sx, sy = worldToScreen(p.x, p.y, p.z)
            local a = clamp(p.life / p.max_life, 0, 1) * pvis
            love.graphics.setColor(p.r, p.g, p.b, a)
            love.graphics.circle("fill", sx, sy, p.size * (0.4 + 0.6 * a))
        end
    end
    love.graphics.setBlendMode("alpha")

    -- Clean UI overlay
    drawHUD()
end
