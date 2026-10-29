-- Procedural art for CARL 4: palette, materials and every mesh, built in code.
-- Meshes use vertex colours; the cel shader + ink outlines (Environment.toon / outline) do the rest.
local Art = {}

Art.pal = {
  sand = Color.hex("#e9c48d"), sand_dark = Color.hex("#d49d63"), sand_light = Color.hex("#f4dcae"),
  rock = Color.hex("#c4643a"), rock_dark = Color.hex("#93452a"), rock_light = Color.hex("#e39a62"), strata = Color.hex("#f0b67a"),
  sage = Color.hex("#9cab78"), sage_dark = Color.hex("#6f8058"),
  cactus = Color.hex("#4f9a52"), cactus_dark = Color.hex("#357540"), cactus_light = Color.hex("#7cc068"),
  joshua = Color.hex("#6b8f4a"), bark = Color.hex("#7a5a3c"), bark_dark = Color.hex("#4f3826"),
  asphalt = Color.hex("#3a3a40"), line_yellow = Color.hex("#f2c94c"), line_white = Color.hex("#efefe8"),
  wood = Color.hex("#b98952"), wood_dark = Color.hex("#7d5631"), wood_grey = Color.hex("#9a8a76"),
  metal = Color.hex("#5a5f69"), metal_dark = Color.hex("#2e3138"), chrome = Color.hex("#c9ced6"),
  red = Color.hex("#d8433b"), white = Color.hex("#f5f3ec"), ink = Color.hex("#1b1720"),
  -- Carl
  carl_skin = Color.hex("#4fb39a"), carl_skin_dark = Color.hex("#2f8a76"), carl_eye = Color.hex("#62d84e"),
  carl_pupil = Color.hex("#0f2a12"), hoodie = Color.hex("#1d1c24"), gold = Color.hex("#e7b53b"), bowtie = Color.hex("#f5d33a"),
  -- Old Face (comms portrait)
  face_dark = Color.hex("#14251b"), face_green = Color.hex("#5fd38a"), face_magenta = Color.hex("#e04fb0"),
  -- enemies
  suit = Color.hex("#f3f1ea"), suit_shadow = Color.hex("#d6d3c8"), skin = Color.hex("#f0c8a6"), hair = Color.hex("#25211f"),
  lemon = Color.hex("#f4d63c"), human_skin = Color.hex("#f2b98f"),
  -- rarity
  common = Color.hex("#e8e8e8"), uncommon = Color.hex("#5ee06a"), rare = Color.hex("#4aa8ff"), epic = Color.hex("#b56cff"), legendary = Color.hex("#ff9a2e"),
  fire = Color.hex("#ff6a2a"), static = Color.hex("#6fe8ff"), curse = Color.hex("#d35cff"),
  cash = Color.hex("#7fe07a"), pill = Color.hex("#ff5d8a"),
}
local P = Art.pal

local function hash(x, y)
  local n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
  return n - math.floor(n)
end
Art.hash = hash

------------------------------------------------------------------ materials
function Art.materials()
  local M = {}
  M.vertex = Material { albedo = Color.WHITE, roughness = 0.9 }
  M.glossy = Material { albedo = Color.WHITE, roughness = 0.25 }
  M.terrain = Material { albedo = Color(1.1, 1.1, 1.1), roughness = 1, texture = require("world_detail").terrain_texture(), triplanar = true, uv_scale = 0.22 }
  M.foliage = Material { albedo = Color.WHITE, roughness = 0.9, wind = 0.08 }
  M.metal = Material { albedo = Color.WHITE, roughness = 0.35, metallic = 0.6 }
  M.gun = Material { albedo = Color.WHITE, roughness = 0.3, metallic = 0.3, rim = 0.25 }
  M.skin = Material { albedo = Color.WHITE, roughness = 0.45, rim = 0.35 }
  M.eye = Material { albedo = Color.WHITE, roughness = 0.05 }
  M.shine = Material { albedo = Color.WHITE, unshaded = true }
  M.glow = Material { albedo = Color.WHITE, unshaded = true }
  M.beam = Material { albedo = Color(1, 1, 1, 0.28), unshaded = true, transparent = true, double_sided = true, no_fog = true }
  M.tracer = Material { albedo = Color(1, 0.9, 0.5, 1), unshaded = true }
  M.shock = Material { albedo = Color(1, 1, 1, 0.5), unshaded = true, transparent = true, double_sided = true }
  M.tractor = Material { albedo = Color.hex("#7dffb0", 0.35), unshaded = true, transparent = true, double_sided = true }
  M.cell = Material { albedo = Color.hex("#9dffcf"), emission = Color.hex("#4dffa6"), emission_energy = 3, effect = "pulse", rim = 0.6 }
  M.glass = Material { albedo = Color.hex("#a8f0ff", 0.45), roughness = 0.05, transparent = true }
  return M
end

------------------------------------------------------------------ helpers
-- Sphere with its bottom flattened at y = cut (for domes and caps).
local function dome(r, cut, col, seg)
  local m = MeshData.sphere(r, seg or 20, 12, col)
  m:displace(function(x, y, z) if y < cut then return 0, cut - y, 0 end end)
  return m
end

local function ellipsoid(r, sx, sy, sz, col, seg)
  local m = MeshData.sphere(r, seg or 18, 12, col)
  m:transform(nil, nil, Vec3(sx, sy, sz))
  return m
end

------------------------------------------------------------------ Carl
-- Returns separate parts so the controller can animate them. Forward is -Z. Feet at y=0.
function Art.carl_parts()
  local parts = {}
  -- Head: big, bald, teal-green, a little egg-shaped.
  local head = ellipsoid(0.36, 1, 1.04, 0.96, P.carl_skin, 24)
  head:paint_fn(function(x, y, z, r, g, b)
    local t = 0.92 + (y + 0.36) * 0.18
    return r * t, g * t, b * t
  end)
  -- Tiny mouth.
  head:append(ellipsoid(0.035, 1.4, 0.6, 0.6, P.carl_skin_dark, 8), Vec3(0, -0.2, -0.32))
  -- Backwards cap: dome + brim at the back + button.
  local cap = dome(0.375, 0.02, P.ink, 22)
  cap:transform(Vec3(0, 0.03, 0.01), nil, Vec3(1, 0.9, 1.02))
  local brim = MeshData.cylinder(0.24, 0.24, 0.035, 16, P.ink)
  brim:transform(nil, nil, Vec3(1.15, 1, 0.75))
  cap:append(brim, Vec3(0, 0.06, 0.38), Quat.euler(0.12, 0, 0))
  cap:append(MeshData.sphere(0.04, 8, 6, P.ink), Vec3(0, 0.37, 0.01))
  cap:append(MeshData.box(0.16, 0.06, 0.02, P.gold), Vec3(0, 0.1, 0.36))   -- strap buckle
  head:append(cap, Vec3(0, 0.08, 0))
  parts.head = head

  -- Eyes: huge glossy green ovals with dark pupils, slightly wrapped round the head.
  local eye = ellipsoid(0.125, 0.85, 1.12, 0.55, P.carl_eye, 40)
  eye:paint_fn(function(x, y, z, r, g, b)
    local d = math.sqrt((x / 0.8) ^ 2 + ((y + 0.01) / 1.15) ^ 2)
    if z < 0 and d < 0.06 then return P.carl_pupil.r, P.carl_pupil.g, P.carl_pupil.b end
    if d > 0.098 then return P.carl_eye.r * 0.45, P.carl_eye.g * 0.55, P.carl_eye.b * 0.45 end
    return r, g, b
  end)
  parts.eye = eye
  parts.shine = MeshData.sphere(0.028, 8, 6, Color.WHITE)

  -- Torso: black hoodie with gold trim and a yellow bow tie.
  local torso = MeshData.capsule(0.21, 0.5, 18, P.hoodie)
  torso:transform(nil, nil, Vec3(1.08, 1, 0.9))
  torso:paint_fn(function(x, y, z, r, g, b)
    if z < 0 and math.abs(x) < 0.025 and y < 0.12 then return P.gold.r, P.gold.g, P.gold.b end   -- zip
    if y < -0.17 and y > -0.21 then return P.gold.r, P.gold.g, P.gold.b end                     -- hem stripe
    return r, g, b
  end)
  local hood = MeshData.torus(0.15, 0.06, 18, 8, P.hoodie)
  hood:paint_fn(function(x, y, z, r, g, b) if y > 0.035 then return P.gold.r, P.gold.g, P.gold.b end return r, g, b end)
  torso:append(hood, Vec3(0, 0.22, 0.02))
  local bow = MeshData()
  bow:append(MeshData.cone(0.06, 0.09, 4, P.bowtie), Vec3(-0.045, 0, 0), Quat.euler(0, 0, -math.pi / 2))
  bow:append(MeshData.cone(0.06, 0.09, 4, P.bowtie), Vec3(0.045, 0, 0), Quat.euler(0, 0, math.pi / 2))
  bow:append(MeshData.sphere(0.03, 8, 6, P.gold), Vec3(0, 0, -0.01))
  torso:append(bow, Vec3(0, 0.2, -0.17))
  parts.torso = torso

  -- Limbs (pivot at the top).
  local arm = MeshData.capsule(0.065, 0.32, 10, P.hoodie)
  arm:transform(Vec3(0, -0.13, 0))
  arm:append(MeshData.torus(0.06, 0.018, 12, 6, P.gold), Vec3(0, -0.22, 0))
  arm:append(MeshData.sphere(0.07, 10, 8, P.carl_skin), Vec3(0, -0.31, 0))
  parts.arm = arm
  local leg = MeshData.capsule(0.075, 0.26, 10, P.hoodie)
  leg:transform(Vec3(0, -0.1, 0))
  local shoe = ellipsoid(0.08, 1, 0.7, 1.45, P.white, 10)
  shoe:paint_fn(function(x, y, z, r, g, b) if y < -0.02 then return 0.25, 0.25, 0.28 end return r, g, b end)
  leg:append(shoe, Vec3(0, -0.22, -0.04))
  parts.leg = leg
  return parts
end

------------------------------------------------------------------ White Suit agent
function Art.suit_parts()
  local parts = {}
  local head = ellipsoid(0.15, 0.9, 1.08, 0.95, P.skin, 16)
  local hair = dome(0.158, 0.03, P.hair, 16)
  head:append(hair, Vec3(0, 0.015, 0.008))
  local shades = MeshData.box(0.26, 0.055, 0.04, P.ink)
  head:append(shades, Vec3(0, 0.02, -0.135))
  head:append(MeshData.box(0.07, 0.012, 0.01, Color.hex("#c23b2f")), Vec3(0, -0.075, -0.142))
  head:append(MeshData.box(0.14, 0.06, 0.12, P.skin), Vec3(0, -0.12, -0.02))   -- jaw
  parts.head = head:flat()
  local torso = MeshData.box(0.48, 0.62, 0.28, P.suit)
  torso:displace(function(x, y, z) if y < 0 then return -x * 0.12, 0, -z * 0.08 end end)
  torso:append(MeshData.box(0.12, 0.42, 0.02, P.white), Vec3(0, 0.08, -0.145))
  torso:append(MeshData.box(0.05, 0.38, 0.02, P.ink), Vec3(0, 0.08, -0.155))
  torso:append(MeshData.box(0.12, 0.06, 0.02, P.ink), Vec3(0.13, 0.17, -0.15))   -- pocket square... in black
  parts.torso = torso:flat()
  local arm = MeshData.box(0.14, 0.58, 0.15, P.suit)
  arm:transform(Vec3(0, -0.27, 0))
  arm:append(MeshData.box(0.1, 0.1, 0.1, P.skin), Vec3(0, -0.6, 0))
  parts.arm = arm:flat()
  local leg = MeshData.box(0.17, 0.82, 0.18, P.suit)
  leg:transform(Vec3(0, -0.4, 0))
  leg:append(MeshData.box(0.18, 0.08, 0.3, P.ink), Vec3(0, -0.8, -0.05))
  parts.leg = leg:flat()
  return parts
end

------------------------------------------------------------------ HU-MAN
-- Focus-tested "normal human" Carl: square jaw, sunglasses, same cap and bow tie. Built at 1x; scaled up.
function Art.human_parts()
  local parts = {}
  local head = MeshData.box(0.5, 0.56, 0.48, P.human_skin)
  head:displace(function(x, y, z) if y < -0.1 then return x * 0.08, 0, 0 end end)
  head:append(MeshData.box(0.56, 0.2, 0.5, P.human_skin), Vec3(0, -0.2, -0.02))   -- the jaw
  head:append(MeshData.box(0.56, 0.12, 0.06, P.ink), Vec3(0, 0.06, -0.26))        -- shades
  head:append(MeshData.box(0.2, 0.04, 0.02, Color.hex("#c46a5a")), Vec3(0, -0.17, -0.28))
  local cap = dome(0.3, 0.02, P.ink, 18)
  cap:transform(nil, nil, Vec3(0.95, 0.6, 0.9))
  head:append(cap, Vec3(0, 0.26, 0))
  local brim = MeshData.box(0.34, 0.03, 0.22, P.ink)
  head:append(brim, Vec3(0, 0.29, 0.3))
  parts.head = head:flat()
  local torso = MeshData.box(0.86, 0.8, 0.46, P.hoodie)
  torso:displace(function(x, y, z) if y < 0 then return -x * 0.15, 0, 0 end end)
  torso:append(MeshData.box(0.04, 0.7, 0.02, P.gold), Vec3(0, -0.02, -0.24))
  torso:append(MeshData.box(0.86, 0.05, 0.47, P.gold), Vec3(0, -0.36, 0))
  local bow = MeshData()
  bow:append(MeshData.cone(0.1, 0.16, 4, P.bowtie), Vec3(-0.08, 0, 0), Quat.euler(0, 0, -math.pi / 2))
  bow:append(MeshData.cone(0.1, 0.16, 4, P.bowtie), Vec3(0.08, 0, 0), Quat.euler(0, 0, math.pi / 2))
  torso:append(bow, Vec3(0, 0.34, -0.25))
  parts.torso = torso:flat()
  local arm = MeshData.box(0.24, 0.72, 0.26, P.hoodie)
  arm:transform(Vec3(0, -0.34, 0))
  arm:append(MeshData.box(0.25, 0.04, 0.27, P.gold), Vec3(0, -0.62, 0))
  arm:append(MeshData.box(0.2, 0.18, 0.22, P.human_skin), Vec3(0, -0.76, 0))
  parts.arm = arm:flat()
  local leg = MeshData.box(0.3, 0.8, 0.3, Color.hex("#3b4a6b"))
  leg:transform(Vec3(0, -0.4, 0))
  leg:append(MeshData.box(0.32, 0.12, 0.44, P.white), Vec3(0, -0.78, -0.06))
  parts.leg = leg:flat()
  return parts
end

------------------------------------------------------------------ Jumper Cactus
function Art.cactus_enemy()
  local m = MeshData.capsule(0.32, 1.2, 12, P.cactus)
  m:transform(Vec3(0, 0.6, 0))
  for _, s in ipairs({ -1, 1 }) do
    local arm = MeshData.capsule(0.13, 0.55, 10, P.cactus)
    m:append(arm, Vec3(s * 0.42, 0.75 + (s > 0 and 0.1 or 0), 0))
    m:append(MeshData.capsule(0.13, 0.32, 10, P.cactus), Vec3(s * 0.3, 0.6 + (s > 0 and 0.1 or 0), 0), Quat.euler(0, 0, s * math.pi / 2))
  end
  m:paint_fn(function(x, y, z, r, g, b)
    local a = math.atan2(z, x) * 8
    local rib = math.abs(math.sin(a)) > 0.8 and 0.82 or 1
    return r * rib, g * rib, b * rib
  end)
  -- Angry face.
  for _, s in ipairs({ -1, 1 }) do
    m:append(ellipsoid(0.06, 1, 1.2, 0.5, P.ink, 8), Vec3(s * 0.11, 0.92, -0.29))
    m:append(MeshData.box(0.13, 0.03, 0.03, P.ink), Vec3(s * 0.11, 1.02, -0.31), Quat.euler(0, 0, s * 0.45))
  end
  m:append(MeshData.box(0.16, 0.035, 0.03, P.ink), Vec3(0, 0.76, -0.31))
  -- Pink flower on top.
  for i = 0, 4 do
    local a = i / 5 * math.tau
    m:append(ellipsoid(0.07, 1, 0.4, 1, Color.hex("#ff7fb0"), 8), Vec3(math.cos(a) * 0.07, 1.22, math.sin(a) * 0.07))
  end
  m:append(MeshData.sphere(0.04, 8, 6, P.bowtie), Vec3(0, 1.25, 0))
  -- Spines.
  local r = Random(4)
  for _ = 1, 40 do
    local a = r:float(0, math.tau)
    local y = r:float(0.2, 1.1)
    m:append(MeshData.box(0.02, 0.02, 0.08, P.sand_light), Vec3(math.cos(a) * 0.32, y, math.sin(a) * 0.32), Quat.from_y(-a + math.pi / 2))
  end
  return m:flat()
end

------------------------------------------------------------------ Lemon Drone
function Art.drone_parts()
  local body = ellipsoid(0.38, 1, 0.75, 1.25, P.lemon, 18)
  body:paint_fn(function(x, y, z, r, g, b)
    if math.abs(z) > 0.43 then return r * 0.85, g * 0.8, b * 0.5 end
    return r, g, b
  end)
  body:append(ellipsoid(0.05, 1, 1, 1.5, Color.hex("#a7c33a"), 6), Vec3(0, 0.05, 0.5))   -- lemon nub
  body:append(MeshData.sphere(0.11, 12, 8, P.ink), Vec3(0, -0.02, -0.4))
  for i = 0, 3 do
    local a = i / 4 * math.tau + math.pi / 4
    local d = Vec3(math.cos(a), 0, math.sin(a))
    body:append(MeshData.box(0.6, 0.05, 0.07, P.metal_dark), d * 0.45 + Vec3(0, 0.12, 0), Quat.from_y(-a))
    body:append(MeshData.cylinder(0.06, 0.06, 0.08, 8, P.metal_dark), d * 0.75 + Vec3(0, 0.14, 0))
  end
  local rotor = MeshData.box(0.5, 0.02, 0.06, P.metal)
  rotor:append(MeshData.box(0.06, 0.02, 0.5, P.metal))
  return { body = body:flat(), rotor = rotor, eye = MeshData.sphere(0.07, 10, 8, Color.WHITE) }
end

------------------------------------------------------------------ guns
-- One mesh per gun type; accent is the rarity colour, glow the element colour (or nil).
function Art.gun_mesh(kind, accent, glow)
  local m = MeshData()
  local body, dark = P.metal, P.metal_dark
  if kind == "pistol" then
    m:append(MeshData.box(0.08, 0.1, 0.32, body), Vec3(0, 0.04, -0.06))
    m:append(MeshData.box(0.07, 0.16, 0.08, dark), Vec3(0, -0.07, 0.04), Quat.euler(-0.25, 0, 0))
    m:append(MeshData.cylinder(0.025, 0.025, 0.1, 8, dark), Vec3(0, 0.06, -0.25), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.box(0.085, 0.03, 0.2, accent), Vec3(0, 0.1, -0.05))
  elseif kind == "smg" then
    m:append(MeshData.box(0.09, 0.12, 0.46, body), Vec3(0, 0.04, -0.1))
    m:append(MeshData.box(0.07, 0.2, 0.07, dark), Vec3(0, -0.1, -0.12))
    m:append(MeshData.box(0.07, 0.14, 0.08, dark), Vec3(0, -0.06, 0.06), Quat.euler(-0.3, 0, 0))
    m:append(MeshData.box(0.06, 0.08, 0.2, dark), Vec3(0, 0.04, 0.2))
    m:append(MeshData.cylinder(0.025, 0.025, 0.14, 8, dark), Vec3(0, 0.06, -0.38), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.box(0.095, 0.03, 0.3, accent), Vec3(0, 0.11, -0.1))
  elseif kind == "shotgun" then
    m:append(MeshData.box(0.1, 0.12, 0.4, body), Vec3(0, 0.03, 0))
    for _, s in ipairs({ -1, 1 }) do
      m:append(MeshData.cylinder(0.035, 0.035, 0.5, 10, dark), Vec3(s * 0.035, 0.07, -0.42), Quat.euler(math.pi / 2, 0, 0))
    end
    m:append(MeshData.box(0.1, 0.1, 0.3, P.wood), Vec3(0, -0.01, 0.32), Quat.euler(0.15, 0, 0))
    m:append(MeshData.box(0.12, 0.06, 0.16, accent), Vec3(0, 0.0, -0.3))
  elseif kind == "rifle" then
    m:append(MeshData.box(0.08, 0.12, 0.7, body), Vec3(0, 0.03, -0.1))
    m:append(MeshData.cylinder(0.022, 0.022, 0.4, 8, dark), Vec3(0, 0.05, -0.65), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.cylinder(0.04, 0.04, 0.26, 10, dark), Vec3(0, 0.14, -0.1), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.cylinder(0.045, 0.045, 0.02, 10, accent), Vec3(0, 0.14, -0.235), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.box(0.07, 0.14, 0.26, P.wood_dark), Vec3(0, -0.03, 0.34))
    m:append(MeshData.box(0.06, 0.12, 0.06, dark), Vec3(0, -0.09, -0.02))
    m:append(MeshData.box(0.085, 0.03, 0.3, accent), Vec3(0, 0.09, -0.3))
  elseif kind == "launcher" then
    m:append(MeshData.cylinder(0.11, 0.11, 0.9, 14, body), Vec3(0, 0.08, -0.1), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.cylinder(0.14, 0.12, 0.12, 14, accent), Vec3(0, 0.08, -0.56), Quat.euler(math.pi / 2, 0, 0))
    m:append(MeshData.box(0.07, 0.16, 0.08, dark), Vec3(0, -0.08, 0.0), Quat.euler(-0.25, 0, 0))
    m:append(MeshData.box(0.05, 0.1, 0.06, dark), Vec3(0, 0.22, -0.05))
  end
  if glow then
    m:append(MeshData.box(0.03, 0.03, 0.12, glow), Vec3(0.055, 0.04, -0.12))
    m:append(MeshData.box(0.03, 0.03, 0.12, glow), Vec3(-0.055, 0.04, -0.12))
  end
  return m:flat()
end

------------------------------------------------------------------ props
function Art.crate()
  local m = MeshData.box(1, 1, 1, P.wood)
  m:paint_fn(function(x, y, z, r, g, b)
    local t = 0.9 + hash(math.floor(y * 4 + 2), math.floor(x * 3 + z * 3)) * 0.18
    return r * t, g * t, b * t
  end)
  for _, s in ipairs({ -1, 1 }) do
    m:append(MeshData.box(1.02, 0.12, 1.02, P.wood_dark), Vec3(0, s * 0.44, 0))
    m:append(MeshData.box(0.12, 1.02, 1.02, P.wood_dark), Vec3(s * 0.44, 0, 0))
  end
  return m:flat()
end

function Art.barrel(col, band)
  local m = MeshData.cylinder(0.4, 0.4, 1.1, 14, col)
  m:paint_fn(function(x, y, z, r, g, b)
    if math.abs(math.abs(y) - 0.3) < 0.04 then return band.r, band.g, band.b end
    return r, g, b
  end)
  m:append(MeshData.cylinder(0.2, 0.2, 0.02, 10, band), Vec3(0, 0.555, 0))
  return m:flat()
end

-- Red "PROP PILLS — HIGHLY FLAMMABLE" barrel with a white pill stripe.
function Art.explosive_barrel()
  local m = MeshData.cylinder(0.4, 0.4, 1.1, 14, P.red)
  m:paint_fn(function(x, y, z, r, g, b)
    if math.abs(y) < 0.1 then return P.white.r, P.white.g, P.white.b end
    if math.abs(math.abs(y) - 0.42) < 0.03 then return 0.3, 0.1, 0.1 end
    return r, g, b
  end)
  m:append(MeshData.capsule(0.07, 0.3, 8, P.pill), Vec3(0, 0, -0.41), Quat.euler(0, 0, math.pi / 2))
  m:append(MeshData.cylinder(0.08, 0.08, 0.06, 8, P.bowtie), Vec3(0.18, 0.57, 0))
  return m:flat()
end

function Art.boulder(seed, r)
  local m = MeshData.icosphere(r, 2, P.rock)
  m:displace(function(x, y, z)
    local n = Noise.perlin3(x * 1.3 + seed * 2.7, y * 1.3, z * 1.3 - seed) * 0.22 * r
    return x / r * n, y / r * n, z / r * n
  end)
  m:paint_fn(function(x, y, z, cr, cg, cb)
    local t = 0.8 + hash(math.floor(x * 4), math.floor(z * 4 + y * 3)) * 0.25
    return P.rock.r * t, P.rock.g * t, P.rock.b * t
  end)
  return m:flat()
end

function Art.rock(seed, size, col)
  col = col or P.rock
  local m = MeshData.icosphere(size, 1, col)
  m:displace(function(x, y, z)
    local n = Noise.perlin3(x * 0.9 + seed * 3.1, y * 0.9, z * 0.9 - seed) * 0.45 * size
    return x / size * n, y / size * n * 0.7, z / size * n
  end)
  m:transform(nil, nil, Vec3(1, 0.65, 1))
  m:paint_fn(function(x, y, z, r, g, b)
    local band = math.floor((y / size + 1) * 3) % 2 == 0 and 1.0 or 0.86
    local t = band * (0.9 + hash(x * 3, z * 3) * 0.15)
    return r * t, g * t, b * t
  end)
  return m:flat()
end

function Art.saguaro(seed)
  local r = Random(seed)
  local h = r:float(3.2, 5.2)
  local m = MeshData.capsule(0.32, h, 12, P.cactus)
  m:transform(Vec3(0, h / 2 - 0.1, 0))
  local arms = r:int(1, 3)
  for i = 1, arms do
    local side = (i % 2 == 0) and -1 or 1
    local a = r:float(-0.5, 0.5) + (side < 0 and math.pi or 0)
    local d = Vec3(math.cos(a), 0, math.sin(a))
    local y0 = r:float(1.3, h * 0.6)
    local out = r:float(0.55, 0.85)
    local up = r:float(0.8, 1.6)
    local elbow = MeshData.capsule(0.2, out + 0.2, 10, P.cactus)
    m:append(elbow, d * (out / 2 + 0.2) + Vec3(0, y0, 0), Quat.from_y(-a) * Quat.euler(0, 0, math.pi / 2))
    m:append(MeshData.capsule(0.2, up + 0.2, 10, P.cactus), d * (out + 0.2) + Vec3(0, y0 + up / 2, 0))
  end
  m:paint_fn(function(x, y, z, cr, cg, cb)
    local rib = math.abs(math.sin(math.atan2(z, x) * 7)) > 0.85 and 0.78 or 1
    local t = rib * (0.92 + y * 0.02)
    return cr * t, cg * t, cb * t
  end)
  return m:flat()
end

function Art.joshua_tree(seed)
  local r = Random(seed)
  local m = MeshData()
  local function branch(pos, dir, len, depth)
    local q = Quat.between(Vec3(0, 1, 0), dir)
    m:append(MeshData.cylinder(0.11 * (depth + 1) * 0.6, 0.14 * (depth + 1) * 0.6, len, 7, P.bark), pos + dir * (len / 2), q)
    local tip = pos + dir * len
    if depth == 0 then
      -- Spiky leaf pompom.
      local tuft = MeshData.icosphere(0.42, 1, P.joshua)
      tuft:displace(function(x, y, z) local k = (hash(x * 9, z * 9 + y) > 0.5) and 0.35 or 0; return x * k, y * k, z * k end)
      m:append(tuft, tip + Vec3(0, 0.15, 0))
      return
    end
    local n = r:int(2, 3)
    for _ = 1, n do
      local nd = (dir + Vec3(r:float(-0.9, 0.9), r:float(0.3, 0.9), r:float(-0.9, 0.9))):normalized()
      branch(tip, nd, len * r:float(0.55, 0.8), depth - 1)
    end
  end
  branch(Vec3(0, 0, 0), Vec3(0, 1, 0), r:float(1.6, 2.4), 2)
  return m:flat()
end

function Art.sagebrush()
  local m = MeshData.icosphere(0.5, 2, P.sage_dark)
  m:displace(function(x, y, z) local n = Noise.perlin3(x * 4, y * 4, z * 4) * 0.25; return x * n, y * n - (y < 0 and y * 0.6 or 0), z * n end)
  m:transform(nil, nil, Vec3(1, 0.6, 1))
  m:paint_fn(function(x, y, z, r, g, b) local t = 0.85 + (y + 0.3) * 0.4; return r * t, g * t, b * t end)
  return m:flat()
end

function Art.tumbleweed()
  local m = MeshData()
  local r = Random(7)
  for _ = 1, 26 do
    local d = r:unit_vec3()
    m:append(MeshData.box(0.04, 0.04, r:float(0.5, 0.9), P.bark:lerp(P.sand, 0.5)), d * 0.2, Quat.look_rotation(r:unit_vec3()))
  end
  return m:flat()
end

function Art.power_pole()
  local m = MeshData.cylinder(0.12, 0.16, 8, 8, P.wood_dark)
  m:transform(Vec3(0, 4, 0))
  m:append(MeshData.box(2.2, 0.14, 0.14, P.wood_dark), Vec3(0, 7.4, 0))
  for _, x in ipairs({ -0.9, 0, 0.9 }) do m:append(MeshData.cylinder(0.05, 0.06, 0.16, 6, Color.hex("#7ab0c9")), Vec3(x, 7.55, 0)) end
  return m:flat()
end

function Art.chest(accent)
  local m = MeshData.box(1.1, 0.55, 0.7, P.metal)
  m:append(MeshData.box(1.14, 0.08, 0.74, accent), Vec3(0, 0.2, 0))
  m:append(MeshData.box(0.18, 0.18, 0.06, P.gold), Vec3(0, 0.12, -0.37))
  local lid = MeshData.box(1.12, 0.2, 0.72, P.metal_dark)
  lid:transform(Vec3(0, 0.1, 0.36))
  lid:append(MeshData.box(1.0, 0.04, 0.6, accent), Vec3(0, 0.21, 0.36))
  return m:flat(), lid:flat()
end

function Art.power_cell()
  local m = MeshData.cylinder(0.22, 0.22, 0.6, 12, Color.WHITE)
  m:append(MeshData.cylinder(0.26, 0.26, 0.1, 12, Color.WHITE), Vec3(0, 0.32, 0))
  m:append(MeshData.cylinder(0.26, 0.26, 0.1, 12, Color.WHITE), Vec3(0, -0.32, 0))
  return m:flat()
end

-- The A.S.S. (Alien Starship): a dented saucer, nose-down in the sand.
function Art.ship()
  local m = MeshData()
  local disc = MeshData.sphere(6, 40, 16, P.chrome)
  disc:transform(nil, nil, Vec3(1, 0.22, 1))
  disc:paint_fn(function(x, y, z, r, g, b)
    local d = math.sqrt(x * x + z * z)
    if d > 5.2 and d < 5.6 then return P.carl_skin.r, P.carl_skin.g, P.carl_skin.b end
    if math.abs(y) < 0.12 then return P.metal.r, P.metal.g, P.metal.b end
    local t = 0.9 + hash(math.floor(x), math.floor(z)) * 0.12
    return r * t, g * t, b * t
  end)
  m:append(disc)
  local rim_lights = 14
  for i = 0, rim_lights - 1 do
    local a = i / rim_lights * math.tau
    m:append(MeshData.sphere(0.22, 8, 6, Color.hex("#7dffb0")), Vec3(math.cos(a) * 5.85, 0, math.sin(a) * 5.85))
  end
  m:append(MeshData.cylinder(2.2, 3, 0.6, 24, P.metal_dark), Vec3(0, -1.3, 0))
  for i = 0, 2 do
    local a = i / 3 * math.tau
    m:append(MeshData.cylinder(0.12, 0.12, 2.2, 6, P.metal), Vec3(math.cos(a) * 3, -1.8, math.sin(a) * 3), Quat.euler(math.cos(a) * 0.4, 0, -math.sin(a) * 0.4))
    m:append(MeshData.cylinder(0.5, 0.6, 0.15, 10, P.metal_dark), Vec3(math.cos(a) * 3.4, -2.8, math.sin(a) * 3.4))
  end
  return m:flat()
end

function Art.ship_dome() return dome(2.6, 0, Color.WHITE, 24) end

function Art.vending()
  local m = MeshData.box(1.2, 2.1, 0.9, Color.hex("#ff5d8a"))
  m:append(MeshData.box(0.8, 1.2, 0.05, Color.hex("#2b2433")), Vec3(-0.12, 0.25, -0.45))
  for row = 0, 3 do
    for col = 0, 2 do
      m:append(MeshData.capsule(0.06, 0.2, 6, ({ P.pill, P.white, P.bowtie })[col + 1]), Vec3(-0.38 + col * 0.26, 0.7 - row * 0.3, -0.48), Quat.euler(0, 0, math.pi / 2))
    end
  end
  m:append(MeshData.box(0.22, 0.6, 0.05, P.chrome), Vec3(0.42, 0.3, -0.46))
  m:append(MeshData.box(1.24, 0.3, 0.94, P.white), Vec3(0, 0.95, 0))
  m:append(MeshData.box(0.7, 0.2, 0.05, Color.hex("#2b2433")), Vec3(0, -0.75, -0.45))
  return m:flat()
end

-- Life-size fiberglass cow (roadside attraction). Heavy.
function Art.cow()
  local m = MeshData.box(1.6, 0.8, 0.75, P.white)
  m:paint_fn(function(x, y, z, r, g, b)
    if Noise.perlin2(x * 2.2 + 3, z * 2.2 + y * 2) > 0.15 then return 0.12, 0.12, 0.14 end
    return r, g, b
  end)
  for _, sx in ipairs({ -0.6, 0.6 }) do
    for _, sz in ipairs({ -0.25, 0.25 }) do m:append(MeshData.box(0.18, 0.6, 0.18, P.white), Vec3(sx, -0.65, sz)) end
  end
  m:append(MeshData.box(0.5, 0.45, 0.4, P.white), Vec3(1.0, 0.25, 0))
  m:append(MeshData.box(0.25, 0.2, 0.36, Color.hex("#f2a6b4")), Vec3(1.3, 0.12, 0))
  m:append(MeshData.box(0.1, 0.1, 0.6, P.sand_light), Vec3(1.0, 0.55, 0))
  return m:flat()
end

function Art.engine_block()
  local m = MeshData.box(0.9, 0.6, 0.7, P.metal)
  for i = 0, 3 do m:append(MeshData.cylinder(0.1, 0.1, 0.1, 8, P.metal_dark), Vec3(-0.3 + i * 0.2, 0.33, 0)) end
  m:append(MeshData.box(0.3, 0.3, 0.72, P.metal_dark), Vec3(0.45, -0.1, 0))
  return m:flat()
end

function Art.tire()
  local m = MeshData.torus(0.36, 0.15, 18, 8, P.ink)
  m:append(MeshData.cylinder(0.22, 0.22, 0.12, 12, P.chrome), Vec3(0, 0, 0), Quat.euler(math.pi / 2, 0, 0))
  m:transform(nil, Quat.euler(math.pi / 2, 0, 0))
  return m:flat()
end

-- A false-front Old West building. w x d footprint, h tall. Returns mesh (origin at floor centre, door facing -Z).
function Art.western_building(w, d, h, col, sign_col)
  local m = MeshData.box(w, h, d, col)
  m:transform(Vec3(0, h / 2, 0))
  m:paint_fn(function(x, y, z, r, g, b)
    local plank = math.floor(y * 3.5)
    local t = 0.88 + hash(plank, math.floor(x + z)) * 0.18
    return r * t, g * t, b * t
  end)
  m:append(MeshData.box(w + 0.4, 1.6, 0.2, col:darken(0.1)), Vec3(0, h + 0.7, -d / 2 + 0.05))   -- false front
  m:append(MeshData.box(w * 0.7, 0.7, 0.08, sign_col or P.wood_dark), Vec3(0, h + 0.6, -d / 2 - 0.1))
  m:append(MeshData.box(1.2, 2.2, 0.1, P.ink), Vec3(0, 1.1, -d / 2 - 0.01))                       -- door
  for _, s in ipairs({ -1, 1 }) do
    m:append(MeshData.box(1.0, 1.0, 0.08, Color.hex("#3b3440")), Vec3(s * w * 0.3, 1.6, -d / 2 - 0.01))
  end
  m:append(MeshData.box(w + 0.4, 0.12, 2.0, P.wood_dark), Vec3(0, 2.9, -d / 2 - 1.0))            -- porch roof
  for _, s in ipairs({ -1, 1 }) do m:append(MeshData.box(0.15, 2.9, 0.15, P.wood_dark), Vec3(s * (w / 2 + 0.05), 1.45, -d / 2 - 1.9)) end
  m:append(MeshData.box(w + 0.4, 0.2, 2.0, P.wood), Vec3(0, 0.1, -d / 2 - 1.0))                  -- boardwalk
  return m:flat()
end

return Art
