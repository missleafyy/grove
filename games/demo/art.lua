-- Procedural art for the showcase: palette, materials, textures and meshes built in code.
local Art = {}

Art.pal = {
  grass = Color.hex("#6fb253"), grass_light = Color.hex("#9ccf63"), grass_dark = Color.hex("#4b8d43"),
  sand = Color.hex("#e9d7a1"), sand_wet = Color.hex("#c9b483"),
  rock = Color.hex("#8d929b"), rock_dark = Color.hex("#666b75"), rock_light = Color.hex("#b3b7bd"),
  dirt = Color.hex("#a98b62"),
  bark = Color.hex("#7a5232"), bark_dark = Color.hex("#5c3c24"),
  leaf = Color.hex("#4e9c45"), leaf_light = Color.hex("#7cc057"), pine = Color.hex("#2f7a4f"),
  blossom = Color.hex("#f4a9c6"), blossom_light = Color.hex("#ffd0e1"), autumn = Color.hex("#e6a33c"),
  mint = Color.hex("#9fe8c4"), mint_dark = Color.hex("#4fbf8a"), mint_glow = Color.hex("#7ee0b4"),
  wood = Color.hex("#b07b47"), wood_dark = Color.hex("#7d5330"),
  stone = Color.hex("#d9d2c3"), stone_dark = Color.hex("#a69f90"),
  roof = Color.hex("#c4523f"), metal = Color.hex("#3b3f47"), lamp = Color.hex("#ffd27a"),
  white = Color.hex("#f6f4ee"), ink = Color.hex("#1f2430"),
}
local P = Art.pal

------------------------------------------------------------------ textures
local function hash(x, y)
  local n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
  return n - math.floor(n)
end

-- Wooden crate face: planks with a darker frame.
function Art.crate_texture()
  return Texture.generate(128, 128, function(x, y, u, v)
    local frame = (u < 0.1 or u > 0.9 or v < 0.1 or v > 0.9)
    local diag = math.abs(u - v) < 0.06 or math.abs(u - (1 - v)) < 0.06
    local plank = math.floor(v * 4)
    local grain = Noise.perlin2(u * 3 + plank * 7.3, v * 40) * 0.08
    local base = 0.78 + grain + hash(plank, 3) * 0.08
    if frame or diag then base = 0.58 + grain end
    local seam = (v * 4) % 1 < 0.04 and not frame
    if seam then base = base * 0.6 end
    local edge = math.min(u, v, 1 - u, 1 - v)
    if frame and edge < 0.015 then base = base * 0.7 end
    return base, base, base, 1
  end)
end

-- Stone tiles for the plaza (used with triplanar mapping).
function Art.tile_texture()
  return Texture.generate(256, 256, function(x, y, u, v)
    local cu, cv = u * 4, v * 4
    local row = math.floor(cv)
    cu = cu + (row % 2) * 0.5
    local fx, fy = cu % 1, cv % 1
    local tile = hash(math.floor(cu), row)
    local grout = math.min(fx, fy, 1 - fx, 1 - fy) < 0.035
    local n = Noise.fbm2(u * 16, v * 16, 3) * 0.08
    local b = 0.86 + tile * 0.1 + n
    if grout then b = 0.55 end
    return b, b * 0.98, b * 0.94, 1
  end)
end

-- Soft noise used to break up large surfaces.
function Art.noise_texture()
  return Texture.generate(256, 256, function(x, y, u, v)
    local n = 0.85 + Noise.fbm2(u * 8, v * 8, 4) * 0.25
    return n, n, n, 1
  end)
end

------------------------------------------------------------------ materials
function Art.materials()
  local M = {}
  M.terrain = Material { albedo = Color.WHITE, roughness = 0.95, texture = Art.noise_texture(), triplanar = true, uv_scale = 0.08 }
  M.vertex = Material { albedo = Color.WHITE, roughness = 0.85 }
  M.foliage = Material { albedo = Color.WHITE, roughness = 0.8, wind = 0.12 }
  M.grass = Material { albedo = Color.WHITE, roughness = 0.9, wind = 9 }
  M.water = Material { albedo = Color.hex("#3d9fc6", 0.72), roughness = 0.08, metallic = 0, transparent = true, effect = "water" }
  M.crate = Material { albedo = Color.hex("#c48e57"), roughness = 0.75, texture = Art.crate_texture() }
  M.tiles = Material { albedo = Color.WHITE, roughness = 0.7, texture = Art.tile_texture(), triplanar = true, uv_scale = 0.12 }
  M.stone = Material { albedo = P.stone, roughness = 0.85 }
  M.metal = Material { albedo = P.metal, roughness = 0.35, metallic = 0.8 }
  M.crystal = Material { albedo = P.mint, roughness = 0.15, emission = P.mint_glow, emission_energy = 3.5, effect = "pulse", rim = 0.6 }
  M.crystal_big = Material { albedo = Color.hex("#b8f5ff"), roughness = 0.1, emission = Color.hex("#7ad8ff"), emission_energy = 4, effect = "pulse", rim = 0.8 }
  M.lamp_glow = Material { albedo = P.lamp, emission = P.lamp, emission_energy = 0.2, unshaded = false }
  M.orb = Material { albedo = Color.hex("#ffe6a6"), emission = Color.hex("#ffb84a"), emission_energy = 8, unshaded = true }
  M.pad = Material { albedo = Color.hex("#ff8fb1"), emission = Color.hex("#ff5f9a"), emission_energy = 2.5, effect = "pulse" }
  M.player = Material { albedo = Color.WHITE, roughness = 0.7, rim = 0.3 }
  M.eye = Material { albedo = P.ink, roughness = 0.15, metallic = 0.1 }
  M.eye_shine = Material { albedo = Color.WHITE, emission = Color.WHITE, emission_energy = 1.5, unshaded = true }
  M.platform = Material { albedo = Color.hex("#d9d2c3"), roughness = 0.6, emission = Color.hex("#7ee0b4"), emission_energy = 0 }
  return M
end

------------------------------------------------------------------ meshes
local function lerpc(a, b, t) return a:lerp(b, t) end

-- Round deciduous tree: trunk + three foliage blobs.
function Art.tree_round(seed, leaf_a, leaf_b)
  local r = Random(seed)
  local m = MeshData()
  local trunk = MeshData.cylinder(0.16, 0.28, 2.6, 7, P.bark)
  m:append(trunk, Vec3(0, 1.3, 0))
  local blobs = { { 0, 3.4, 0, 1.55 }, { 0.75, 2.9, 0.3, 1.1 }, { -0.6, 3.05, -0.45, 1.15 }, { 0.1, 4.25, -0.2, 1.0 } }
  for i, b in ipairs(blobs) do
    local c = lerpc(leaf_a, leaf_b, r:float())
    local blob = MeshData.icosphere(b[4], 1, c)
    blob:displace(function(x, y, z)
      local n = Noise.perlin3(x * 1.3 + seed, y * 1.3, z * 1.3 + i) * 0.28
      return x * n, y * n * 0.6, z * n
    end)
    -- Darker underside reads as ambient occlusion.
    blob:paint_fn(function(x, y, z, cr, cg, cb)
      local t = math.clamp(0.75 + y / b[4] * 0.35, 0.55, 1.1)
      return cr * t, cg * t, cb * t
    end)
    m:append(blob, Vec3(b[1], b[2], b[3]))
  end
  return m:flat()
end

function Art.tree_pine(seed)
  local r = Random(seed)
  local m = MeshData()
  m:append(MeshData.cylinder(0.12, 0.22, 1.6, 6, P.bark_dark), Vec3(0, 0.8, 0))
  local y = 1.2
  local w = 1.7
  for i = 1, 4 do
    local c = P.pine:lerp(P.leaf, r:float(0, 0.35)):darken(0.05 * (4 - i))
    local cone = MeshData.cylinder(0.05, w, 1.7, 8, c, true)
    cone:displace(function(x, yy, z) return x * r:float(-0.06, 0.06), 0, z * r:float(-0.06, 0.06) end)
    m:append(cone, Vec3(0, y + 0.85, 0), Quat.from_y(r:float(0, 6.28)))
    y = y + 1.05
    w = w * 0.76
  end
  return m:flat()
end

-- Grass tuft: crossed blades, dark at the root and light at the tip.
function Art.grass_tuft()
  local m = MeshData()
  local r = Random(4)
  for i = 1, 5 do
    local ang = i / 5 * math.pi + r:float(0, 0.4)
    local h = r:float(0.35, 0.65)
    local lean = r:float(-0.15, 0.15)
    local dx, dz = math.cos(ang) * 0.06, math.sin(ang) * 0.06
    local ox, oz = r:float(-0.12, 0.12), r:float(-0.12, 0.12)
    m:color(P.grass_dark:darken(0.25))
    local a = m:vertex(ox - dx, 0, oz - dz, 0, 1, 0)
    local b = m:vertex(ox + dx, 0, oz + dz, 0, 1, 0)
    m:color(P.grass_light:lighten(0.15))
    local c = m:vertex(ox + lean, h, oz + lean * 0.5, 0, 1, 0)
    m:tri(a, b, c)
    m:tri(a, c, b)  -- both windings so the back keeps the upward normal
  end
  return m
end

function Art.flower(col)
  local m = MeshData()
  m:append(MeshData.cylinder(0.015, 0.02, 0.35, 4, P.grass_dark, false), Vec3(0, 0.175, 0))
  for i = 0, 4 do
    local a = i / 5 * math.tau
    m:append(MeshData.icosphere(0.055, 0, col), Vec3(math.cos(a) * 0.06, 0.37, math.sin(a) * 0.06), nil, Vec3(1, 0.4, 1))
  end
  m:append(MeshData.icosphere(0.04, 0, Color.hex("#ffd34d")), Vec3(0, 0.39, 0))
  return m:flat()
end

function Art.rock(seed, size)
  local m = MeshData.icosphere(size, 1, P.rock)
  m:displace(function(x, y, z)
    local n = Noise.perlin3(x * 0.9 + seed * 3.1, y * 0.9, z * 0.9 - seed) * 0.45 * size
    return x / size * n, y / size * n * 0.7, z / size * n
  end)
  m:transform(nil, nil, Vec3(1, 0.7, 1))
  m:paint_fn(function(x, y, z, cr, cg, cb)
    local t = 0.8 + hash(x * 3, z * 3) * 0.25 + y / size * 0.15
    if y > size * 0.35 then return P.grass.r * t, P.grass.g * t, P.grass.b * t end  -- mossy tops
    return cr * t, cg * t, cb * t
  end)
  return m:flat()
end

function Art.barrel()
  local m = MeshData.cylinder(0.42, 0.42, 1.1, 14, P.wood)
  m:paint_fn(function(x, y, z, r, g, b)
    if math.abs(y) > 0.38 and math.abs(y) < 0.46 or math.abs(y) < 0.04 then return P.metal.r, P.metal.g, P.metal.b end
    local plank = math.floor((math.atan2(z, x) + math.pi) / math.tau * 14)
    local t = 0.9 + hash(plank, 1) * 0.2
    return r * t, g * t, b * t
  end)
  -- bulge
  m:displace(function(x, y, z) local k = (1 - (y / 0.55) ^ 2) * 0.08; return x * k, 0, z * k end)
  return m:smooth_normals()
end

function Art.crystal_mesh(h)
  h = h or 1
  local m = MeshData()
  local main = MeshData.cylinder(0, 0.32, 0.55 * h, 6, Color.WHITE, false)
  local base = MeshData.cylinder(0.32, 0.18, 0.35 * h, 6, Color.WHITE, false)
  m:append(main, Vec3(0, 0.45 * h, 0))
  m:append(base, Vec3(0, 0.0, 0))
  return m:flat()
end

function Art.lamp_post()
  local m = MeshData()
  m:append(MeshData.cylinder(0.07, 0.1, 2.6, 8, P.metal), Vec3(0, 1.3, 0))
  m:append(MeshData.cylinder(0.18, 0.22, 0.12, 8, P.metal), Vec3(0, 0.06, 0))
  m:append(MeshData.cylinder(0.24, 0.12, 0.14, 8, P.metal), Vec3(0, 2.95, 0))
  m:append(MeshData.cylinder(0.02, 0.3, 0.25, 8, P.metal), Vec3(0, 3.25, 0))
  return m:flat()
end

-- Floating island chunk: grassy top, rocky cone underneath.
function Art.sky_island(seed, radius)
  local r = Random(seed)
  local m = MeshData()
  local top = MeshData.cylinder(radius, radius * 0.95, 0.6, 14, P.grass)
  top:displace(function(x, y, z)
    if y > 0 then return 0, Noise.perlin2(x * 0.4 + seed, z * 0.4) * 0.15, 0 end
    return 0, 0, 0
  end)
  top:paint_fn(function(x, y, z, cr, cg, cb)
    if y < 0.2 then return P.dirt.r, P.dirt.g, P.dirt.b end
    local t = 0.9 + hash(x, z) * 0.2
    return cr * t, cg * t, cb * t
  end)
  m:append(top, Vec3(0, -0.3, 0))
  local under = MeshData.cylinder(radius * 0.95, 0.3, radius * 1.6, 12, P.rock)
  under:displace(function(x, y, z)
    local n = Noise.perlin3(x * 0.5 + seed, y * 0.5, z * 0.5) * 0.35
    return x * n, 0, z * n
  end)
  under:paint_fn(function(x, y, z, cr, cg, cb)
    local t = 0.75 + hash(x * 2, y * 2) * 0.3
    return cr * t, cg * t, cb * t
  end)
  m:append(under, Vec3(0, -0.6 - radius * 0.8, 0))
  return m:flat()
end

-- Mascot character pieces.
function Art.player_parts()
  local parts = {}
  local body = MeshData.sphere(0.5, 28, 20, P.mint)
  body:transform(nil, nil, Vec3(1, 0.92, 1))
  body:paint_fn(function(x, y, z, r, g, b)
    if y < -0.15 then local t = 0.92 return r * t, g * t, b * t end  -- slightly darker belly-bottom
    return r, g, b
  end)
  parts.body = body:upload()
  parts.eye = MeshData.sphere(0.075, 12, 10, Color.WHITE):transform(nil, nil, Vec3(0.8, 1.25, 0.5)):upload()
  parts.shine = MeshData.sphere(0.025, 8, 6, Color.WHITE):upload()
  parts.cheek = MeshData.sphere(0.06, 10, 8, Color.hex("#ff9db5")):transform(nil, nil, Vec3(1, 0.6, 0.35)):upload()
  parts.foot = MeshData.sphere(0.16, 14, 10, P.mint_dark):transform(nil, nil, Vec3(1, 0.6, 1.3)):upload()
  local sprout = MeshData()
  sprout:append(MeshData.cylinder(0.025, 0.035, 0.28, 6, P.mint_dark), Vec3(0, 0.14, 0))
  local leaf = MeshData.sphere(0.16, 12, 8, Color.hex("#5fd18f")):transform(nil, nil, Vec3(1, 0.22, 0.55))
  sprout:append(leaf, Vec3(0.14, 0.3, 0), Quat.euler(0, 0, 0.5))
  local leaf2 = MeshData.sphere(0.12, 12, 8, Color.hex("#7fe0a6")):transform(nil, nil, Vec3(1, 0.22, 0.55))
  sprout:append(leaf2, Vec3(-0.11, 0.26, 0), Quat.euler(0, 0, -0.6))
  parts.sprout = sprout:upload()
  return parts
end

return Art
