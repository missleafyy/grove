-- Gear: manufacturer traits, shields, grenade mods, enemy health layers and elemental effectiveness.
local Art = require("art")
local P = Art.pal
local Gear = {}

------------------------------------------------------------------ manufacturers
-- Every maker plays differently (applied when a gun is rolled; the trait text shows on the loot card).
Gear.MAKERS = {
  ["Pretend Co."] = { tag = "THROW-TO-RELOAD", desc = "Reloading throws the gun. It explodes. A new one digistructs.", color = Color.hex("#a98bff") },
  ["Prop Pills Arms"] = { tag = "ALWAYS ELEMENTAL", desc = "Every Prop Pills gun has an element, and procs it more.", color = Color.hex("#ff7fa8") },
  ["Mall of the Future"] = { tag = "SMART SPREAD", desc = "Gets more accurate the longer you hold the trigger.", color = Color.hex("#4ff0d8") },
  ["Sequel Committee Surplus"] = { tag = "MORE OF IT", desc = "+35% fire rate and +40% magazine. Quantity over quality.", color = Color.hex("#c9b46a") },
  ["Garf's"] = { tag = "LASAGNA-POWERED", desc = "+55% damage, +50% crit damage, slower. Never elemental.", color = Color.hex("#ff9a3c") },
  ["Postal Service"] = { tag = "EXPRESS ROUNDS", desc = "Every shot explodes on delivery. Signature required.", color = Color.hex("#7fb0ff") },
}

function Gear.apply_maker(gun, r)
  local m = gun.maker
  if m == "Prop Pills Arms" then
    if not gun.element then gun.element = r:pick({ "fire", "static", "curse" }) end
    gun.elem_bonus = 0.15
  elseif m == "Sequel Committee Surplus" then
    gun.rate = gun.rate * 1.35
    gun.mag = math.max(1, math.floor(gun.mag * 1.4 + 0.5))
  elseif m == "Garf's" then
    gun.damage = gun.damage * 1.55
    gun.rate = gun.rate * 0.78
    gun.crit = gun.crit * 1.5
    if gun.rarity < 5 then gun.element = nil end
  elseif m == "Postal Service" then
    gun.express = true
    gun.damage = gun.damage * 0.85
  elseif m == "Pretend Co." then
    gun.throw_reload = true
    gun.reload = gun.reload * 0.8
  elseif m == "Mall of the Future" then
    gun.smart = true
    gun.spread = gun.spread * 1.4
  end
end

------------------------------------------------------------------ elements vs health layers
-- Enemies carry up to three layers: shield (blue), armor (yellow), flesh (red).
Gear.LAYER_COLOR = { shield = Color.hex("#5fd6ff"), armor = Color.hex("#ffcf4a"), flesh = Color.hex("#ff5a52") }
Gear.EFFECT = {
  fire = { flesh = 1.75, armor = 0.75, shield = 0.5 },
  static = { flesh = 1.0, armor = 1.0, shield = 2.0 },
  curse = { flesh = 0.9, armor = 1.75, shield = 0.75 },
}
function Gear.mult(element, layer)
  local e = element and Gear.EFFECT[element]
  return e and e[layer] or 1
end

------------------------------------------------------------------ shields
local SHIELD_KINDS = {
  { kind = "standard", name = { "Bubble Wrap", "Packing Peanut", "Return Label" }, cap = 1.0, delay = 3.5, rate = 0.30, desc = nil },
  { kind = "turtle", name = { "Tortoise Mode", "Big Box Store", "Freight Class" }, cap = 1.6, delay = 4.5, rate = 0.18, desc = "Huge capacity, slow to recharge, -10% max health" },
  { kind = "nova", name = { "Static Nova", "Ratio Burst", "Rage Quit" }, cap = 0.85, delay = 3.2, rate = 0.32, desc = "Releases a static nova when it breaks" },
  { kind = "roid", name = { "Roid Rage", "Pretzel Arms", "Hands-On" }, cap = 0.75, delay = 3.0, rate = 0.35, desc = "Melee does triple damage while the shield is down" },
  { kind = "quick", name = { "Same-Day", "Overnight", "Express Lane" }, cap = 0.8, delay = 1.8, rate = 0.45, desc = "Recharges almost right away" },
}
local SHIELD_MAKERS = { "Pretend Co.", "Mall of the Future", "Postal Service", "Prop Pills Arms" }

function Gear.roll_shield(level, rarity, r)
  r = r or rng
  local k = r:pick(SHIELD_KINDS)
  local rr = ({ 1.0, 1.12, 1.26, 1.42, 1.65 })[rarity]
  return {
    type = "shield", kind = k.kind, rarity = rarity, level = level,
    name = r:pick(k.name) .. (rarity >= 4 and "+" or ""),
    maker = r:pick(SHIELD_MAKERS),
    capacity = math.floor(60 * 1.12 ^ (level - 1) * k.cap * rr * r:float(0.92, 1.08)),
    delay = k.delay * r:float(0.9, 1.1) / (1 + (rarity - 1) * 0.06),
    rate = k.rate * r:float(0.9, 1.1) * (1 + (rarity - 1) * 0.08),
    desc = k.desc,
  }
end

------------------------------------------------------------------ grenade mods
local GRENADE_KINDS = {
  { kind = "standard", name = { "Package Bomb", "Prop Pill Bottle", "Lasagna Pan" }, dmg = 1.0, radius = 4.5, desc = nil },
  { kind = "mirv", name = { "Junk Mail", "Spam Folder", "Chain Letter" }, dmg = 0.6, radius = 3.6, desc = "Splits into four child grenades" },
  { kind = "singularity", name = { "Black Hole Sun", "Gravity Well", "Focus Group" }, dmg = 0.8, radius = 4.2, desc = "Pulls enemies in, then explodes" },
  { kind = "transfusion", name = { "Blood Drive", "Leech Mail", "Vampire Fang" }, dmg = 0.7, radius = 4.0, desc = "Heals you for a share of the damage" },
}
function Gear.roll_grenade(level, rarity, r)
  r = r or rng
  local k = r:pick(GRENADE_KINDS)
  local rr = ({ 1.0, 1.15, 1.32, 1.55, 1.85 })[rarity]
  local element = (rarity >= 2 and r:chance(0.25 + rarity * 0.12)) and r:pick({ "fire", "static", "curse" }) or nil
  return {
    type = "grenade", kind = k.kind, rarity = rarity, level = level, element = element,
    name = r:pick(k.name), maker = "Postal Service",
    damage = math.floor(90 * 1.13 ^ (level - 1) * k.dmg * rr), radius = k.radius * (1 + (rarity - 1) * 0.05),
    desc = k.desc,
  }
end

function Gear.default_shield() return Gear.roll_shield(1, 1, Random(7)) end
function Gear.default_grenade()
  local g = Gear.roll_grenade(1, 1, Random(3))
  g.kind, g.name, g.desc, g.element, g.radius = "standard", "Package Bomb", nil, nil, 4.5
  return g
end

------------------------------------------------------------------ item pickups (shields, grenade mods)
local meshes
function Gear.init(M)
  Gear.M = M
  meshes = {
    shield = MeshData.cylinder(0.32, 0.32, 0.1, 6, Color.hex("#5fd6ff")):transform(nil, Quat.euler(math.pi / 2, 0, 0)):upload(),
    shield_core = MeshData.cylinder(0.18, 0.18, 0.14, 6, Color.hex("#1a2a3a")):transform(nil, Quat.euler(math.pi / 2, 0, 0)):upload(),
    grenade = MeshData.capsule(0.13, 0.36, 10, Color.hex("#4a6a3a")):upload(),
    grenade_band = MeshData.cylinder(0.14, 0.14, 0.06, 10, Color.hex("#e7b53b")):upload(),
    pin = MeshData.box(0.06, 0.12, 0.06, Color.hex("#c9ced6")):transform(Vec3(0, 0.22, 0)):upload(),
  }
  Gear.meshes = meshes
end

-- Grenade mesh used for thrown grenades too.
function Gear.grenade_node(props)
  local n = Node3D(props or {})
  n:add_child(MeshInstance3D { mesh = meshes.grenade, material = Gear.M.glossy })
  n:add_child(MeshInstance3D { mesh = meshes.grenade_band, material = Gear.M.metal })
  n:add_child(MeshInstance3D { mesh = meshes.pin, material = Gear.M.metal })
  return n
end

function Gear.item_pickup(pos, item, vel)
  local Loot = require("loot")
  local col = Loot.RARITY[item.rarity].color
  local b = RigidBody3D { name = "ItemPickup", position = pos, shape = Shape.box(0.5, 0.3, 0.5), mass = 3, friction = 0.8, angular_damp = 0.8,
    groups = { "gun_pickups" } }
  if item.type == "shield" then
    b:add_child(MeshInstance3D { mesh = meshes.shield, material = Gear.M.glossy, tint = col:lighten(0.2), scale = Vec3(1.2) })
    b:add_child(MeshInstance3D { mesh = meshes.shield_core, material = Gear.M.metal, scale = Vec3(1.2) })
  else
    b:add_child(Gear.grenade_node { scale = Vec3(1.4), rotation = Quat.euler(0, 0, math.pi / 2) })
  end
  b.item = item
  b:set_velocity(vel or Vec3(rng:float(-2, 2), 5, rng:float(-2, 2)))
  local beam = MeshInstance3D { mesh = Loot.meshes.beam, material = Gear.M.beam, tint = col:with_alpha(0.35), top_level = true, cast_shadow = false,
    scale = Vec3(1, 2 + item.rarity * 1.2, 1) }
  b:add_child(beam)
  b._process = function(self, dt)
    beam.position = self.position + Vec3(0, -0.1, 0)
    beam.rotation = Quat()
    if self.position.y < -30 then self:queue_free() end
  end
  return b
end

return Gear
