-- Vector, quaternion and colour value types plus math helpers and noise.
-- Vec3/Quat/Color are FFI structs: operators always return new values.
-- They are mutable (v.x = 1 works) so copy with :copy() before mutating a shared one.
local ffi = require("ffi")
local sqrt, sin, cos, abs, floor, min, max, atan2, asin, acos, pi = math.sqrt, math.sin, math.cos, math.abs, math.floor, math.min, math.max, math.atan2, math.asin, math.acos, math.pi

ffi.cdef [[
typedef struct { double x, y, z; } grove_vec3;
typedef struct { double x, y, z, w; } grove_quat;
typedef struct { double r, g, b, a; } grove_color;
]]

-------------------------------------------------------------------- Vec3
local Vec3_t
local V = {}
V.__index = V

local function vec(x, y, z) return Vec3_t(x or 0, y or 0, z or 0) end

V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
  if type(a) == "number" then return vec(b.x * a, b.y * a, b.z * a) end
  if type(b) == "number" then return vec(a.x * b, a.y * b, a.z * b) end
  return vec(a.x * b.x, a.y * b.y, a.z * b.z)
end
V.__div = function(a, b)
  if type(b) == "number" then return vec(a.x / b, a.y / b, a.z / b) end
  return vec(a.x / b.x, a.y / b.y, a.z / b.z)
end
V.__unm = function(a) return vec(-a.x, -a.y, -a.z) end
V.__eq = function(a, b) return ffi.istype(Vec3_t, b) and a.x == b.x and a.y == b.y and a.z == b.z end
V.__tostring = function(a) return string.format("Vec3(%.3f, %.3f, %.3f)", a.x, a.y, a.z) end
V.__len = function(a) return sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

function V.length(a) return sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function V.length_sq(a) return a.x * a.x + a.y * a.y + a.z * a.z end
function V.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function V.cross(a, b) return vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
function V.normalized(a)
  local l = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
  if l < 1e-9 then return vec(0, 0, 0) end
  return vec(a.x / l, a.y / l, a.z / l)
end
function V.distance(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z; return sqrt(dx * dx + dy * dy + dz * dz) end
function V.distance_sq(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z; return dx * dx + dy * dy + dz * dz end
function V.lerp(a, b, t) return vec(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t) end
function V.copy(a) return vec(a.x, a.y, a.z) end
function V.flat(a) return vec(a.x, 0, a.z) end
function V.with_y(a, y) return vec(a.x, y, a.z) end
function V.unpack(a) return a.x, a.y, a.z end
function V.abs(a) return vec(abs(a.x), abs(a.y), abs(a.z)) end
function V.clamp_length(a, m)
  local l = a:length()
  if l > m and l > 0 then return a * (m / l) end
  return vec(a.x, a.y, a.z)
end
function V.move_toward(a, b, delta)
  local d = b - a
  local l = d:length()
  if l <= delta or l < 1e-9 then return b:copy() end
  return a + d * (delta / l)
end
function V.reflect(a, n) return a - n * (2 * a:dot(n)) end
function V.project(a, n) return n * (a:dot(n) / n:dot(n)) end
function V.slide(a, n) return a - n * a:dot(n) end
-- Frame-rate independent smoothing: approach b at 'speed' (1/seconds).
function V.damp(a, b, speed, dt) return a:lerp(b, 1 - math.exp(-speed * dt)) end
function V.rotated_y(a, ang) local c, s = cos(ang), sin(ang); return vec(a.x * c + a.z * s, a.y, -a.x * s + a.z * c) end

Vec3_t = ffi.metatype("grove_vec3", V)
Vec3 = setmetatable({
  ZERO = vec(0, 0, 0), ONE = vec(1, 1, 1), UP = vec(0, 1, 0), DOWN = vec(0, -1, 0),
  LEFT = vec(-1, 0, 0), RIGHT = vec(1, 0, 0), FORWARD = vec(0, 0, -1), BACK = vec(0, 0, 1),
  is = function(v) return ffi.istype(Vec3_t, v) end,
}, { __call = function(_, x, y, z)
  if y == nil and x ~= nil then return vec(x, x, x) end
  return vec(x, y, z)
end })

-------------------------------------------------------------------- Quat
local Quat_t
local Q = {}
Q.__index = Q
local function quat(x, y, z, w) return Quat_t(x, y, z, w) end

Q.__mul = function(a, b)
  if ffi.istype(Vec3_t, b) then
    -- rotate vector
    local qx, qy, qz, qw = a.x, a.y, a.z, a.w
    local tx = 2 * (qy * b.z - qz * b.y)
    local ty = 2 * (qz * b.x - qx * b.z)
    local tz = 2 * (qx * b.y - qy * b.x)
    return vec(b.x + qw * tx + (qy * tz - qz * ty), b.y + qw * ty + (qz * tx - qx * tz), b.z + qw * tz + (qx * ty - qy * tx))
  end
  return quat(
    a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
end
Q.__tostring = function(q) return string.format("Quat(%.3f, %.3f, %.3f, %.3f)", q.x, q.y, q.z, q.w) end

function Q.inverse(q) return quat(-q.x, -q.y, -q.z, q.w) end
function Q.copy(q) return quat(q.x, q.y, q.z, q.w) end
function Q.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w end
function Q.normalized(q)
  local l = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
  if l < 1e-9 then return quat(0, 0, 0, 1) end
  return quat(q.x / l, q.y / l, q.z / l, q.w / l)
end
function Q.slerp(a, b, t)
  local d = a:dot(b)
  local bx, by, bz, bw = b.x, b.y, b.z, b.w
  if d < 0 then d = -d; bx, by, bz, bw = -bx, -by, -bz, -bw end
  if d > 0.9995 then
    return quat(a.x + (bx - a.x) * t, a.y + (by - a.y) * t, a.z + (bz - a.z) * t, a.w + (bw - a.w) * t):normalized()
  end
  local th = acos(d)
  local s = sin(th)
  local wa, wb = sin((1 - t) * th) / s, sin(t * th) / s
  return quat(a.x * wa + bx * wb, a.y * wa + by * wb, a.z * wa + bz * wb, a.w * wa + bw * wb)
end
function Q.damp(a, b, speed, dt) return a:slerp(b, 1 - math.exp(-speed * dt)) end
function Q.forward(q) return q * vec(0, 0, -1) end
function Q.right(q) return q * vec(1, 0, 0) end
function Q.up(q) return q * vec(0, 1, 0) end
-- Euler angles in radians, YXZ order (yaw, then pitch, then roll) like Godot.
function Q.to_euler(q)
  local x, y, z, w = q.x, q.y, q.z, q.w
  local sinp = 2 * (w * x - y * z)
  local pitch = abs(sinp) >= 1 and (sinp > 0 and pi / 2 or -pi / 2) or asin(sinp)
  local yaw = atan2(2 * (w * y + x * z), 1 - 2 * (x * x + y * y))
  local roll = atan2(2 * (w * z + x * y), 1 - 2 * (x * x + z * z))
  return vec(pitch, yaw, roll)
end
function Q.yaw(q) return q:to_euler().y end

local function axis_angle(axis, ang)
  local a = axis:normalized()
  local s = sin(ang * 0.5)
  return quat(a.x * s, a.y * s, a.z * s, cos(ang * 0.5))
end

Quat_t = ffi.metatype("grove_quat", Q)
Quat = setmetatable({
  IDENTITY = quat(0, 0, 0, 1),
  axis_angle = axis_angle,
  euler = function(x, y, z)
    if ffi.istype(Vec3_t, x) then x, y, z = x.x, x.y, x.z end
    return axis_angle(vec(0, 1, 0), y or 0) * axis_angle(vec(1, 0, 0), x or 0) * axis_angle(vec(0, 0, 1), z or 0)
  end,
  euler_deg = function(x, y, z)
    local r = pi / 180
    return Quat.euler((x or 0) * r, (y or 0) * r, (z or 0) * r)
  end,
  from_y = function(ang) return axis_angle(vec(0, 1, 0), ang) end,
  -- Rotation whose -Z axis points along 'fwd'.
  look_rotation = function(fwd, up)
    up = up or vec(0, 1, 0)
    local f = fwd:normalized()
    if f:length_sq() < 1e-9 then return quat(0, 0, 0, 1) end
    local r = up:cross(-f)
    if r:length_sq() < 1e-9 then r = vec(1, 0, 0) end
    r = r:normalized()
    local u = (-f):cross(r)
    local zx, zy, zz = -f.x, -f.y, -f.z
    local m00, m11, m22 = r.x, u.y, zz
    local tr = m00 + m11 + m22
    local qx, qy, qz, qw
    if tr > 0 then
      local s = sqrt(tr + 1) * 2
      qw = 0.25 * s; qx = (u.z - zy) / s; qy = (zx - r.z) / s; qz = (r.y - u.x) / s
    elseif m00 > m11 and m00 > m22 then
      local s = sqrt(1 + m00 - m11 - m22) * 2
      qw = (u.z - zy) / s; qx = 0.25 * s; qy = (u.x + r.y) / s; qz = (zx + r.z) / s
    elseif m11 > m22 then
      local s = sqrt(1 + m11 - m00 - m22) * 2
      qw = (zx - r.z) / s; qx = (u.x + r.y) / s; qy = 0.25 * s; qz = (zy + u.z) / s
    else
      local s = sqrt(1 + m22 - m00 - m11) * 2
      qw = (r.y - u.x) / s; qx = (zx + r.z) / s; qy = (zy + u.z) / s; qz = 0.25 * s
    end
    return quat(qx, qy, qz, qw):normalized()
  end,
  between = function(a, b)
    a, b = a:normalized(), b:normalized()
    local d = a:dot(b)
    if d > 0.99999 then return quat(0, 0, 0, 1) end
    if d < -0.99999 then
      local ax = vec(1, 0, 0):cross(a)
      if ax:length_sq() < 1e-6 then ax = vec(0, 1, 0):cross(a) end
      return axis_angle(ax, pi)
    end
    local c = a:cross(b)
    return quat(c.x, c.y, c.z, 1 + d):normalized()
  end,
  is = function(q) return ffi.istype(Quat_t, q) end,
}, { __call = function(_, x, y, z, w) return quat(x or 0, y or 0, z or 0, w or 1) end })

-------------------------------------------------------------------- Color
local Color_t
local Cm = {}
Cm.__index = Cm
local function color(r, g, b, a) return Color_t(r, g, b, a or 1) end
Cm.__mul = function(a, b)
  if type(b) == "number" then return color(a.r * b, a.g * b, a.b * b, a.a) end
  if type(a) == "number" then return color(b.r * a, b.g * a, b.b * a, b.a) end
  return color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)
end
Cm.__add = function(a, b) return color(a.r + b.r, a.g + b.g, a.b + b.b, a.a + b.a) end
Cm.__tostring = function(c) return string.format("Color(%.3f, %.3f, %.3f, %.3f)", c.r, c.g, c.b, c.a) end
function Cm.lerp(a, b, t) return color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t) end
function Cm.with_alpha(c, a) return color(c.r, c.g, c.b, a) end
function Cm.copy(c) return color(c.r, c.g, c.b, c.a) end
function Cm.lighten(c, t) return c:lerp(color(1, 1, 1, c.a), t) end
function Cm.darken(c, t) return c:lerp(color(0, 0, 0, c.a), t) end
function Cm.unpack(c) return c.r, c.g, c.b, c.a end

Color_t = ffi.metatype("grove_color", Cm)

local function hsv(h, s, v, a)
  h = (h % 1) * 6
  local i = floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  local r, g, b
  if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
  return color(r, g, b, a or 1)
end

Color = setmetatable({
  hex = function(s, a)
    s = s:gsub("#", "")
    local r, g, b = tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16)
    local aa = #s >= 8 and tonumber(s:sub(7, 8), 16) / 255 or (a or 1)
    return color(r / 255, g / 255, b / 255, aa)
  end,
  hsv = hsv,
  is = function(c) return ffi.istype(Color_t, c) end,
  WHITE = color(1, 1, 1), BLACK = color(0, 0, 0), CLEAR = color(0, 0, 0, 0),
  RED = color(0.9, 0.2, 0.2), GREEN = color(0.3, 0.8, 0.35), BLUE = color(0.25, 0.45, 0.95),
  YELLOW = color(1, 0.85, 0.2), GRAY = color(0.5, 0.5, 0.5),
}, { __call = function(_, r, g, b, a)
  if type(r) == "string" then return Color.hex(r, g) end
  if g == nil then return color(r, r, r, 1) end
  return color(r, g, b, a)
end })

-------------------------------------------------------------------- helpers
function math.clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
function math.lerp(a, b, t) return a + (b - a) * t end
function math.inverse_lerp(a, b, v) return (v - a) / (b - a) end
function math.remap(v, a, b, c, d) return c + (d - c) * ((v - a) / (b - a)) end
function math.smoothstep(a, b, v) local t = math.clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) end
function math.sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
function math.round(v) return floor(v + 0.5) end
function math.move_toward(a, b, d) if abs(b - a) <= d then return b end return a + math.sign(b - a) * d end
function math.damp(a, b, speed, dt) return a + (b - a) * (1 - math.exp(-speed * dt)) end
function math.wrap_angle(a) return (a + pi) % (2 * pi) - pi end
function math.lerp_angle(a, b, t) return a + math.wrap_angle(b - a) * t end
function math.deg(r) return r * 180 / pi end
function math.rad(d) return d * pi / 180 end
math.tau = pi * 2

-------------------------------------------------------------------- random
-- Seedable generator (xorshift32) so generated worlds are repeatable.
Random = class("Random")
function Random:_init(seed)
  if type(seed) == "table" then seed = seed.seed end
  self.state = (math.floor(tonumber(seed) or os.time()) % 2147483646) + 1
end
local bit = require("bit")
local bxor, lshift, rshift = bit.bxor, bit.lshift, bit.rshift
-- Returns a float in [0, 1).
function Random:next()
  local x = self.state
  x = bxor(x, lshift(x, 13))
  x = bxor(x, rshift(x, 17))
  x = bxor(x, lshift(x, 5))
  self.state = x
  return (x % 4294967296) / 4294967296
end
function Random:float(a, b)
  local r = self:next()
  if a == nil then return r end
  if b == nil then return r * a end
  return a + (b - a) * r
end
function Random:int(a, b) return math.floor(self:float(a, b + 1)) end
function Random:pick(t) return t[self:int(1, #t)] end
function Random:chance(p) return self:float() < p end
function Random:unit_vec3()
  local z = self:float(-1, 1)
  local a = self:float(0, math.tau)
  local r = sqrt(1 - z * z)
  return vec(r * cos(a), r * sin(a), z)
end
function Random:in_circle(radius)
  local a = self:float(0, math.tau)
  local r = sqrt(self:float()) * (radius or 1)
  return r * cos(a), r * sin(a)
end
rng = Random(1337)

-------------------------------------------------------------------- noise
-- 2D/3D gradient noise (Perlin) and fractal sums, deterministic per seed.
Noise = {}
local perm = {}
function Noise.seed(seed)
  local r = Random(seed)
  local p = {}
  for i = 0, 255 do p[i] = i end
  for i = 255, 1, -1 do
    local j = r:int(0, i)
    p[i], p[j] = p[j], p[i]
  end
  for i = 0, 511 do perm[i] = p[i % 256] end
end
Noise.seed(0)

local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end
local function grad2(h, x, y)
  h = h % 8
  local u = h < 4 and x or y
  local v = h < 4 and y or x
  return ((h % 2) == 0 and u or -u) + ((math.floor(h / 2) % 2) == 0 and v or -v)
end
local function grad3(h, x, y, z)
  h = h % 16
  local u = h < 8 and x or y
  local v = h < 4 and y or ((h == 12 or h == 14) and x or z)
  return ((h % 2) == 0 and u or -u) + ((math.floor(h / 2) % 2) == 0 and v or -v)
end

function Noise.perlin2(x, y)
  local xi, yi = floor(x), floor(y)
  local xf, yf = x - xi, y - yi
  xi, yi = xi % 256, yi % 256
  local u, v = fade(xf), fade(yf)
  local aa, ab = perm[perm[xi] + yi], perm[perm[xi] + yi + 1]
  local ba, bb = perm[perm[xi + 1] + yi], perm[perm[xi + 1] + yi + 1]
  local x1 = grad2(aa, xf, yf) + (grad2(ba, xf - 1, yf) - grad2(aa, xf, yf)) * u
  local x2 = grad2(ab, xf, yf - 1) + (grad2(bb, xf - 1, yf - 1) - grad2(ab, xf, yf - 1)) * u
  return (x1 + (x2 - x1) * v) * 0.7
end

function Noise.perlin3(x, y, z)
  local xi, yi, zi = floor(x), floor(y), floor(z)
  local xf, yf, zf = x - xi, y - yi, z - zi
  xi, yi, zi = xi % 256, yi % 256, zi % 256
  local u, v, w = fade(xf), fade(yf), fade(zf)
  local A, B = perm[xi] + yi, perm[xi + 1] + yi
  local AA, AB, BA, BB = perm[A] + zi, perm[A + 1] + zi, perm[B] + zi, perm[B + 1] + zi
  local function l(a, b, t) return a + (b - a) * t end
  return l(l(l(grad3(perm[AA], xf, yf, zf), grad3(perm[BA], xf - 1, yf, zf), u),
             l(grad3(perm[AB], xf, yf - 1, zf), grad3(perm[BB], xf - 1, yf - 1, zf), u), v),
           l(l(grad3(perm[AA + 1], xf, yf, zf - 1), grad3(perm[BA + 1], xf - 1, yf, zf - 1), u),
             l(grad3(perm[AB + 1], xf, yf - 1, zf - 1), grad3(perm[BB + 1], xf - 1, yf - 1, zf - 1), u), v), w)
end

function Noise.fbm2(x, y, octaves, lacunarity, gain)
  octaves, lacunarity, gain = octaves or 4, lacunarity or 2, gain or 0.5
  local s, a, f, norm = 0, 1, 1, 0
  for _ = 1, octaves do
    s = s + Noise.perlin2(x * f, y * f) * a
    norm = norm + a
    a = a * gain
    f = f * lacunarity
  end
  return s / norm
end

function Noise.fbm3(x, y, z, octaves)
  octaves = octaves or 4
  local s, a, f, norm = 0, 1, 1, 0
  for _ = 1, octaves do
    s = s + Noise.perlin3(x * f, y * f, z * f) * a
    norm = norm + a
    a = a * 0.5
    f = f * 2
  end
  return s / norm
end
