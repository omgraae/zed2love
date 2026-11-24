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
    extern vec2 blur_step;
    extern number center_protect;

    vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
    {
      if (dot(blur_step, blur_step) < 0.00000001) {
        return color * Texel(texture, tc);
      }

      // Slightly reduce blur right at the center focal point while streaking across the frame
      number dist = length((tc - vec2(0.5)) * vec2(1.4, 1.0));
      number radial = mix(1.0 - center_protect, 1.25, clamp(dist * 1.45, 0.0, 1.0));
      vec2 step_uv = blur_step * radial;

      vec4 acc = vec4(0.0);
      number total_w = 0.0;
      for (int i = 0; i < 9; i++) {
        number fi = float(i);
        number w = 1.0 - (fi / 10.5);
        vec2 uv = clamp(tc + step_uv * fi, vec2(0.001), vec2(0.999));
        acc += Texel(texture, uv) * w;
        total_w += w;
      }
      return color * (acc / total_w);
    }]]

  local dir_x, dir_y = 0, 0
  local strength = 0
  local center_protect = 0.25

  local setters = {
    direction = function(v)
      assert(type(v) == "table" and #v >= 2, "Invalid value for `direction': expected {dx, dy}")
      dir_x = tonumber(v[1]) or 0
      dir_y = tonumber(v[2]) or 0
    end,
    strength = function(v)
      strength = math.max(0, tonumber(v) or 0)
    end,
    center_protect = function(v)
      center_protect = math.max(0, math.min(0.95, tonumber(v) or 0.25))
    end,
  }

  local draw = function(buffer)
    local w = math.max(1, love.graphics.getWidth())
    local h = math.max(1, love.graphics.getHeight())
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if strength <= 0.05 or len <= 0.0001 then
      shader:send("blur_step", { 0, 0 })
    else
      local nx = dir_x / len
      local ny = dir_y / len
      -- Spread `strength` pixels across 8 directional intervals
      shader:send("blur_step", { (nx * strength / 8.0) / w, (ny * strength / 8.0) / h })
    end
    shader:send("center_protect", center_protect)
    moonshine.draw_shader(buffer, shader)
  end

  return moonshine.Effect{
    name = "motionblur",
    draw = draw,
    setters = setters,
    defaults = {
      direction = { 0, 0 },
      strength = 0,
      center_protect = 0.25,
    }
  }
end
