-- Nevada: desert basin ringed by mountains, mesas, Route 45, and the places the story visits.
local Art = require("art")
local P = Art.pal
local World = {}

local SIZE, RES = 440, 176

-- Route 45 wanders north-south through the basin.
local function road_x(z) return -35 + math.sin(z * 0.012) * 15 end
World.road_x = road_x

-- Named places. h = ground level the terrain is flattened to.
local zones = {
  crash = { x = 30, z = 105, r = 26, h = 0.4 },
  weigh = { x = road_x(15) + 20, z = 15, r = 18, h = 0.3 },
  town = { x = 95, z = -20, r = 34, h = 0.5 },
  lift = { x = -84, z = -72, r = 7, h = 0.4, blend = 4 },
}
World.zones = zones

local mesas = {
  { x = -90, z = -100, r = 17, h = 24, noise = 0.6, puzzle = true },
  { x = 55, z = -130, r = 26, h = 18, noise = 3 },
  { x = 150, z = 70, r = 20, h = 14, noise = 3 },
  { x = -140, z = 55, r = 24, h = 20, noise = 3 },
  { x = -20, z = -175, r = 32, h = 26, noise = 4 },
  { x = 150, z = -110, r = 12, h = 32, noise = 2 },
  { x = -150, z = -40, r = 14, h = 12, noise = 2 },
  { x = 110, z = 150, r = 18, h = 16, noise = 3 },
}
World.mesas = mesas
World.lift_mesa = mesas[1]

local function smooth(a, b, x) return math.smoothstep(a, b, x) end

local function raw_height(x, z)
  local h = Noise.fbm2(x * 0.011 + 3, z * 0.011 - 7, 4) * 5 + Noise.perlin2(x * 0.045, z * 0.045) * 0.7
  for _, m in ipairs(mesas) do
    local d = math.sqrt((x - m.x) ^ 2 + (z - m.z) ^ 2) + Noise.perlin2(x * 0.06 + m.x, z * 0.06) * m.noise
    if d < m.r + 8 then
      local t = smooth(m.r + 4, m.r, d)
      -- A ledge halfway down gives the cliffs layered strata.
      local hm = m.h * (t > 0.5 and (0.55 + 0.45 * smooth(0.65, 0.9, t)) or 0.55 * smooth(0, 0.35, t))
      h = math.max(h, hm + Noise.perlin2(x * 0.2, z * 0.2) * 0.3)
    end
  end
  local e = math.max(math.abs(x), math.abs(z))
  if e > 165 then
    local k = (e - 165) / 45
    h = h + k ^ 1.5 * 48 * (0.75 + 0.35 * Noise.perlin2(x * 0.02, z * 0.02))
  end
  return h
end

local function height(x, z)
  local h = raw_height(x, z)
  for _, zn in pairs(zones) do
    local d = math.sqrt((x - zn.x) ^ 2 + (z - zn.z) ^ 2)
    local b = zn.blend or 14
    if d < zn.r + b then h = math.lerp(h, zn.h, smooth(zn.r + b, zn.r, d)) end
  end
  local dx = math.abs(x - road_x(z))
  if dx < 12 and math.max(math.abs(x), math.abs(z)) < 200 then h = math.lerp(h, 0.25, smooth(12, 6, dx)) end
  return h
end
World.height = height

local strata = { P.rock, P.rock_light, P.strata, P.rock, P.rock_dark, P.rock_light }
local function terrain_color(x, y, z)
  local e = 1.2
  local nx = height(x + e, z) - height(x - e, z)
  local nz = height(x, z + e) - height(x, z - e)
  local steep = math.sqrt(nx * nx + nz * nz) / (2 * e)
  local n = Noise.perlin2(x * 0.08, z * 0.08)
  if steep > 0.55 or y > 9 then
    local band = strata[math.floor((y + n * 0.6) / 2.4) % #strata + 1]
    return band
  end
  if y > 4 and steep > 0.3 then return P.rock_light:lerp(P.sand_dark, 0.4) end
  if n > 0.25 then return P.sand_dark end
  if n < -0.3 then return P.sand_light end
  return P.sand
end

-- Strip mesh that follows the road at ground height.
local function road_strip(x_off, width, col, dash)
  local m = MeshData()
  m:color(col)
  local step = 2
  local prev
  for z = -200, 200, step do
    local on = not dash or (math.floor(z / 4) % 2 == 0)
    local cx = road_x(z) + x_off
    local a = m:vertex(cx - width / 2, height(cx - width / 2, z) + 0.06, z, 0, 1, 0)
    local b = m:vertex(cx + width / 2, height(cx + width / 2, z) + 0.06, z, 0, 1, 0)
    if prev and on then m:quad(prev[1], a, b, prev[2]) end
    prev = { a, b }
  end
  return m
end

function World.build(M)
  local root = Node3D { name = "Nevada" }
  local r = Random(45)

  local grid = MeshData.grid(SIZE, SIZE, RES, RES, height, terrain_color)
  root:add_child(StaticBody3D { name = "Terrain", shape = Shape.mesh(grid), friction = 0.9, groups = { "ground" } })
  root:add_child(MeshInstance3D { name = "TerrainMesh", mesh = grid:copy():flat():upload(), material = M.terrain })

  -- Route 45.
  root:add_child(MeshInstance3D { mesh = road_strip(0, 9, P.asphalt):upload(), material = M.vertex, cast_shadow = false })
  local lines = road_strip(0, 0.25, P.line_yellow, true)
  lines:append(road_strip(-4, 0.2, P.line_white))
  lines:append(road_strip(4, 0.2, P.line_white))
  lines:transform(Vec3(0, 0.02, 0))
  root:add_child(MeshInstance3D { mesh = lines:upload(), material = M.vertex, cast_shadow = false })

  local function clear_of_zones(x, z, pad)
    for _, zn in pairs(zones) do
      if (x - zn.x) ^ 2 + (z - zn.z) ^ 2 < (math.max(zn.r, 16) + pad) ^ 2 then return false end
    end
    if math.abs(x - road_x(z)) < 9 then return false end
    return true
  end
  local function flat_spot(x, z, max_h)
    local h = height(x, z)
    if h > (max_h or 6) then return nil end
    if math.abs(height(x + 1.5, z) - height(x - 1.5, z)) > 1 or math.abs(height(x, z + 1.5) - height(x, z - 1.5)) > 1 then return nil end
    return h
  end

  -- Saguaros, with trunk colliders.
  local sag_kinds = {}
  for i = 1, 4 do sag_kinds[i] = { mesh = Art.saguaro(i * 13):upload(), list = {} } end
  for _ = 1, 3000 do
    local x, z = r:float(-170, 170), r:float(-170, 170)
    local h = flat_spot(x, z)
    if h and clear_of_zones(x, z, 3) and Noise.perlin2(x * 0.03 + 9, z * 0.03) > -0.1 then
      local k = sag_kinds[r:int(1, 4)]
      if #k.list < 45 then
        local s = r:float(0.8, 1.2)
        k.list[#k.list + 1] = { Vec3(x, h - 0.1, z), Quat.from_y(r:float(0, 6.28)), s }
        root:add_child(StaticBody3D { position = Vec3(x, h + 2 * s, z), shape = Shape.cylinder(0.35 * s, 4 * s) })
      end
    end
  end
  -- Joshua trees.
  local josh_kinds = {}
  for i = 1, 3 do josh_kinds[i] = { mesh = Art.joshua_tree(i * 7):upload(), list = {} } end
  for _ = 1, 2000 do
    local x, z = r:float(-170, 170), r:float(-170, 170)
    local h = flat_spot(x, z)
    if h and clear_of_zones(x, z, 4) and Noise.perlin2(x * 0.025 - 5, z * 0.025 + 2) > 0.1 then
      local k = josh_kinds[r:int(1, 3)]
      if #k.list < 30 then
        local s = r:float(0.9, 1.5)
        k.list[#k.list + 1] = { Vec3(x, h - 0.1, z), Quat.from_y(r:float(0, 6.28)), s }
        root:add_child(StaticBody3D { position = Vec3(x, h + 1.2 * s, z), shape = Shape.cylinder(0.2 * s, 2.4 * s) })
      end
    end
  end
  for _, group in ipairs({ sag_kinds, josh_kinds }) do
    for _, k in ipairs(group) do
      local mm = MultiMeshInstance3D { mesh = k.mesh, material = M.foliage }
      for i, t in ipairs(k.list) do
        local tint = r:float(0.9, 1.08)
        mm:set_instance(i, t[1], t[2], t[3], Color(tint, tint, tint))
      end
      root:add_child(mm)
    end
  end
  -- Sagebrush everywhere (no collision, no shadows).
  local sage = MultiMeshInstance3D { mesh = Art.sagebrush():upload(), material = M.foliage, cast_shadow = false }
  local n = 0
  for _ = 1, 12000 do
    if n >= 1600 then break end
    local x, z = r:float(-175, 175), r:float(-175, 175)
    local h = flat_spot(x, z, 4)
    if h and math.abs(x - road_x(z)) > 6 then
      n = n + 1
      local t = r:float(0.85, 1.1)
      sage:set_instance(n, Vec3(x, h, z), Quat.from_y(r:float(0, 6.28)), r:float(0.6, 1.5), Color(t, t, t * 0.95))
    end
  end
  root:add_child(sage)
  -- Rocks.
  local rock_mm = {}
  for i = 1, 3 do rock_mm[i] = { mm = MultiMeshInstance3D { mesh = Art.rock(i, 1):upload(), material = M.vertex }, n = 0 } end
  for _ = 1, 900 do
    local x, z = r:float(-180, 180), r:float(-180, 180)
    local h = height(x, z)
    if clear_of_zones(x, z, 2) then
      local k = rock_mm[r:int(1, 3)]
      if k.n < 60 then
        k.n = k.n + 1
        local s = r:float(0.4, 2.6)
        k.mm:set_instance(k.n, Vec3(x, h - 0.25 * s, z), Quat.euler(r:float(-0.2, 0.2), r:float(0, 6.28), 0), s)
        if s > 1.1 then root:add_child(StaticBody3D { position = Vec3(x, h, z), shape = Shape.sphere(0.7 * s) }) end
      end
    end
  end
  for _, k in ipairs(rock_mm) do root:add_child(k.mm) end

  -- Power poles along the road.
  local poles = MultiMeshInstance3D { mesh = Art.power_pole():upload(), material = M.vertex }
  local pn = 0
  for z = -190, 190, 28 do
    local x = road_x(z) + 8
    pn = pn + 1
    poles:set_instance(pn, Vec3(x, height(x, z) - 0.2, z), Quat.from_y(math.atan2(road_x(z + 1) - road_x(z), 1)), 1)
    root:add_child(StaticBody3D { position = Vec3(x, height(x, z) + 4, z), shape = Shape.cylinder(0.16, 8) })
  end
  root:add_child(poles)

  World.build_town(root, M, r)
  require("world_detail").build(root, M, { height = height, road_x = road_x, clear = clear_of_zones, flat_spot = flat_spot })
  return root
end

------------------------------------------------------------------ Rhyolite Springs (ghost town)
function World.build_town(root, M, r)
  local zt = zones.town
  local function building(x, z, w, d, h, yaw, col, label)
    local gy = zt.h
    local b = StaticBody3D { position = Vec3(x, gy, z), rotation = Quat.from_y(yaw), shape = Shape.offset(Shape.box(w, h, d), Vec3(0, h / 2, 0)),
      MeshInstance3D { mesh = Art.western_building(w, d, h, col):upload(), material = M.vertex },
    }
    -- False front collider.
    b:add_child(StaticBody3D { position = Vec3(0, h + 0.7, -d / 2 + 0.05), shape = Shape.box(w + 0.4, 1.6, 0.2) })
    root:add_child(b)
    if label then
      root:add_child(Label3D { text = label, position = b:to_global(Vec3(0, h + 0.65, -d / 2 - 0.3)), size = 22, color = Color.hex("#fff1d6"), max_distance = 45 })
    end
    return b
  end
  -- Main street runs north-south through the town centre; buildings face the street.
  local x0, z0 = zt.x, zt.z
  building(x0 - 12, z0 - 16, 8, 9, 5, -math.pi / 2, P.wood, "SALOON")
  building(x0 - 12, z0 - 4, 7, 8, 4.5, -math.pi / 2, P.wood_grey, "GENERAL STORE")
  building(x0 - 12, z0 + 8, 7, 8, 4, -math.pi / 2, P.wood_dark:lighten(0.15), "ASSAY OFFICE")
  building(x0 + 12, z0 - 14, 7, 8, 4.5, math.pi / 2, P.wood_grey:lighten(0.1), "GARF'S DINER")
  building(x0 + 12, z0 + 12, 6, 7, 4, math.pi / 2, P.wood, "LITTLE GREEN INN")
  -- Water tower.
  local wt = Node3D { position = Vec3(x0 + 20, zt.h, z0 + 22) }
  local tower = MeshData()
  for _, sx in ipairs({ -1.5, 1.5 }) do for _, sz in ipairs({ -1.5, 1.5 }) do tower:append(MeshData.box(0.25, 7, 0.25, P.wood_dark), Vec3(sx, 3.5, sz)) end end
  tower:append(MeshData.cylinder(2.3, 2.3, 3, 16, P.wood), Vec3(0, 8.5, 0))
  tower:append(MeshData.cone(2.6, 1.4, 16, P.wood_dark), Vec3(0, 10.7, 0))
  wt:add_child(MeshInstance3D { mesh = tower:flat():upload(), material = M.vertex })
  wt:add_child(StaticBody3D { position = Vec3(0, 8.5, 0), shape = Shape.cylinder(2.3, 3) })
  for _, sx in ipairs({ -1.5, 1.5 }) do for _, sz in ipairs({ -1.5, 1.5 }) do wt:add_child(StaticBody3D { position = Vec3(sx, 3.5, sz), shape = Shape.box(0.25, 7, 0.25) }) end end
  root:add_child(wt)
  -- Hitching rails and a broken wagon for cover.
  for i = -1, 1 do
    root:add_child(StaticBody3D { position = Vec3(x0 - 6, zt.h + 0.5, z0 + i * 10), shape = Shape.box(0.2, 1, 3),
      MeshInstance3D { mesh = MeshData.box(0.2, 1, 3, P.wood_dark):flat():upload(), material = M.vertex } })
  end
end

------------------------------------------------------------------ sky + light
function World.environment()
  Environment:set {
    sky_top = Color.hex("#2f6cc9"), sky_horizon = Color.hex("#f7d7a6"), ground = Color.hex("#c98d5a"),
    fog_color = Color.hex("#f0c896"), fog_density = 0.0042, fog_height = 0, fog_height_density = 0.004, fog_sun_scatter = 0.5,
    ambient_energy = 0.9, reflection_energy = 0.3, clouds = 0.25, cloud_speed = 0.6, stars = 0,
    exposure = 1.08, bloom_strength = 0.06, bloom_threshold = 1.2, saturation = 1.18, contrast = 1.06, vignette = 0.28,
    sun_shadows = true, shadow_distance = 110,
    toon = 3, outline = 2.0, outline_color = Color.hex("#1a1020"), outline_fade = 160,
  }
end

return World
