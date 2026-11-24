love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";../../?.lua;../../?/init.lua")
package.path = "../../?.lua;../../?/init.lua;" .. package.path

local lovemap = require("src.lovemap")

-- 16x16 Single-Level Arena Map (1 = Red Brick PNG, 2 = Sci-Fi Tech Panel PNG, 0 = Open Floor)
local MAP = {
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    { 1, 0, 0, 0, 0, 0, 1, 0, 0, 2, 0, 0, 0, 0, 0, 1 },
    { 1, 0, 2, 2, 0, 0, 1, 0, 0, 2, 0, 0, 1, 1, 0, 1 },
    { 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1 },
    { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
    { 1, 0, 0, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 0, 0, 1 },
    { 1, 1, 1, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 2, 2, 1 },
    { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
    { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
    { 1, 2, 2, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 1, 1, 1 },
    { 1, 0, 0, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 0, 0, 1 },
    { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
    { 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 1 },
    { 1, 0, 1, 1, 0, 0, 2, 0, 0, 1, 0, 0, 2, 2, 0, 1 },
    { 1, 0, 0, 0, 0, 0, 2, 0, 0, 1, 0, 0, 0, 0, 0, 1 },
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
}

local SPAWN_POINTS = {
    { x = 2.5,  y = 14.5 },
    { x = 14.5, y = 2.5 },
    { x = 14.5, y = 14.5 },
    { x = 8.0,  y = 8.0 },
    { x = 8.0,  y = 2.5 },
    { x = 2.5,  y = 8.0 },
}

local NUM_RAYS = 400 -- 400 columns * 4px = 1600 virtual width
local STRIP_W = 1600 / NUM_RAYS
local TEX_SIZE = 64
local MONSTER_FRAMES = 8

local wall_textures = {}
local wall_quads = {}
local monster_img
local monster_quads = {}
local z_buffer = {}
local monsters = {}
local game_state = "playing" -- "playing", "game_over", "quit_declined"
local font_death_lg
local font_death_md

local player = {
    x = 2.5,
    y = 2.5,
    dir_x = 1.0,
    dir_y = 0.0,
    plane_x = 0.0,
    plane_y = 0.66,
    hp = 100,
    kills = 0,
    muzzle_timer = 0,
    hurt_timer = 0,
}

local function spawnMonster(idx)
    local sp = SPAWN_POINTS[((idx - 1) % #SPAWN_POINTS) + 1]
    return {
        x = sp.x,
        y = sp.y,
        hp = 3,
        alive = true,
        respawn_timer = 0,
        hit_flash = 0,
        spawn_idx = idx,
        anim_seed = idx * 1.37,
    }
end

local function resetGame()
    player.x = 2.5
    player.y = 2.5
    player.dir_x = 1.0
    player.dir_y = 0.0
    player.plane_x = 0.0
    player.plane_y = 0.66
    player.hp = 100
    player.kills = 0
    player.muzzle_timer = 0
    player.hurt_timer = 0
    game_state = "playing"

    monsters = {}
    for i = 1, #SPAWN_POINTS do
        monsters[i] = spawnMonster(i)
    end
end

local function isWall(x, y)
    local mx = math.floor(x)
    local my = math.floor(y)
    if my < 1 or my > #MAP or mx < 1 or mx > #MAP[1] then
        return true
    end
    return MAP[my][mx] > 0
end

local function fireWeapon()
    if game_state ~= "playing" then return end
    if player.muzzle_timer > 0.05 then return end
    player.muzzle_timer = 0.14

    -- Hitscan against monsters sorted by distance
    local best_m = nil
    local best_dist = 999
    for _, m in ipairs(monsters) do
        if m.alive then
            local dx = m.x - player.x
            local dy = m.y - player.y
            local inv_det = 1.0 / (player.plane_x * player.dir_y - player.dir_x * player.plane_y)
            local trans_x = inv_det * (player.dir_y * dx - player.dir_x * dy)
            local trans_y = inv_det * (-player.plane_y * dx + player.plane_x * dy)
            if trans_y > 0.2 then
                local screen_x = (1600 * 0.5) * (1 + trans_x / trans_y)
                local sprite_w = math.abs(900 / trans_y) * 0.45
                local ray_col = math.max(1, math.min(NUM_RAYS, math.floor(screen_x / STRIP_W) + 1))
                if math.abs(screen_x - 800) <= sprite_w and trans_y < (z_buffer[ray_col] or 999) then
                    if trans_y < best_dist then
                        best_dist = trans_y
                        best_m = m
                    end
                end
            end
        end
    end

    if best_m then
        best_m.hp = best_m.hp - 1
        best_m.hit_flash = 0.15
        if best_m.hp <= 0 then
            best_m.alive = false
            best_m.respawn_timer = 3.5 -- Respawn after 3.5 seconds!
            player.kills = player.kills + 1
        end
    end
end

function love.load()
    lovemap.aspect(16, 9)

    local fx = lovemap.setShaders("vignette", "glow")
    fx.vignette.opacity = 0.45
    fx.glow.min_luma = 0.72
    fx.glow.strength = 5

    font_death_lg = love.graphics.newFont(56)
    font_death_md = love.graphics.newFont(26)

    -- Load PNG surface textures & 8-frame animated monster PNG sprite sheet
    wall_textures[1] = love.graphics.newImage("assets/wall_brick.png")
    wall_textures[2] = love.graphics.newImage("assets/wall_tech.png")
    monster_img = love.graphics.newImage("assets/monster.png")

    for _, img in pairs(wall_textures) do
        img:setFilter("nearest", "nearest")
    end
    monster_img:setFilter("nearest", "nearest")

    -- Prebuild 1-pixel-wide vertical slice Quads for mapping PNG columns to 3D wall surfaces
    for x = 0, TEX_SIZE - 1 do
        wall_quads[x] = love.graphics.newQuad(x, 0, 1, TEX_SIZE, TEX_SIZE, TEX_SIZE)
    end

    -- Prebuild 8 animation frame Quads for the monster sprite sheet
    local mw, mh = monster_img:getDimensions()
    local frames = math.max(1, math.floor(mw / TEX_SIZE))
    for f = 1, MONSTER_FRAMES do
        local frame_idx = ((f - 1) % frames)
        monster_quads[f] = love.graphics.newQuad(frame_idx * TEX_SIZE, 0, TEX_SIZE, TEX_SIZE, mw, mh)
    end

    resetGame()
end

function love.keypressed(key, scancode)
    if game_state == "game_over" or game_state == "quit_declined" then
        if key == "y" or scancode == "y" then
            resetGame()
        elseif key == "n" or scancode == "n" then
            game_state = "quit_declined"
            love.event.quit()
        end
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if game_state == "game_over" or game_state == "quit_declined" then
        local mx, my = lovemap.toGame(x, y)
        -- Clickable [Y] Restart and [N] Quit buttons on the death screen
        if my >= 500 and my <= 562 then
            if mx >= 510 and mx <= 775 then
                resetGame()
            elseif mx >= 825 and mx <= 1090 then
                game_state = "quit_declined"
                love.event.quit()
            end
        end
    end
end

function love.update(dt)
    player.muzzle_timer = math.max(0, player.muzzle_timer - dt)
    player.hurt_timer = math.max(0, player.hurt_timer - dt)

    if game_state ~= "playing" then
        -- Also poll Y / N directly in love.update so keyboard input works 100% reliably in both desktop & WASM
        if love.keyboard.isDown("y") then
            resetGame()
        elseif love.keyboard.isDown("n") and game_state ~= "quit_declined" then
            game_state = "quit_declined"
            love.event.quit()
        end
        return
    end

    -- Rotation (Left/Right Arrows or Q/E)
    local rot_speed = 2.4 * dt
    local rot = 0
    if love.keyboard.isDown("right", "e") then rot = rot_speed end
    if love.keyboard.isDown("left", "q") then rot = -rot_speed end
    if rot ~= 0 then
        local cos_r, sin_r = math.cos(rot), math.sin(rot)
        local old_dx = player.dir_x
        player.dir_x = player.dir_x * cos_r - player.dir_y * sin_r
        player.dir_y = old_dx * sin_r + player.dir_y * cos_r
        local old_px = player.plane_x
        player.plane_x = player.plane_x * cos_r - player.plane_y * sin_r
        player.plane_y = old_px * sin_r + player.plane_y * cos_r
    end

    -- Movement (W/S or Up/Down + A/D strafe)
    local move_speed = 3.6 * dt
    local mx, my = 0, 0
    if love.keyboard.isDown("w", "up") then
        mx = mx + player.dir_x * move_speed
        my = my + player.dir_y * move_speed
    end
    if love.keyboard.isDown("s", "down") then
        mx = mx - player.dir_x * move_speed
        my = my - player.dir_y * move_speed
    end
    if love.keyboard.isDown("d") then
        mx = mx + player.plane_x * move_speed
        my = my + player.plane_y * move_speed
    end
    if love.keyboard.isDown("a") then
        mx = mx - player.plane_x * move_speed
        my = my - player.plane_y * move_speed
    end

    local pad = 0.25
    if not isWall(player.x + mx + (mx > 0 and pad or -pad), player.y) then
        player.x = player.x + mx
    end
    if not isWall(player.x, player.y + my + (my > 0 and pad or -pad)) then
        player.y = player.y + my
    end

    if love.keyboard.isDown("space") or love.mouse.isDown(1) then
        fireWeapon()
    end

    -- Monster AI & Automatic Respawning
    for _, m in ipairs(monsters) do
        m.hit_flash = math.max(0, m.hit_flash - dt)
        if not m.alive then
            m.respawn_timer = m.respawn_timer - dt
            if m.respawn_timer <= 0 then
                local sp = SPAWN_POINTS[((m.spawn_idx + player.kills) % #SPAWN_POINTS) + 1]
                m.x, m.y = sp.x, sp.y
                m.hp = 3
                m.alive = true
            end
        else
            local dx = player.x - m.x
            local dy = player.y - m.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0.65 then
                local step = 1.45 * dt
                local nx = m.x + (dx / dist) * step
                local ny = m.y + (dy / dist) * step
                if not isWall(nx, m.y) then m.x = nx end
                if not isWall(m.x, ny) then m.y = ny end
            else
                if player.hurt_timer <= 0 then
                    player.hp = math.max(0, player.hp - 20)
                    player.hurt_timer = 0.55
                    if player.hp <= 0 then
                        player.hp = 0
                        game_state = "game_over"
                        return
                    end
                end
            end
        end
    end
end

-- Renders articulated 3D-projected spindly clawing arms with sharp taloned claws
-- and a long wagging forked tongue for each visible monster
local function drawAnimatedMonsterAppendages(m, screen_x, draw_y, sprite_size, shade, now)
    local s = sprite_size / 64.0
    local phase = now * 7.5 + m.anim_seed
    local bob = math.sin(phase) * 1.5 * s
    local cx = screen_x
    local cy = draw_y

    local r_mult = (m.hit_flash > 0) and 1.0 or shade
    local g_mult = (m.hit_flash > 0) and 0.3 or shade
    local b_mult = (m.hit_flash > 0) and 0.3 or shade

    -- 1. Articulated Spindly Clawing Arms & Sharp Taloned Claws (Left & Right)
    for side = -1, 1, 2 do
        local arm_phase = (side == -1) and phase or (phase + math.pi * 0.85)
        local shoulder_x = cx + side * 12 * s
        local shoulder_y = cy + 25 * s + bob

        -- Spindly upper arm reaching outward
        local elbow_x = cx + side * (23 + math.sin(arm_phase) * 4) * s
        local elbow_y = cy + (19 + math.cos(arm_phase) * 5) * s + bob

        -- Spindly forearm slashing forward/downward in a clawing motion
        local wrist_x = cx + side * (29 + math.cos(arm_phase * 1.2) * 5) * s
        local wrist_y = cy + (31 + math.sin(arm_phase * 1.2) * 8) * s + bob

        -- Draw spindly upper arm & forearm bones
        love.graphics.setColor(0.62 * r_mult, 0.12 * g_mult, 0.18 * b_mult, 1)
        love.graphics.setLineWidth(math.max(2, 3.4 * s))
        love.graphics.line(shoulder_x, shoulder_y, elbow_x, elbow_y)
        love.graphics.setColor(0.74 * r_mult, 0.15 * g_mult, 0.22 * b_mult, 1)
        love.graphics.setLineWidth(math.max(1.5, 2.8 * s))
        love.graphics.line(elbow_x, elbow_y, wrist_x, wrist_y)

        -- Knobby elbow & wrist joints
        love.graphics.circle("fill", elbow_x, elbow_y, math.max(1.5, 2.2 * s))
        love.graphics.circle("fill", wrist_x, wrist_y, math.max(1.5, 2.0 * s))

        -- 4 Long Razor-Sharp Taloned Claws at the end of each spindly hand
        local base_ang = (side == -1) and 1.85 or 1.29
        local slash_ang = math.sin(arm_phase) * 0.38 * side
        for c_idx = -1.5, 1.5, 1.0 do
            local ang = base_ang + c_idx * 0.34 + slash_ang
            local mid_x = wrist_x + math.cos(ang) * 6.5 * s
            local mid_y = wrist_y + math.sin(ang) * 6.5 * s
            -- Curved talon tip hooking inward
            local tip_ang = ang - side * 0.35
            local tip_x = mid_x + math.cos(tip_ang) * 6.0 * s
            local tip_y = mid_y + math.sin(tip_ang) * 6.0 * s

            -- Ivory bone talon
            love.graphics.setColor(0.96 * r_mult, 0.94 * g_mult, 0.82 * b_mult, 1)
            love.graphics.polygon(
                "fill",
                wrist_x - 1.2 * s, wrist_y,
                wrist_x + 1.2 * s, wrist_y,
                mid_x + 0.8 * s,   mid_y,
                tip_x,             tip_y,
                mid_x - 0.8 * s,   mid_y
            )
            -- Crimson blood-stained talon tip
            love.graphics.setColor(1.0 * r_mult, 0.18 * g_mult, 0.20 * b_mult, 1)
            love.graphics.circle("fill", tip_x, tip_y, math.max(1, 1.1 * s))
        end
    end

    -- 2. Long Sinuous Wagging Tongue Lashing Out of the Fanged Maw
    local maw_x = cx
    local maw_y = cy + 31 * s + bob
    local wag_a = math.sin(phase * 1.35) * 9.5 * s
    local wag_b = math.sin(phase * 1.35 - 1.1) * 14.5 * s
    local wag_c = math.sin(phase * 1.35 - 2.2) * 18.0 * s

    local t1_x, t1_y = maw_x + wag_a * 0.45, maw_y + 7.5 * s
    local t2_x, t2_y = maw_x + wag_b * 0.75, maw_y + 15.0 * s + math.cos(phase * 2) * 2.0 * s
    local t3_x, t3_y = maw_x + wag_c,        maw_y + 22.5 * s + math.sin(phase * 2) * 2.5 * s

    love.graphics.setColor(0.95 * r_mult, 0.20 * g_mult, 0.42 * b_mult, 1)
    love.graphics.setLineWidth(math.max(2, 4.2 * s))
    love.graphics.line(maw_x, maw_y, t1_x, t1_y, t2_x, t2_y)
    love.graphics.setColor(1.0 * r_mult, 0.32 * g_mult, 0.54 * b_mult, 1)
    love.graphics.setLineWidth(math.max(1.5, 2.8 * s))
    love.graphics.line(t2_x, t2_y, t3_x, t3_y)

    -- Forked wagging tongue tips
    love.graphics.setLineWidth(math.max(1, 1.8 * s))
    love.graphics.line(t3_x, t3_y, t3_x - 3.5 * s + wag_c * 0.15, t3_y + 4.5 * s)
    love.graphics.line(t3_x, t3_y, t3_x + 3.5 * s + wag_c * 0.15, t3_y + 4.5 * s)
end

function lovemap.draw()
    local now = love.timer.getTime()

    -- Ceiling & Floor background
    love.graphics.setColor(0.08, 0.09, 0.13, 1)
    love.graphics.rectangle("fill", 0, 0, 1600, 450)
    love.graphics.setColor(0.14, 0.14, 0.17, 1)
    love.graphics.rectangle("fill", 0, 450, 1600, 450)

    -- 1. 3D DDA Raycaster: projects PNG texture columns onto virtual wall surfaces
    for col = 1, NUM_RAYS do
        local cam_x = 2 * (col - 1) / NUM_RAYS - 1
        local ray_dx = player.dir_x + player.plane_x * cam_x
        local ray_dy = player.dir_y + player.plane_y * cam_x

        local map_x = math.floor(player.x)
        local map_y = math.floor(player.y)

        local delta_x = (ray_dx == 0) and 1e30 or math.abs(1 / ray_dx)
        local delta_y = (ray_dy == 0) and 1e30 or math.abs(1 / ray_dy)

        local step_x, side_x
        local step_y, side_y

        if ray_dx < 0 then
            step_x = -1
            side_x = (player.x - map_x) * delta_x
        else
            step_x = 1
            side_x = (map_x + 1.0 - player.x) * delta_x
        end
        if ray_dy < 0 then
            step_y = -1
            side_y = (player.y - map_y) * delta_y
        else
            step_y = 1
            side_y = (map_y + 1.0 - player.y) * delta_y
        end

        local hit = 0
        local side = 0
        while hit == 0 do
            if side_x < side_y then
                side_x = side_x + delta_x
                map_x = map_x + step_x
                side = 0
            else
                side_y = side_y + delta_y
                map_y = map_y + step_y
                side = 1
            end
            if map_y >= 1 and map_y <= #MAP and map_x >= 1 and map_x <= #MAP[1] then
                hit = MAP[map_y][map_x]
            else
                hit = 1
            end
        end

        local perp_dist = (side == 0) and (side_x - delta_x) or (side_y - delta_y)
        if perp_dist < 0.05 then perp_dist = 0.05 end
        z_buffer[col] = perp_dist

        local line_h = 900 / perp_dist
        local draw_y = 450 - line_h * 0.5

        -- Exact texture UV coordinate on the hit wall surface
        local wall_x
        if side == 0 then
            wall_x = player.y + perp_dist * ray_dy
        else
            wall_x = player.x + perp_dist * ray_dx
        end
        wall_x = wall_x - math.floor(wall_x)

        local tex_x = math.floor(wall_x * TEX_SIZE)
        if (side == 0 and ray_dx > 0) or (side == 1 and ray_dy < 0) then
            tex_x = TEX_SIZE - tex_x - 1
        end
        tex_x = math.max(0, math.min(TEX_SIZE - 1, tex_x))

        -- Distance fog + side shading
        local shade = math.min(1.0, 1.8 / (1.0 + perp_dist * 0.22))
        if side == 1 then shade = shade * 0.76 end
        love.graphics.setColor(shade, shade, shade, 1)

        local tex = wall_textures[hit] or wall_textures[1]
        love.graphics.draw(tex, wall_quads[tex_x], (col - 1) * STRIP_W, draw_y, 0, STRIP_W, line_h / TEX_SIZE)
    end

    -- 2. Project & Depth-Sort Respawning 3D Monster Sprites (clipped against wall Z-buffer)
    local visible_sprites = {}
    for _, m in ipairs(monsters) do
        if m.alive then
            local dx = m.x - player.x
            local dy = m.y - player.y
            local dist_sq = dx * dx + dy * dy
            table.insert(visible_sprites, { m = m, dist_sq = dist_sq })
        end
    end
    table.sort(visible_sprites, function(a, b) return a.dist_sq > b.dist_sq end)

    local inv_det = 1.0 / (player.plane_x * player.dir_y - player.dir_x * player.plane_y)
    for _, entry in ipairs(visible_sprites) do
        local m = entry.m
        local dx = m.x - player.x
        local dy = m.y - player.y
        local trans_x = inv_det * (player.dir_y * dx - player.dir_x * dy)
        local trans_y = inv_det * (-player.plane_y * dx + player.plane_x * dy)

        if trans_y > 0.2 then
            local screen_x = (1600 * 0.5) * (1 + trans_x / trans_y)
            local sprite_size = math.abs(900 / trans_y) * 0.78
            local draw_x = screen_x - sprite_size * 0.5
            local draw_y = 450 - sprite_size * 0.45

            local center_col = math.max(1, math.min(NUM_RAYS, math.floor(screen_x / STRIP_W) + 1))
            if trans_y < (z_buffer[center_col] or 999) then
                local shade = math.min(1.0, 2.0 / (1.0 + trans_y * 0.18))
                if m.hit_flash > 0 then
                    love.graphics.setColor(1, 0.3, 0.3, 1)
                else
                    love.graphics.setColor(shade, shade, shade, 1)
                end
                local frame = (math.floor(now * 10 + m.anim_seed * 3) % MONSTER_FRAMES) + 1
                love.graphics.draw(monster_img, monster_quads[frame], draw_x, draw_y, 0, sprite_size / TEX_SIZE, sprite_size / TEX_SIZE)

                -- Overlay articulated spindly clawing arms with sharp taloned claws & long wagging tongue
                drawAnimatedMonsterAppendages(m, screen_x, draw_y, sprite_size, shade, now)
            end
        end
    end

    -- 3. First-Person Plasma Blaster & Muzzle Flash
    local bob_x = (game_state == "playing") and (math.sin(now * 6) * 8) or 0
    local bob_y = (game_state == "playing") and (math.abs(math.cos(now * 6)) * 6) or 35
    local recoil = player.muzzle_timer * 180

    if player.muzzle_timer > 0 then
        love.graphics.setColor(1.0, 0.85, 0.35, 0.9)
        love.graphics.circle("fill", 800 + bob_x, 665 + bob_y + recoil, 55)
    end
    love.graphics.setColor(0.26, 0.29, 0.36, 1)
    love.graphics.polygon("fill", 745 + bob_x, 900, 775 + bob_x, 680 + bob_y + recoil, 825 + bob_x, 680 + bob_y + recoil, 855 + bob_x, 900)
    love.graphics.setColor(0.35, 0.88, 1.0, 1)
    love.graphics.rectangle("fill", 790 + bob_x, 700 + bob_y + recoil, 20, 95, 4, 4)

    -- Crosshair
    love.graphics.setColor(0.35, 1.0, 0.55, 0.85)
    love.graphics.setLineWidth(2)
    love.graphics.line(786, 450, 814, 450)
    love.graphics.line(800, 436, 800, 464)

    -- Hurt flash overlay
    if player.hurt_timer > 0 then
        love.graphics.setColor(0.9, 0.1, 0.1, player.hurt_timer * 0.45)
        love.graphics.rectangle("fill", 0, 0, 1600, 900)
    end

    -- Top HUD & Mini-Map
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 20, 20, 180, 180, 6, 6)
    local cell = 10
    for r = 1, #MAP do
        for c = 1, #MAP[1] do
            if MAP[r][c] > 0 then
                love.graphics.setColor(0.55, 0.6, 0.7, 1)
                love.graphics.rectangle("fill", 22 + (c - 1) * cell, 22 + (r - 1) * cell, cell - 1, cell - 1)
            end
        end
    end
    for _, m in ipairs(monsters) do
        if m.alive then
            love.graphics.setColor(1, 0.25, 0.3, 1)
            love.graphics.circle("fill", 22 + (m.x - 1) * cell, 22 + (m.y - 1) * cell, 3)
        end
    end
    love.graphics.setColor(0.2, 1, 0.4, 1)
    love.graphics.circle("fill", 22 + (player.x - 1) * cell, 22 + (player.y - 1) * cell, 3.5)

    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 220, 20, 1360, 52, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        string.format(
            "WOLFENDOOM 3D  |  HP: %d%%  |  FRAGS: %d (Monsters Respawn!)  |  WASD: Move/Strafe | Left/Right or Q/E: Turn | Space/Click: Fire",
            player.hp,
            player.kills
        ),
        245,
        36,
        0,
        1.18,
        1.18
    )

    -- Crimson Red Death Screen Overlay ("Game Over! - restart? y/n")
    if game_state == "game_over" or game_state == "quit_declined" then
        local prev_font = love.graphics.getFont()
        local pulse = 0.78 + math.sin(now * 4) * 0.06

        -- Full-screen crimson blood wash
        love.graphics.setColor(0.58, 0.02, 0.04, pulse)
        love.graphics.rectangle("fill", 0, 0, 1600, 900)

        -- Dark crimson center modal
        love.graphics.setColor(0.18, 0.01, 0.02, 0.94)
        love.graphics.rectangle("fill", 330, 260, 940, 340, 16, 16)
        love.graphics.setColor(0.98, 0.22, 0.24, 1)
        love.graphics.setLineWidth(4)
        love.graphics.rectangle("line", 330, 260, 940, 340, 16, 16)

        love.graphics.setFont(font_death_lg)
        love.graphics.setColor(1.0, 0.92, 0.92, 1)
        love.graphics.printf("Game Over! - restart? y/n", 330, 320, 940, "center")

        love.graphics.setFont(font_death_md)
        love.graphics.setColor(1.0, 0.72, 0.72, 0.95)
        if game_state == "quit_declined" then
            love.graphics.printf(string.format("Final Frags: %d   —   Farewell, Marine! (Press Y or click Yes to play again)", player.kills), 330, 425, 940, "center")
        else
            love.graphics.printf(string.format("Final Frags: %d   —   Press [Y] or [N] on keyboard (or click below)", player.kills), 330, 425, 940, "center")
        end

        -- Interactive [Y] Restart & [N] Quit buttons (also respond to Y / N keys)
        love.graphics.setColor(0.20, 0.65, 0.30, 1)
        love.graphics.rectangle("fill", 510, 500, 265, 62, 10, 10)
        love.graphics.setColor(0.45, 0.95, 0.55, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 510, 500, 265, 62, 10, 10)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("[Y] Yes - Restart", 510, 517, 265, "center")

        love.graphics.setColor(0.68, 0.14, 0.16, 1)
        love.graphics.rectangle("fill", 825, 500, 265, 62, 10, 10)
        love.graphics.setColor(1.0, 0.45, 0.45, 1)
        love.graphics.rectangle("line", 825, 500, 265, 62, 10, 10)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("[N] No - Quit", 825, 517, 265, "center")

        love.graphics.setFont(prev_font)
    end
end
