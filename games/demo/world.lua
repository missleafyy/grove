-- Builds Skylight Isle: terrain, sea, vegetation, landmarks, physics playground and collectibles.
local Art = require("art")
local Props = require("props")
local P = Art.pal
local World = {}

------------------------------------------------------------------ terrain shape
local zones = {
  plaza = { x = 44, z = 4, r = 15 },
  spawn = { x = 0, z = 30, r = 12 },
  ruins = { x = -34, z = -26, r = 12 },
  windmill = { x = -56, z = 22, r = 8 },
  camp = { x = 12, z = 74, r = 7 },
}

local function raw_height(x, z)
  local d = math.sqrt(x * x + z * z) / 100
  d = d + Noise.fbm2(x * 0.012 + 3.7, z * 0.012 - 1.3, 3) * 0.22
  local mask = math.smoothstep(1.0, 0.6, d)
  local hills = (Noise.fbm2(x * 0.021, z * 0.021, 4) * 0.5 + 0.5) * 9
  local mountain = math.exp(-((x + 6) ^ 2 + (z + 60) ^ 2) / (2 * 19 ^ 2)) * 26
  return mask * (3 + hills + mountain) - (1 - mask) * 9
end

for _, zn in pairs(zones) do zn.h = raw_height(zn.x, zn.z) end
zones.plaza.h = math.max(zones.plaza.h, 4)
zones.camp.h = 1.6

local function height(x, z)
  local h = raw_height(x, z)
  for _, zn in pairs(zones) do
    local d = math.sqrt((x - zn.x) ^ 2 + (z - zn.z) ^ 2)
    if d < zn.r then h = math.lerp(h, zn.h, math.smoothstep(zn.r, zn.r * 0.55, d)) end
  end
  return h
end
World.height = height
World.zones = zones

local paths = {
  { zones.spawn, zones.plaza }, { zones.spawn, zones.ruins }, { zones.spawn, zones.windmill }, { zones.spawn, zones.camp },
}
local function path_distance(x, z)
  local best = 1e9
  for _, p in ipairs(paths) do
    local ax, az, bx, bz = p[1].x, p[1].z, p[2].x, p[2].z
    local dx, dz = bx - ax, bz - az
    local t = math.clamp(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1)
    -- Gentle wiggle so paths don't look ruler-straight.
    local wx = ax + dx * t + math.sin(t * 9 + ax) * 2.5 * math.sin(t * math.pi)
    local wz = az + dz * t
    best = math.min(best, math.sqrt((x - wx) ^ 2 + (z - wz) ^ 2))
  end
  return best
end
World.path_distance = path_distance

local function slope(x, z)
  local e = 1
  local hx = height(x + e, z) - height(x - e, z)
  local hz = height(x, z + e) - height(x, z - e)
  return Vec3(-hx, 2 * e, -hz):normalized().y
end

local function terrain_color(x, y, z)
  local n = Noise.fbm2(x * 0.05, z * 0.05, 3)
  local s = slope(x, z)
  local c
  if y < 0.6 then c = P.sand_wet:lerp(P.sand, math.clamp((y + 3) / 3.6, 0, 1))
  elseif y < 1.9 then c = P.sand:lerp(P.grass_light, math.smoothstep(1.2, 1.9, y))
  else
    c = n > 0.08 and P.grass:lerp(P.grass_light, math.clamp(n * 3, 0, 1)) or P.grass:lerp(P.grass_dark, math.clamp(-n * 3, 0, 1))
  end
  if s < 0.78 and y > 1 then c = c:lerp(P.rock:lerp(P.rock_dark, math.clamp(n + 0.5, 0, 1)), math.smoothstep(0.78, 0.68, s)) end
  if y > 1.5 then
    local pd = path_distance(x, z)
    if pd < 2.2 then c = c:lerp(P.dirt, math.smoothstep(2.2, 1.2, pd) * 0.9) end
    local zd = math.sqrt((x - zones.ruins.x) ^ 2 + (z - zones.ruins.z) ^ 2)
    if zd < 10 then c = c:lerp(P.stone_dark, math.smoothstep(10, 8, zd) * 0.6) end
  end
  return c
end

------------------------------------------------------------------ build
function World.build(M)
  local root = Node3D { name = "Island" }
  local r = Random(2024)

  -- Terrain: visual mesh is faceted, collision uses the smooth grid.
  local size, res = 300, 150
  local grid = MeshData.grid(size, size, res, res, height, terrain_color)
  root:add_child(StaticBody3D { name = "Terrain", shape = Shape.mesh(grid), friction = 0.9 })
  local vis = grid:copy():flat()
  root:add_child(MeshInstance3D { name = "TerrainMesh", mesh = vis:upload(), material = M.terrain })

  -- Sea: subdivided so the vertex waves have something to move.
  local sea = MeshData.grid(2600, 2600, 260, 260)
  root:add_child(MeshInstance3D { name = "Sea", mesh = sea:upload(), material = M.water, cast_shadow = false })

  -- Vegetation as instanced meshes.
  local function ok_spot(x, z, min_h, max_h, max_slope_y)
    local h = height(x, z)
    if h < (min_h or 2.2) or h > (max_h or 40) then return nil end
    if slope(x, z) < (max_slope_y or 0.82) then return nil end
    if path_distance(x, z) < 3 then return nil end
    for _, zn in pairs(zones) do
      if (x - zn.x) ^ 2 + (z - zn.z) ^ 2 < (zn.r + 2) ^ 2 then return nil end
    end
    return h
  end

  local tree_kinds = {
    { mesh = Art.tree_round(1, P.leaf, P.leaf_light):upload(), list = {} },
    { mesh = Art.tree_round(2, P.leaf_light, P.grass_light):upload(), list = {} },
    { mesh = Art.tree_round(3, P.blossom, P.blossom_light):upload(), list = {} },
    { mesh = Art.tree_round(4, P.autumn, Color.hex("#f2c14e")):upload(), list = {} },
    { mesh = Art.tree_pine(5):upload(), list = {} },
  }
  local trees = 0
  for _ = 1, 4000 do
    if trees >= 230 then break end
    local x, z = r:float(-110, 110), r:float(-110, 110)
    local forest = Noise.fbm2(x * 0.03 + 11, z * 0.03 - 4, 3)
    local h = ok_spot(x, z)
    if h and forest > -0.02 then
      local kind
      if h > 14 then kind = 5
      elseif forest > 0.25 then kind = r:chance(0.5) and 5 or 1
      else kind = r:pick({ 1, 1, 2, 2, 3, 4 }) end
      local k = tree_kinds[kind]
      local s = r:float(0.8, 1.35)
      k.list[#k.list + 1] = { Vec3(x, h - 0.15, z), Quat.from_y(r:float(0, 6.28)), s }
      root:add_child(StaticBody3D { position = Vec3(x, h + 1.5 * s, z), shape = Shape.cylinder(0.3 * s, 3 * s) })
      trees = trees + 1
    end
  end
  for _, k in ipairs(tree_kinds) do
    local mm = MultiMeshInstance3D { mesh = k.mesh, material = M.foliage }
    for i, t in ipairs(k.list) do
      local tint = r:float(0.88, 1.08)
      mm:set_instance(i, t[1], t[2], t[3], Color(tint, tint, tint))
    end
    root:add_child(mm)
  end

  -- Grass tufts (thousands, one draw call, no shadows).
  local grass = MultiMeshInstance3D { mesh = Art.grass_tuft():upload(), material = M.grass, cast_shadow = false }
  local n = 0
  for _ = 1, 30000 do
    if n >= 9000 then break end
    local x, z = r:float(-105, 105), r:float(-105, 105)
    local h = height(x, z)
    if h > 2.0 and h < 22 and slope(x, z) > 0.85 and path_distance(x, z) > 1.8 then
      local zp = zones.plaza
      if (x - zp.x) ^ 2 + (z - zp.z) ^ 2 > 15 ^ 2 then
        n = n + 1
        local c = terrain_color(x, h, z)
        grass:set_instance(n, Vec3(x, h - 0.05, z), Quat.from_y(r:float(0, 6.28)), r:float(0.7, 1.4), c:lighten(0.1))
      end
    end
  end
  root:add_child(grass)

  local flower_cols = { Color.hex("#ff8fb1"), Color.hex("#fff1a8"), Color.hex("#b9a6ff"), Color.WHITE }
  for _, col in ipairs(flower_cols) do
    local fm = MultiMeshInstance3D { mesh = Art.flower(col):upload(), material = M.vertex, cast_shadow = false }
    local cnt = 0
    for _ = 1, 3000 do
      if cnt >= 220 then break end
      local x, z = r:float(-90, 90), r:float(-90, 90)
      local h = ok_spot(x, z, 2.2, 16, 0.88)
      if h and Noise.perlin2(x * 0.05 + col.r * 10, z * 0.05) > 0.15 then
        cnt = cnt + 1
        fm:set_instance(cnt, Vec3(x, h - 0.02, z), Quat.from_y(r:float(0, 6.28)), r:float(0.8, 1.3))
      end
    end
    root:add_child(fm)
  end

  -- Rocks, with simple sphere colliders for the big ones.
  local rock_meshes = { Art.rock(1, 1):upload(), Art.rock(2, 1):upload(), Art.rock(3, 1):upload() }
  local rock_mm = {}
  for i, m in ipairs(rock_meshes) do rock_mm[i] = MultiMeshInstance3D { mesh = m, material = M.vertex } end
  local rc = { 0, 0, 0 }
  for _ = 1, 600 do
    local x, z = r:float(-115, 115), r:float(-115, 115)
    local h = height(x, z)
    if h > -1 and h < 30 and path_distance(x, z) > 3 and ok_spot(x, z, -1, 30, 0.6) then
      local kind = r:int(1, 3)
      if rc[kind] < 28 then
        rc[kind] = rc[kind] + 1
        local s = r:float(0.4, 2.2)
        rock_mm[kind]:set_instance(rc[kind], Vec3(x, h - 0.2 * s, z), Quat.euler(r:float(-0.2, 0.2), r:float(0, 6.28), r:float(-0.2, 0.2)), s)
        if s > 0.9 then root:add_child(StaticBody3D { position = Vec3(x, h, z), shape = Shape.sphere(0.75 * s) }) end
      end
    end
  end
  for _, mm in ipairs(rock_mm) do root:add_child(mm) end

  World.build_landmarks(root, M, r)
  return root
end

------------------------------------------------------------------ landmarks
function World.build_landmarks(root, M, r)
  local zp = zones.plaza
  local ph = zp.h

  -- Physics playground: tiled plaza, crate wall, barrels, dominoes.
  root:add_child(StaticBody3D { name = "Plaza", position = Vec3(zp.x, ph - 0.5, zp.z), shape = Shape.box(26, 1.2, 26),
    MeshInstance3D { mesh = MeshData.box(26, 1.2, 26):upload(), material = M.tiles } })
  local top = ph + 0.1
  for row = 0, 4 do
    for col = 0, 4 - row do
      local x = zp.x + 6 + (col - (4 - row) / 2) * 1.02
      root:add_child(Props.crate(Vec3(x, top + 0.5 + row * 1.0, zp.z - 6)))
    end
  end
  for i = 0, 5 do
    local a = i / 6 * math.tau
    root:add_child(Props.barrel(Vec3(zp.x - 7 + math.cos(a) * 1.0, top + 0.55, zp.z - 5 + math.sin(a) * 1.0)))
  end
  root:add_child(Props.barrel(Vec3(zp.x - 7, top + 1.65, zp.z - 5)))
  -- Domino spiral.
  local dom_mesh = MeshData.box(0.25, 1.6, 0.8):upload()
  local dom_mat = Material { albedo = Color.hex("#f2efe6"), roughness = 0.4 }
  local dom_mat2 = Material { albedo = Color.hex("#4fbf8a"), roughness = 0.4 }
  for i = 0, 26 do
    local t = i / 26
    local a = t * math.pi * 1.4
    local rad = 4.8 - t * 1.6
    local x, z = zp.x - 2 + math.cos(a) * rad, zp.z + 4 + math.sin(a) * rad
    local d = RigidBody3D { name = "Domino", position = Vec3(x, top + 0.8, z), rotation = Quat.from_y(-a), shape = Shape.box(0.25, 1.6, 0.8), mass = 3, friction = 0.4,
      MeshInstance3D { mesh = dom_mesh, material = (i % 3 == 0) and dom_mat2 or dom_mat } }
    root:add_child(d)
  end
  -- Big ball to roll around.
  local ball_mesh = MeshData.sphere(1, 32, 24):upload()
  root:add_child(RigidBody3D { name = "BigBall", position = Vec3(zp.x + 4, top + 1.2, zp.z + 6), shape = Shape.sphere(1.2), mass = 30, bounce = 0.3, friction = 0.8,
    MeshInstance3D { mesh = ball_mesh, material = Material { albedo = Color.hex("#ff8fb1"), roughness = 0.35 }, scale = Vec3(1.2) } })

  root:add_child(Props.sign(Vec3(zp.x - 14, height(zp.x - 14, zp.z + 1), zp.z + 1), math.pi / 2, "Physics Playground"))
  root:add_child(Props.jump_pad(Vec3(zp.x + 8, top, zp.z + 8), 26))

  -- Sky islands above the playground, linked by moving platforms.
  local base = Vec3(zp.x + 8, top, zp.z + 8)
  local i1 = base + Vec3(-2, 12.5, -12)
  local i2 = base + Vec3(-22, 15, -26)
  local i3 = base + Vec3(-30, 24, -46)
  local islands = { { i1, 5, 11 }, { i2, 4.5, 12 }, { i3, 6, 13 } }
  for _, is in ipairs(islands) do
    local md = Art.sky_island(is[3], is[2])
    root:add_child(StaticBody3D { name = "SkyIsland", position = is[1], shape = Shape.convex(md),
      MeshInstance3D { mesh = md:upload(), material = M.vertex } })
  end
  root:add_child(Props.moving_platform(i1 + Vec3(-5, 0, -4), i2 + Vec3(5, -1, 5), 7, 0))
  root:add_child(Props.moving_platform(i2 + Vec3(-2, 0, -6), i3 + Vec3(3, -1.5, 7), 8, 0.25))
  root:add_child(Props.crystal(i1 + Vec3(1, 1.2, 1)))
  root:add_child(Props.crystal(i2 + Vec3(0, 1.2, 0)))
  root:add_child(Props.crystal(i3 + Vec3(0, 1.8, 0), true))
  local pine = Art.tree_pine(77):upload()
  root:add_child(MeshInstance3D { mesh = pine, material = M.foliage, position = i3 + Vec3(-2.5, -0.2, -2), scale = Vec3(1.1) })
  root:add_child(MeshInstance3D { mesh = Art.tree_round(78, P.blossom, P.blossom_light):upload(), material = M.foliage, position = i2 + Vec3(1.8, -0.1, -1.5), scale = Vec3(0.8) })

  -- Ancient ruins: a ring of pillars around an altar.
  local zr = zones.ruins
  for i = 0, 9 do
    local a = i / 10 * math.tau
    local x, z = zr.x + math.cos(a) * 8, zr.z + math.sin(a) * 8
    local broken = i == 3 or i == 7
    if i ~= 5 then
      root:add_child(Props.pillar(Vec3(x, height(x, z) - 0.2, z), broken and r:float(1.2, 2.2) or 4.4, broken))
    end
  end
  -- One pillar has fallen over and can be pushed.
  root:add_child(RigidBody3D { name = "FallenPillar", position = Vec3(zr.x + 3, zr.h + 0.65, zr.z + 9), rotation = Quat.euler(0, 0.4, math.pi / 2),
    shape = Shape.cylinder(0.6, 3.2), mass = 80,
    MeshInstance3D { mesh = Props.meshes.pillar, material = M.vertex, scale = Vec3(1, 3.2, 1) } })
  root:add_child(StaticBody3D { name = "Altar", position = Vec3(zr.x, zr.h + 0.4, zr.z), shape = Shape.box(3, 1, 3),
    MeshInstance3D { mesh = MeshData.box(3, 1, 3, P.stone_dark):flat():upload(), material = M.vertex } })
  root:add_child(Props.crystal(Vec3(zr.x, zr.h + 1.6, zr.z)))
  root:add_child(Props.sign(Vec3(zr.x + 9, height(zr.x + 9, zr.z + 9), zr.z + 9), -0.6, "Ancient Ruins"))

  -- Windmill on the west hill.
  local zw = zones.windmill
  local wm = Node3D { name = "Windmill", position = Vec3(zw.x, zw.h - 0.2, zw.z) }
  wm:add_child(StaticBody3D { shape = Shape.offset(Shape.cylinder(2.0, 9), Vec3(0, 4.5, 0)),
    MeshInstance3D { mesh = MeshData.cylinder(1.4, 2.3, 9, 12, P.white):flat():upload(), material = M.vertex, position = Vec3(0, 4.5, 0) },
    MeshInstance3D { mesh = MeshData.cone(2.0, 3, 12, P.roof):flat():upload(), material = M.vertex, position = Vec3(0, 10.5, 0) },
    MeshInstance3D { mesh = MeshData.box(1.0, 1.8, 0.2, P.wood_dark):upload(), material = M.vertex, position = Vec3(0, 0.9, -2.25) } })
  local blades_md = MeshData()
  for i = 0, 3 do
    local q = Quat.euler(0, 0, i * math.pi / 2)
    blades_md:append(MeshData.box(0.35, 6, 0.08, P.wood), q * Vec3(0, 3.2, 0), q)
    blades_md:append(MeshData.box(1.3, 4.8, 0.04, P.white), q * Vec3(0.75, 3.6, 0.02), q)
  end
  blades_md:append(MeshData.cylinder(0.35, 0.35, 0.6, 10, P.wood_dark), nil, Quat.euler(math.pi / 2, 0, 0))
  local blades = MeshInstance3D { name = "Blades", mesh = blades_md:flat():upload(), material = M.vertex, position = Vec3(0, 8.4, -2.0) }
  blades._process = function(self, dt) self:rotate_local(Vec3(0, 0, 1), dt * 0.8) end
  wm:add_child(blades)
  wm:add_child(Props.crystal(Vec3(0, 12.6, 0)))
  root:add_child(wm)
  root:add_child(Props.sign(Vec3(zw.x + 6, height(zw.x + 6, zw.z + 6), zw.z + 6), 0.8, "Windmill Hill"))
  -- Steps up to the windmill crystal: a spiral of floating stones.
  for i = 0, 8 do
    local a = i / 9 * math.tau * 1.1 + 0.6
    local p = Vec3(zw.x + math.cos(a) * 3.6, zw.h + 1.0 + i * 1.25, zw.z + math.sin(a) * 3.6)
    root:add_child(StaticBody3D { position = p, shape = Shape.box(1.6, 0.4, 1.6),
      MeshInstance3D { mesh = MeshData.box(1.6, 0.4, 1.6, P.stone):flat():upload(), material = M.vertex } })
  end

  -- Beach campfire.
  local zc = zones.camp
  root:add_child(Props.campfire(Vec3(zc.x, zc.h, zc.z)))
  for i = 0, 2 do
    local a = i / 3 * math.tau + 0.4
    root:add_child(StaticBody3D { position = Vec3(zc.x + math.cos(a) * 2.6, zc.h + 0.25, zc.z + math.sin(a) * 2.6), rotation = Quat.from_y(-a + math.pi / 2),
      shape = Shape.box(1.8, 0.5, 0.5), MeshInstance3D { mesh = MeshData.box(1.8, 0.5, 0.5, P.bark):flat():upload(), material = M.vertex } })
  end
  root:add_child(Props.crystal(Vec3(zc.x - 3, zc.h + 1, zc.z + 3)))

  -- Lamp posts along the paths.
  for _, p in ipairs(paths) do
    for t = 0.2, 0.9, 0.23 do
      local x = p[1].x + (p[2].x - p[1].x) * t + 2.6
      local z = p[1].z + (p[2].z - p[1].z) * t
      local h = height(x, z)
      if h > 1.5 then root:add_child(Props.lamp(Vec3(x, h - 0.1, z))) end
    end
  end

  -- Remaining crystals scattered around the island.
  local spots = {
    Vec3(-6, 0, 18), Vec3(26, 0, 36), Vec3(-60, 0, -12), Vec3(-6, 0, -60), Vec3(64, 0, -30), Vec3(-30, 0, 58),
  }
  for _, s in ipairs(spots) do
    root:add_child(Props.crystal(Vec3(s.x, height(s.x, s.z) + 1.0, s.z)))
  end

  -- Fireflies drift over the meadow at night.
  World.fireflies = Particles3D { name = "Fireflies", position = Vec3(0, zones.spawn.h + 1.5, 20), emit_box = Vec3(40, 1.5, 40),
    rate = 0, lifetime = 6, speed = 0.3, spread = 180, size = 0.07, size_end = 0.07, amount = 400,
    color = Color(0.85, 1, 0.5, 1), color_end = Color(0.8, 1, 0.4, 0), turbulence = 2.5 }
  root:add_child(World.fireflies)

  root:add_child(Props.sign(Vec3(6, height(6, 20), 20), 0.3, "Welcome to Skylight Isle"))
end

return World
