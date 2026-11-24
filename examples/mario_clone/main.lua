love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";../../?.lua;../../?/init.lua")
package.path = "../../?.lua;../../?/init.lua;" .. package.path

local lovemap = require("src.lovemap")

local TILE = 60 -- 15 rows * 60 = 900 virtual height
local GRAVITY = 1850
local JUMP_VEL = -880
local MOVE_SPEED = 390

-- 3 Self-Contained 15-Row Tilemaps
-- All platforms, blocks, and pipes are stepped at 2-tile vertical increments (120px)
-- with generous horizontal runways so every jump is easily reachable with ZERO air control.
-- Sewer pipes ('P') are placed on solid ground and automatically extend all the way to the ground.
-- Legend: '#' Ground, 'B' Brick, '?' Question Coin Block, 'P' Pipe, '^' Hazard Spikes,
--         'C' Floating Coin, 'E' Goomba Enemy, 'F' Goal Flagpole
local LEVELS = {
    {
        name = "Level 1-1: Green Hills",
        sky = { 0.36, 0.58, 0.98, 1.0 },
        ground_col = { 0.78, 0.42, 0.18, 1.0 },
        rows = {
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                     F",
            "                                        C C C                        F",
            "                   C C C               BBBBBBB                       F",
            "             ?    BBBBBBB                                            F",
            "           BBBBB               BBBBBB            ?B?                 F",
            "     P                    P                 P           BBBB         F",
            "     P        E           P       E         P     E                  F",
            "#####################################  ###############################",
            "#####################################  ###############################",
        },
    },
    {
        name = "Level 1-2: Underground Cavern",
        sky = { 0.08, 0.10, 0.20, 1.0 },
        ground_col = { 0.25, 0.38, 0.65, 1.0 },
        rows = {
            "######################################################################",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                   C   C   C                         F",
            "                                  BBBBBBBBBBB                        F",
            "                      C C C                         C C              F",
            "                     BBBBBBB                       BBBBB             F",
            "              ?B?           BBBBBB           BBBBB                   F",
            "        BBBBB          P                                  P          F",
            "            E          P      E                  E        P          F",
            "###################  ##########^^^############  ######################",
            "######################################################################",
        },
    },
    {
        name = "Level 1-3: Sunset Fortress",
        sky = { 0.22, 0.10, 0.16, 1.0 },
        ground_col = { 0.55, 0.52, 0.58, 1.0 },
        rows = {
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                                                      ",
            "                                               C C C                 F",
            "                                              BBBBBBB                F",
            "                            C   C                       C C          F",
            "                           BBBBBBB                     BBBBB         F",
            "                 ?B?              BBBBBB      BBBBBB                 F",
            "        BBBBB         BBBBBB                                P        F",
            "              E                 E                 E         P        F",
            "######  #####^^^#######  #######^^^######  ######^^^#####  ###########",
            "######  ###############  ################  ##############  ###########",
        },
    },
}

local level_idx = 1
local grid = {}
local map_w = 0
local map_h = 15
local coins = {}
local enemies = {}
local particles = {}
local flag_x = 0
local cam_x = 0
local score = 0
local coin_count = 0
local lives = 3
local state = "playing" -- "playing", "level_clear", "game_won", "game_over"
local state_timer = 0
local player = {}

local function loadLevel(idx)
    level_idx = idx
    local def = LEVELS[level_idx]
    lovemap.background = def.sky
    grid = {}
    coins = {}
    enemies = {}
    particles = {}
    map_h = #def.rows
    map_w = #def.rows[1]
    flag_x = (map_w - 2) * TILE

    for r = 1, map_h do
        grid[r] = {}
        local row_str = def.rows[r]
        for c = 1, map_w do
            local ch = row_str:sub(c, c)
            if ch == "C" then
                table.insert(coins, { x = (c - 0.5) * TILE, y = (r - 0.5) * TILE, taken = false })
                grid[r][c] = " "
            elseif ch == "E" then
                table.insert(enemies, {
                    x = (c - 1) * TILE + 8,
                    y = (r - 1) * TILE + 12,
                    w = 44,
                    h = 48,
                    vx = -125,
                    vy = 0,
                    alive = true,
                })
                grid[r][c] = " "
            elseif ch == "F" then
                flag_x = (c - 0.5) * TILE
                grid[r][c] = " "
            else
                grid[r][c] = ch
            end
        end
    end

    -- Ensure every sewer pipe ('P') extends all the way down to solid ground (or bottom of map)
    for c = 1, map_w do
        local pipe_started = false
        for r = 1, map_h do
            if grid[r][c] == "P" then
                pipe_started = true
            elseif pipe_started then
                if grid[r][c] == "#" then
                    break
                else
                    grid[r][c] = "P"
                end
            end
        end
    end

    player = {
        x = 2 * TILE,
        y = 11 * TILE - 52,
        w = 44,
        h = 52,
        vx = 0,
        vy = 0,
        on_ground = false,
        facing = 1,
        anim_timer = 0,
    }
    cam_x = 0
    state = "playing"
    state_timer = 0
end

local function isSolid(ch)
    return ch == "#" or ch == "B" or ch == "?" or ch == "U" or ch == "P" or ch == "^"
end

local function spawnPop(x, y, col, text)
    table.insert(particles, { x = x, y = y, vy = -180, age = 0, life = 0.7, col = col, text = text })
end

local function loseLife()
    lives = lives - 1
    if lives <= 0 then
        state = "game_over"
    else
        loadLevel(level_idx)
    end
end

local function moveAndCollide(ent, dt, is_player)
    -- Horizontal movement
    ent.x = ent.x + ent.vx * dt
    local c1 = math.floor(ent.x / TILE) + 1
    local c2 = math.floor((ent.x + ent.w - 0.01) / TILE) + 1
    local r1 = math.floor(ent.y / TILE) + 1
    local r2 = math.floor((ent.y + ent.h - 0.01) / TILE) + 1

    for r = math.max(1, r1), math.min(map_h, r2) do
        for c = math.max(1, c1), math.min(map_w, c2) do
            local ch = grid[r][c]
            if isSolid(ch) then
                if ent.vx > 0 then
                    ent.x = (c - 1) * TILE - ent.w
                    if not is_player then ent.vx = -ent.vx end
                elseif ent.vx < 0 then
                    ent.x = c * TILE
                    if not is_player then ent.vx = -ent.vx end
                end
            end
        end
    end

    -- Vertical movement
    ent.vy = ent.vy + GRAVITY * dt
    ent.y = ent.y + ent.vy * dt
    ent.on_ground = false

    c1 = math.floor(ent.x / TILE) + 1
    c2 = math.floor((ent.x + ent.w - 0.01) / TILE) + 1
    r1 = math.floor(ent.y / TILE) + 1
    r2 = math.floor((ent.y + ent.h - 0.01) / TILE) + 1

    for r = math.max(1, r1), math.min(map_h, r2) do
        for c = math.max(1, c1), math.min(map_w, c2) do
            local ch = grid[r][c]
            if isSolid(ch) then
                if is_player and ch == "^" then
                    loseLife()
                    return
                end
                if ent.vy > 0 then
                    ent.y = (r - 1) * TILE - ent.h
                    ent.vy = 0
                    ent.on_ground = true
                elseif ent.vy < 0 then
                    ent.y = r * TILE
                    ent.vy = 0
                    if is_player and ch == "?" then
                        grid[r][c] = "U"
                        coin_count = coin_count + 1
                        score = score + 200
                        spawnPop((c - 0.5) * TILE, (r - 1) * TILE, { 1, 0.9, 0.2, 1 }, "+200")
                    elseif is_player and ch == "B" then
                        grid[r][c] = " "
                        score = score + 50
                        spawnPop((c - 0.5) * TILE, (r - 0.5) * TILE, { 0.85, 0.45, 0.25, 1 }, "BREAK!")
                    end
                end
            end
        end
    end
end

function love.load()
    lovemap.aspect(16, 9)
    loadLevel(1)
end

function love.update(dt)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.age = p.age + dt
        p.y = p.y + p.vy * dt
        if p.age >= p.life then
            table.remove(particles, i)
        end
    end

    if state == "level_clear" then
        state_timer = state_timer + dt
        if state_timer > 1.4 then
            if level_idx < #LEVELS then
                loadLevel(level_idx + 1)
            else
                state = "game_won"
            end
        end
        return
    elseif state == "game_won" or state == "game_over" then
        if love.keyboard.isDown("r", "space", "return") then
            lives = 3
            score = 0
            coin_count = 0
            loadLevel(1)
        end
        return
    end

    -- Player controls: ZERO air control (horizontal velocity can only be changed while on_ground)
    if player.on_ground then
        player.vx = 0
        if love.keyboard.isDown("left", "a") then
            player.vx = -MOVE_SPEED
            player.facing = -1
        end
        if love.keyboard.isDown("right", "d") then
            player.vx = MOVE_SPEED
            player.facing = 1
        end
        if love.keyboard.isDown("space", "up", "w") then
            player.vy = JUMP_VEL
            player.on_ground = false
        end
    end

    -- Advance walk animation cycle
    if player.on_ground and math.abs(player.vx) > 1 then
        player.anim_timer = player.anim_timer + dt * 14
    elseif player.on_ground then
        player.anim_timer = 0
    end

    moveAndCollide(player, dt, true)
    if state ~= "playing" then return end

    -- Pit fall check
    if player.y > lovemap.height + 80 then
        loseLife()
        return
    end

    -- Collect floating coins
    local px, py = player.x + player.w * 0.5, player.y + player.h * 0.5
    for _, c in ipairs(coins) do
        if not c.taken and math.abs(px - c.x) < 36 and math.abs(py - c.y) < 36 then
            c.taken = true
            coin_count = coin_count + 1
            score = score + 100
            spawnPop(c.x, c.y, { 1, 0.9, 0.2, 1 }, "+100")
        end
    end

    -- Update enemies & stomp / hurt checks
    for _, e in ipairs(enemies) do
        if e.alive then
            moveAndCollide(e, dt, false)
            if player.x + player.w > e.x and player.x < e.x + e.w and player.y + player.h > e.y and player.y < e.y + e.h then
                if player.vy > 0 and (player.y + player.h - player.vy * dt) <= e.y + 18 then
                    e.alive = false
                    player.vy = JUMP_VEL * 0.65
                    score = score + 250
                    spawnPop(e.x + 20, e.y, { 0.4, 1.0, 0.5, 1 }, "STOMP +250")
                else
                    loseLife()
                    return
                end
            end
        end
    end

    -- Reach the goal flagpole
    if player.x + player.w >= flag_x then
        score = score + 1000
        state = "level_clear"
        state_timer = 0
        spawnPop(flag_x, player.y, { 0.3, 1.0, 0.4, 1 }, "COURSE CLEAR! +1000")
    end

    -- Smooth camera follow
    local target_cam = math.max(0, math.min(map_w * TILE - lovemap.width, player.x - lovemap.width * 0.35))
    cam_x = cam_x + (target_cam - cam_x) * math.min(1, dt * 10)
end

-- Draws the small animated fat dude with a red baseball cap, blue suit, and red tie
local function drawFatSuitHero(p)
    local cx = p.x + p.w * 0.5
    local cy = p.y
    local dir = p.facing
    local walk = math.sin(p.anim_timer)
    local bob = (p.on_ground and math.abs(p.vx) > 1) and math.abs(math.cos(p.anim_timer)) * 2.5 or 0
    local in_air = not p.on_ground

    -- 1. Animated Legs (Blue suit trousers + dark dress shoes)
    local left_leg_off = in_air and -5 or (walk * 6)
    local right_leg_off = in_air and 5 or (-walk * 6)

    -- Back leg
    love.graphics.setColor(0.11, 0.22, 0.55, 1)
    love.graphics.rectangle("fill", cx - 10 + right_leg_off, cy + 37 - bob, 10, 12, 3, 3)
    love.graphics.setColor(0.15, 0.14, 0.16, 1)
    love.graphics.ellipse("fill", cx - 5 + right_leg_off + dir * 2, cy + 50 - bob, 7, 3.5)

    -- Front leg
    love.graphics.setColor(0.15, 0.30, 0.72, 1)
    love.graphics.rectangle("fill", cx + left_leg_off, cy + 37 - bob, 10, 12, 3, 3)
    love.graphics.setColor(0.18, 0.16, 0.18, 1)
    love.graphics.ellipse("fill", cx + 5 + left_leg_off + dir * 2, cy + 50 - bob, 7, 3.5)

    -- 2. Back Arm (swinging blue suit sleeve + chubby hand)
    local arm_swing = in_air and -6 or (-walk * 7)
    love.graphics.setColor(0.12, 0.25, 0.62, 1)
    love.graphics.ellipse("fill", cx - dir * 13 + arm_swing * 0.4, cy + 28 - bob, 7, 9)
    love.graphics.setColor(0.98, 0.78, 0.64, 1)
    love.graphics.circle("fill", cx - dir * 14 + arm_swing * 0.6, cy + 35 - bob, 4.5)

    -- 3. Fat Round Belly in Blue Suit Jacket
    love.graphics.setColor(0.16, 0.34, 0.80, 1)
    love.graphics.ellipse("fill", cx + dir * 2, cy + 29 - bob, 22, 15)
    -- Subtle dark blue jacket outline / lapels
    love.graphics.setColor(0.10, 0.20, 0.52, 1)
    love.graphics.setLineWidth(1.5)
    love.graphics.ellipse("line", cx + dir * 2, cy + 29 - bob, 22, 15)

    -- 4. Crisp White Shirt Collar / V-Neck
    love.graphics.setColor(0.96, 0.97, 1.0, 1)
    love.graphics.polygon(
        "fill",
        cx - 7 + dir * 3, cy + 16 - bob,
        cx + 7 + dir * 3, cy + 16 - bob,
        cx + dir * 4,     cy + 29 - bob
    )

    -- 5. Animated Red Tie (knot + flapping tie blade over the round belly)
    local tie_sway = -p.vx * 0.012 + (in_air and -3 * dir or walk * 2.0)
    love.graphics.setColor(0.88, 0.12, 0.15, 1)
    love.graphics.circle("fill", cx + dir * 3.5, cy + 18 - bob, 3)
    love.graphics.polygon(
        "fill",
        cx + dir * 2,                cy + 20 - bob,
        cx + dir * 5,                cy + 20 - bob,
        cx + dir * 6 + tie_sway,     cy + 35 - bob,
        cx + dir * 3.5 + tie_sway,   cy + 39 - bob,
        cx + dir * 1 + tie_sway,     cy + 35 - bob
    )

    -- 6. Front Arm (blue suit sleeve + chubby hand)
    local front_arm_y = in_air and (cy + 21 - bob) or (cy + 28 - bob)
    love.graphics.setColor(0.20, 0.40, 0.88, 1)
    love.graphics.ellipse("fill", cx + dir * 8 - arm_swing * 0.5, front_arm_y, 7, 9)
    love.graphics.setColor(0.98, 0.78, 0.64, 1)
    love.graphics.circle("fill", cx + dir * 9 - arm_swing * 0.7, front_arm_y + (in_air and -6 or 7), 4.5)

    -- 7. Chubby Round Head & Rosy Cheek
    love.graphics.setColor(0.98, 0.80, 0.64, 1)
    love.graphics.ellipse("fill", cx + dir * 1, cy + 11 - bob, 13.5, 10.5)
    -- Chubby double-chin / rosy cheek
    love.graphics.setColor(0.95, 0.58, 0.52, 0.65)
    love.graphics.circle("fill", cx + dir * 7, cy + 13 - bob, 3.2)
    -- Round nose
    love.graphics.setColor(0.94, 0.70, 0.54, 1)
    love.graphics.circle("fill", cx + dir * 13, cy + 11 - bob, 3)
    -- Eye
    love.graphics.setColor(0.12, 0.12, 0.15, 1)
    love.graphics.circle("fill", cx + dir * 8, cy + 9 - bob, 2.0)

    -- 8. Red Baseball Cap (rounded dome + long visor pointing in facing direction)
    love.graphics.setColor(0.90, 0.14, 0.16, 1)
    love.graphics.arc("fill", cx + dir * 1, cy + 7 - bob, 14, math.pi, math.pi * 2)
    -- Baseball cap top button
    love.graphics.setColor(0.70, 0.08, 0.10, 1)
    love.graphics.circle("fill", cx + dir * 1, cy - 7 - bob, 2)
    -- White cap front emblem
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", cx + dir * 8, cy + 2 - bob, 2.3)
    -- Baseball cap visor / brim
    love.graphics.setColor(0.82, 0.10, 0.12, 1)
    if dir == 1 then
        love.graphics.rectangle("fill", cx + 2, cy + 4 - bob, 20, 4.5, 2, 2)
    else
        love.graphics.rectangle("fill", cx - 22, cy + 4 - bob, 20, 4.5, 2, 2)
    end
end

function lovemap.draw()
    local def = LEVELS[level_idx]

    love.graphics.push()
    love.graphics.translate(-math.floor(cam_x), 0)

    -- Decorative background clouds / pillars
    love.graphics.setColor(1, 1, 1, 0.14)
    for i = 1, 14 do
        love.graphics.circle("fill", i * 340, 170 + (i % 3) * 65, 55)
        love.graphics.circle("fill", i * 340 + 45, 175 + (i % 3) * 65, 42)
    end

    -- Draw flagpole
    love.graphics.setColor(0.85, 0.88, 0.92, 1)
    love.graphics.rectangle("fill", flag_x - 4, 5 * TILE, 8, 8 * TILE)
    love.graphics.setColor(1.0, 0.85, 0.2, 1)
    love.graphics.circle("fill", flag_x, 5 * TILE, 14)
    love.graphics.setColor(0.2, 0.88, 0.35, 1)
    love.graphics.polygon("fill", flag_x + 4, 5 * TILE + 8, flag_x + 76, 5 * TILE + 34, flag_x + 4, 5 * TILE + 60)

    -- Draw tiles
    for r = 1, map_h do
        for c = 1, map_w do
            local ch = grid[r][c]
            local tx, ty = (c - 1) * TILE, (r - 1) * TILE
            if ch == "#" then
                love.graphics.setColor(def.ground_col)
                love.graphics.rectangle("fill", tx, ty, TILE - 2, TILE - 2, 4, 4)
                love.graphics.setColor(0.25, 0.78, 0.32, 1)
                love.graphics.rectangle("fill", tx, ty, TILE - 2, 10, 3, 3)
            elseif ch == "B" then
                love.graphics.setColor(0.72, 0.32, 0.18, 1)
                love.graphics.rectangle("fill", tx + 1, ty + 1, TILE - 2, TILE - 2, 4, 4)
            elseif ch == "?" then
                love.graphics.setColor(0.98, 0.78, 0.18, 1)
                love.graphics.rectangle("fill", tx + 1, ty + 1, TILE - 2, TILE - 2, 6, 6)
                love.graphics.setColor(0.45, 0.25, 0.05, 1)
                love.graphics.print("?", tx + 24, ty + 18, 0, 1.5, 1.5)
            elseif ch == "U" then
                love.graphics.setColor(0.45, 0.42, 0.38, 1)
                love.graphics.rectangle("fill", tx + 1, ty + 1, TILE - 2, TILE - 2, 4, 4)
            elseif ch == "P" then
                local is_top = (r == 1) or (grid[r - 1][c] ~= "P")
                -- Pipe body shaft
                love.graphics.setColor(0.16, 0.68, 0.26, 1)
                love.graphics.rectangle("fill", tx + 3, ty, TILE - 6, TILE)
                -- Specular vertical highlight on pipe shaft
                love.graphics.setColor(0.34, 0.88, 0.42, 0.65)
                love.graphics.rectangle("fill", tx + 10, ty, 10, TILE)
                -- Only draw the wide sewer pipe rim at the very top tile of the pipe
                if is_top then
                    love.graphics.setColor(0.22, 0.80, 0.32, 1)
                    love.graphics.rectangle("fill", tx - 3, ty, TILE + 6, 18, 4, 4)
                    love.graphics.setColor(0.42, 0.95, 0.50, 0.75)
                    love.graphics.rectangle("fill", tx + 6, ty + 2, 12, 14, 2, 2)
                end
            elseif ch == "^" then
                love.graphics.setColor(0.92, 0.22, 0.22, 1)
                love.graphics.polygon("fill", tx, ty + TILE, tx + TILE * 0.5, ty + 14, tx + TILE, ty + TILE)
            end
        end
    end

    -- Draw floating coins
    love.graphics.setColor(1.0, 0.86, 0.18, 1)
    for _, c in ipairs(coins) do
        if not c.taken then
            love.graphics.circle("fill", c.x, c.y, 15)
            love.graphics.setColor(0.85, 0.62, 0.10, 1)
            love.graphics.circle("line", c.x, c.y, 15)
            love.graphics.setColor(1.0, 0.86, 0.18, 1)
        end
    end

    -- Draw Goomba enemies
    for _, e in ipairs(enemies) do
        if e.alive then
            love.graphics.setColor(0.58, 0.30, 0.16, 1)
            love.graphics.rectangle("fill", e.x, e.y, e.w, e.h, 14, 14)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("fill", e.x + 12, e.y + 18, 5)
            love.graphics.circle("fill", e.x + e.w - 12, e.y + 18, 5)
            love.graphics.setColor(0.1, 0.1, 0.1, 1)
            love.graphics.circle("fill", e.x + 12, e.y + 18, 2.5)
            love.graphics.circle("fill", e.x + e.w - 12, e.y + 18, 2.5)
        end
    end

    -- Draw our animated fat dude in a blue suit, red tie, and red baseball cap
    drawFatSuitHero(player)

    -- Floating score popups
    for _, p in ipairs(particles) do
        love.graphics.setColor(p.col)
        love.graphics.print(p.text, p.x - 20, p.y, 0, 1.3, 1.3)
    end

    love.graphics.pop()

    -- Top HUD Bar
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 20, 16, 1560, 48, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        string.format(
            "%s   |   SCORE: %05d   |   COINS: %02d   |   LIVES: %d   |   A/D or Arrows: Walk (Zero Air Control), Space/W/Up: Jump",
            def.name,
            score,
            coin_count,
            lives
        ),
        34,
        32,
        0,
        1.15,
        1.15
    )

    if state == "level_clear" then
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", 500, 360, 600, 140, 12, 12)
        love.graphics.setColor(0.3, 1.0, 0.45, 1)
        love.graphics.print("COURSE CLEAR!", 670, 410, 0, 2.2, 2.2)
    elseif state == "game_won" or state == "game_over" then
        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.rectangle("fill", 440, 320, 720, 220, 14, 14)
        love.graphics.setColor(1, 0.9, 0.3, 1)
        local msg = state == "game_won" and "CONGRATULATIONS! ALL 3 LEVELS CLEARED!" or "GAME OVER"
        love.graphics.print(msg, 510, 375, 0, 1.8, 1.8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Press SPACE or R to play again", 630, 450, 0, 1.4, 1.4)
    end
end
