-- Detailed procedural guns. Each manufacturer has its own look; rarity paints the accent stripe and
-- elemental guns get glowing vents. Forward is -Z, the grip sits at the origin (where the hand holds it).
-- Returns body, slide and magazine as separate meshes so the slide can kick and the mag can drop.
local Art = require("art")
local P = Art.pal
local GunArt = {}

local function C(h) return Color.hex(h) end
local SCHEMES = {
  ["Pretend Co."] = { body = C("#5b3f8a"), dark = C("#2b2140"), trim = C("#e7b53b"), grip = C("#1d1c24"), style = "toy" },
  ["Prop Pills Arms"] = { body = C("#f2efe6"), dark = C("#b8342e"), trim = C("#d8433b"), grip = C("#3a3a42"), style = "pill" },
  ["Mall of the Future"] = { body = C("#c9ced6"), dark = C("#3b4250"), trim = C("#4ff0d8"), grip = C("#23262e"), style = "sleek" },
  ["Sequel Committee Surplus"] = { body = C("#5f6a3e"), dark = C("#2f3524"), trim = C("#c9b46a"), grip = C("#7d5631"), style = "surplus" },
  ["Garf's"] = { body = C("#e0782e"), dark = C("#6e3a1e"), trim = C("#d8433b"), grip = C("#b98952"), style = "diner" },
  ["Postal Service"] = { body = C("#2a3f7a"), dark = C("#151d38"), trim = C("#f5f3ec"), grip = C("#1b1720"), style = "postal" },
}
GunArt.SCHEMES = SCHEMES

local function box(m, w, h, d, col, pos, rot) m:append(MeshData.box(w, h, d, col), pos, rot) end
local function tube(m, r, len, col, pos, seg, r2)
  m:append(MeshData.cylinder(r2 or r, r, len, seg or 12, col), pos, Quat.euler(math.pi / 2, 0, 0))
end
local function ring(m, R, r, col, pos) m:append(MeshData.torus(R, r, 14, 6, col), pos, Quat.euler(math.pi / 2, 0, 0)) end
local function screw(m, col, x, y, z) m:append(MeshData.cylinder(0.008, 0.008, 0.006, 6, col), Vec3(x, y, z), Quat.euler(0, 0, math.pi / 2)) end

-- Grip with finger grooves and a trigger guard + trigger in front of it.
local function grip(m, s, len, tilt, z)
  local g = MeshData.box(0.05, len, 0.075, s.grip)
  g:paint_fn(function(x, y, zz, r, gg, b)
    if zz < -0.03 and math.floor((y + 1) * 40) % 3 == 0 then return r * 0.6, gg * 0.6, b * 0.6 end   -- grooves
    if math.abs(x) > 0.02 and math.floor((y + 1) * 60 + zz * 60) % 2 == 0 then return r * 0.8, gg * 0.8, b * 0.8 end  -- stipple
    return r, gg, b
  end)
  m:append(g, Vec3(0, -len / 2 + 0.01, z or 0.02), Quat.euler(-tilt, 0, 0))
  box(m, 0.054, 0.02, 0.08, s.dark, Vec3(0, -len + 0.01, (z or 0.02) + len * math.sin(tilt) * 0.9), Quat.euler(-tilt, 0, 0))  -- base plate
  local guard = MeshData.torus(0.04, 0.007, 16, 5, s.dark)
  guard:displace(function(x, y, zz) if zz > 0 then return 0, 0, -zz end end)
  m:append(guard, Vec3(0, -0.02, -0.05), Quat.euler(0, math.pi / 2, 0))
  box(m, 0.012, 0.035, 0.012, P.metal_dark, Vec3(0, -0.025, -0.045), Quat.euler(-0.3, 0, 0))
end

local function sights(m, s, z_front, z_rear, y)
  box(m, 0.012, 0.025, 0.02, s.dark, Vec3(0, y + 0.012, z_front))
  box(m, 0.006, 0.006, 0.006, s.trim, Vec3(0, y + 0.026, z_front))
  for _, sx in ipairs({ -1, 1 }) do box(m, 0.012, 0.022, 0.018, s.dark, Vec3(sx * 0.016, y + 0.011, z_rear)) end
end

local function vents(m, col, x, y, z0, n, step)
  for i = 0, n - 1 do box(m, 0.006, 0.014, 0.022, col, Vec3(x, y, z0 - i * step)) end
end

local function stripe(m, accent, w, y, z, len) box(m, w, 0.012, len, accent, Vec3(0, y, z)) end

------------------------------------------------------------------ per kind
local BUILD = {}

function BUILD.pistol(s, accent, glow)
  local body, slide, mag = MeshData(), MeshData(), MeshData()
  -- Frame under the slide, with a rail.
  box(body, 0.05, 0.04, 0.24, s.dark, Vec3(0, 0.0, -0.08))
  for i = 0, 3 do box(body, 0.054, 0.008, 0.014, P.metal_dark, Vec3(0, -0.022, -0.13 - i * 0.026)) end
  grip(body, s, 0.15, 0.22, 0.03)
  box(body, 0.03, 0.03, 0.03, s.dark, Vec3(0, 0.05, 0.08), Quat.euler(0.6, 0, 0))   -- hammer
  -- Slide: chunky top half, serrations, ejection port, barrel poking out.
  local sl = s.style == "pill" and MeshData.capsule(0.04, 0.3, 12, s.body):transform(nil, Quat.euler(math.pi / 2, 0, 0)):transform(nil, nil, Vec3(0.75, 0.95, 1))
    or MeshData.box(0.058, 0.06, 0.28, s.body)
  slide:append(sl, Vec3(0, 0.05, -0.09))
  for i = 0, 5 do
    for _, sx in ipairs({ -1, 1 }) do box(slide, 0.004, 0.04, 0.006, s.dark, Vec3(sx * 0.03, 0.05, 0.02 - i * 0.012)) end
  end
  box(slide, 0.004, 0.022, 0.05, P.metal_dark, Vec3(0.03, 0.065, -0.07))
  stripe(slide, accent, 0.06, 0.082, -0.1, 0.16)
  sights(slide, s, -0.215, 0.03, 0.08)
  tube(body, 0.016, 0.06, P.metal_dark, Vec3(0, 0.05, -0.24))
  ring(body, 0.016, 0.005, s.trim, Vec3(0, 0.05, -0.27))
  if s.style == "toy" then body:append(MeshData.sphere(0.02, 8, 6, s.trim), Vec3(0, 0.05, -0.27)) end  -- orange-tip style toy muzzle cap ring
  if glow then vents(slide, glow, 0.031, 0.04, -0.12, 3, 0.03); vents(slide, glow, -0.031, 0.04, -0.12, 3, 0.03) end
  box(mag, 0.042, 0.03, 0.06, s.trim, Vec3(0, -0.15, 0.06), Quat.euler(-0.22, 0, 0))
  return body, slide, mag, Vec3(0, 0.05, -0.29)
end

function BUILD.smg(s, accent, glow)
  local body, slide, mag = MeshData(), MeshData(), MeshData()
  box(body, 0.07, 0.09, 0.36, s.body, Vec3(0, 0.04, -0.1))
  box(body, 0.074, 0.02, 0.3, s.dark, Vec3(0, 0.0, -0.1))
  -- Barrel shroud with cooling holes.
  tube(body, 0.03, 0.2, s.dark, Vec3(0, 0.05, -0.36), 10)
  for i = 0, 4 do for _, sx in ipairs({ -1, 1 }) do box(body, 0.005, 0.014, 0.018, P.ink, Vec3(sx * 0.03, 0.05, -0.29 - i * 0.032)) end end
  tube(body, 0.02, 0.05, P.metal_dark, Vec3(0, 0.05, -0.48))
  ring(body, 0.022, 0.006, s.trim, Vec3(0, 0.05, -0.5))
  grip(body, s, 0.14, 0.28, 0.06)
  -- Folding stock: two struts and a butt pad.
  for _, sx in ipairs({ -1, 1 }) do box(body, 0.008, 0.012, 0.22, s.dark, Vec3(sx * 0.025, 0.04, 0.18)) end
  box(body, 0.06, 0.09, 0.02, s.grip, Vec3(0, 0.02, 0.29))
  -- Top rail + red-dot.
  for i = 0, 6 do box(body, 0.04, 0.008, 0.014, P.metal_dark, Vec3(0, 0.09, 0.02 - i * 0.03)) end
  box(body, 0.04, 0.04, 0.07, s.dark, Vec3(0, 0.115, -0.05))
  box(body, 0.03, 0.026, 0.006, Color.hex("#ff4a3a"), Vec3(0, 0.12, -0.086))
  -- Charging handle (the moving part) and ejection port.
  box(slide, 0.03, 0.016, 0.03, s.trim, Vec3(0.045, 0.07, -0.02))
  box(slide, 0.004, 0.03, 0.06, P.ink, Vec3(0.036, 0.05, -0.08))
  stripe(body, accent, 0.075, 0.068, -0.14, 0.2)
  vents(body, s.trim, -0.036, 0.03, -0.02, 4, 0.025)
  if glow then vents(body, glow, 0.036, 0.025, -0.15, 4, 0.03); vents(body, glow, -0.036, 0.055, -0.15, 4, 0.03) end
  -- Long stick mag.
  box(mag, 0.032, 0.17, 0.05, s.dark, Vec3(0, -0.07, -0.14), Quat.euler(0.12, 0, 0))
  box(mag, 0.036, 0.02, 0.056, s.trim, Vec3(0, -0.155, -0.13), Quat.euler(0.12, 0, 0))
  return body, slide, mag, Vec3(0, 0.05, -0.52)
end

function BUILD.shotgun(s, accent, glow)
  local body, slide, mag = MeshData(), MeshData(), MeshData()
  box(body, 0.075, 0.09, 0.3, s.body, Vec3(0, 0.03, -0.04))
  box(body, 0.08, 0.02, 0.06, s.trim, Vec3(0, 0.08, 0.05))
  -- Double barrels side by side with a rib and bead sight.
  for _, sx in ipairs({ -1, 1 }) do
    tube(body, 0.026, 0.48, P.metal_dark, Vec3(sx * 0.027, 0.055, -0.42), 12)
    ring(body, 0.027, 0.006, s.dark, Vec3(sx * 0.027, 0.055, -0.66))
    body:append(MeshData.cylinder(0.016, 0.016, 0.004, 10, P.ink), Vec3(sx * 0.027, 0.055, -0.663), Quat.euler(math.pi / 2, 0, 0))
  end
  box(body, 0.012, 0.01, 0.46, s.dark, Vec3(0, 0.085, -0.42))
  body:append(MeshData.sphere(0.008, 6, 4, s.trim), Vec3(0, 0.094, -0.64))
  -- Wooden stock with a recoil pad.
  local stock = MeshData.box(0.06, 0.1, 0.3, s.grip)
  stock:displace(function(x, y, z) if z > 0 then return 0, -y * z * 0.6 - z * 0.12, 0 end end)
  body:append(stock, Vec3(0, -0.01, 0.26))
  box(body, 0.064, 0.1, 0.02, P.ink, Vec3(0, -0.04, 0.42))
  grip(body, s, 0.09, 0.4, 0.06)
  -- Pump forend (the moving part), with ridges.
  local pump = MeshData.box(0.07, 0.05, 0.16, s.grip)
  pump:paint_fn(function(x, y, z, r, g, b) if math.floor((z + 1) * 50) % 3 == 0 then return r * 0.7, g * 0.7, b * 0.7 end return r, g, b end)
  slide:append(pump, Vec3(0, 0.015, -0.32))
  stripe(body, accent, 0.078, 0.0, -0.08, 0.2)
  screw(body, s.trim, 0.04, 0.03, 0.04); screw(body, s.trim, -0.04, 0.03, 0.04)
  if glow then vents(body, glow, 0.039, 0.03, -0.1, 3, 0.04); vents(body, glow, -0.039, 0.03, -0.1, 3, 0.04) end
  -- Shell carrier on the side counts as the "mag".
  for i = 0, 3 do mag:append(MeshData.cylinder(0.012, 0.012, 0.05, 8, Color.hex("#d8433b")), Vec3(0.045, 0.02, -0.08 + i * 0.03)) end
  return body, slide, mag, Vec3(0, 0.055, -0.67)
end

function BUILD.rifle(s, accent, glow)
  local body, slide, mag = MeshData(), MeshData(), MeshData()
  box(body, 0.06, 0.085, 0.42, s.body, Vec3(0, 0.03, -0.12))
  -- Long fluted barrel and a muzzle brake.
  tube(body, 0.018, 0.5, P.metal_dark, Vec3(0, 0.045, -0.58), 10)
  for i = 0, 3 do box(body, 0.04, 0.004, 0.08, P.ink, Vec3(0, 0.045, -0.44 - i * 0.1)) end
  box(body, 0.05, 0.035, 0.07, s.dark, Vec3(0, 0.045, -0.86))
  for i = 0, 2 do box(body, 0.054, 0.02, 0.008, P.ink, Vec3(0, 0.045, -0.835 - i * 0.022)) end
  -- Scope with lens shine and turrets.
  tube(body, 0.026, 0.28, s.dark, Vec3(0, 0.135, -0.12), 14)
  tube(body, 0.036, 0.06, s.dark, Vec3(0, 0.135, -0.28), 14, 0.028)
  tube(body, 0.032, 0.05, s.dark, Vec3(0, 0.135, 0.03), 14, 0.026)
  body:append(MeshData.cylinder(0.03, 0.03, 0.004, 14, Color.hex("#7de3ff")), Vec3(0, 0.135, -0.312), Quat.euler(math.pi / 2, 0, 0))
  body:append(MeshData.cylinder(0.012, 0.012, 0.03, 8, s.trim), Vec3(0, 0.17, -0.12))
  body:append(MeshData.cylinder(0.012, 0.012, 0.03, 8, s.trim), Vec3(0.035, 0.135, -0.12), Quat.euler(0, 0, math.pi / 2))
  for _, z in ipairs({ -0.2, -0.04 }) do box(body, 0.02, 0.05, 0.02, s.dark, Vec3(0, 0.095, z)) end
  -- Thumbhole stock and cheek rest.
  local stock = MeshData.box(0.055, 0.12, 0.3, s.grip)
  stock:displace(function(x, y, z) if y < 0 and z < 0 then return 0, -z * 0.3, 0 end end)
  body:append(stock, Vec3(0, -0.01, 0.25))
  box(body, 0.05, 0.03, 0.14, s.grip:lighten(0.1), Vec3(0, 0.065, 0.24))
  box(body, 0.06, 0.13, 0.02, P.ink, Vec3(0, -0.01, 0.405))
  grip(body, s, 0.12, 0.3, 0.06)
  -- Bipod folded under the handguard.
  for _, sx in ipairs({ -1, 1 }) do box(body, 0.008, 0.008, 0.16, P.metal_dark, Vec3(sx * 0.02, -0.025, -0.38)) end
  -- Bolt handle (the moving part).
  slide:append(MeshData.cylinder(0.008, 0.008, 0.06, 6, s.trim), Vec3(0.05, 0.05, 0.0), Quat.euler(0, 0, math.pi / 2))
  slide:append(MeshData.sphere(0.016, 8, 6, s.trim), Vec3(0.08, 0.05, 0.0))
  stripe(body, accent, 0.064, 0.074, -0.2, 0.18)
  if glow then vents(body, glow, 0.031, 0.02, -0.18, 5, 0.035); vents(body, glow, -0.031, 0.02, -0.18, 5, 0.035) end
  box(mag, 0.04, 0.07, 0.07, s.dark, Vec3(0, -0.035, -0.06))
  return body, slide, mag, Vec3(0, 0.045, -0.9)
end

function BUILD.launcher(s, accent, glow)
  local body, slide, mag = MeshData(), MeshData(), MeshData()
  local tubem = MeshData.cylinder(0.085, 0.085, 0.84, 16, s.body)
  tubem:paint_fn(function(x, y, z, r, g, b)
    if math.abs(math.abs(y) - 0.2) < 0.03 then return accent.r, accent.g, accent.b end
    if math.abs(y) < 0.01 then return s.trim.r, s.trim.g, s.trim.b end
    return r, g, b
  end)
  body:append(tubem, Vec3(0, 0.1, -0.12), Quat.euler(math.pi / 2, 0, 0))
  -- Flared front bell and rear venturi.
  tube(body, 0.11, 0.1, s.dark, Vec3(0, 0.1, -0.57), 16, 0.088)
  ring(body, 0.11, 0.012, s.trim, Vec3(0, 0.1, -0.62))
  tube(body, 0.075, 0.1, P.metal_dark, Vec3(0, 0.1, 0.33), 16, 0.1)
  -- Warhead peeking out (the "mag": it pops off on reload).
  mag:append(MeshData.cone(0.07, 0.14, 12, Color.hex("#d8433b")), Vec3(0, 0.1, -0.66), Quat.euler(-math.pi / 2, 0, 0))
  -- Side box sight with glowing reticle, front grip, shoulder pad, hazard stripes.
  box(body, 0.06, 0.07, 0.14, s.dark, Vec3(-0.11, 0.17, -0.1))
  box(body, 0.04, 0.04, 0.004, Color.hex("#7dffb0"), Vec3(-0.11, 0.18, -0.172))
  grip(body, s, 0.13, 0.15, 0.04)
  box(body, 0.04, 0.12, 0.05, s.grip, Vec3(0, -0.02, -0.32), Quat.euler(0.15, 0, 0))
  box(body, 0.1, 0.03, 0.2, s.grip, Vec3(0, 0.02, 0.12))
  for i = 0, 4 do box(body, 0.03, 0.006, 0.18, i % 2 == 0 and P.line_yellow or P.ink, Vec3(0.07, 0.15 - i * 0.012, 0.18), Quat.euler(0, 0, 0.8)) end
  -- Arming lever (moving part).
  box(slide, 0.02, 0.05, 0.02, s.trim, Vec3(0.09, 0.12, 0.05))
  if glow then for i = 0, 5 do box(body, 0.012, 0.012, 0.05, glow, Vec3(math.sin(i) * 0.087, 0.1 + math.cos(i) * 0.087, -0.25 - (i % 2) * 0.1)) end end
  return body, slide, mag, Vec3(0, 0.1, -0.7)
end

-- gun: a rolled gun table (kind, maker, rarity accent passed separately).
function GunArt.build(kind, maker, accent, glow)
  local s = SCHEMES[maker] or SCHEMES["Pretend Co."]
  local body, slide, mag, muzzle = BUILD[kind](s, accent, glow)
  -- Maker badge on the left side.
  box(body, 0.003, 0.025, 0.04, s.trim, Vec3(-0.04, 0.03, -0.02))
  return { body = body:flat(), slide = slide:flat(), mag = mag:flat(), muzzle = muzzle }
end

-- Spent casing and muzzle-flash star, shared by every gun.
function GunArt.casing(kind)
  if kind == "shotgun" then
    local m = MeshData.cylinder(0.014, 0.014, 0.05, 8, Color.hex("#d8433b"))
    m:append(MeshData.cylinder(0.015, 0.015, 0.012, 8, P.gold), Vec3(0, -0.025, 0))
    return m:flat()
  end
  local m = MeshData.cylinder(0.006, 0.007, 0.028, 6, P.gold)
  return m:flat()
end

function GunArt.flash()
  local m = MeshData()
  local y = Color(1, 0.95, 0.6)
  -- Crossed blades pointing down -Z plus a front star.
  for i = 0, 3 do
    local q = Quat.euler(0, 0, i * math.pi / 4)
    local blade = MeshData.cone(0.05, 0.36, 4, y)
    blade:transform(nil, Quat.euler(-math.pi / 2, 0, 0)); blade:transform(nil, nil, Vec3(1, 0.25, 1))
    m:append(blade, Vec3(0, 0, -0.16), q)
  end
  for i = 0, 5 do
    local a = i / 6 * math.tau
    local spike = MeshData.cone(0.03, 0.16, 3, y)
    m:append(spike, Vec3(math.cos(a) * 0.06, math.sin(a) * 0.06, -0.02), Quat.euler(0, 0, a - math.pi / 2))
  end
  m:append(MeshData.icosphere(0.06, 1, Color.WHITE))
  return m
end

return GunArt
