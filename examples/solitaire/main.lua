love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";../../?.lua;../../?/init.lua")
package.path = "../../?.lua;../../?/init.lua;" .. package.path

local lovemap = require("src.lovemap")

local CARD_W = 130
local CARD_H = 182
local SUITS = {
    { name = "Spades",   sym = "S", color = "black", rgb = { 0.14, 0.16, 0.22, 1 } },
    { name = "Hearts",   sym = "H", color = "red",   rgb = { 0.86, 0.18, 0.22, 1 } },
    { name = "Clubs",    sym = "C", color = "black", rgb = { 0.14, 0.16, 0.22, 1 } },
    { name = "Diamonds", sym = "D", color = "red",   rgb = { 0.86, 0.18, 0.22, 1 } },
}
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

local stock = {}
local waste = {}
local foundations = { {}, {}, {}, {} }
local tableau = { {}, {}, {}, {}, {}, {}, {} }
local all_cards = {}
local drag = nil -- { cards = {}, source_pile = tbl, offset_x = num, offset_y = num }
local z_counter = 1
local won = false

local function pileSlotPosition(kind, idx, card_idx)
    if kind == "stock" then
        return 110, 70
    elseif kind == "waste" then
        return 275, 70
    elseif kind == "foundation" then
        return 660 + (idx - 1) * 195, 70
    elseif kind == "tableau" then
        local y_off = (card_idx - 1) * 32
        return 110 + (idx - 1) * 195, 295 + y_off
    end
    return 0, 0
end

local function updateTargets()
    for i, c in ipairs(stock) do
        c.tx, c.ty = pileSlotPosition("stock", 1, i)
    end
    for i, c in ipairs(waste) do
        c.tx, c.ty = pileSlotPosition("waste", 1, i)
        c.tx = c.tx + math.min(2, i - 1) * 6
    end
    for f = 1, 4 do
        for i, c in ipairs(foundations[f]) do
            c.tx, c.ty = pileSlotPosition("foundation", f, i)
        end
    end
    won = (#foundations[1] + #foundations[2] + #foundations[3] + #foundations[4]) == 52
    for t = 1, 7 do
        for i, c in ipairs(tableau[t]) do
            c.tx, c.ty = pileSlotPosition("tableau", t, i)
        end
    end
end

local function dealNewGame()
    stock = {}
    waste = {}
    foundations = { {}, {}, {}, {} }
    tableau = { {}, {}, {}, {}, {}, {}, {} }
    all_cards = {}
    drag = nil
    z_counter = 1
    won = false

    local deck = {}
    for s = 1, 4 do
        for r = 1, 13 do
            local card = {
                suit = s,
                rank = r,
                face_up = false,
                x = 110,
                y = 70,
                vx = 0,
                vy = 0,
                tx = 110,
                ty = 70,
                angle = 0,
                v_angle = 0,
                scale = 1.0,
                z = z_counter,
            }
            z_counter = z_counter + 1
            table.insert(deck, card)
            table.insert(all_cards, card)
        end
    end

    -- Fisher-Yates shuffle
    for i = #deck, 2, -1 do
        local j = love.math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end

    local cursor = 1
    for t = 1, 7 do
        for i = 1, t do
            local c = deck[cursor]
            cursor = cursor + 1
            c.face_up = (i == t)
            c.z = z_counter
            z_counter = z_counter + 1
            table.insert(tableau[t], c)
        end
    end
    while cursor <= #deck do
        local c = deck[cursor]
        cursor = cursor + 1
        c.face_up = false
        table.insert(stock, c)
    end
    updateTargets()
end

local function canDropOnFoundation(card, f_idx)
    local pile = foundations[f_idx]
    local top = pile[#pile]
    if not top then
        return card.rank == 1
    end
    return top.suit == card.suit and card.rank == top.rank + 1
end

local function canDropOnTableau(card, t_idx)
    local pile = tableau[t_idx]
    local top = pile[#pile]
    if not top then
        return card.rank == 13
    end
    local diff_color = SUITS[card.suit].color ~= SUITS[top.suit].color
    return top.face_up and diff_color and (card.rank == top.rank - 1)
end

local function flipTopTableau()
    for t = 1, 7 do
        local pile = tableau[t]
        if #pile > 0 and not pile[#pile].face_up then
            pile[#pile].face_up = true
            pile[#pile].v_angle = 8.0 -- physical flip impulse
        end
    end
end

function love.load()
    love.math.setRandomSeed(os.time())
    lovemap.aspect(16, 9, { background = { 0.08, 0.34, 0.22, 1.0 } })

    -- Full-screen CRT + scanlines + vignette shader chain
    local fx = lovemap.setShaders("crt", "scanlines", "vignette")
    fx.scanlines.opacity = 0.24
    fx.vignette.opacity = 0.38
    fx.crt.distortionFactor = { 1.04, 1.05 }

    dealNewGame()
end

function love.update(dt)
    local mx, my = lovemap.getMousePosition(true)

    -- Update dragged card targets to follow mouse
    if drag then
        for i, c in ipairs(drag.cards) do
            c.tx = mx - drag.offset_x
            c.ty = my - drag.offset_y + (i - 1) * 32
        end
    end

    -- Physical spring-damper simulation for every card (position, velocity, tilt, lift scale)
    local stiffness = 210
    local damping = 18
    for _, c in ipairs(all_cards) do
        local is_dragged = false
        if drag then
            for _, dc in ipairs(drag.cards) do
                if dc == c then is_dragged = true break end
            end
        end

        local ax = (c.tx - c.x) * stiffness - c.vx * damping
        local ay = (c.ty - c.y) * stiffness - c.vy * damping
        c.vx = c.vx + ax * dt
        c.vy = c.vy + ay * dt
        c.x = c.x + c.vx * dt
        c.y = c.y + c.vy * dt

        -- Physical tilt proportional to horizontal velocity
        local target_angle = math.max(-0.35, math.min(0.35, c.vx * 0.00038))
        local a_ang = (target_angle - c.angle) * 180 - c.v_angle * 16
        c.v_angle = c.v_angle + a_ang * dt
        c.angle = c.angle + c.v_angle * dt

        local target_scale = is_dragged and 1.09 or 1.0
        c.scale = c.scale + (target_scale - c.scale) * math.min(1, dt * 16)
    end
end

function love.mousepressed(x, y, button)
    local mx, my = lovemap.toGame(x, y)

    -- Right-click: Auto-send eligible top cards to foundation
    if button == 2 then
        local candidates = {}
        if #waste > 0 then table.insert(candidates, waste) end
        for t = 1, 7 do
            if #tableau[t] > 0 then table.insert(candidates, tableau[t]) end
        end
        for _, pile in ipairs(candidates) do
            local card = pile[#pile]
            for f = 1, 4 do
                if canDropOnFoundation(card, f) then
                    table.remove(pile)
                    card.z = z_counter
                    z_counter = z_counter + 1
                    card.v_angle = -6.0
                    table.insert(foundations[f], card)
                    flipTopTableau()
                    updateTargets()
                    return
                end
            end
        end
        return
    end

    if button ~= 1 then return end

    -- New Deal button hit test
    if mx >= 435 and mx <= 585 and my >= 115 and my <= 170 then
        dealNewGame()
        return
    end

    -- Stock pile click: draw to waste or recycle waste
    local sx, sy = pileSlotPosition("stock", 1, 1)
    if mx >= sx and mx <= sx + CARD_W and my >= sy and my <= sy + CARD_H then
        if #stock > 0 then
            local c = table.remove(stock)
            c.face_up = true
            c.z = z_counter
            z_counter = z_counter + 1
            c.v_angle = 9.0
            table.insert(waste, c)
        else
            while #waste > 0 do
                local c = table.remove(waste)
                c.face_up = false
                c.z = z_counter
                z_counter = z_counter + 1
                table.insert(stock, c)
            end
        end
        updateTargets()
        return
    end

    -- Check tableau piles from top card down
    for t = 1, 7 do
        local pile = tableau[t]
        for i = #pile, 1, -1 do
            local c = pile[i]
            if c.face_up and mx >= c.x and mx <= c.x + CARD_W and my >= c.y and my <= c.y + CARD_H then
                local moved = {}
                for k = i, #pile do
                    local mc = pile[k]
                    mc.z = z_counter
                    z_counter = z_counter + 1
                    table.insert(moved, mc)
                end
                for _ = #pile, i, -1 do
                    table.remove(pile)
                end
                drag = {
                    cards = moved,
                    source_pile = pile,
                    offset_x = mx - c.x,
                    offset_y = my - c.y,
                }
                return
            end
        end
    end

    -- Check waste top card
    if #waste > 0 then
        local c = waste[#waste]
        if mx >= c.x and mx <= c.x + CARD_W and my >= c.y and my <= c.y + CARD_H then
            table.remove(waste)
            c.z = z_counter
            z_counter = z_counter + 1
            drag = { cards = { c }, source_pile = waste, offset_x = mx - c.x, offset_y = my - c.y }
            return
        end
    end
end

function love.mousereleased(x, y, button)
    if button ~= 1 or not drag then return end
    local mx, my = lovemap.toGame(x, y)
    local lead = drag.cards[1]
    local placed = false

    -- 1. Try dropping single card on Foundation
    if #drag.cards == 1 then
        for f = 1, 4 do
            local fx, fy = pileSlotPosition("foundation", f, 1)
            if mx >= fx - 25 and mx <= fx + CARD_W + 25 and my >= fy - 25 and my <= fy + CARD_H + 25 then
                if canDropOnFoundation(lead, f) then
                    table.insert(foundations[f], lead)
                    placed = true
                    break
                end
            end
        end
    end

    -- 2. Try dropping stack on Tableau
    if not placed then
        for t = 1, 7 do
            local tx, ty = pileSlotPosition("tableau", t, math.max(1, #tableau[t]))
            if mx >= tx - 30 and mx <= tx + CARD_W + 30 and my >= 270 and my <= ty + CARD_H + 60 then
                if canDropOnTableau(lead, t) then
                    for _, c in ipairs(drag.cards) do
                        table.insert(tableau[t], c)
                    end
                    placed = true
                    break
                end
            end
        end
    end

    -- 3. Return to source pile if invalid drop
    if not placed then
        for _, c in ipairs(drag.cards) do
            table.insert(drag.source_pile, c)
        end
    else
        flipTopTableau()
    end

    drag = nil
    updateTargets()
end

local function drawSuitGlyph(suit_idx, cx, cy, size)
    local s = SUITS[suit_idx]
    love.graphics.setColor(s.rgb)
    if s.sym == "D" then
        love.graphics.polygon("fill", cx, cy - size, cx + size * 0.75, cy, cx, cy + size, cx - size * 0.75, cy)
    elseif s.sym == "H" then
        love.graphics.circle("fill", cx - size * 0.38, cy - size * 0.25, size * 0.45)
        love.graphics.circle("fill", cx + size * 0.38, cy - size * 0.25, size * 0.45)
        love.graphics.polygon("fill", cx - size * 0.82, cy - size * 0.05, cx + size * 0.82, cy - size * 0.05, cx, cy + size * 0.95)
    elseif s.sym == "S" then
        love.graphics.polygon("fill", cx, cy - size * 0.95, cx - size * 0.82, cy + size * 0.15, cx + size * 0.82, cy + size * 0.15)
        love.graphics.circle("fill", cx - size * 0.36, cy + size * 0.18, size * 0.42)
        love.graphics.circle("fill", cx + size * 0.36, cy + size * 0.18, size * 0.42)
        love.graphics.polygon("fill", cx, cy + size * 0.3, cx - size * 0.25, cy + size * 0.95, cx + size * 0.25, cy + size * 0.95)
    else -- Clubs
        love.graphics.circle("fill", cx, cy - size * 0.38, size * 0.40)
        love.graphics.circle("fill", cx - size * 0.40, cy + size * 0.15, size * 0.40)
        love.graphics.circle("fill", cx + size * 0.40, cy + size * 0.15, size * 0.40)
        love.graphics.polygon("fill", cx, cy + size * 0.2, cx - size * 0.25, cy + size * 0.95, cx + size * 0.25, cy + size * 0.95)
    end
end

local function drawCard(c)
    love.graphics.push()
    love.graphics.translate(c.x + CARD_W * 0.5, c.y + CARD_H * 0.5)
    love.graphics.rotate(c.angle)
    love.graphics.scale(c.scale, c.scale)

    -- Soft physical drop shadow (expands when lifted)
    local sh_off = 5 + (c.scale - 1.0) * 120
    love.graphics.setColor(0, 0, 0, 0.36)
    love.graphics.rectangle("fill", -CARD_W * 0.5 + sh_off, -CARD_H * 0.5 + sh_off, CARD_W, CARD_H, 10, 10)

    if not c.face_up then
        love.graphics.setColor(0.95, 0.94, 0.90, 1)
        love.graphics.rectangle("fill", -CARD_W * 0.5, -CARD_H * 0.5, CARD_W, CARD_H, 10, 10)
        love.graphics.setColor(0.18, 0.34, 0.68, 1)
        love.graphics.rectangle("fill", -CARD_W * 0.5 + 8, -CARD_H * 0.5 + 8, CARD_W - 16, CARD_H - 16, 6, 6)
        love.graphics.setColor(0.32, 0.52, 0.88, 1)
        love.graphics.circle("line", 0, 0, 28)
    else
        love.graphics.setColor(0.98, 0.97, 0.94, 1)
        love.graphics.rectangle("fill", -CARD_W * 0.5, -CARD_H * 0.5, CARD_W, CARD_H, 10, 10)
        love.graphics.setColor(0.25, 0.25, 0.28, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", -CARD_W * 0.5, -CARD_H * 0.5, CARD_W, CARD_H, 10, 10)

        local s = SUITS[c.suit]
        local r_str = RANKS[c.rank]
        love.graphics.setColor(s.rgb)
        love.graphics.print(r_str, -CARD_W * 0.5 + 12, -CARD_H * 0.5 + 10, 0, 1.4, 1.4)
        drawSuitGlyph(c.suit, -CARD_W * 0.5 + 22, -CARD_H * 0.5 + 48, 9)
        drawSuitGlyph(c.suit, 0, 8, 26)
    end
    love.graphics.pop()
end

function lovemap.draw()
    -- Felt table outlines for Stock, Waste, Foundations, and Tableau columns
    love.graphics.setLineWidth(2)
    local sx, sy = pileSlotPosition("stock", 1, 1)
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("line", sx, sy, CARD_W, CARD_H, 10, 10)
    love.graphics.print("CYCLE", sx + 38, sy + 82)

    local wx, wy = pileSlotPosition("waste", 1, 1)
    love.graphics.rectangle("line", wx, wy, CARD_W, CARD_H, 10, 10)

    for f = 1, 4 do
        local fx, fy = pileSlotPosition("foundation", f, 1)
        love.graphics.setColor(1, 1, 1, 0.24)
        love.graphics.rectangle("line", fx, fy, CARD_W, CARD_H, 10, 10)
        drawSuitGlyph(f, fx + CARD_W * 0.5, fy + CARD_H * 0.5, 22)
    end

    for t = 1, 7 do
        local tx, ty = pileSlotPosition("tableau", t, 1)
        love.graphics.setColor(1, 1, 1, 0.16)
        love.graphics.rectangle("line", tx, ty, CARD_W, CARD_H, 10, 10)
    end

    -- "New Deal" button
    love.graphics.setColor(0.15, 0.52, 0.34, 1)
    love.graphics.rectangle("fill", 435, 115, 150, 55, 10, 10)
    love.graphics.setColor(0.85, 0.95, 0.88, 1)
    love.graphics.rectangle("line", 435, 115, 150, 55, 10, 10)
    love.graphics.print("NEW DEAL", 464, 134, 0, 1.25, 1.25)

    -- Sort cards by Z-order so moving and dragged cards render on top
    local sorted = {}
    for i, c in ipairs(all_cards) do sorted[i] = c end
    table.sort(sorted, function(a, b) return a.z < b.z end)
    for _, c in ipairs(sorted) do
        drawCard(c)
    end

    love.graphics.setColor(0.92, 0.98, 0.92, 0.9)
    love.graphics.print(
        "CRT Solitaire | Drag cards with Left-Click | Right-Click to auto-move to Foundation | Click Stock to draw",
        110,
        24,
        0,
        1.15,
        1.15
    )

    if won then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 480, 360, 640, 160, 14, 14)
        love.graphics.setColor(1, 0.9, 0.3, 1)
        love.graphics.print("YOU WON SOLITAIRE!", 615, 415, 0, 2.0, 2.0)
    end
end
