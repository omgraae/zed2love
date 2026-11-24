love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";../../?.lua;../../?/init.lua")
package.path = "../../?.lua;../../?/init.lua;" .. package.path

local lovemap = require("src.lovemap")

local MAP_SIZE = 28 -- 28x28 large isometric map
local TILE_W = 84
local TILE_H = 42

-- Gentle, flatter elevation profile so hills and highlands only partially overlap
-- the lower edge of nearby cities rather than covering them completely
local BIOMES = {
    water  = { name = "Deep Water",    col = { 0.16, 0.44, 0.74, 1 }, elev = 0 },
    coast  = { name = "Shallow Cove",  col = { 0.25, 0.58, 0.82, 1 }, elev = 3 },
    meadow = { name = "Lush Meadow",   col = { 0.34, 0.68, 0.36, 1 }, elev = 10 },
    forest = { name = "Ancient Woods", col = { 0.20, 0.52, 0.28, 1 }, elev = 13 },
    hills  = { name = "Golden Hills",  col = { 0.62, 0.64, 0.32, 1 }, elev = 18 },
    peak   = { name = "Highlands",     col = { 0.72, 0.74, 0.78, 1 }, elev = 24 },
}

local DISASTERS = {
    { name = "Monsoon Flood",    color = { 0.28, 0.76, 1.00, 1 }, cost_food = 12, cost_timber = 18 },
    { name = "Summer Drought",   color = { 1.00, 0.68, 0.20, 1 }, cost_food = 22, cost_timber = 8  },
    { name = "Landslide Tremor", color = { 0.98, 0.36, 0.30, 1 }, cost_food = 10, cost_timber = 22 },
    { name = "Blighted Harvest", color = { 0.86, 0.46, 0.98, 1 }, cost_food = 25, cost_timber = 10 },
}

local tiles = {}
local settlements = {}
local settlement_at = {} -- settlement_at[gx][gy] = index
local routes = {}        -- { from = idx, to = idx }
local clouds = {}        -- drifting procedural clouds
local selected_idx = 1
local hover_gx, hover_gy = 14, 14
local cam_x, cam_y = 800, 150
local CAM_START_X, CAM_START_Y = cam_x, cam_y

-- Cloud parallax: 1.0 = glued to the landscape, 0.0 = fixed to the screen.
-- 1.12 makes the clouds slide slightly faster than the terrain: they are nearer the camera.
local CLOUD_PARALLAX = 1.12
local CLOUD_COUNT = 14
local CLOUD_FIELD_W, CLOUD_FIELD_H = 2400, 1500   -- wrapping area (larger than the 1600x900 view)
local CLOUD_MARGIN_X, CLOUD_MARGIN_Y = 400, 300   -- off-screen band so clouds wrap out of sight

--- Screen position of a cloud: its drift position plus a parallax share of the camera
--- offset, wrapped inside the cloud field so the sky never runs out while panning.
local function cloudScreenPos(c)
    local x = c.x + (cam_x - CAM_START_X) * CLOUD_PARALLAX
    local y = c.y + (cam_y - CAM_START_Y) * CLOUD_PARALLAX
    x = (x + CLOUD_MARGIN_X) % CLOUD_FIELD_W - CLOUD_MARGIN_X
    y = (y + CLOUD_MARGIN_Y) % CLOUD_FIELD_H - CLOUD_MARGIN_Y
    return x, y
end
local turn = 1
local harmony = 40
local food = 65
local timber = 65
local knowledge = 30
local aids_sent = 0
local log_messages = {}

-- Fonts (larger, crisp typography across all panels & map labels)
local font_sm
local font_md
local font_lg
local font_xl

-- Shaders & procedural cloud texture
local pulse_fx
local cloud_shader
local cloud_tex

-- Achievement Popup System
local unlocked_achievements = {}
local active_popups = {} -- { title, desc, timer, max_time }
local unlocked_count = 0

local function unlockAchievement(id, title, desc)
    if unlocked_achievements[id] then return end
    unlocked_achievements[id] = true
    unlocked_count = unlocked_count + 1
    table.insert(active_popups, {
        title = title,
        desc = desc,
        timer = 5.5,
        max_time = 5.5,
    })
    table.insert(log_messages, 1, string.format("[ACHIEVEMENT] %s — %s", title, desc))
    if #log_messages > 5 then
        table.remove(log_messages)
    end
end

local function addLog(msg)
    table.insert(log_messages, 1, string.format("[Turn %d] %s", turn, msg))
    if #log_messages > 5 then
        table.remove(log_messages)
    end
end

local function isoToScreen(gx, gy, elev)
    elev = elev or 0
    local sx = cam_x + (gx - gy) * (TILE_W * 0.5)
    local sy = cam_y + (gx + gy) * (TILE_H * 0.5) - elev
    return sx, sy
end

local function screenToIso(sx, sy)
    local dx = sx - cam_x
    local dy = sy - cam_y
    local gx = math.floor((dx / (TILE_W * 0.5) + dy / (TILE_H * 0.5)) * 0.5 + 0.5)
    local gy = math.floor((dy / (TILE_H * 0.5) - dx / (TILE_W * 0.5)) * 0.5 + 0.5)
    return gx, gy
end

local function hasRoute(a, b)
    for _, r in ipairs(routes) do
        if (r.from == a and r.to == b) or (r.from == b and r.to == a) then
            return true
        end
    end
    return false
end

local function isConnectedToNetwork(target_idx)
    local visited = { [1] = true }
    local queue = { 1 }
    while #queue > 0 do
        local curr = table.remove(queue, 1)
        if curr == target_idx then return true end
        for _, r in ipairs(routes) do
            local nxt = (r.from == curr and r.to) or (r.to == curr and r.from) or nil
            if nxt and not visited[nxt] then
                visited[nxt] = true
                table.insert(queue, nxt)
            end
        end
    end
    return false
end

local function checkHarmonyAchievements(partner_a, partner_b)
    local connected_count = 0
    for i = 1, #settlements do
        if isConnectedToNetwork(i) then
            connected_count = connected_count + 1
        end
    end

    if #routes >= 2 then
        unlockAchievement("first_accord", "First Accord of Friendship", "Established your first new trade route between sister settlements.")
    end
    if connected_count >= 5 then
        unlockAchievement("golden_web", "Golden Trade Web", "Connected 5 civilizations in cooperative prosperity.")
    end
    if connected_count >= #settlements then
        unlockAchievement("all_connected", "Grand Archipelago Alliance", "United all 8 peaceful civilizations in a single cooperative network!")
    end
    if aids_sent >= 1 then
        unlockAchievement("first_aid", "Hands Across the Water", "Dispatched an emergency relief convoy to a city in trouble.")
    end
    if aids_sent >= 3 then
        unlockAchievement("lifesavers", "Guardians of Mutual Aid", "Rescued 3 settlements from natural emergencies through solidarity.")
    end

    if partner_a and partner_b then
        local sa, sb = settlements[partner_a], settlements[partner_b]
        local pair_harmony = math.min(100, math.floor((sa.bond + sb.bond) * 0.5))
        if pair_harmony >= 60 then
            unlockAchievement(
                "pair_60_" .. math.min(partner_a, partner_b) .. "_" .. math.max(partner_a, partner_b),
                "Sister Cities in Harmony (60+)",
                string.format("%s & %s reached %d%% bilateral Harmony!", sa.name, sb.name, pair_harmony)
            )
        end
        if pair_harmony >= 85 then
            unlockAchievement(
                "pair_85_" .. math.min(partner_a, partner_b) .. "_" .. math.max(partner_a, partner_b),
                "Radiant Concord (85+)",
                string.format("An unbreakable bond of %d%% Harmony flourishes between %s & %s!", pair_harmony, sa.name, sb.name)
            )
        end
    end

    if harmony >= 75 then
        unlockAchievement("global_75", "Chorus of the Archipelago", "Global Harmony across all civilizations reached 75/100!")
    end
    if harmony >= 100 then
        unlockAchievement("global_100", "Utopian Enlightenment", "Reached 100/100 Global Harmony — a golden age of peace and mutual aid!")
    end
end

local function generateWorld()
    tiles = {}
    settlement_at = {}
    for gx = 1, MAP_SIZE do
        tiles[gx] = {}
        settlement_at[gx] = {}
        for gy = 1, MAP_SIZE do
            local n = love.math.noise(gx * 0.13 + 3.1, gy * 0.13 + 7.4)
            local dist_edge = math.min(gx - 1, gy - 1, MAP_SIZE - gx, MAP_SIZE - gy) / 6.0
            local h = n * math.min(1.0, dist_edge)
            local b = "water"
            if h > 0.70 then b = "peak"
            elseif h > 0.56 then b = "hills"
            elseif h > 0.43 then b = "forest"
            elseif h > 0.28 then b = "meadow"
            elseif h > 0.18 then b = "coast"
            end
            tiles[gx][gy] = { biome = b, road = false }
        end
    end

    -- Place 8 peaceful sister civilizations across the archipelago, each with a unique fantasy architectural style!
    local civ_defs = {
        { name = "Aurelia",        style = "high_castle",       style_label = "High Castle",        gx = 14, gy = 14, color = { 0.98, 0.84, 0.28, 1 } },
        { name = "Sylvan Havens",  style = "sylvan_city",       style_label = "Sylvan Tree-City",   gx = 8,  gy = 11, color = { 0.35, 0.92, 0.52, 1 } },
        { name = "Coralia Reach",  style = "coral_citadel",     style_label = "Tidal Coral Spire",  gx = 20, gy = 10, color = { 0.32, 0.84, 0.98, 1 } },
        { name = "Sunspire",       style = "desert_temple",     style_label = "Desert Temple",      gx = 10, gy = 20, color = { 0.98, 0.62, 0.28, 1 } },
        { name = "Verdant Hollow", style = "walled_garden",     style_label = "Walled Garden",      gx = 21, gy = 19, color = { 0.58, 0.95, 0.38, 1 } },
        { name = "Cloudcrest",     style = "sky_observatory",   style_label = "Astral Citadel",     gx = 6,  gy = 6,  color = { 0.78, 0.62, 0.98, 1 } },
        { name = "Ambergranary",   style = "terrace_granary",   style_label = "Windmill Cloister",  gx = 16, gy = 23, color = { 0.95, 0.76, 0.35, 1 } },
        { name = "Lumina Port",    style = "harbor_lighthouse", style_label = "Pharos Harbor",      gx = 23, gy = 14, color = { 0.45, 0.95, 0.85, 1 } },
    }

    settlements = {}
    for i, c in ipairs(civ_defs) do
        tiles[c.gx][c.gy].biome = "meadow"
        -- Keep the diagonal front tile (gx+1, gy+1) open meadow so no mountain ever blocks the center of a city,
        -- while placing a gentle hill or highland off to one side ((gx+1, gy) or (gx, gy+1)) so foreground terrain
        -- only partially overlaps ~20% of one lower corner of the city!
        if c.gx + 1 <= MAP_SIZE and c.gy + 1 <= MAP_SIZE then
            tiles[c.gx + 1][c.gy + 1].biome = "meadow"
        end
        if i == 2 or i == 4 or i == 6 then
            if c.gx + 1 <= MAP_SIZE then
                tiles[c.gx + 1][c.gy].biome = "peak"
            end
        elseif i == 3 or i == 5 or i == 7 then
            if c.gy + 1 <= MAP_SIZE then
                tiles[c.gx][c.gy + 1].biome = "hills"
            end
        end

        settlement_at[c.gx][c.gy] = i
        settlements[i] = {
            id = i,
            name = c.name,
            style = c.style,
            style_label = c.style_label,
            gx = c.gx,
            gy = c.gy,
            color = c.color,
            prosperity = 1,
            bond = (i <= 2) and 45 or 25, -- Harmony bond degree (0..100)
            emergency = nil,
        }
    end

    -- Start with 1 active emergency so the player immediately sees the visual distress indicator!
    settlements[3].emergency = { kind = DISASTERS[1], turns_left = 4 }

    -- Initialize floating fine clouds scattered over a wrapping cloud field
    clouds = {}
    for i = 1, CLOUD_COUNT do
        table.insert(clouds, {
            x = ((i * 0.618034) % 1) * CLOUD_FIELD_W,
            y = ((i * 0.381966 + (i % 3) * 0.29) % 1) * CLOUD_FIELD_H,
            w = 340 + (i % 3) * 90,
            h = 150 + (i % 2) * 55,
            speed = 18 + (i % 4) * 7,
            seed = i * 19.3,
        })
    end

    routes = { { from = 1, to = 2 } }
    selected_idx = 3
    turn = 1
    harmony = 40
    food = 65
    timber = 65
    knowledge = 30
    aids_sent = 0
    unlocked_achievements = {}
    active_popups = {}
    unlocked_count = 0
    log_messages = {}
    addLog("Welcome to Utopia! Coralia Reach faces a Monsoon Flood — select it and send relief aid!")
end

local function endTurn()
    turn = turn + 1

    -- 1. Cooperative Trade & Shared Yields
    local connected_count = 0
    for i = 1, #settlements do
        if isConnectedToNetwork(i) then
            connected_count = connected_count + 1
            settlements[i].bond = math.min(100, settlements[i].bond + 4)
        end
    end
    local gain_food = 10 + connected_count * 4 + #routes * 2
    local gain_timber = 10 + connected_count * 3 + #routes * 2
    local gain_know = 4 + connected_count * 2
    food = food + gain_food
    timber = timber + gain_timber
    knowledge = knowledge + gain_know

    -- Check bilateral harmony achievements along active trade routes
    for _, r in ipairs(routes) do
        checkHarmonyAchievements(r.from, r.to)
    end

    -- 2. Progress active natural emergencies
    local active_emergencies = 0
    for _, s in ipairs(settlements) do
        if s.emergency then
            s.emergency.turns_left = s.emergency.turns_left - 1
            if s.emergency.turns_left <= 0 then
                addLog(s.name .. " weathered the " .. s.emergency.kind.name .. ", though recovery was slow.")
                s.emergency = nil
            else
                active_emergencies = active_emergencies + 1
            end
        end
    end

    -- 3. Chance of a natural emergency striking a settlement
    if active_emergencies < 2 and love.math.random() < 0.65 then
        local idx = love.math.random(1, #settlements)
        local target = settlements[idx]
        if not target.emergency then
            local dis = DISASTERS[love.math.random(1, #DISASTERS)]
            target.emergency = { kind = dis, turns_left = 3 }
            addLog("EMERGENCY: " .. target.name .. " faces a " .. dis.name .. "! Send a relief convoy.")
        end
    else
        harmony = math.min(100, harmony + 2)
        addLog(string.format("Peaceful season: +%d Food, +%d Timber, +%d Knowledge shared.", gain_food, gain_timber, gain_know))
    end

    checkHarmonyAchievements()
end

local function establishTradeRoute(target_idx)
    local best_from = 1
    local best_dist = 9999
    local t_set = settlements[target_idx]
    for i, s in ipairs(settlements) do
        if i ~= target_idx and isConnectedToNetwork(i) and not hasRoute(i, target_idx) then
            local d = math.abs(s.gx - t_set.gx) + math.abs(s.gy - t_set.gy)
            if d < best_dist then
                best_dist = d
                best_from = i
            end
        end
    end

    if target_idx == 1 or hasRoute(best_from, target_idx) then
        addLog("Trade route already active with " .. t_set.name .. ".")
        return
    end
    local cost_t = 20
    local cost_f = 15
    if timber < cost_t or food < cost_f then
        addLog("Need 20 Timber & 15 Food to build a trade route caravan.")
        return
    end
    timber = timber - cost_t
    food = food - cost_f
    table.insert(routes, { from = best_from, to = target_idx })
    harmony = math.min(100, harmony + 10)
    t_set.prosperity = t_set.prosperity + 1
    t_set.bond = math.min(100, t_set.bond + 22)
    settlements[best_from].bond = math.min(100, settlements[best_from].bond + 15)
    addLog("Trade route established between " .. settlements[best_from].name .. " & " .. t_set.name .. "! (+10 Harmony)")
    checkHarmonyAchievements(best_from, target_idx)
end

local function sendReliefAid(target_idx)
    local s = settlements[target_idx]
    if not s or not s.emergency then
        addLog(s.name .. " has no active emergency right now.")
        return
    end
    local dis = s.emergency.kind
    if food < dis.cost_food or timber < dis.cost_timber then
        addLog(string.format("Need %d Food & %d Timber to send relief aid.", dis.cost_food, dis.cost_timber))
        return
    end
    food = food - dis.cost_food
    timber = timber - dis.cost_timber
    s.emergency = nil
    s.prosperity = s.prosperity + 1
    s.bond = math.min(100, s.bond + 28)
    settlements[1].bond = math.min(100, settlements[1].bond + 14)
    aids_sent = aids_sent + 1
    harmony = math.min(100, harmony + 14)
    addLog("Relief convoy arrived at " .. s.name .. "! The " .. dis.name .. " was overcome together. (+14 Harmony)")
    checkHarmonyAchievements(1, target_idx)
end

local function shareFestival(target_idx)
    local s = settlements[target_idx]
    if knowledge < 20 then
        addLog("Need 20 Knowledge to host a Festival of Mutual Aid & Ecology.")
        return
    end
    knowledge = knowledge - 20
    s.prosperity = s.prosperity + 1
    s.bond = math.min(100, s.bond + 20)
    harmony = math.min(100, harmony + 8)
    addLog("Shared ecological knowledge with " .. s.name .. "! Harmony Bond rose to " .. s.bond .. "%.")
    checkHarmonyAchievements(1, target_idx)
end

function love.load()
    love.math.setRandomSeed(os.time())
    lovemap.aspect(16, 9, { background = { 0.10, 0.24, 0.42, 1.0 } })

    font_sm = love.graphics.newFont(16)
    font_md = love.graphics.newFont(18)
    font_lg = love.graphics.newFont(22)
    font_xl = love.graphics.newFont(26)
    love.graphics.setFont(font_md)

    local fx = lovemap.setShaders("vignette")
    fx.vignette.opacity = 0.28

    -- Per-object glow shader for highlighted settlements & emergency beacons
    pulse_fx = lovemap.newEffect("glow")
    pulse_fx.glow.min_luma = 0.25
    pulse_fx.glow.strength = 6

    local id = love.image.newImageData(2, 2)
    id:mapPixel(function() return 1, 1, 1, 1 end)
    cloud_tex = love.graphics.newImage(id)

    -- Fine procedural FBM cloud fragment shader for drifting atmospheric clouds
    cloud_shader = love.graphics.newShader([[
        extern number time;
        extern number seed;

        number hash(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
        }

        number noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(
                mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
                mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
                u.y
            );
        }

        number fbm(vec2 p) {
            number v = 0.0;
            number a = 0.5;
            for (int i = 0; i < 4; i++) {
                v += a * noise(p);
                p = p * 2.15 + vec2(1.7, 9.2);
                a *= 0.5;
            }
            return v;
        }

        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 centered = (tc - vec2(0.5)) * 2.0;
            number dist = length(centered);
            number edge = 1.0 - smoothstep(0.25, 0.98, dist);
            vec2 uv = tc * vec2(4.5, 2.8) + vec2(time * 0.06 + seed, seed * 0.37);
            number n = fbm(uv);
            number wisp = fbm(uv * 2.3 - vec2(time * 0.09, 0.0));
            number cloud = smoothstep(0.36, 0.78, (n * 0.68 + wisp * 0.32) * edge * 1.35);
            return vec4(color.rgb, color.a * cloud);
        }
    ]])

    generateWorld()
end

function love.update(dt)
    local pan_speed = 520 * dt
    if love.keyboard.isDown("left", "a") then cam_x = cam_x + pan_speed end
    if love.keyboard.isDown("right", "d") then cam_x = cam_x - pan_speed end
    if love.keyboard.isDown("up", "w") then cam_y = cam_y + pan_speed end
    if love.keyboard.isDown("down", "s") then cam_y = cam_y - pan_speed end

    local mx, my = lovemap.getMousePosition(true)
    hover_gx, hover_gy = screenToIso(mx, my)

    -- Drift atmospheric fine clouds across the sky
    for _, c in ipairs(clouds) do
        c.x = (c.x + c.speed * dt) % CLOUD_FIELD_W
    end

    -- Update achievement toast popups
    for i = #active_popups, 1, -1 do
        local p = active_popups[i]
        p.timer = p.timer - dt
        if p.timer <= 0 then
            table.remove(active_popups, i)
        end
    end
end

function love.keypressed(key)
    if key == "space" or key == "return" then
        endTurn()
    elseif key == "t" then
        establishTradeRoute(selected_idx)
    elseif key == "h" then
        sendReliefAid(selected_idx)
    elseif key == "g" then
        shareFestival(selected_idx)
    elseif key == "tab" then
        selected_idx = (selected_idx % #settlements) + 1
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    local mx, my = lovemap.toGame(x, y)

    -- Check clicking on "CITIES IN TROUBLE" alert cards in top-left alert panel
    local trouble_y = 132
    for i, s in ipairs(settlements) do
        if s.emergency then
            if mx >= 20 and mx <= 480 and my >= trouble_y and my <= trouble_y + 44 then
                selected_idx = i
                -- Center camera on the troubled city
                local elev = BIOMES[tiles[s.gx][s.gy].biome].elev
                local sx, sy = isoToScreen(s.gx, s.gy, elev)
                cam_x = cam_x + (760 - sx)
                cam_y = cam_y + (420 - sy)
                return
            end
            trouble_y = trouble_y + 50
        end
    end

    -- Check bottom-right action panel buttons
    if mx >= 1135 and mx <= 1565 then
        if my >= 615 and my <= 665 then
            establishTradeRoute(selected_idx)
            return
        elseif my >= 675 and my <= 725 then
            sendReliefAid(selected_idx)
            return
        elseif my >= 735 and my <= 785 then
            shareFestival(selected_idx)
            return
        elseif my >= 800 and my <= 865 then
            endTurn()
            return
        end
    end

    -- Check clicking on a settlement on the isometric map
    for i, s in ipairs(settlements) do
        local b = BIOMES[tiles[s.gx][s.gy].biome]
        local sx, sy = isoToScreen(s.gx, s.gy, b.elev)
        if math.abs(mx - sx) < 48 and math.abs(my - (sy - 18)) < 46 then
            selected_idx = i
            return
        end
    end
end

-- Detailed, varied fantasy architectural variations for each city type:
-- "high_castle", "sylvan_city", "desert_temple", "walled_garden",
-- "coral_citadel", "sky_observatory", "terrace_granary", "harbor_lighthouse"
local function drawFantasyCityStyle(s, sx, sy, now)
    local st = s.style

    if st == "high_castle" then
        -- HIGH CASTLE: Ivory curtain wall, crenellations, twin royal-blue spire turrets, grand central keep & golden banner
        love.graphics.setColor(0.84, 0.82, 0.78, 1)
        love.graphics.polygon("fill", sx - 32, sy + 2, sx, sy + 15, sx + 32, sy + 2, sx + 32, sy - 16, sx - 32, sy - 16)
        -- Flanking round turrets
        love.graphics.setColor(0.90, 0.88, 0.84, 1)
        love.graphics.rectangle("fill", sx - 34, sy - 38, 12, 40, 2, 2)
        love.graphics.rectangle("fill", sx + 22, sy - 38, 12, 40, 2, 2)
        -- Pointed royal-blue conical turret roofs
        love.graphics.setColor(0.18, 0.38, 0.78, 1)
        love.graphics.polygon("fill", sx - 36, sy - 38, sx - 28, sy - 54, sx - 20, sy - 38)
        love.graphics.polygon("fill", sx + 20, sy - 38, sx + 28, sy - 54, sx + 36, sy - 38)
        -- Soaring central grand keep
        love.graphics.setColor(0.96, 0.94, 0.88, 1)
        love.graphics.rectangle("fill", sx - 16, sy - 46, 32, 48, 3, 3)
        -- Battlement merlons
        for mx = -15, 11, 8 do
            love.graphics.rectangle("fill", sx + mx, sy - 51, 5, 5)
        end
        -- Central pointed spire & fluttering golden sun banner
        love.graphics.setColor(0.22, 0.46, 0.88, 1)
        love.graphics.polygon("fill", sx - 11, sy - 46, sx, sy - 68, sx + 11, sy - 46)
        local wave = math.sin(now * 5) * 3
        love.graphics.setColor(1.0, 0.84, 0.22, 1)
        love.graphics.polygon("fill", sx, sy - 68, sx + 16, sy - 64 + wave, sx, sy - 59)
        -- Golden arched gate & rose window
        love.graphics.setColor(0.42, 0.28, 0.16, 1)
        love.graphics.rectangle("fill", sx - 6, sy - 12, 12, 14, 4, 4)
        love.graphics.setColor(1.0, 0.86, 0.35, 1)
        love.graphics.circle("fill", sx, sy - 30, 5.5)

    elseif st == "sylvan_city" then
        -- SYLVAN TREE-CITY: Giant ancient golden-bark World Tree, suspended elven treehouse pavilions, emerald canopy domes & hanging lanterns
        -- Winding root arches & massive trunk
        love.graphics.setColor(0.55, 0.36, 0.20, 1)
        love.graphics.polygon("fill", sx - 22, sy + 6, sx - 9, sy - 28, sx + 9, sy - 28, sx + 22, sy + 6)
        love.graphics.setColor(0.68, 0.46, 0.26, 1)
        love.graphics.rectangle("fill", sx - 8, sy - 38, 16, 40, 4, 4)
        -- Lush layered emerald & jade leaf canopies
        love.graphics.setColor(0.14, 0.54, 0.28, 1)
        love.graphics.ellipse("fill", sx - 22, sy - 30, 20, 13)
        love.graphics.ellipse("fill", sx + 22, sy - 30, 20, 13)
        love.graphics.setColor(0.22, 0.72, 0.38, 1)
        love.graphics.ellipse("fill", sx, sy - 46, 28, 17)
        love.graphics.setColor(0.38, 0.88, 0.50, 1)
        love.graphics.ellipse("fill", sx, sy - 56, 18, 11)
        -- Elven wooden pavilions nestled in the boughs + silver crescent spire
        love.graphics.setColor(0.92, 0.82, 0.58, 1)
        love.graphics.rectangle("fill", sx - 27, sy - 32, 11, 10, 2, 2)
        love.graphics.rectangle("fill", sx + 16, sy - 32, 11, 10, 2, 2)
        love.graphics.rectangle("fill", sx - 7, sy - 46, 14, 13, 3, 3)
        -- Curved silver elven roofs
        love.graphics.setColor(0.78, 0.96, 0.88, 1)
        love.graphics.polygon("fill", sx - 30, sy - 32, sx - 21.5, sy - 41, sx - 13, sy - 32)
        love.graphics.polygon("fill", sx + 13, sy - 32, sx + 21.5, sy - 41, sx + 30, sy - 32)
        love.graphics.polygon("fill", sx - 11, sy - 46, sx, sy - 64, sx + 11, sy - 46)
        -- Glowing hanging fairy-lantern orbs
        local glow = 0.75 + math.sin(now * 4) * 0.25
        love.graphics.setColor(1.0, 0.94, 0.45, glow)
        love.graphics.circle("fill", sx - 22, sy - 18, 3.2)
        love.graphics.circle("fill", sx + 22, sy - 18, 3.2)
        love.graphics.circle("fill", sx, sy - 67, 4.0)

    elseif st == "desert_temple" then
        -- DESERT TEMPLE: 3-tiered golden sandstone ziggurat pyramid, central grand stairway, twin carved obelisks & sacred solar flame altar
        -- Tier 1 (base ziggurat terrace)
        love.graphics.setColor(0.82, 0.58, 0.28, 1)
        love.graphics.polygon("fill", sx - 36, sy + 4, sx, sy + 16, sx + 36, sy + 4, sx + 30, sy - 12, sx - 30, sy - 12)
        -- Tier 2 (mid ziggurat terrace)
        love.graphics.setColor(0.90, 0.66, 0.34, 1)
        love.graphics.polygon("fill", sx - 25, sy - 12, sx + 25, sy - 12, sx + 19, sy - 27, sx - 19, sy - 27)
        -- Tier 3 (upper sanctuary terrace)
        love.graphics.setColor(0.96, 0.74, 0.40, 1)
        love.graphics.polygon("fill", sx - 15, sy - 27, sx + 15, sy - 27, sx + 10, sy - 41, sx - 10, sy - 41)
        -- Grand central ceremonial staircase
        love.graphics.setColor(0.98, 0.86, 0.56, 1)
        love.graphics.polygon("fill", sx - 7, sy + 12, sx + 7, sy + 12, sx + 4, sy - 41, sx - 4, sy - 41)
        -- Twin flanking sandstone obelisks with floating solar crystals
        love.graphics.setColor(0.76, 0.50, 0.22, 1)
        love.graphics.polygon("fill", sx - 35, sy + 2, sx - 29, sy + 2, sx - 30, sy - 38, sx - 32, sy - 45, sx - 34, sy - 38)
        love.graphics.polygon("fill", sx + 29, sy + 2, sx + 35, sy + 2, sx + 34, sy - 38, sx + 32, sy - 45, sx + 30, sy - 38)
        -- Sacred solar flame burning atop the summit altar
        local flicker = math.sin(now * 9) * 2.5
        love.graphics.setColor(1.0, 0.42, 0.14, 0.95)
        love.graphics.circle("fill", sx, sy - 48, 7)
        love.graphics.setColor(1.0, 0.92, 0.35, 1)
        love.graphics.polygon("fill", sx - 5, sy - 46, sx + flicker * 0.4, sy - 63 + flicker, sx + 5, sy - 46)
        love.graphics.circle("fill", sx - 32, sy - 49, 3.2)
        love.graphics.circle("fill", sx + 32, sy - 49, 3.2)

    elseif st == "walled_garden" then
        -- WALLED GARDEN: Isometric terracotta-and-jade sanctuary walls, corner gazebos, blooming flower terraces, glass conservatory dome & fountain
        -- Isometric diamond outer garden wall
        love.graphics.setColor(0.86, 0.78, 0.66, 1)
        love.graphics.polygon("fill", sx, sy - 22, sx + 38, sy - 2, sx, sy + 18, sx - 38, sy - 2)
        -- Lush emerald inner botanical courtyard
        love.graphics.setColor(0.24, 0.76, 0.38, 1)
        love.graphics.polygon("fill", sx, sy - 18, sx + 31, sy - 2, sx, sy + 14, sx - 31, sy - 2)
        -- Blooming magenta & gold flower beds
        love.graphics.setColor(0.96, 0.38, 0.68, 1)
        love.graphics.circle("fill", sx - 15, sy - 2, 3.5)
        love.graphics.circle("fill", sx + 15, sy - 2, 3.5)
        love.graphics.setColor(1.0, 0.88, 0.28, 1)
        love.graphics.circle("fill", sx - 10, sy + 4, 3.0)
        love.graphics.circle("fill", sx + 10, sy + 4, 3.0)
        -- 4 Cornerjade-roofed garden gazebos
        love.graphics.setColor(0.18, 0.62, 0.48, 1)
        love.graphics.circle("fill", sx - 34, sy - 4, 6)
        love.graphics.circle("fill", sx + 34, sy - 4, 6)
        love.graphics.circle("fill", sx, sy - 22, 6)
        -- Shimmering crystal glass conservatory dome & golden finial
        love.graphics.setColor(0.72, 0.94, 0.98, 0.88)
        love.graphics.arc("fill", sx, sy - 6, 17, math.pi, math.pi * 2)
        love.graphics.setColor(0.95, 1.0, 1.0, 0.95)
        love.graphics.arc("line", sx, sy - 6, 17, math.pi, math.pi * 2)
        -- Bubbling azure courtyard fountain in front
        local spray = 3 + math.abs(math.sin(now * 6)) * 4
        love.graphics.setColor(0.30, 0.82, 1.0, 1)
        love.graphics.ellipse("fill", sx, sy + 8, 8, 4)
        love.graphics.line(sx, sy + 8, sx, sy + 8 - spray)

    elseif st == "coral_citadel" then
        -- TIDAL CORAL SPIRE-CITY: Mother-of-pearl lagoon ring, aquamarine sea-glass domes & spiral rose-coral minarets
        love.graphics.setColor(0.24, 0.78, 0.92, 0.85)
        love.graphics.ellipse("fill", sx, sy + 2, 36, 16)
        love.graphics.setColor(0.94, 0.92, 0.96, 1)
        love.graphics.rectangle("fill", sx - 20, sy - 26, 40, 26, 6, 6)
        -- Spiral rose-coral minarets
        love.graphics.setColor(0.96, 0.46, 0.64, 1)
        love.graphics.polygon("fill", sx - 28, sy + 2, sx - 20, sy + 2, sx - 24, sy - 48)
        love.graphics.polygon("fill", sx + 20, sy + 2, sx + 28, sy + 2, sx + 24, sy - 48)
        -- Aquamarine pearl dome & glowing tidal orb
        love.graphics.setColor(0.32, 0.88, 0.98, 1)
        love.graphics.arc("fill", sx, sy - 26, 18, math.pi, math.pi * 2)
        love.graphics.setColor(0.98, 0.98, 1.0, 1)
        love.graphics.circle("fill", sx, sy - 50, 5.5)

    elseif st == "sky_observatory" then
        -- ASTRAL OBSERVATORY: Stepped marble acropolis, amethyst dome & rotating golden armillary sphere rings
        love.graphics.setColor(0.88, 0.88, 0.94, 1)
        love.graphics.rectangle("fill", sx - 26, sy - 18, 52, 20, 4, 4)
        love.graphics.rectangle("fill", sx - 16, sy - 34, 32, 20, 4, 4)
        -- Royal amethyst observatory dome
        love.graphics.setColor(0.58, 0.38, 0.88, 1)
        love.graphics.arc("fill", sx, sy - 34, 16, math.pi, math.pi * 2)
        -- Rotating golden celestial armillary rings above the dome
        love.graphics.setColor(1.0, 0.88, 0.38, 0.95)
        love.graphics.setLineWidth(2)
        local rx = 12 + math.sin(now * 2.5) * 4
        love.graphics.ellipse("line", sx, sy - 56, rx, 7)
        love.graphics.ellipse("line", sx, sy - 56, 7, 12)
        love.graphics.circle("fill", sx, sy - 56, 3.5)

    elseif st == "terrace_granary" then
        -- WINDMILL CLOISTER: Warm amber harvest halls, golden granary silos & animated 4-sail rotating windmill
        love.graphics.setColor(0.82, 0.52, 0.24, 1)
        love.graphics.rectangle("fill", sx - 30, sy - 20, 34, 22, 3, 3)
        love.graphics.setColor(0.95, 0.78, 0.32, 1)
        love.graphics.arc("fill", sx - 13, sy - 20, 15, math.pi, math.pi * 2)
        -- Tall windmill tower on the right
        love.graphics.setColor(0.72, 0.44, 0.20, 1)
        love.graphics.polygon("fill", sx + 4, sy + 2, sx + 24, sy + 2, sx + 20, sy - 44, sx + 8, sy - 44)
        -- Animated rotating windmill sails
        local wx, wy = sx + 14, sy - 38
        love.graphics.setColor(0.98, 0.95, 0.86, 1)
        love.graphics.setLineWidth(3)
        for k = 0, 3 do
            local a = now * 1.8 + k * (math.pi * 0.5)
            love.graphics.line(wx, wy, wx + math.cos(a) * 20, wy + math.sin(a) * 20)
        end
        love.graphics.setColor(1.0, 0.84, 0.25, 1)
        love.graphics.circle("fill", wx, wy, 3.5)

    else
        -- PHAROS HARBOR LIGHTHOUSE: Canal guildhalls & tall striped Pharos lighthouse with sweeping golden light beam
        love.graphics.setColor(0.28, 0.68, 0.64, 1)
        love.graphics.rectangle("fill", sx - 30, sy - 20, 26, 22, 3, 3)
        love.graphics.setColor(0.92, 0.94, 0.96, 1)
        love.graphics.polygon("fill", sx + 2, sy + 2, sx + 20, sy + 2, sx + 16, sy - 54, sx + 6, sy - 54)
        -- Teal lighthouse stripe
        love.graphics.setColor(0.20, 0.78, 0.72, 1)
        love.graphics.polygon("fill", sx + 4, sy - 18, sx + 18, sy - 18, sx + 17, sy - 34, sx + 5, sy - 34)
        -- Sweeping golden lighthouse lantern beam
        local beam_x = math.cos(now * 2.2) * 34
        love.graphics.setColor(1.0, 0.94, 0.45, 0.45)
        love.graphics.polygon("fill", sx + 11, sy - 58, sx + 11 + beam_x, sy - 68, sx + 11 + beam_x, sy - 48)
        love.graphics.setColor(1.0, 0.95, 0.55, 1)
        love.graphics.circle("fill", sx + 11, sy - 58, 5)
    end
end

-- Draws the 3D architectural structures of a settlement ON its tile during the isometric tile pass,
-- so foreground hills/mountains at higher (gx, gy) naturally partially overlap the lower corner of the city!
local function drawSettlementStructures(i, s, sx, sy, now)
    local function renderArchitecture()
        if i == selected_idx then
            love.graphics.setColor(1, 0.95, 0.55, 0.90)
            love.graphics.setLineWidth(3)
            love.graphics.ellipse("line", sx, sy + 2, 42, 21)
        end

        -- Trouble ground distress rings if facing an emergency
        if s.emergency then
            local r_pulse = 32 + (now * 24) % 24
            love.graphics.setColor(s.emergency.kind.color[1], s.emergency.kind.color[2], s.emergency.kind.color[3], 0.85)
            love.graphics.setLineWidth(3)
            love.graphics.ellipse("line", sx, sy + 2, r_pulse, r_pulse * 0.55)
        end

        drawFantasyCityStyle(s, sx, sy, now)
    end

    if i == selected_idx or s.emergency then
        lovemap.withEffect(pulse_fx, renderArchitecture)
    else
        renderArchitecture()
    end
end

local function drawIsoTile(gx, gy, biome_def, highlight)
    local sx, sy = isoToScreen(gx, gy, biome_def.elev)
    local hw, hh = TILE_W * 0.5, TILE_H * 0.5

    -- 3D Tile side skirt for elevation
    if biome_def.elev > 0 then
        love.graphics.setColor(biome_def.col[1] * 0.62, biome_def.col[2] * 0.62, biome_def.col[3] * 0.62, 1)
        love.graphics.polygon(
            "fill",
            sx - hw, sy,
            sx, sy + hh,
            sx + hw, sy,
            sx + hw, sy + biome_def.elev,
            sx, sy + hh + biome_def.elev,
            sx - hw, sy + biome_def.elev
        )
    end

    -- Diamond top face
    love.graphics.setColor(biome_def.col)
    love.graphics.polygon("fill", sx, sy - hh, sx + hw, sy, sx, sy + hh, sx - hw, sy)

    if highlight then
        love.graphics.setColor(1, 1, 0.75, 0.65)
        love.graphics.setLineWidth(2)
        love.graphics.polygon("line", sx, sy - hh, sx + hw, sy, sx, sy + hh, sx - hw, sy)
    else
        love.graphics.setColor(0, 0, 0, 0.12)
        love.graphics.setLineWidth(1)
        love.graphics.polygon("line", sx, sy - hh, sx + hw, sy, sx, sy + hh, sx - hw, sy)
    end

    -- Flatter, broader hills and mountains so they add 3D relief and only partially overlap
    -- the bottom edge of cities behind them without ever hiding the city!
    local b_name = tiles[gx][gy].biome
    if b_name == "forest" then
        love.graphics.setColor(0.12, 0.36, 0.18, 1)
        love.graphics.polygon("fill", sx - 9, sy - 2, sx, sy - 20, sx + 9, sy - 2)
    elseif b_name == "hills" then
        love.graphics.setColor(0.54, 0.56, 0.28, 1)
        love.graphics.polygon("fill", sx - 24, sy + 2, sx - 8, sy - 9, sx + 8, sy - 9, sx + 24, sy + 2)
    elseif b_name == "peak" then
        love.graphics.setColor(0.60, 0.63, 0.68, 1)
        love.graphics.polygon("fill", sx - 28, sy + 3, sx - 7, sy - 14, sx + 7, sy - 14, sx + 28, sy + 3)
        love.graphics.setColor(0.92, 0.95, 0.99, 1)
        love.graphics.polygon("fill", sx - 13, sy - 7, sx - 6, sy - 14, sx + 6, sy - 14, sx + 13, sy - 7)
    end
end

function lovemap.draw()
    local now = love.timer.getTime()

    -- 1. Render 28x28 Isometric Archipelago AND Cities in true back-to-front depth order!
    for gx = 1, MAP_SIZE do
        for gy = 1, MAP_SIZE do
            local t_cell = tiles[gx][gy]
            local b = BIOMES[t_cell.biome]
            drawIsoTile(gx, gy, b, gx == hover_gx and gy == hover_gy)

            local s_idx = settlement_at[gx][gy]
            if s_idx then
                local s = settlements[s_idx]
                local sx, sy = isoToScreen(gx, gy, b.elev)
                drawSettlementStructures(s_idx, s, sx, sy, now)
            end
        end
    end

    -- 2. Draw Cooperative Trade Routes & Moving Aid Caravans
    for _, r in ipairs(routes) do
        local s1 = settlements[r.from]
        local s2 = settlements[r.to]
        local x1, y1 = isoToScreen(s1.gx, s1.gy, BIOMES[tiles[s1.gx][s1.gy].biome].elev + 10)
        local x2, y2 = isoToScreen(s2.gx, s2.gy, BIOMES[tiles[s2.gx][s2.gy].biome].elev + 10)

        love.graphics.setColor(1.0, 0.88, 0.42, 0.78)
        love.graphics.setLineWidth(3)
        love.graphics.line(x1, y1, x2, y2)

        -- Animated trade caravan dot traveling along the route
        local p = (now * 0.35 + r.from * 0.2) % 1
        local cx = x1 + (x2 - x1) * p
        local cy = y1 + (y2 - y1) * p
        love.graphics.setColor(1, 0.96, 0.75, 1)
        love.graphics.circle("fill", cx, cy, 6.5)
    end

    -- 3. Draw Floating Shadered Fine Clouds & Soft Cloud Shadows over the Isometric World
    -- Clouds follow the camera at CLOUD_PARALLAX of the landscape's speed (slight parallax)
    for _, c in ipairs(clouds) do
        local cx, cy = cloudScreenPos(c)
        love.graphics.setColor(0.03, 0.06, 0.12, 0.14)
        love.graphics.ellipse("fill", cx + 35, cy + 75, c.w * 0.42, c.h * 0.34)
    end
    for _, c in ipairs(clouds) do
        local cx, cy = cloudScreenPos(c)
        lovemap.withEffect(cloud_shader, { time = now, seed = c.seed }, function()
            love.graphics.setColor(0.96, 0.98, 1.0, 0.55)
            love.graphics.draw(cloud_tex, cx - c.w * 0.5, cy - c.h * 0.5, 0, c.w * 0.5, c.h * 0.5)
        end)
    end

    -- 4. Draw Settlement Nameplates & High-Visibility Distress Beacons for Cities in Trouble
    love.graphics.setFont(font_md)
    for i, s in ipairs(settlements) do
        local elev = BIOMES[tiles[s.gx][s.gy].biome].elev
        local sx, sy = isoToScreen(s.gx, s.gy, elev)

        -- City Nameplate Pill
        local label = string.format("%s [%s] (Lv.%d | %d%%)", s.name, s.style_label, s.prosperity, s.bond)
        local tw = font_md:getWidth(label)
        love.graphics.setColor(0.05, 0.10, 0.18, 0.84)
        love.graphics.rectangle("fill", sx - tw * 0.5 - 10, sy + 16, tw + 20, 26, 6, 6)
        if i == selected_idx then
            love.graphics.setColor(1.0, 0.90, 0.40, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", sx - tw * 0.5 - 10, sy + 16, tw + 20, 26, 6, 6)
        end
        love.graphics.setColor(1, 1, 1, 0.96)
        love.graphics.print(label, sx - tw * 0.5, sy + 19)

        -- High-Visibility Emergency Beacon & Warning Banner if City is in Trouble!
        if s.emergency then
            local dc = s.emergency.kind.color
            local bob = math.sin(now * 6) * 5

            -- Vertical distress light column
            love.graphics.setColor(dc[1], dc[2], dc[3], 0.22 + math.sin(now * 8) * 0.08)
            love.graphics.polygon("fill", sx - 14, sy - 58, sx + 14, sy - 58, sx + 28, sy - 165, sx - 28, sy - 165)

            -- Warning Banner Pill above city
            local alert_txt = string.format("! IN TROUBLE: %s (%dt) !", s.emergency.kind.name, s.emergency.turns_left)
            local aw = font_md:getWidth(alert_txt)
            local bx, by = sx - aw * 0.5 - 14, sy - 104 + bob
            love.graphics.setColor(0.18, 0.04, 0.06, 0.94)
            love.graphics.rectangle("fill", bx, by, aw + 28, 34, 8, 8)
            love.graphics.setColor(dc[1], dc[2], dc[3], 1)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", bx, by, aw + 28, 34, 8, 8)
            love.graphics.setColor(1, 0.95, 0.90, 1)
            love.graphics.print(alert_txt, bx + 14, by + 6)
        end
    end

    -- 5. Top Resource & Global Harmony Bar (Larger Font)
    love.graphics.setColor(0.06, 0.12, 0.20, 0.92)
    love.graphics.rectangle("fill", 20, 14, 1560, 60, 10, 10)
    love.graphics.setFont(font_lg)
    love.graphics.setColor(0.98, 0.88, 0.42, 1)
    love.graphics.print(
        string.format(
            "UTOPIA  |  Turn: %d  |  Harmony: %d/100  |  Food: %d  |  Timber: %d  |  Knowledge: %d  |  Routes: %d  |  Achievements: %d",
            turn,
            harmony,
            food,
            timber,
            knowledge,
            #routes,
            unlocked_count
        ),
        36,
        31
    )

    -- 6. Top-Left "CITIES IN TROUBLE" Visual Tracker Panel
    local troubled_list = {}
    for i, s in ipairs(settlements) do
        if s.emergency then
            table.insert(troubled_list, { idx = i, s = s })
        end
    end
    love.graphics.setColor(0.10, 0.14, 0.22, 0.90)
    local tracker_h = 46 + math.max(1, #troubled_list) * 50
    love.graphics.rectangle("fill", 20, 86, 465, tracker_h, 10, 10)
    love.graphics.setFont(font_md)
    if #troubled_list > 0 then
        love.graphics.setColor(1.0, 0.45, 0.40, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 20, 86, 465, tracker_h, 10, 10)
        love.graphics.print("CITIES IN TROUBLE (Click to Focus & Aid):", 34, 96)
        local ty = 130
        for _, entry in ipairs(troubled_list) do
            local s = entry.s
            local dc = s.emergency.kind.color
            love.graphics.setColor(0.22, 0.08, 0.10, 0.92)
            love.graphics.rectangle("fill", 30, ty, 445, 42, 6, 6)
            love.graphics.setColor(dc)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", 30, ty, 445, 42, 6, 6)
            love.graphics.setColor(1, 0.95, 0.92, 1)
            love.graphics.print(
                string.format("! %s: %s (%dt left)", s.name, s.emergency.kind.name, s.emergency.turns_left),
                42,
                ty + 10
            )
            ty = ty + 50
        end
    else
        love.graphics.setColor(0.38, 0.92, 0.58, 1)
        love.graphics.print("ALL CITIES SAFE & THRIVING", 34, 96)
        love.graphics.setColor(0.82, 0.90, 0.96, 1)
        love.graphics.print("No active natural emergencies across the archipelago.", 34, 134)
    end

    -- 7. Achievement Toast Popups (Top-Center Sliding Banner when Harmony Degrees are Reached!)
    if #active_popups > 0 then
        local pop = active_popups[1]
        local bx, by, bw, bh = 495, 86, 610, 92
        love.graphics.setColor(0.12, 0.16, 0.26, 0.96)
        love.graphics.rectangle("fill", bx, by, bw, bh, 12, 12)
        love.graphics.setColor(1.0, 0.84, 0.28, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", bx, by, bw, bh, 12, 12)

        -- Golden star emblem
        love.graphics.circle("fill", bx + 42, by + 46, 22)
        love.graphics.setColor(0.12, 0.16, 0.26, 1)
        love.graphics.setFont(font_xl)
        love.graphics.print("*", bx + 35, by + 33)

        love.graphics.setFont(font_lg)
        love.graphics.setColor(1.0, 0.88, 0.36, 1)
        love.graphics.print("HARMONY ACHIEVEMENT: " .. pop.title, bx + 78, by + 16)
        love.graphics.setFont(font_md)
        love.graphics.setColor(0.92, 0.96, 1.0, 1)
        love.graphics.print(pop.desc, bx + 78, by + 50)
    end

    -- 8. Bottom-Left Cooperative Chronicle Log (Larger Font)
    love.graphics.setColor(0.06, 0.12, 0.20, 0.88)
    love.graphics.rectangle("fill", 20, 685, 1085, 195, 10, 10)
    love.graphics.setFont(font_lg)
    love.graphics.setColor(0.65, 0.88, 1.0, 1)
    love.graphics.print("CHRONICLE OF MUTUAL AID  (WASD/Arrows: Pan | Click/Tab: Select City)", 38, 698)
    love.graphics.setFont(font_md)
    love.graphics.setColor(0.92, 0.95, 0.98, 1)
    for idx, msg in ipairs(log_messages) do
        love.graphics.print(msg, 38, 706 + idx * 28)
    end

    -- 9. Bottom-Right Selected Civilization & Cooperative Actions Panel (Larger Font)
    local sel = settlements[selected_idx]
    love.graphics.setColor(0.06, 0.12, 0.20, 0.92)
    love.graphics.rectangle("fill", 1120, 490, 460, 390, 12, 12)
    love.graphics.setFont(font_xl)
    love.graphics.setColor(sel.color)
    love.graphics.print(string.format("%s (%s)", sel.name, sel.style_label), 1140, 505)

    love.graphics.setFont(font_md)
    love.graphics.setColor(0.85, 0.92, 0.98, 1)
    love.graphics.print(
        string.format("Prosperity: Lv.%d   |   Harmony Bond: %d%%   |   Linked: %s", sel.prosperity, sel.bond, isConnectedToNetwork(selected_idx) and "Yes" or "No"),
        1140,
        544
    )
    if sel.emergency then
        love.graphics.setColor(sel.emergency.kind.color)
        love.graphics.print(
            string.format("IN TROUBLE: %s (%d turns, %dF/%dT)", sel.emergency.kind.name, sel.emergency.turns_left, sel.emergency.kind.cost_food, sel.emergency.kind.cost_timber),
            1140,
            574
        )
    else
        love.graphics.setColor(0.45, 0.95, 0.62, 1)
        love.graphics.print("Status: Thriving in Peace & Solidarity", 1140, 574)
    end

    -- Cooperative Action Buttons
    local buttons = {
        { y = 615, h = 50, col = { 0.18, 0.48, 0.68, 1 }, label = "[T] Build Trade Route (20 Timber, 15 Food)" },
        { y = 675, h = 50, col = { 0.22, 0.62, 0.42, 1 }, label = "[H] Send Emergency Relief Aid Convoy" },
        { y = 735, h = 50, col = { 0.48, 0.35, 0.72, 1 }, label = "[G] Share Ecological Knowledge (20 Know.)" },
        { y = 800, h = 62, col = { 0.82, 0.56, 0.18, 1 }, label = "[SPACE] End Turn & Share Harvests" },
    }
    for _, b in ipairs(buttons) do
        love.graphics.setColor(b.col)
        love.graphics.rectangle("fill", 1135, b.y, 430, b.h, 8, 8)
        love.graphics.setColor(1, 1, 1, 0.98)
        love.graphics.print(b.label, 1150, b.y + b.h * 0.5 - 10)
    end
end
