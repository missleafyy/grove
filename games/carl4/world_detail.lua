-- Extra set dressing for Nevada: ground clutter, more cactus species, roadside fences/signs/billboards,
-- wrecked cars, cattle skulls, hoodoos and a rock arch, a far mountain ring, plus living things
-- (circling vultures, wandering dust devils) and town/crash-site clutter.
local Art = require("art")
local P = Art.pal
local Detail = {}

local function C(h) return Color.hex(h) end
local function sm(a, b, x) return math.smoothstep(a, b, x) end

------------------------------------------------------------------ meshes
local function pebble(seed)
  local m = MeshData.icosphere(1, 1, C("#a98e72"))
  local r = Random(seed)
  m:displace(function(x, y, z) local k = 1 + r:float(-0.25, 0.2); return x * (k - 1), y * (k - 1) * 0.6 - 0.35 * y, z * (k - 1) end)
  return m:flat()
end

local function grass_tuft(seed)
  local m = MeshData()
  local r = Random(seed)
  for _ = 1, 9 do
    local col = C("#c9b073"):lerp(C("#8f8a4e"), r:float(0, 1))
    local blade = MeshData.cone(0.025, r:float(0.25, 0.5), 3, col)
    m:append(blade, Vec3(r:float(-0.08, 0.08), 0.15, r:float(-0.08, 0.08)), Quat.euler(r:float(-0.5, 0.5), r:float(0, 6.28), r:float(-0.5, 0.5)))
  end
  return m:flat()
end

local function barrel_cactus()
  local m = MeshData.sphere(0.35, 24, 12, C("#4f8a3c"))
  m:displace(function(x, y, z)
    local a = math.atan2(x, z)
    local rib = 1 + math.cos(a * 12) * 0.06
    local yy = y < 0 and y * 0.4 or y * 1.15
    return x * (rib - 1), yy - y + 0.12, z * (rib - 1)
  end)
  m:paint_fn(function(x, y, z, r, g, b)
    local a = math.atan2(x, z)
    if math.cos(a * 12) > 0.85 then return 0.85, 0.75, 0.45 end   -- spine ridges
    return r, g, b
  end)
  for i = 0, 5 do
    local a = i / 6 * math.tau
    m:append(MeshData.sphere(0.05, 6, 4, C("#f5d33a")), Vec3(math.sin(a) * 0.08, 0.5, math.cos(a) * 0.08))
  end
  m:append(MeshData.sphere(0.04, 6, 4, C("#e8743b")), Vec3(0, 0.52, 0))
  return m:flat()
end

local function cholla(seed)
  local m = MeshData()
  local r = Random(seed)
  local fuzz = C("#c8c7a0")
  local function seg(pos, dir, depth)
    local len = r:float(0.3, 0.45)
    local q = Quat.look_rotation(dir) * Quat.euler(-math.pi / 2, 0, 0)
    local s = MeshData.capsule(0.07, len, 8, C("#7f9a54"))
    s:paint_fn(function(x, y, z, rr, gg, bb) if math.floor((y + 1) * 30 + math.atan2(x, z) * 3) % 3 == 0 then return fuzz.r, fuzz.g, fuzz.b end return rr, gg, bb end)
    local tip = pos + dir * len
    m:append(s, (pos + tip) * 0.5, q)
    if depth < 3 then
      for _ = 1, r:int(1, 2) do
        local d2 = (dir + Vec3(r:float(-0.9, 0.9), r:float(0.1, 0.6), r:float(-0.9, 0.9))):normalized()
        seg(tip, d2, depth + 1)
      end
    else
      m:append(MeshData.sphere(0.05, 6, 4, C("#e6d24a")), tip)
    end
  end
  m:append(MeshData.capsule(0.09, 0.6, 8, C("#6e7d48")), Vec3(0, 0.3, 0))
  seg(Vec3(0, 0.55, 0), Vec3(0, 1, 0), 1)
  return m:flat()
end

local function yucca(seed)
  local m = MeshData()
  local r = Random(seed)
  for i = 1, 26 do
    local a = r:float(0, math.tau)
    local tilt = r:float(0.15, 1.2)
    local col = C("#7c9a5a"):lerp(C("#a7b56b"), r:float(0, 1))
    local leaf = MeshData.cone(0.035, r:float(0.5, 0.8), 3, col)
    leaf:transform(nil, nil, Vec3(1, 1, 0.35))
    m:append(leaf, Vec3(0, 0.25, 0), Quat.euler(0, a, 0) * Quat.euler(tilt, 0, 0))
  end
  m:append(MeshData.cylinder(0.08, 0.12, 0.3, 8, C("#6b5a3e")), Vec3(0, 0.12, 0))
  -- Flower stalk on some.
  m:append(MeshData.cylinder(0.015, 0.02, 1.2, 5, C("#8f8a4e")), Vec3(0, 0.9, 0))
  for i = 0, 7 do m:append(MeshData.sphere(0.04, 5, 4, C("#f3ecd2")), Vec3(math.sin(i) * 0.05, 1.2 + i * 0.05, math.cos(i) * 0.05)) end
  return m:flat()
end

local function cattle_skull()
  local m = MeshData()
  local bone = C("#eee6d2")
  local skull = MeshData.sphere(0.16, 12, 8, bone)
  skull:transform(nil, nil, Vec3(1, 0.7, 1.4))
  m:append(skull, Vec3(0, 0.08, 0))
  m:append(MeshData.box(0.12, 0.08, 0.2, bone), Vec3(0, 0.05, -0.22))
  for _, s in ipairs({ -1, 1 }) do
    m:append(MeshData.sphere(0.045, 6, 4, P.ink), Vec3(s * 0.08, 0.12, -0.1))
    local horn = MeshData.cone(0.035, 0.32, 6, bone)
    m:append(horn, Vec3(s * 0.22, 0.14, 0.05), Quat.euler(0, 0, s * -1.2))
    m:append(MeshData.cone(0.022, 0.12, 5, bone), Vec3(s * 0.36, 0.26, 0.05), Quat.euler(0, 0, s * -0.2))
  end
  return m:flat()
end

local function fence_post()
  local m = MeshData.cylinder(0.06, 0.07, 1.4, 6, C("#8a7a62"))
  m:transform(Vec3(0, 0.7, 0))
  m:append(MeshData.cone(0.07, 0.06, 6, C("#6e604c")), Vec3(0, 1.43, 0))
  return m:flat()
end

local function wire()
  local m = MeshData.box(0.015, 0.015, 1, C("#5a5f69"))
  return m
end

local function sign_mesh(kind)
  local m = MeshData()
  m:append(MeshData.cylinder(0.04, 0.04, 2.2, 6, P.chrome), Vec3(0, 1.1, 0))
  if kind == "speed" then
    m:append(MeshData.box(0.7, 0.9, 0.04, P.white), Vec3(0, 2.0, 0))
    m:append(MeshData.box(0.62, 0.82, 0.045, P.ink), Vec3(0, 2.0, 0))
    m:append(MeshData.box(0.56, 0.76, 0.05, P.white), Vec3(0, 2.0, 0))
  elseif kind == "route" then
    local shield = MeshData.cylinder(0.42, 0.42, 0.04, 6, P.white)
    m:append(shield, Vec3(0, 2.1, 0), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.cylinder(0.36, 0.36, 0.05, 6, P.ink), Vec3(0, 2.1, 0), Quat.euler(math.pi / 2, 0, 0))
  elseif kind == "green" then
    m:append(MeshData.cylinder(0.04, 0.04, 2.2, 6, P.chrome), Vec3(1.4, 1.1, 0))
    m:append(MeshData.box(1.9, 0.8, 0.04, C("#1f6b3a")), Vec3(0.7, 2.2, 0))
    m:append(MeshData.box(1.8, 0.7, 0.045, P.white), Vec3(0.7, 2.2, 0))
    m:append(MeshData.box(1.74, 0.64, 0.05, C("#1f6b3a")), Vec3(0.7, 2.2, 0))
  elseif kind == "warn" then
    m:append(MeshData.box(0.7, 0.7, 0.04, P.line_yellow), Vec3(0, 2.0, 0), Quat.euler(0, 0, math.pi / 4))
    m:append(MeshData.box(0.6, 0.6, 0.045, P.ink), Vec3(0, 2.0, 0), Quat.euler(0, 0, math.pi / 4))
    m:append(MeshData.box(0.54, 0.54, 0.05, P.line_yellow), Vec3(0, 2.0, 0), Quat.euler(0, 0, math.pi / 4))
  end
  return m:flat()
end

local function billboard_mesh(col_a, col_b)
  local m = MeshData()
  for _, x in ipairs({ -2.8, 0, 2.8 }) do m:append(MeshData.box(0.25, 6, 0.25, P.wood_dark), Vec3(x, 3, 0.3)) end
  for _, y in ipairs({ 2.5, 4.5 }) do m:append(MeshData.box(6.4, 0.15, 0.15, P.wood_dark), Vec3(0, y, 0.45)) end
  m:append(MeshData.box(7.4, 3.4, 0.2, col_a), Vec3(0, 5.2, 0))
  m:append(MeshData.box(7.0, 3.0, 0.22, col_b), Vec3(0, 5.2, 0))
  m:append(MeshData.box(7.4, 0.1, 0.8, P.wood_grey), Vec3(0, 3.45, -0.3))     -- catwalk
  for i = 0, 3 do m:append(MeshData.cylinder(0.06, 0.12, 0.25, 6, P.metal_dark), Vec3(-2.6 + i * 1.75, 7.0, -0.3), Quat.euler(-0.6, 0, 0)) end  -- lamps
  -- Peeling-paint patches.
  local r = Random(#tostring(col_a))
  for _ = 1, 6 do m:append(MeshData.box(r:float(0.2, 0.6), r:float(0.2, 0.5), 0.23, col_a:darken(0.15)), Vec3(r:float(-3, 3), r:float(4, 6.4), 0)) end
  return m:flat()
end

local function wreck_car(seed)
  local r = Random(seed)
  local paint = r:pick({ C("#9a4b3a"), C("#4b6b8a"), C("#c9a24a"), C("#6a7a5a") })
  local rust = C("#7a4a2a")
  local m = MeshData()
  local body = MeshData.box(1.9, 0.6, 4.4, paint)
  body:paint_fn(function(x, y, z, rr, gg, bb)
    if Noise.perlin3(x * 3 + seed, y * 3, z * 3) > 0.15 then return rust.r, rust.g, rust.b end
    return rr, gg, bb
  end)
  m:append(body, Vec3(0, 0.55, 0))
  local cab = MeshData.box(1.7, 0.55, 2.0, paint)
  cab:displace(function(x, y, z) if y > 0 then return -x * 0.12, 0, -z * 0.15 end end)
  cab:paint_fn(function(x, y, z, rr, gg, bb)
    if y > 0.02 and math.abs(x) > 0.6 then return 0.15, 0.18, 0.2 end      -- empty windows
    if y > 0.02 and math.abs(z) > 0.8 then return 0.15, 0.18, 0.2 end
    return rr, gg, bb
  end)
  m:append(cab, Vec3(0, 1.12, 0.2))
  for _, sx in ipairs({ -1, 1 }) do
    for _, sz in ipairs({ -1.4, 1.4 }) do m:append(MeshData.cylinder(0.3, 0.3, 0.12, 10, P.ink), Vec3(sx * 0.95, 0.15, sz), Quat.euler(0, 0, math.pi / 2)) end
    m:append(MeshData.sphere(0.12, 8, 6, C("#e0d8b0")), Vec3(sx * 0.65, 0.65, -2.21))
  end
  m:append(MeshData.box(2.0, 0.15, 0.2, P.chrome), Vec3(0, 0.35, -2.25))
  m:append(MeshData.box(2.0, 0.15, 0.2, P.chrome), Vec3(0, 0.35, 2.25))
  -- Popped hood.
  m:append(MeshData.box(1.7, 0.05, 1.2, paint:darken(0.1)), Vec3(0, 1.1, -1.5), Quat.euler(-0.7, 0, 0))
  return m:flat()
end

local function hoodoo(seed)
  local r = Random(seed)
  local m = MeshData()
  local y = 0
  local bands = { C("#c96a3d"), C("#e09a62"), C("#b85a35"), C("#efc08a"), C("#d07a48") }
  for i = 1, r:int(4, 6) do
    local rad = r:float(0.7, 1.2) * (1 - i * 0.06)
    local h = r:float(0.9, 1.6)
    local s = MeshData.sphere(1, 12, 8, bands[(i % #bands) + 1])
    s:transform(nil, nil, Vec3(rad, h * 0.6, rad))
    local rr = Random(seed + i)
    s:displace(function(x, yy, z) local k = rr:float(-0.08, 0.08); return x * k, 0, z * k end)
    m:append(s, Vec3(r:float(-0.1, 0.1), y + h * 0.5, r:float(-0.1, 0.1)))
    y = y + h * 0.85
  end
  -- Hard cap rock.
  local cap = MeshData.cylinder(1.3, 1.1, 0.5, 9, C("#6e4a38"))
  m:append(cap, Vec3(0.2, y + 0.2, 0), Quat.euler(0.1, 0, 0.08))
  return m:flat(), y + 0.45
end

local function arch()
  local m = MeshData.torus(6, 1.6, 28, 10, C("#d0784a"))
  m:displace(function(x, y, z)
    local n = Noise.perlin3(x * 0.4, y * 0.4, z * 0.4) * 0.6
    if z < -1.0 then return 0, 0, 0 end
    return x * n * 0.1, y * n * 0.1, z * n * 0.1
  end)
  m:paint_fn(function(x, y, z, r, g, b)
    local band = math.floor((z + 8) * 0.9) % 3
    local c = band == 0 and C("#d0784a") or band == 1 and C("#e8a46e") or C("#b45c38")
    return c.r, c.g, c.b
  end)
  m:transform(nil, Quat.euler(math.pi / 2, 0, 0))
  return m:flat()
end

local function far_mountain(seed)
  local r = Random(seed)
  local m = MeshData.cone(1, 1, 7, C("#b77a62"))
  m:displace(function(x, y, z) local k = r:float(-0.15, 0.15); return x * k, (y > 0.4 and r:float(-0.1, 0.05) or 0), z * k end)
  m:paint_fn(function(x, y, z, rr, gg, bb)
    local c = C("#9a6a68"):lerp(C("#c98d6a"), sm(-0.5, 0.5, y))
    return c.r, c.g, c.b
  end)
  return m:flat()
end

local function vulture()
  local m = MeshData()
  local black = C("#1d1a20")
  local body = MeshData.sphere(0.25, 8, 6, black)
  body:transform(nil, nil, Vec3(0.8, 0.7, 1.8))
  m:append(body)
  m:append(MeshData.sphere(0.09, 6, 4, C("#b8433b")), Vec3(0, 0.05, -0.5))
  for _, s in ipairs({ -1, 1 }) do
    local wing = MeshData.box(1.3, 0.04, 0.5, black)
    wing:displace(function(x, y, z) return 0, math.abs(x) * 0.15, x * s > 0.3 and z * -0.2 or 0 end)
    m:append(wing, Vec3(s * 0.7, 0.05, 0))
    for i = 0, 3 do m:append(MeshData.box(0.08, 0.02, 0.3, black), Vec3(s * (1.35 + i * 0.02), 0.25, -0.12 + i * 0.1), Quat.euler(0, s * (0.2 + i * 0.12), 0)) end
  end
  m:append(MeshData.box(0.4, 0.03, 0.35, black), Vec3(0, 0, 0.55))
  return m:flat()
end

local function windmill_parts()
  local tower = MeshData()
  for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
    tower:append(MeshData.box(0.12, 9, 0.12, P.metal), Vec3(sx * 0.6, 4.5, sz * 0.6), Quat.euler(sz * -0.06, 0, sx * 0.06))
  end end
  for i = 1, 4 do tower:append(MeshData.box(1.3 - i * 0.12, 0.06, 1.3 - i * 0.12, P.metal_dark), Vec3(0, i * 2, 0)) end
  tower:append(MeshData.box(0.5, 0.4, 0.8, P.metal_dark), Vec3(0, 9.1, 0.1))
  tower:append(MeshData.box(0.05, 1.0, 1.4, P.red), Vec3(0, 9.2, 1.1))     -- tail vane
  local fan = MeshData()
  for i = 0, 15 do
    local a = i / 16 * math.tau
    fan:append(MeshData.box(0.18, 1.1, 0.02, P.metal), Vec3(math.sin(a) * 0.8, math.cos(a) * 0.8, 0), Quat.euler(0, 0.4, -a))
  end
  fan:append(MeshData.torus(1.3, 0.03, 24, 4, P.metal_dark), Vec3(), Quat.euler(math.pi / 2, 0, 0))
  fan:append(MeshData.cylinder(0.14, 0.14, 0.2, 8, P.red), Vec3(), Quat.euler(math.pi / 2, 0, 0))
  return tower:flat(), fan:flat()
end

------------------------------------------------------------------ build
function Detail.terrain_texture()
  -- Tileable sand grain: speckles plus soft ripples, multiplied over the terrain's vertex colours.
  local N = 256
  local function h(x, y) local s = math.sin(x * 127.1 + y * 311.7) * 43758.5453; return s - math.floor(s) end
  return Texture.generate(N, N, function(x, y, u, v)
    local ripple = math.sin((u + math.sin(v * math.tau * 2) * 0.04) * math.tau * 6) * 0.03
    local low = (math.sin(u * math.tau * 3 + 1.3) * math.sin(v * math.tau * 2 + 0.4)) * 0.04
    local g = h(x, y)
    local speck = g > 0.93 and -0.18 or (g < 0.05 and 0.06 or 0)
    local k = 0.9 + ripple + low + speck + (h(x * 3, y * 7) - 0.5) * 0.06
    return k, k * 0.985, k * 0.97, 1
  end)
end

function Detail.build(root, M, ctx)
  local r = Random(77)
  local height, road_x, clear, flat_spot = ctx.height, ctx.road_x, ctx.clear, ctx.flat_spot
  local function mm(mesh, mat, shadow) local n = MultiMeshInstance3D { mesh = mesh:upload(), material = mat or M.vertex, cast_shadow = shadow ~= false }; root:add_child(n); return n end
  local function near_zone(x, z, extra)
    for _, zn in pairs(World.zones) do if (x - zn.x) ^ 2 + (z - zn.z) ^ 2 < (zn.r + extra) ^ 2 then return true end end
    return false
  end

  -- Ground clutter: pebbles and dry grass (no shadows, everywhere).
  local peb = { mm(pebble(1), M.vertex, false), mm(pebble(2), M.vertex, false) }
  local pn = { 0, 0 }
  for _ = 1, 4000 do
    local x, z = r:float(-180, 180), r:float(-180, 180)
    local h = flat_spot(x, z, 8)
    if h then
      local k = r:int(1, 2)
      pn[k] = pn[k] + 1
      local t = r:float(0.8, 1.15)
      peb[k]:set_instance(pn[k], Vec3(x, h, z), Quat.euler(0, r:float(0, 6.28), 0), r:float(0.06, 0.22), Color(t, t * 0.97, t * 0.93))
    end
  end
  local grass = { mm(grass_tuft(3), M.foliage, false), mm(grass_tuft(4), M.foliage, false) }
  local gn = { 0, 0 }
  for _ = 1, 9000 do
    local x, z = r:float(-180, 180), r:float(-180, 180)
    if Noise.perlin2(x * 0.05, z * 0.05) > -0.15 then
      local h = flat_spot(x, z, 6)
      if h and math.abs(x - road_x(z)) > 5.5 then
        local k = r:int(1, 2)
        gn[k] = gn[k] + 1
        local t = r:float(0.85, 1.1)
        grass[k]:set_instance(gn[k], Vec3(x, h - 0.05, z), Quat.from_y(r:float(0, 6.28)), r:float(0.7, 1.5), Color(t, t, t * 0.9))
      end
    end
  end

  -- More cactus species.
  local barrel = mm(barrel_cactus(), M.foliage)
  local cholla_k = { mm(cholla(5), M.foliage), mm(cholla(9), M.foliage) }
  local yucca_k = { mm(yucca(2), M.foliage), mm(yucca(6), M.foliage) }
  local bn, cn, yn = 0, { 0, 0 }, { 0, 0 }
  for _ = 1, 2500 do
    local x, z = r:float(-170, 170), r:float(-170, 170)
    local h = flat_spot(x, z, 5)
    if h and clear(x, z, 1) then
      local roll = r:float(0, 1)
      if roll < 0.35 and bn < 140 then
        bn = bn + 1
        barrel:set_instance(bn, Vec3(x, h - 0.05, z), Quat.from_y(r:float(0, 6.28)), r:float(0.7, 1.3))
      elseif roll < 0.65 then
        local k = r:int(1, 2)
        if cn[k] < 70 then cn[k] = cn[k] + 1; cholla_k[k]:set_instance(cn[k], Vec3(x, h - 0.05, z), Quat.from_y(r:float(0, 6.28)), r:float(0.9, 1.5)) end
      else
        local k = r:int(1, 2)
        if yn[k] < 90 then yn[k] = yn[k] + 1; yucca_k[k]:set_instance(yn[k], Vec3(x, h - 0.05, z), Quat.from_y(r:float(0, 6.28)), r:float(0.8, 1.4)) end
      end
    end
  end

  -- Cattle skulls.
  local skulls = mm(cattle_skull(), M.vertex)
  local sn = 0
  for _ = 1, 400 do
    local x, z = r:float(-170, 170), r:float(-170, 170)
    local h = flat_spot(x, z, 5)
    if h and sn < 45 then sn = sn + 1; skulls:set_instance(sn, Vec3(x, h, z), Quat.euler(r:float(-0.2, 0.2), r:float(0, 6.28), r:float(-0.3, 0.3)), r:float(0.9, 1.2)) end
  end

  -- Barbed-wire ranch fence on both sides of Route 45, with gaps near places.
  local posts, wires = mm(fence_post(), M.vertex), mm(wire(), M.metal, false)
  local fp, fw = 0, 0
  for _, side in ipairs({ -12, 12 }) do
    local prev
    for z = -195, 195, 4 do
      local x = road_x(z) + side
      local h = height(x, z)
      local gap = near_zone(x, z, 6) or (z % 60 < 4)
      if not gap then
        fp = fp + 1
        local lean = Quat.euler(r:float(-0.08, 0.08), r:float(0, 6.28), r:float(-0.08, 0.08))
        posts:set_instance(fp, Vec3(x, h - 0.1, z), lean, Vec3(1, r:float(0.9, 1.1), 1))
        local here = Vec3(x, h, z)
        if prev then
          local d = here - prev
          for _, wy in ipairs({ 0.5, 0.85, 1.2 }) do
            fw = fw + 1
            local a, b = prev + Vec3(0, wy, 0), here + Vec3(0, wy - 0.04, 0)
            wires:set_instance(fw, (a + b) * 0.5 + Vec3(0, -0.04, 0), Quat.look_rotation(b - a), Vec3(1, 1, d:length()))
          end
        end
        prev = here
      else
        prev = nil
      end
    end
  end

  -- Road signs and mile markers, with Label3D text.
  local function sign(kind, z, side, text, sub, col)
    local x = road_x(z) + side
    local h = height(x, z)
    local face = Quat.from_y(side > 0 and math.pi * 0.5 or -math.pi * 0.5) * Quat.from_y(side > 0 and -0.5 or 0.5)
    local n = Node3D { position = Vec3(x, h, z), rotation = face }
    n:add_child(MeshInstance3D { mesh = sign_mesh(kind):upload(), material = M.vertex })
    n:add_child(StaticBody3D { position = Vec3(0, 1.1, 0), shape = Shape.cylinder(0.06, 2.2) })
    root:add_child(n)
    local tp = n:to_global(Vec3(kind == "green" and 0.7 or 0, kind == "green" and 2.3 or 2.05, -0.1))
    root:add_child(Label3D { text = text, position = tp, size = kind == "green" and 15 or 14, color = col or P.ink, outline = 0, max_distance = 35 })
    if sub then root:add_child(Label3D { text = sub, position = tp - Vec3(0, 0.3, 0), size = 11, color = col or P.ink, outline = 0, max_distance = 30 }) end
  end
  sign("speed", -60, 6.2, "SPEED", "LIMIT 45")
  sign("route", -20, -6.2, "45", nil, P.white)
  sign("green", 40, 6.2, "RHYOLITE SPRINGS", "EXIT 2 MI", P.white)
  sign("warn", 75, -6.2, "UFO", "XING")
  sign("green", 135, -6.2, "AREA 51", "DO NOT", P.white)
  sign("speed", 160, 6.2, "SPEED", "LIMIT ??")
  sign("warn", -120, 6.2, "COWS", "AIRBORNE")
  sign("route", 100, 6.2, "45", nil, P.white)
  local markers = mm(MeshData.box(0.18, 1.1, 0.04, C("#2e7d4f")):append(MeshData.box(0.2, 0.12, 0.05, P.white), Vec3(0, 0.4, 0)), M.vertex)
  local mk = 0
  for z = -180, 180, 30 do
    local x = road_x(z) + 6.8
    mk = mk + 1
    markers:set_instance(mk, Vec3(x, height(x, z) + 0.5, z), Quat.from_y(math.pi * 0.5))
  end

  -- Billboards facing the road.
  local function billboard(z, side, a, b, line1, line2, c1, c2)
    local x = road_x(z) + side
    local n = Node3D { position = Vec3(x, height(x, z) - 0.2, z), rotation = Quat.from_y(side > 0 and math.pi * 0.5 + 0.35 or -math.pi * 0.5 - 0.35) }
    n:add_child(MeshInstance3D { mesh = billboard_mesh(a, b):upload(), material = M.vertex })
    n:add_child(StaticBody3D { position = Vec3(0, 5.2, 0), shape = Shape.box(7.4, 3.4, 0.4) })
    for _, px in ipairs({ -2.8, 0, 2.8 }) do n:add_child(StaticBody3D { position = Vec3(px, 1.8, 0.3), shape = Shape.box(0.25, 3.6, 0.25) }) end
    root:add_child(n)
    root:add_child(Label3D { text = line1, position = n:to_global(Vec3(0, 5.8, -0.2)), size = 40, color = c1, outline = 4, outline_color = P.ink, max_distance = 120 })
    root:add_child(Label3D { text = line2, position = n:to_global(Vec3(0, 4.6, -0.2)), size = 22, color = c2, outline = 3, outline_color = P.ink, max_distance = 90 })
  end
  billboard(-90, 22, C("#d8433b"), C("#f5f3ec"), "PROP PILLS", "ask your doctor if you're real", C("#d8433b"), C("#1b1720"))
  billboard(60, -24, C("#3b4250"), C("#4ff0d8"), "MALL OF THE FUTURE", "exit now · the future is closed sundays", C("#f5f3ec"), C("#1b1720"))
  billboard(150, 24, C("#6e3a1e"), C("#e0782e"), "GARF'S DINER", "12 mi · try the 'meat'", C("#fff1d6"), C("#1b1720"))
  billboard(-150, -22, C("#151d38"), C("#2a3f7a"), "POSTAL SERVICE", "we deliver. eventually.", C("#f5f3ec"), C("#f5d33a"))

  -- Wrecked cars by the road and out in the scrub.
  for i, spot in ipairs({ { -70, 10, 0.9 }, { 20, -16, -0.4 }, { 120, 15, 2.2 }, { -140, -14, 1.3 } }) do
    local z = spot[1]
    local x = road_x(z) + spot[2]
    if not near_zone(x, z, 4) then
      local h = height(x, z)
      local n = Node3D { position = Vec3(x, h - 0.15, z), rotation = Quat.euler(0, spot[3], i % 2 == 0 and 0.08 or -0.05) }
      n:add_child(MeshInstance3D { mesh = wreck_car(i * 11):upload(), material = M.vertex })
      n:add_child(StaticBody3D { position = Vec3(0, 0.8, 0), shape = Shape.box(1.9, 1.4, 4.4) })
      root:add_child(n)
    end
  end

  -- Hoodoos and a rock arch.
  for i = 1, 14 do
    for _ = 1, 30 do
      local x, z = r:float(-165, 165), r:float(-165, 165)
      local h = flat_spot(x, z, 4)
      if h and clear(x, z, 6) then
        local mesh, top = hoodoo(i * 31)
        local s = r:float(1.2, 2.2)
        local n = Node3D { position = Vec3(x, h - 0.3, z), rotation = Quat.from_y(r:float(0, 6.28)), scale = Vec3(s) }
        n:add_child(MeshInstance3D { mesh = mesh:upload(), material = M.vertex })
        n:add_child(StaticBody3D { position = Vec3(0, top * 0.5, 0), shape = Shape.cylinder(0.8, top) })
        root:add_child(n)
        break
      end
    end
  end
  do
    local x, z = -40, 150
    local h = height(x, z)
    local n = Node3D { position = Vec3(x, h - 1.5, z), rotation = Quat.from_y(0.6) }
    n:add_child(MeshInstance3D { mesh = arch():upload(), material = M.vertex })
    for _, sx in ipairs({ -6, 6 }) do n:add_child(StaticBody3D { position = Vec3(sx, 2.5, 0), shape = Shape.box(3, 5, 3) }) end
    n:add_child(StaticBody3D { position = Vec3(0, 6.6, 0), shape = Shape.box(9, 2.4, 3) })
    root:add_child(n)
  end

  -- Far mountain ring beyond the playable basin.
  local fm = { mm(far_mountain(1), M.terrain, false), mm(far_mountain(2), M.terrain, false) }
  local fn = { 0, 0 }
  for i = 0, 59 do
    local a = i / 60 * math.tau + r:float(-0.03, 0.03)
    local d = r:float(260, 330)
    local k = r:int(1, 2)
    fn[k] = fn[k] + 1
    local hh = r:float(35, 80)
    fm[k]:set_instance(fn[k], Vec3(math.cos(a) * d, -2, math.sin(a) * d), Quat.from_y(r:float(0, 6.28)), Vec3(r:float(40, 70), hh, r:float(40, 70)))
  end

  -- Vultures circling over the desert (and over anything dead).
  local vm = vulture():upload()
  for i = 1, 6 do
    local c = Vec3(r:float(-120, 120), r:float(30, 48), r:float(-120, 120))
    local rad, spd, ph = r:float(10, 22), r:float(0.18, 0.3), r:float(0, 6.28)
    local v = MeshInstance3D { mesh = vm, material = M.vertex, cast_shadow = true }
    v._process = function(self, dt)
      ph = ph + dt * spd
      local p = c + Vec3(math.cos(ph) * rad, math.sin(ph * 0.7) * 2, math.sin(ph) * rad)
      local tangent = Vec3(-math.sin(ph), 0, math.cos(ph))
      self.position = p
      self.rotation = Quat.look_rotation(tangent) * Quat.euler(0, 0, -0.35)
    end
    root:add_child(v)
  end

  -- Dust devils wandering the flats.
  for i = 1, 4 do
    local pos = Vec3(r:float(-120, 120), 0, r:float(-120, 120))
    local dir = Vec3(r:float(-1, 1), 0, r:float(-1, 1)):normalized()
    local dd = Particles3D { rate = 55, lifetime = 2.6, speed = 4.5, spread = 12, size = 0.7, size_end = 2.4, amount = 160, turbulence = 3,
      emit_radius = 0.9, color = Color(0.86, 0.72, 0.52, 0.32), color_end = Color(0.86, 0.72, 0.52, 0), additive = false, gravity = Vec3(0, 0.5, 0) }
    local t = r:float(0, 10)
    dd._process = function(self, dt)
      t = t + dt
      pos = pos + (dir + Vec3(math.sin(t * 0.7), 0, math.cos(t * 0.5)) * 0.6) * dt * 2.5
      if math.abs(pos.x) > 150 or math.abs(pos.z) > 150 then dir = -dir end
      self.position = Vec3(pos.x, height(pos.x, pos.z) + 0.2, pos.z)
      self.direction = Vec3(math.sin(t * 9) * 0.25, 1, math.cos(t * 9) * 0.25)
    end
    root:add_child(dd)
  end

  -- Town clutter: windmill, crates, hitching rails, wagon wheels, lanterns.
  local tz = World.zones.town
  do
    local tower, fan = windmill_parts()
    local n = Node3D { position = Vec3(tz.x + 22, tz.h, tz.z + 18) }
    n:add_child(MeshInstance3D { mesh = tower:upload(), material = M.vertex })
    local hub = n:add_child(Node3D { position = Vec3(0, 9.2, -0.4) })
    hub:add_child(MeshInstance3D { mesh = fan:upload(), material = M.vertex })
    hub._process = function(self, dt) self.rotation = self.rotation * Quat.euler(0, 0, dt * 1.6) end
    for _, sx in ipairs({ -0.6, 0.6 }) do for _, sz in ipairs({ -0.6, 0.6 }) do n:add_child(StaticBody3D { position = Vec3(sx, 4.5, sz), shape = Shape.box(0.15, 9, 0.15) }) end end
    root:add_child(n)
    -- Water trough under it.
    n:add_child(MeshInstance3D { mesh = MeshData.box(2.4, 0.6, 0.8, P.wood_dark):append(MeshData.box(2.2, 0.05, 0.6, C("#4f8fa8")), Vec3(0, 0.26, 0)):flat():upload(), material = M.vertex, position = Vec3(1.8, 0.3, 0) })
  end
  local wheel = MeshData.torus(0.55, 0.05, 20, 5, P.wood_dark)
  for i = 0, 7 do wheel:append(MeshData.box(0.04, 1.05, 0.04, P.wood), Vec3(), Quat.euler(0, 0, i * math.pi / 8)) end
  wheel:append(MeshData.cylinder(0.1, 0.1, 0.15, 8, P.metal_dark), Vec3(), Quat.euler(math.pi / 2, 0, 0))
  local wheels = mm(wheel:flat(), M.vertex)
  local rails = mm(MeshData.box(2.4, 0.1, 0.1, P.wood):append(MeshData.box(0.12, 1.0, 0.12, P.wood_dark), Vec3(-1.1, -0.5, 0)):append(MeshData.box(0.12, 1.0, 0.12, P.wood_dark), Vec3(1.1, -0.5, 0)):flat(), M.vertex)
  local lantern = MeshData.box(0.18, 0.25, 0.18, P.metal_dark):append(MeshData.box(0.13, 0.18, 0.13, C("#ffd27a")), Vec3(0, 0, 0)):append(MeshData.cone(0.14, 0.1, 4, P.metal_dark), Vec3(0, 0.17, 0))
  local lanterns = mm(lantern:flat(), M.vertex, false)
  local wn, rn, ln = 0, 0, 0
  for i = 1, 10 do
    local a = i / 10 * math.tau + 0.3
    local d = r:float(10, 26)
    local x, z = tz.x + math.cos(a) * d, tz.z + math.sin(a) * d
    local h = height(x, z)
    if i % 3 == 0 then wn = wn + 1; wheels:set_instance(wn, Vec3(x, h + 0.5, z), Quat.from_y(a) * Quat.euler(0.25, 0, 0))
    elseif i % 3 == 1 then rn = rn + 1; rails:set_instance(rn, Vec3(x, h + 1.0, z), Quat.from_y(a + math.pi / 2))
    end
    ln = ln + 1
    lanterns:set_instance(ln, Vec3(x + 0.5, h + 2.3, z), Quat.from_y(a))
  end

  -- Crash site: scorched ground, hull shards and a smoking furrow.
  local cz = World.zones.crash
  local scorch = MeshData.cylinder(1, 1, 0.02, 40, C("#2a2224"))
  scorch:displace(function(x, y, z)
    local d = math.sqrt(x * x + z * z)
    if d < 0.99 then return 0, 0, 0 end
    local k = 0.75 + Noise.perlin2(math.atan2(x, z) * 2, 3) * 0.5
    return x * (k - 1), 0, z * (k - 1)
  end)
  scorch:paint_fn(function(x, y, z, rr, gg, bb)
    local d = math.sqrt(x * x + z * z)
    local c = C("#2b2224"):lerp(C("#8a6448"), sm(0.25, 0.8, d)):lerp(C("#d9b98c"), sm(0.7, 1.0, d))
    return c.r, c.g, c.b
  end)
  root:add_child(MeshInstance3D { mesh = scorch:upload(), material = M.vertex, cast_shadow = false, position = Vec3(cz.x, cz.h + 0.03, cz.z), scale = Vec3(9, 1, 7) })
  local shard = MeshData.box(1, 0.08, 0.6, P.chrome):append(MeshData.box(0.5, 0.1, 0.3, C("#4ff0d8")), Vec3(0.2, 0.02, 0))
  local shards = mm(shard:flat(), M.metal)
  for i = 1, 22 do
    local a, d = r:float(0, 6.28), r:float(9, 24)
    local x, z = cz.x + math.cos(a) * d, cz.z + math.sin(a) * d
    shards:set_instance(i, Vec3(x, height(x, z) + 0.05, z), Quat.euler(r:float(-0.5, 0.5), r:float(0, 6.28), r:float(-0.6, 0.6)), r:float(0.4, 1.3))
  end
  for i = 1, 3 do
    local a = i * 2.1
    root:add_child(Particles3D { position = Vec3(cz.x + math.cos(a) * 6, cz.h + 0.3, cz.z + math.sin(a) * 6), rate = 6, lifetime = 5, speed = 1.4, spread = 15,
      size = 0.8, size_end = 3.2, amount = 40, color = Color(0.25, 0.22, 0.22, 0.4), color_end = Color(0.4, 0.38, 0.36, 0), additive = false, gravity = Vec3(0.3, 0.2, 0) })
  end
end

return Detail
