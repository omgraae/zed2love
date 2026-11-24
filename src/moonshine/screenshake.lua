--[[
The MIT License (MIT)

Copyright (c) 2026 zed2love contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

return function(moonshine)
  local shader = love.graphics.newShader[[
    extern vec2 offset;
    extern number rot;
    extern number zoom;
    extern number aspect;

    vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
    {
      vec2 p = tc - vec2(0.5);
      p.x *= aspect;
      number c = cos(rot);
      number s = sin(rot);
      p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
      p.x /= aspect;
      vec2 uv = clamp(p * zoom + vec2(0.5) + offset, vec2(0.001), vec2(0.999));
      return color * Texel(texture, uv);
    }]]

  local intensity = 0
  local frequency = 42
  local rotation = 0.0035
  local custom_time = nil

  local setters = {
    intensity = function(v) intensity = math.max(0, tonumber(v) or 0) end,
    frequency = function(v) frequency = math.max(0, tonumber(v) or 42) end,
    rotation  = function(v) rotation  = tonumber(v) or 0.0035 end,
    time      = function(v) custom_time = v ~= nil and tonumber(v) or nil end,
  }

  local draw = function(buffer)
    local w = math.max(1, love.graphics.getWidth())
    local h = math.max(1, love.graphics.getHeight())
    shader:send("aspect", w / h)

    if intensity <= 0.001 then
      shader:send("offset", { 0, 0 })
      shader:send("rot", 0)
      shader:send("zoom", 1.0)
    else
      local t = custom_time or love.timer.getTime()
      -- Layered incommensurate harmonics for crisp, organic impact tremor
      local ox = (math.sin(t * frequency * 1.00) * 0.65 + math.cos(t * frequency * 2.37 + 1.1) * 0.35) * intensity
      local oy = (math.cos(t * frequency * 1.19 + 0.7) * 0.65 + math.sin(t * frequency * 2.71 + 2.4) * 0.35) * intensity
      local ang = math.sin(t * frequency * 0.83 + 0.4) * rotation * math.min(2.5, intensity / 8.0)
      -- Micro-zoom inwards so rotated/shifted edges never show borders
      local margin = math.min(0.06, (intensity / math.min(w, h)) * 1.6 + math.abs(ang) * 0.75)
      shader:send("offset", { ox / w, oy / h })
      shader:send("rot", ang)
      shader:send("zoom", 1.0 - margin)
    end

    moonshine.draw_shader(buffer, shader)
  end

  return moonshine.Effect{
    name = "screenshake",
    draw = draw,
    setters = setters,
    defaults = {
      intensity = 0,
      frequency = 42,
      rotation = 0.0035,
    }
  }
end
