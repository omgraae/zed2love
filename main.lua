local lovemap = require("src.lovemap")

function love.load()
    -- 16:9 aspect ratio -> 1600x900 virtual game coordinates
    -- Also hooks F11 (fullscreen), ESC (exit fullscreen), resize, and lovemap.draw()
    lovemap.aspect(16, 9)
end

function love.update(dt)
end

function lovemap.draw()
    love.graphics.print("Hello, zed2love!", 720, 440)
end
