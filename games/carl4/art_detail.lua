-- Detailed hard-surface meshes: storefronts, the Bank of Rhyolite, the weigh-station booth, chain-link fencing,
-- crates, barrels, the lockbox, the vending machine and the A.S.S. These replace the simple versions in art.lua
-- (same names and conventions). Everything is real geometry so the cel shader's ink outlines pick it up.
local Art = require("art")
local P = Art.pal

local function hash(x, y)
  local n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
  return n - math.floor(n)
end

-- m:box(...) shorthand: append a box of size (sx, sy, sz) at pos with optional rotation.
local function box(m, sx, sy, sz, col, pos, rot) m:append(MeshData.box(sx, sy, sz, col), pos, rot) end
local function cyl(m, rt, rb, h, seg, col, pos, rot) m:append(MeshData.cylinder(rt, rb, h, seg, col), pos, rot) end

local glass = Color.hex("#2b3a4a")
local glass_hi = Color.hex("#6f8fa8")

------------------------------------------------------------------ crate
-- 1 m crate: framed edges, planked faces with gaps, a diagonal brace and steel corner caps.
function Art.crate()
  local m = MeshData()
  local wood, dark = P.wood, P.wood_dark
  box(m, 0.9, 0.9, 0.9, dark:darken(0.25), Vec3())             -- core (shows in the plank gaps)
  -- Planks on each face (4 per face, alternating shade).
  for face = 0, 5 do
    local rot = ({ Quat(), Quat.euler(0, math.pi, 0), Quat.euler(0, math.pi / 2, 0), Quat.euler(0, -math.pi / 2, 0),
      Quat.euler(math.pi / 2, 0, 0), Quat.euler(-math.pi / 2, 0, 0) })[face + 1]
    for i = 0, 3 do
      local shade = 0.9 + hash(face, i) * 0.2
      local c = Color(wood.r * shade, wood.g * shade, wood.b * shade)
      box(m, 0.8, 0.19, 0.04, c, rot * Vec3(0, -0.3 + i * 0.2, 0.465), rot)
    end
    if face < 4 then
      -- Diagonal brace.
      box(m, 1.02, 0.11, 0.05, dark, rot * Vec3(0, 0, 0.49), rot * Quat.euler(0, 0, 0.785))
    end
  end
  -- Edge frame.
  for _, sx in ipairs({ -1, 1 }) do
    for _, sz in ipairs({ -1, 1 }) do
      box(m, 0.12, 1.0, 0.12, dark, Vec3(sx * 0.45, 0, sz * 0.45))
      box(m, 1.0, 0.12, 0.12, dark, Vec3(0, sx * 0.45, sz * 0.45))
      box(m, 0.12, 0.12, 1.0, dark, Vec3(sx * 0.45, sz * 0.45, 0))
    end
  end
  -- Steel corner caps.
  for _, sx in ipairs({ -1, 1 }) do
    for _, sy in ipairs({ -1, 1 }) do
      for _, sz in ipairs({ -1, 1 }) do box(m, 0.16, 0.16, 0.16, P.metal, Vec3(sx * 0.455, sy * 0.455, sz * 0.455)) end
    end
  end
  return m:flat()
end

------------------------------------------------------------------ barrels
local function barrel_shell(col, rib)
  local m = MeshData.cylinder(0.4, 0.4, 1.1, 20, col)
  m:paint_fn(function(x, y, z, r, g, b)
    local t = 0.94 + hash(math.floor(math.atan2(x, z) * 3), 1) * 0.1
    return r * t, g * t, b * t
  end)
  for _, y in ipairs({ -0.3, 0.3 }) do m:append(MeshData.torus(0.405, 0.025, 20, 4, rib), Vec3(0, y, 0)) end
  for _, y in ipairs({ -0.54, 0.54 }) do m:append(MeshData.torus(0.395, 0.03, 20, 4, rib), Vec3(0, y, 0)) end
  cyl(m, 0.36, 0.36, 0.02, 18, col:darken(0.2), Vec3(0, 0.545, 0))      -- recessed lid
  cyl(m, 0.06, 0.06, 0.05, 8, rib, Vec3(0.2, 0.57, 0.08))                -- bung
  cyl(m, 0.035, 0.035, 0.04, 8, rib, Vec3(-0.22, 0.565, -0.05))          -- vent
  return m
end

function Art.barrel(col, band)
  local m = barrel_shell(col, band)
  -- Stencilled white label panel.
  box(m, 0.36, 0.26, 0.02, P.white, Vec3(0, 0.02, -0.4))
  box(m, 0.24, 0.04, 0.025, P.ink, Vec3(0, 0.06, -0.405))
  box(m, 0.18, 0.04, 0.025, P.ink, Vec3(0, -0.02, -0.405))
  return m:flat()
end

-- Red "PROP PILLS — HIGHLY FLAMMABLE" barrel: white band, big pill decal, hazard diamond on the back.
function Art.explosive_barrel()
  local m = barrel_shell(P.red, Color.hex("#7a1e1a"))
  cyl(m, 0.41, 0.41, 0.2, 20, P.white, Vec3(0, 0, 0))
  m:append(MeshData.capsule(0.075, 0.3, 8, P.pill), Vec3(0, 0, -0.42), Quat.euler(0, 0, math.pi / 2))
  box(m, 0.16, 0.16, 0.03, P.white, Vec3(0.05, 0, -0.43), Quat.euler(0, 0, 0))
  box(m, 0.3, 0.3, 0.03, P.line_yellow, Vec3(0, 0.32, 0.41), Quat.euler(0, 0, 0.785))
  box(m, 0.2, 0.2, 0.035, P.ink, Vec3(0, 0.32, 0.415), Quat.euler(0, 0, 0.785))
  box(m, 0.07, 0.12, 0.04, Color.hex("#ff8a3a"), Vec3(0, 0.32, 0.42))
  return m:flat()
end

------------------------------------------------------------------ lockbox
-- Lost & Found lockbox: plinth, straps, corner caps, side handles, a glowing lock and a rounded lid.
function Art.chest(accent)
  local m = MeshData()
  local body, dark = P.metal, P.metal_dark
  box(m, 1.16, 0.08, 0.76, dark, Vec3(0, -0.26, 0))                      -- plinth
  box(m, 1.1, 0.48, 0.7, body, Vec3(0, 0.02, 0))
  for _, sx in ipairs({ -0.36, 0.36 }) do box(m, 0.12, 0.5, 0.74, accent, Vec3(sx, 0.02, 0)) end
  for _, sx in ipairs({ -1, 1 }) do
    for _, sz in ipairs({ -1, 1 }) do box(m, 0.08, 0.52, 0.08, dark, Vec3(sx * 0.55, 0.02, sz * 0.35)) end
    -- Handle.
    box(m, 0.05, 0.06, 0.3, P.chrome, Vec3(sx * 0.61, 0.1, 0))
    box(m, 0.07, 0.14, 0.05, dark, Vec3(sx * 0.58, 0.1, -0.13))
    box(m, 0.07, 0.14, 0.05, dark, Vec3(sx * 0.58, 0.1, 0.13))
  end
  -- Lock plate with a glowing slot.
  box(m, 0.26, 0.24, 0.05, P.gold, Vec3(0, 0.1, -0.37))
  box(m, 0.14, 0.05, 0.06, accent:lighten(0.3), Vec3(0, 0.14, -0.38))
  box(m, 0.05, 0.08, 0.06, P.ink, Vec3(0, 0.04, -0.38))
  -- Lid: a shallow barrel vault, hinged at the back (pivot convention from art.lua: centred at z = 0.36).
  local lid = MeshData()
  local half = MeshData.cylinder(0.36, 0.36, 1.12, 16, P.metal_dark)
  half:transform(nil, Quat.euler(0, 0, math.pi / 2))
  half:transform(nil, nil, Vec3(1, 0.45, 1))
  lid:append(half, Vec3(0, 0.0, 0))
  for _, sx in ipairs({ -0.36, 0.36 }) do
    local strap = MeshData.cylinder(0.375, 0.375, 0.12, 16, accent)
    strap:transform(nil, Quat.euler(0, 0, math.pi / 2))
    strap:transform(nil, nil, Vec3(1, 0.47, 1))
    lid:append(strap, Vec3(sx, 0, 0))
  end
  box(lid, 1.14, 0.06, 0.74, dark, Vec3(0, -0.02, 0))
  -- Keep only the top half visible: the bottom half sits inside the box.
  lid:transform(Vec3(0, 0.12, 0.36))
  return m:flat(), lid:flat()
end

------------------------------------------------------------------ vending machine
function Art.vending()
  local m = MeshData()
  local pink, pink_dark = Color.hex("#ff5d8a"), Color.hex("#c23a64")
  box(m, 1.2, 2.1, 0.9, pink, Vec3())
  box(m, 1.24, 0.08, 0.94, pink_dark, Vec3(0, -1.02, 0))
  for _, sx in ipairs({ -0.5, 0.5 }) do box(m, 0.14, 0.08, 0.14, P.metal_dark, Vec3(sx, -1.09, 0)) end   -- feet
  -- Lit header with the pill logo.
  box(m, 1.16, 0.34, 0.06, P.white, Vec3(0, 0.86, -0.46))
  m:append(MeshData.capsule(0.09, 0.42, 10, pink), Vec3(-0.06, 0.86, -0.5), Quat.euler(0, 0, math.pi / 2))
  box(m, 0.02, 0.18, 0.02, P.white, Vec3(-0.06, 0.86, -0.59))
  -- Window bezel, glass, shelves and stock.
  box(m, 0.86, 1.26, 0.04, pink_dark, Vec3(-0.12, 0.08, -0.455))
  for _, sx in ipairs({ -0.53, 0.29 }) do box(m, 0.06, 1.26, 0.12, pink_dark, Vec3(sx, 0.08, -0.5)) end
  for _, sy in ipairs({ -0.55, 0.71 }) do box(m, 0.88, 0.06, 0.12, pink_dark, Vec3(-0.12, sy, -0.5)) end
  box(m, 0.78, 1.16, 0.012, Color.hex("#1c1626"), Vec3(-0.12, 0.08, -0.481))    -- dark interior
  for row = 0, 3 do
    local y = 0.5 - row * 0.28
    box(m, 0.74, 0.025, 0.1, P.chrome, Vec3(-0.12, y - 0.1, -0.47))
    for col = 0, 3 do
      local c = ({ P.pill, P.white, P.bowtie, Color.hex("#7fd0ff") })[(row + col) % 4 + 1]
      m:append(MeshData.capsule(0.05, 0.16, 6, c), Vec3(-0.4 + col * 0.19, y - 0.03, -0.49), Quat.euler(0, 0, math.pi / 2))
      box(m, 0.02, 0.06, 0.06, P.chrome, Vec3(-0.4 + col * 0.19, y - 0.13, -0.5))                  -- spiral coil end
    end
  end
  box(m, 0.25, 0.02, 0.01, Color.hex("#cfe8ff"), Vec3(-0.05, 0.42, -0.545), Quat.euler(0, 0, -0.5))
  -- Control column: price screen, keypad, coin slot.
  box(m, 0.22, 1.26, 0.04, pink_dark, Vec3(0.43, 0.08, -0.46))
  box(m, 0.16, 0.12, 0.03, Color.hex("#1a2a1e"), Vec3(0.43, 0.55, -0.48))
  box(m, 0.12, 0.03, 0.035, Color.hex("#7dff6a"), Vec3(0.43, 0.56, -0.49))
  for r = 0, 3 do
    for c = 0, 2 do box(m, 0.04, 0.04, 0.03, P.chrome, Vec3(0.39 + c * 0.04, 0.38 - r * 0.05, -0.48)) end
  end
  box(m, 0.1, 0.14, 0.03, P.metal_dark, Vec3(0.43, 0.1, -0.48))
  box(m, 0.02, 0.08, 0.035, P.ink, Vec3(0.43, 0.1, -0.49))
  -- Delivery flap.
  box(m, 0.8, 0.26, 0.05, P.metal_dark, Vec3(-0.08, -0.74, -0.46))
  box(m, 0.72, 0.18, 0.03, P.ink, Vec3(-0.08, -0.74, -0.48))
  -- Side vents.
  for _, sx in ipairs({ -1, 1 }) do
    for i = 0, 4 do box(m, 0.02, 0.04, 0.5, pink_dark, Vec3(sx * 0.605, -0.5 + i * 0.09, 0)) end
  end
  return m:flat()
end

------------------------------------------------------------------ the A.S.S.
-- The saucer with panel seams, scorch, an underside engine ring, landing struts, a hatch and an antenna.
function Art.ship()
  local m = MeshData()
  local disc = MeshData.sphere(6, 48, 18, P.chrome)
  disc:transform(nil, nil, Vec3(1, 0.22, 1))
  disc:paint_fn(function(x, y, z, r, g, b)
    local d = math.sqrt(x * x + z * z)
    if d > 5.2 and d < 5.6 then return P.carl_skin.r, P.carl_skin.g, P.carl_skin.b end
    if math.abs(y) < 0.12 then return P.metal.r, P.metal.g, P.metal.b end
    -- Scorch from the crash on one side.
    local burn = Noise.perlin2(x * 0.35 + 4, z * 0.35) + (x + z) * 0.05
    if burn > 0.28 then local k = burn > 0.45 and 0.35 or 0.6 return r * k, g * k, b * k end
    local t = 0.9 + hash(math.floor(x * 0.8), math.floor(z * 0.8)) * 0.12
    return r * t, g * t, b * t
  end)
  m:append(disc)
  -- Panel seams: concentric rings on the top and bottom shells.
  for _, d in ipairs({ 3.1, 4.4 }) do
    local y = 0.22 * math.sqrt(36 - d * d)
    local ring = MeshData.torus(d, 0.06, 40, 4, P.metal)
    m:append(ring, Vec3(0, y - 0.02, 0))
    m:append(MeshData.torus(d, 0.06, 40, 4, P.metal), Vec3(0, -(y - 0.02), 0))
  end
  -- Radial seams between them.
  for i = 0, 11 do
    local a = i / 12 * math.tau
    local d = 3.75
    local y = 0.22 * math.sqrt(36 - d * d)
    box(m, 0.08, 0.06, 1.35, P.metal, Vec3(math.cos(a) * d, y + 0.02, math.sin(a) * d), Quat.from_y(-a + math.pi / 2) * Quat.euler(0.12, 0, 0))
  end
  -- Dome collar and a hatch.
  m:append(MeshData.torus(2.65, 0.14, 36, 6, P.metal_dark), Vec3(0, 1.0, 0))
  box(m, 1.2, 0.12, 0.9, P.metal_dark, Vec3(3.5, 0.95, 0), Quat.euler(0, 0, -0.2))
  box(m, 0.3, 0.08, 0.12, P.chrome, Vec3(3.2, 1.06, 0), Quat.euler(0, 0, -0.2))
  -- Rim lights.
  for i = 0, 17 do
    local a = i / 18 * math.tau
    m:append(MeshData.sphere(0.2, 8, 6, Color.hex("#7dffb0")), Vec3(math.cos(a) * 5.88, 0, math.sin(a) * 5.88))
  end
  -- Underside: engine housing with vents, a glow ring is added as its own node in places.lua.
  cyl(m, 2.2, 3, 0.6, 28, P.metal_dark, Vec3(0, -1.3, 0))
  cyl(m, 1.6, 1.8, 0.2, 24, P.metal, Vec3(0, -1.65, 0))
  for i = 0, 11 do
    local a = i / 12 * math.tau
    box(m, 0.12, 0.45, 0.5, P.metal, Vec3(math.cos(a) * 2.7, -1.3, math.sin(a) * 2.7), Quat.from_y(-a))
  end
  -- Landing struts with feet and pistons.
  for i = 0, 2 do
    local a = i / 3 * math.tau + 0.3
    local tilt = Quat.euler(math.cos(a) * 0.4, 0, -math.sin(a) * 0.4)
    cyl(m, 0.14, 0.14, 2.2, 8, P.metal, Vec3(math.cos(a) * 3, -1.8, math.sin(a) * 3), tilt)
    cyl(m, 0.09, 0.09, 1.2, 8, P.chrome, Vec3(math.cos(a) * 3.25, -2.3, math.sin(a) * 3.25), tilt)
    cyl(m, 0.5, 0.6, 0.15, 12, P.metal_dark, Vec3(math.cos(a) * 3.4, -2.8, math.sin(a) * 3.4))
  end
  -- Bent antenna.
  cyl(m, 0.04, 0.05, 1.6, 6, P.chrome, Vec3(-4.2, 1.4, 1.5), Quat.euler(0.3, 0, 0.5))
  m:append(MeshData.sphere(0.12, 8, 6, Color.hex("#ff5d8a")), Vec3(-4.6, 2.1, 1.75))
  return m:flat()
end

------------------------------------------------------------------ western storefronts
-- False-front Old West building: lap siding, framed windows with muntins, panelled door, porch with brackets,
-- boardwalk planks, cornice trim and a framed sign board. Origin at floor centre, door facing -Z.
function Art.western_building(w, d, h, col, sign_col)
  local m = MeshData()
  local trim = col:darken(0.28)
  local front = -d / 2
  box(m, w, h, d, col:darken(0.08), Vec3(0, h / 2, 0))
  -- Lap siding on the front and sides: overlapping boards.
  local boards = math.floor(h / 0.3)
  for i = 0, boards - 1 do
    local y = 0.15 + i * 0.3
    local shade = 0.92 + hash(i, w) * 0.14
    local c = Color(col.r * shade, col.g * shade, col.b * shade)
    box(m, w + 0.02, 0.26, 0.05, c, Vec3(0, y, front - 0.02), Quat.euler(-0.08, 0, 0))
    for _, sx in ipairs({ -1, 1 }) do box(m, 0.05, 0.26, d - 0.1, c, Vec3(sx * (w / 2 + 0.02), y, 0), Quat.euler(0, 0, sx * 0.08)) end
  end
  -- Corner boards.
  for _, sx in ipairs({ -1, 1 }) do
    box(m, 0.2, h + 0.05, 0.2, trim, Vec3(sx * w / 2, h / 2, front))
    box(m, 0.2, h + 0.05, 0.2, trim, Vec3(sx * w / 2, h / 2, d / 2))
  end
  -- Pitched roof behind the false front.
  local roof = MeshData.box(w + 0.3, 0.14, d * 0.56, P.wood_dark)
  m:append(roof, Vec3(0, h + 0.45, -d * 0.22), Quat.euler(0.32, 0, 0))
  m:append(roof, Vec3(0, h + 0.45, d * 0.22), Quat.euler(-0.32, 0, 0))
  -- False front with cornice and a framed sign board.
  box(m, w + 0.4, 1.7, 0.2, col:darken(0.12), Vec3(0, h + 0.75, front + 0.05))
  box(m, w + 0.7, 0.18, 0.4, trim, Vec3(0, h + 1.65, front + 0.02))
  box(m, w + 0.55, 0.1, 0.32, trim:lighten(0.1), Vec3(0, h + 1.52, front + 0.02))
  for i = -2, 2 do box(m, 0.12, 0.16, 0.1, trim, Vec3(i * (w + 0.3) / 5, h + 1.43, front - 0.1)) end    -- dentils
  box(m, w * 0.74, 0.8, 0.08, trim, Vec3(0, h + 0.62, front - 0.11))
  box(m, w * 0.7, 0.68, 0.06, sign_col or Color.hex("#3b2a1d"), Vec3(0, h + 0.62, front - 0.15))
  -- Door: frame, two panels, knob, transom.
  box(m, 1.5, 2.5, 0.12, trim, Vec3(0, 1.25, front - 0.04))
  box(m, 1.2, 2.2, 0.06, P.wood_dark, Vec3(0, 1.1, front - 0.08))
  for _, y in ipairs({ 0.6, 1.55 }) do box(m, 0.85, 0.65, 0.05, P.wood_dark:darken(0.2), Vec3(0, y, front - 0.11)) end
  cyl(m, 0.05, 0.05, 0.06, 8, P.gold, Vec3(0.42, 1.1, front - 0.14), Quat.euler(math.pi / 2, 0, 0))
  box(m, 1.2, 0.3, 0.05, glass, Vec3(0, 2.38, front - 0.08))
  -- Windows either side: frame, sill, glass, muntins, a glare stripe.
  for _, s in ipairs({ -1, 1 }) do
    local wx = s * w * 0.3
    box(m, 1.25, 1.35, 0.1, trim, Vec3(wx, 1.65, front - 0.05))
    box(m, 1.05, 1.15, 0.05, glass, Vec3(wx, 1.65, front - 0.09))
    box(m, 0.06, 1.15, 0.07, trim, Vec3(wx, 1.65, front - 0.1))
    box(m, 1.05, 0.06, 0.07, trim, Vec3(wx, 1.65, front - 0.1))
    box(m, 1.4, 0.1, 0.22, trim, Vec3(wx, 0.95, front - 0.12))
    box(m, 0.5, 0.06, 0.02, glass_hi, Vec3(wx - 0.2, 1.95, front - 0.12), Quat.euler(0, 0, -0.6))
    -- Shutters.
    for _, k in ipairs({ -1, 1 }) do
      box(m, 0.36, 1.3, 0.05, col:darken(0.35), Vec3(wx + k * 0.82, 1.65, front - 0.06))
      for j = 0, 4 do box(m, 0.3, 0.04, 0.06, col:darken(0.45), Vec3(wx + k * 0.82, 1.15 + j * 0.25, front - 0.08)) end
    end
  end
  -- Porch: roof, posts with brackets, boardwalk planks, a step and a hitching rail.
  box(m, w + 0.4, 0.12, 2.1, P.wood_dark, Vec3(0, 2.95, front - 1.0), Quat.euler(-0.05, 0, 0))
  box(m, w + 0.5, 0.18, 0.12, trim, Vec3(0, 2.86, front - 2.02))
  for _, s in ipairs({ -1, -0.33, 0.33, 1 }) do
    local px = s * (w / 2 + 0.05)
    box(m, 0.16, 2.9, 0.16, P.wood_dark, Vec3(px, 1.45, front - 1.9))
    box(m, 0.08, 0.5, 0.5, P.wood_dark, Vec3(px, 2.6, front - 1.7), Quat.euler(0.785, 0, 0))
  end
  for i = 0, 7 do
    local shade = 0.85 + hash(i, 3) * 0.2
    box(m, w + 0.4, 0.12, 0.24, Color(P.wood.r * shade, P.wood.g * shade, P.wood.b * shade), Vec3(0, 0.12, front - 0.15 - i * 0.255))
  end
  box(m, w * 0.4, 0.1, 0.4, P.wood_dark, Vec3(0, 0.05, front - 2.25))
  box(m, w * 0.5, 0.08, 0.08, P.wood_dark, Vec3(w * 0.15, 0.9, front - 2.9))
  for _, s in ipairs({ -1, 1 }) do box(m, 0.1, 0.9, 0.1, P.wood_dark, Vec3(w * 0.15 + s * w * 0.24, 0.45, front - 2.9)) end
  return m:flat()
end

------------------------------------------------------------------ Bank of Rhyolite
-- Stone bank shell (sides, back, roof, parapet, pilasters, cornice, arched side windows, steps). The open front is
-- filled by the breakable vault panels. Origin at floor centre, front facing -Z.
function Art.bank(W, D, H)
  local m = MeshData()
  local stone = Color.hex("#c7b394")
  local stone_dark = Color.hex("#9e8a6c")
  local stone_light = Color.hex("#dccaa8")
  -- Rusticated block courses on the side and back walls.
  local course = 0.5
  for j = 0, math.floor(H / course) - 1 do
    local y = course * (j + 0.5)
    local off = (j % 2) * 0.6
    for _, side in ipairs({ -1, 1 }) do
      local x = side * W / 2
      local n = math.floor(D / 1.2)
      for i = 0, n - 1 do
        local z = -D / 2 + (i + 0.5) * (D / n) + (off - 0.3) * 0.0
        local sh = 0.9 + hash(i + side * 7, j) * 0.18
        box(m, 0.6, course - 0.05, D / n - 0.05, Color(stone.r * sh, stone.g * sh, stone.b * sh), Vec3(x, y, z))
      end
    end
    local nb = math.floor(W / 1.25)
    for i = 0, nb - 1 do
      local sh = 0.9 + hash(i, j + 20) * 0.18
      box(m, W / nb - 0.05, course - 0.05, 0.6, Color(stone.r * sh, stone.g * sh, stone.b * sh), Vec3(-W / 2 + (i + 0.5) * W / nb, y, D / 2))
    end
  end
  box(m, W - 0.2, H - 0.1, D - 0.2, stone_dark, Vec3(0, H / 2, 0))     -- mortar core
  -- Roof slab, cornice and parapet.
  box(m, W + 0.6, 0.5, D + 0.6, stone_dark, Vec3(0, H + 0.25, 0))
  box(m, W + 1.0, 0.22, D + 1.0, stone_light, Vec3(0, H + 0.05, 0))
  box(m, W + 0.8, 0.16, D + 0.8, stone_light, Vec3(0, H + 0.55, 0))
  for i = 0, 15 do box(m, 0.2, 0.2, 0.2, stone_light, Vec3(-W / 2 + 0.3 + i * (W - 0.6) / 15, H - 0.12, -D / 2 - 0.45)) end   -- dentils
  -- Front parapet with a stepped pediment and a date stone.
  box(m, W + 0.8, 1.7, 0.45, stone, Vec3(0, H + 1.4, -D / 2 + 0.1))
  box(m, W * 0.5, 0.6, 0.45, stone, Vec3(0, H + 2.5, -D / 2 + 0.1))
  box(m, W * 0.24, 0.5, 0.45, stone, Vec3(0, H + 3.0, -D / 2 + 0.1))
  box(m, W + 1.0, 0.16, 0.6, stone_light, Vec3(0, H + 2.28, -D / 2 + 0.1))
  box(m, W * 0.54, 0.14, 0.6, stone_light, Vec3(0, H + 2.84, -D / 2 + 0.1))
  box(m, 1.4, 0.4, 0.1, stone_light, Vec3(0, H + 3.0, -D / 2 - 0.16))
  box(m, W * 0.82, 0.9, 0.1, Color.hex("#3b2a1d"), Vec3(0, H + 1.3, -D / 2 - 0.16))           -- sign board
  box(m, W * 0.86, 1.0, 0.06, P.gold, Vec3(0, H + 1.3, -D / 2 - 0.12))
  -- Pilasters framing the vault, with bases and capitals.
  for _, s in ipairs({ -1, 1 }) do
    local px = s * (W / 2 + 0.05)
    box(m, 0.9, H, 0.7, stone_light, Vec3(px, H / 2, -D / 2 - 0.1))
    box(m, 1.1, 0.4, 0.9, stone, Vec3(px, 0.2, -D / 2 - 0.1))
    box(m, 1.15, 0.25, 0.95, stone, Vec3(px, H - 0.25, -D / 2 - 0.1))
    for k = 0, 3 do box(m, 0.1, H - 1.0, 0.06, stone_dark, Vec3(px - 0.3 + k * 0.2, H / 2, -D / 2 - 0.47)) end    -- fluting
  end
  box(m, W + 0.4, 0.45, 0.7, stone_light, Vec3(0, H - 0.05, -D / 2 - 0.1))                      -- lintel
  -- Arched windows down each side with bars.
  for _, side in ipairs({ -1, 1 }) do
    for _, z in ipairs({ -D * 0.22, D * 0.22 }) do
      local x = side * (W / 2 + 0.3)
      box(m, 0.12, 1.6, 1.0, Color.hex("#1d1a24"), Vec3(x, 2.4, z))
      m:append(MeshData.cylinder(0.5, 0.5, 0.12, 12, Color.hex("#1d1a24")), Vec3(x, 3.2, z), Quat.euler(0, 0, math.pi / 2))
      m:append(MeshData.torus(0.58, 0.09, 14, 4, stone_light), Vec3(x + side * 0.02, 3.2, z), Quat.euler(0, 0, math.pi / 2))
      box(m, 0.25, 0.14, 1.3, stone_light, Vec3(x, 1.55, z))
      box(m, 0.18, 0.3, 0.22, stone_light, Vec3(x + side * 0.03, 3.72, z))                     -- keystone
      for b = -1, 1 do box(m, 0.05, 2.0, 0.05, P.metal_dark, Vec3(x + side * 0.05, 2.6, z + b * 0.28)) end
    end
  end
  -- Steps.
  for i = 0, 2 do box(m, W + 1.4 - i * 0.4, 0.18, 0.5, stone_light:darken(i * 0.04), Vec3(0, 0.09 + i * 0.0, -D / 2 - 0.75 - (2 - i) * 0.5 + 0.5)) end
  -- Gas lamps on the pilasters.
  for _, s in ipairs({ -1, 1 }) do
    local px = s * (W / 2 + 0.05)
    box(m, 0.08, 0.5, 0.08, P.metal_dark, Vec3(px, 3.3, -D / 2 - 0.6))
    box(m, 0.3, 0.4, 0.3, Color.hex("#ffe08a"), Vec3(px, 3.0, -D / 2 - 0.85))
    box(m, 0.38, 0.08, 0.38, P.metal_dark, Vec3(px, 3.24, -D / 2 - 0.85))
  end
  return m:flat()
end

-- A vault panel in unit size (scaled by the breakable): riveted steel with a raised border and a hazard band.
function Art.vault_panel()
  local m = MeshData()
  box(m, 1, 1, 1, Color.hex("#8d939e"), Vec3())
  local rim = Color.hex("#6a707c")
  box(m, 1.0, 0.1, 1.06, rim, Vec3(0, 0.45, 0))
  box(m, 1.0, 0.1, 1.06, rim, Vec3(0, -0.45, 0))
  box(m, 0.07, 1.0, 1.06, rim, Vec3(0.465, 0, 0))
  box(m, 0.07, 1.0, 1.06, rim, Vec3(-0.465, 0, 0))
  for i = 0, 5 do
    local x = -0.4 + i * 0.16
    for _, y in ipairs({ -0.45, 0.45 }) do box(m, 0.04, 0.05, 1.1, Color.hex("#b8bec8"), Vec3(x, y, 0)) end
  end
  box(m, 0.6, 0.08, 1.04, P.line_yellow, Vec3(0, 0.0, 0))
  for i = 0, 3 do box(m, 0.06, 0.08, 1.05, P.ink, Vec3(-0.24 + i * 0.16, 0.0, 0), Quat.euler(0, 0, 0.6)) end
  return m:flat()
end

------------------------------------------------------------------ weigh station booth
-- Scale-house booth: siding, wraparound windows, a door, a flat roof with overhang, AC unit and a red stripe.
function Art.weigh_booth()
  local m = MeshData()
  local wall_c = Color.hex("#e3dccb")
  box(m, 4, 3, 3, wall_c, Vec3(0, 1.5, 0))
  for i = 0, 9 do box(m, 4.04, 0.04, 3.04, wall_c:darken(0.12), Vec3(0, 0.15 + i * 0.3, 0)) end    -- siding lines
  box(m, 4.06, 0.25, 3.06, P.red, Vec3(0, 0.55, 0))
  -- Window band on three sides.
  for _, f in ipairs({ { Vec3(0, 2.0, -1.53), Vec3(3.2, 0.9, 0.06) }, { Vec3(-2.03, 2.0, 0), Vec3(0.06, 0.9, 2.2) }, { Vec3(2.03, 2.0, 0), Vec3(0.06, 0.9, 2.2) } }) do
    box(m, f[2].x + 0.14, f[2].y + 0.14, f[2].z + 0.14, P.metal_dark, f[1])
    box(m, f[2].x, f[2].y, f[2].z + 0.02, glass, f[1])
  end
  for i = -1, 1 do box(m, 0.06, 0.9, 0.1, P.metal_dark, Vec3(i * 1.05, 2.0, -1.55)) end
  -- Door on the back.
  box(m, 0.9, 2.1, 0.08, P.metal, Vec3(1.0, 1.05, 1.53))
  box(m, 0.5, 0.4, 0.09, glass, Vec3(1.0, 1.6, 1.54))
  -- Roof.
  box(m, 4.8, 0.22, 3.8, P.metal_dark, Vec3(0, 3.1, 0))
  box(m, 4.9, 0.1, 3.9, P.red, Vec3(0, 3.0, 0))
  box(m, 1.1, 0.55, 0.8, P.chrome, Vec3(-1.0, 3.48, 0.5))
  for i = 0, 4 do box(m, 0.9, 0.04, 0.04, P.metal, Vec3(-1.0, 3.3 + i * 0.08, 0.1)) end
  cyl(m, 0.06, 0.06, 1.2, 6, P.metal, Vec3(1.6, 3.8, 1.2))
  return m:flat()
end

-- Diamond-plate scale deck with hazard edges, 6 x 4.
function Art.scale_deck()
  local m = MeshData()
  box(m, 6, 0.16, 4, Color.hex("#7d8590"), Vec3())
  for i = 0, 11 do
    for j = 0, 7 do
      if (i + j) % 2 == 0 then box(m, 0.18, 0.03, 0.06, Color.hex("#9aa2ad"), Vec3(-2.75 + i * 0.5, 0.09, -1.75 + j * 0.5), Quat.euler(0, 0.6, 0)) end
    end
  end
  for _, s in ipairs({ -1, 1 }) do
    for i = 0, 7 do
      box(m, 0.2, 0.18, 0.5, i % 2 == 0 and P.line_yellow or P.ink, Vec3(s * 3.0, 0.02, -1.75 + i * 0.5))
    end
  end
  return m:flat()
end

------------------------------------------------------------------ chain-link fencing
-- Chain-link texture (alpha-tested) for fence panels.
function Art.chainlink_texture()
  return Texture.generate(64, 64, function(x, y)
    local u, v = (x + y) % 16, (x - y + 64) % 16
    local wire = u < 2 or v < 2
    if wire then return Color(0.75, 0.77, 0.8, 1) end
    return Color(0, 0, 0, 0)
  end)
end

-- Posts, top rail and barbed wire for a fence run of length len along +X, height h. Origin at the bottom-left end.
function Art.fence_frame(len, h)
  local m = MeshData()
  local posts = math.max(1, math.floor(len / 2.5))
  for i = 0, posts do
    local x = i * len / posts
    cyl(m, 0.06, 0.06, h + 0.3, 8, P.chrome, Vec3(x, (h + 0.3) / 2, 0))
    cyl(m, 0.08, 0.08, 0.05, 8, P.metal, Vec3(x, h + 0.32, 0))
    box(m, 0.05, 0.5, 0.05, P.metal, Vec3(x, h + 0.5, -0.12), Quat.euler(-0.5, 0, 0))
  end
  cyl(m, 0.04, 0.04, len, 6, P.chrome, Vec3(len / 2, h, 0), Quat.euler(0, 0, math.pi / 2))
  cyl(m, 0.03, 0.03, len, 6, P.chrome, Vec3(len / 2, 0.15, 0), Quat.euler(0, 0, math.pi / 2))
  for _, k in ipairs({ 0.35, 0.6 }) do
    cyl(m, 0.012, 0.012, len, 4, P.metal_dark, Vec3(len / 2, h + k, -0.12 - k * 0.3), Quat.euler(0, 0, math.pi / 2))
  end
  return m:flat()
end

return Art
