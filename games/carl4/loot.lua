-- Loot: procedural guns (rarity, element, stats, names), pickups, chests and the vending machine.
local Art = require("art")
local GunArt = require("gun_art")
local Props = require("props")
local Gear = require("gear")
local P = Art.pal
local Loot = {}
local M

Loot.RARITY = {
  { name = "Common", color = P.common, mult = 1.0, weight = 50 },
  { name = "Uncommon", color = P.uncommon, mult = 1.15, weight = 28 },
  { name = "Rare", color = P.rare, mult = 1.32, weight = 14 },
  { name = "Epic", color = P.epic, mult = 1.55, weight = 6 },
  { name = "Legendary", color = P.legendary, mult = 1.85, weight = 2 },
}

Loot.ELEMENTS = {
  fire = { name = "Fire", color = P.fire, desc = "Sets targets on fire" },
  static = { name = "Static", color = P.static, desc = "Arcs to nearby enemies" },
  curse = { name = "Curse", color = P.curse, desc = "Hit targets float helplessly" },
}

-- Base stats at level 1.
Loot.TYPES = {
  pistol = { label = "Pistol", damage = 17, rate = 4.5, mag = 12, reload = 1.15, spread = 1.0, pellets = 1, sound = "pistol" },
  smg = { label = "SMG", damage = 8.5, rate = 11, mag = 32, reload = 1.6, spread = 2.6, pellets = 1, sound = "smg" },
  shotgun = { label = "Shotgun", damage = 9, rate = 1.35, mag = 6, reload = 2.0, spread = 6.5, pellets = 9, sound = "shotgun" },
  rifle = { label = "Rifle", damage = 58, rate = 1.6, mag = 6, reload = 1.9, spread = 0.15, pellets = 1, sound = "rifle", zoom = true },
  launcher = { label = "Launcher", damage = 115, rate = 0.9, mag = 3, reload = 2.4, spread = 0.4, pellets = 1, sound = "launcher", splash = 4 },
}
local TYPE_ORDER = { "pistol", "smg", "shotgun", "rifle", "launcher" }

local MAKERS = { "Pretend Co.", "Prop Pills Arms", "Mall of the Future", "Sequel Committee Surplus", "Garf's", "Postal Service" }
local PREFIX = { "Focus-Tested", "Off-Brand", "Sequel", "Normal Human", "Discount", "Mall-Grade", "Unclipped", "Store-Brand", "Deadpan", "Overnight" }
local ELEMENT_PREFIX = { fire = { "Hot Take", "Flamer's", "Lasagna-Warm" }, static = { "Static", "Storm Flock", "Thunder Ram" }, curse = { "Spooky", "Cursed", "Haunted" } }
local NOUN = {
  pistol = { "Peashooter", "Hand Cannon", "Probe", "Courier" },
  smg = { "Spammer", "Chatbot", "Click Farm", "Junk Mailer" },
  shotgun = { "Boomstick", "Spreader", "Garf Special", "Food Court" },
  rifle = { "Long Distance Call", "Spoilers", "Process Server" },
  launcher = { "Sequel Hook", "Express Delivery", "Ratio Lord" },
}
-- Legendary uniques: name, element, flavour, trait.
local UNIQUE = {
  pistol = { name = "NOBODY CLIP THAT", element = "static", flavour = "\"Nobody clip that.\"", trait = "crit_bonus" },
  smg = { name = "DESERT BUS", element = "fire", flavour = "Route 45. Never stops.", trait = "bottomless" },
  shotgun = { name = "SPOOKY ALIMONY", element = "curse", flavour = "Paid in full. Eventually.", trait = "extra_pellets" },
  rifle = { name = "STILL IN TRANSIT", element = "static", flavour = "Your package is on its way.", trait = "pierce" },
  launcher = { name = "BY THE POWER OF NEVADA", element = "fire", flavour = "Focus groups loved it.", trait = "cluster" },
}

function Loot.init(materials)
  M = materials
  Loot.mesh_cache = {}
  Loot.meshes = {
    cash = MeshData.box(0.32, 0.06, 0.16, P.cash):flat():upload(),
    pill = MeshData.capsule(0.12, 0.42, 10, P.pill):transform(nil, Quat.euler(0, 0, math.pi / 2)):upload(),
    beam = MeshData.cylinder(0.12, 0.2, 1, 10, Color.WHITE, false):transform(Vec3(0, 0.5, 0)):upload(),
    cell = Art.power_cell():upload(),
  }
  local base, lid = Art.chest(P.gold)
  Loot.meshes.chest, Loot.meshes.chest_lid = base:upload(), lid:upload()
  local rb, rl = Art.chest(P.legendary)
  Loot.meshes.chest_red, Loot.meshes.chest_red_lid = rb:upload(), rl:upload()
  Loot.meshes.vending = Art.vending():upload()
  M.pickup_glow = Material { albedo = Color.WHITE, unshaded = true }
end

-- Uploaded body/slide/mag meshes plus muzzle offset for a gun (cached by look).
function Loot.gun_parts(gun)
  local key = gun.kind .. gun.rarity .. (gun.element or "") .. (gun.maker or "")
  if not Loot.mesh_cache[key] then
    local glow = gun.element and Loot.ELEMENTS[gun.element].color or nil
    local parts = GunArt.build(gun.kind, gun.maker, Loot.RARITY[gun.rarity].color, glow)
    local whole = MeshData()
    whole:append(parts.body); whole:append(parts.slide); whole:append(parts.mag)
    Loot.mesh_cache[key] = { body = parts.body:upload(), slide = parts.slide:upload(), mag = parts.mag:upload(), whole = whole:upload(), muzzle = parts.muzzle }
  end
  return Loot.mesh_cache[key]
end

function Loot.gun_mesh(gun) return Loot.gun_parts(gun).whole end

local function roll_rarity(r, min_rarity, luck)
  local total = 0
  local weights = {}
  for i, rr in ipairs(Loot.RARITY) do
    local w = i >= (min_rarity or 1) and rr.weight * (1 + (luck or 0) * (i - 1) * 0.6) or 0
    weights[i] = w
    total = total + w
  end
  local x = r:float(0, total)
  for i, w in ipairs(weights) do
    x = x - w
    if x <= 0 then return i end
  end
  return #weights
end

-- Generates a gun table. kind/rarity optional.
function Loot.roll_gun(level, opts)
  opts = opts or {}
  local r = rng
  local kind = opts.kind or r:pick(TYPE_ORDER)
  local rarity = opts.rarity or roll_rarity(r, opts.min_rarity, opts.luck)
  local base = Loot.TYPES[kind]
  local rr = Loot.RARITY[rarity]
  local scale = 1.13 ^ (level - 1) * rr.mult
  local function vary(x, amt) return x * (1 + r:float(-amt, amt)) end
  local gun = {
    kind = kind, rarity = rarity, level = level, label = base.label,
    damage = vary(base.damage * scale, 0.1), rate = vary(base.rate, 0.12), mag = math.max(1, math.floor(vary(base.mag, 0.2) + 0.5)),
    reload = vary(base.reload, 0.15), spread = vary(base.spread, 0.2), pellets = base.pellets, splash = base.splash, zoom = base.zoom,
    crit = 2.0, sound = base.sound, maker = r:pick(MAKERS),
  }
  local elem_chance = ({ 0, 0.2, 0.45, 0.7, 1 })[rarity]
  if opts.element ~= nil then gun.element = opts.element or nil
  elseif r:chance(elem_chance) then gun.element = r:pick({ "fire", "static", "curse" }) end
  Gear.apply_maker(gun, r)
  if rarity == 5 then
    local u = UNIQUE[kind]
    gun.name, gun.element, gun.flavour, gun.trait = u.name, u.element, u.flavour, u.trait
    if gun.trait == "bottomless" then gun.mag = 60 end
    if gun.trait == "extra_pellets" then gun.pellets = 14 end
    if gun.trait == "crit_bonus" then gun.crit = 3.2 end
  else
    local pre = gun.element and r:pick(ELEMENT_PREFIX[gun.element]) or r:pick(PREFIX)
    gun.name = pre .. " " .. r:pick(NOUN[kind])
  end
  gun.element_chance = gun.element and (0.25 + rarity * 0.07 + (gun.elem_bonus or 0)) or 0
  gun.ammo = gun.mag
  gun.dps = gun.damage * gun.pellets * gun.rate
  return gun
end

-- Price at the vending machine and sale value.
function Loot.value(gun) return math.floor(40 * gun.level * (1 + (gun.rarity - 1) * 0.8)) end

------------------------------------------------------------------ pickups
-- A gun lying in the world: a physics body with a rarity-coloured light beam above it.
function Loot.gun_pickup(pos, gun, vel)
  local col = Loot.RARITY[gun.rarity].color
  local b = RigidBody3D { name = "GunPickup", position = pos, rotation = Quat.euler(0, rng:float(0, 6.28), 0), shape = Shape.box(0.3, 0.25, 0.9),
    mass = 4, friction = 0.8, angular_damp = 0.8, groups = { "gun_pickups" },
    MeshInstance3D { mesh = Loot.gun_mesh(gun), material = M.metal, scale = Vec3(1.3) },
  }
  b.gun = gun
  b:set_velocity(vel or Vec3(rng:float(-2, 2), 5, rng:float(-2, 2)))
  local beam = MeshInstance3D { mesh = Loot.meshes.beam, material = M.beam, tint = col:with_alpha(0.35), top_level = true, cast_shadow = false,
    scale = Vec3(1, 2 + gun.rarity * 1.2, 1) }
  b:add_child(beam)
  if gun.rarity >= 3 then b:add_child(OmniLight3D { color = col, energy = 1.5 + gun.rarity * 0.5, range = 4, position = Vec3(0, 0.6, 0) }) end
  b._process = function(self, dt)
    beam.position = self.position + Vec3(0, -0.1, 0)
    beam.rotation = Quat()
    if self.position.y < -30 then self:queue_free() end
  end
  return b
end

-- Small stuff that flies at the player when near: cash and Prop Pills.
local function magnet_pickup(kind, pos, amount, vel)
  local b = RigidBody3D { name = kind, position = pos, shape = Shape.box(0.3, 0.12, 0.3), mass = 1, bounce = 0.4, friction = 0.6 }
  if kind == "grenade" then b:add_child(Gear.grenade_node {})
  else b:add_child(MeshInstance3D { mesh = kind == "cash" and Loot.meshes.cash or Loot.meshes.pill, material = M.glossy }) end
  b:set_velocity(vel or Vec3(rng:float(-3, 3), rng:float(4, 7), rng:float(-3, 3)))
  b.born = Game.time
  b._process = function(self, dt)
    local p = G.player
    if not p or p.dead or Game.time - self.born < 0.5 then return end
    local target = p.position + Vec3(0, 0.6, 0)
    local d = self.position:distance(target)
    if kind == "pill" and p.hp >= p.max_hp then return end
    if kind == "grenade" and G.grenades >= p:max_grenades() then return end
    if d < 4.5 then self:set_velocity((target - self.position):normalized() * 14) end
    if d < 0.9 then
      if kind == "grenade" then
        G.grenades = G.grenades + 1
        Audio.play(SFX.mag_in, { volume = 0.5, pitch = 0.8 })
      elseif kind == "cash" then
        G.cash = G.cash + amount
        G.stats.cash = G.stats.cash + amount
        Audio.play(SFX.coin, { volume = 0.35, pitch = rng:float(0.95, 1.2) })
      else
        p:heal(p.max_hp * 0.35)
        Audio.play(SFX.pill, { volume = 0.5 })
        G.hud:toast("Prop Pills", "+35% health")
      end
      self:queue_free()
    end
    if Game.time - self.born > 60 then self:queue_free() end
  end
  return b
end
function Loot.cash(pos, amount, vel) return magnet_pickup("cash", pos, amount, vel) end
function Loot.pill(pos, vel) return magnet_pickup("pill", pos, 0, vel) end
function Loot.grenade_ammo(pos, vel) return magnet_pickup("grenade", pos, 0, vel) end

-- A shield or grenade mod of a rolled rarity.
function Loot.roll_item(level, opts)
  opts = opts or {}
  local rarity = roll_rarity(rng, opts.min_rarity, opts.luck)
  if (opts.kind or (rng:chance(0.5) and "shield" or "grenade")) == "shield" then return Gear.roll_shield(level, rarity) end
  return Gear.roll_grenade(level, rarity)
end

-- What an enemy drops when it dies. Badasses burst into a loot shower.
function Loot.drop(root, pos, level, luck, badass)
  luck = luck or 0
  local cash = math.floor(rng:float(4, 9) * level * (1 + luck))
  for _ = 1, badass and 6 or rng:int(1, 3) do root:add_child(Loot.cash(pos + Vec3(0, 0.6, 0), math.ceil(cash / 2))) end
  if rng:chance(0.18 + luck * 0.1) then root:add_child(Loot.pill(pos + Vec3(0, 0.8, 0))) end
  if rng:chance(0.12 + luck * 0.1) then root:add_child(Loot.grenade_ammo(pos + Vec3(0, 0.8, 0))) end
  if badass then
    Audio.play_at(SFX.chest, pos, { volume = 0.7, pitch = 1.2 })
    for i = 1, rng:int(2, 4) do
      local a = i * 2.1
      root:add_child(Loot.gun_pickup(pos + Vec3(0, 1.2, 0), Loot.roll_gun(level, { luck = luck, min_rarity = 2 }), Vec3(math.cos(a) * 3, 7, math.sin(a) * 3)))
    end
    if rng:chance(0.6) then root:add_child(Gear.item_pickup(pos + Vec3(0, 1.2, 0), Loot.roll_item(level, { luck = luck, min_rarity = 2 }))) end
    return
  end
  if rng:chance(0.22 + luck * 0.35) then root:add_child(Loot.gun_pickup(pos + Vec3(0, 1, 0), Loot.roll_gun(level, { luck = luck }))) end
  if rng:chance(0.06 + luck * 0.05) then root:add_child(Gear.item_pickup(pos + Vec3(0, 1, 0), Loot.roll_item(level, { luck = luck }))) end
end

------------------------------------------------------------------ chests
-- "Lost & Found" chest. Opening it pops loot out with physics. tier 2 = red legendary-ish chest.
function Loot.chest(pos, yaw, level, tier)
  tier = tier or 1
  local red = tier >= 2
  local c = StaticBody3D { name = "Chest", position = pos, rotation = Quat.from_y(yaw or 0), shape = Shape.offset(Shape.box(1.1, 0.75, 0.7), Vec3(0, 0.1, 0)),
    groups = { "interactables" },
    MeshInstance3D { mesh = red and Loot.meshes.chest_red or Loot.meshes.chest, material = M.metal },
  }
  local lid = c:add_child(Node3D { position = Vec3(0, 0.27, -0.36) })
  lid:add_child(MeshInstance3D { mesh = red and Loot.meshes.chest_red_lid or Loot.meshes.chest_lid, material = M.metal, position = Vec3(0, 0, 0) })
  local glow = c:add_child(OmniLight3D { color = red and P.legendary or P.gold, energy = 1.2, range = 3.5, position = Vec3(0, 0.8, -0.5) })
  c.prompt = red and "Open Sequel Committee Lockbox" or "Open Lost & Found"
  c.level = level
  function c:interact()
    if self.opened then return end
    self.opened = true
    self.prompt = nil
    G.stats.chests = G.stats.chests + 1
    Audio.play_at(SFX.chest, self.position, { volume = 0.8 })
    Tween.to(lid, { rotation = Quat.euler(-1.9, 0, 0) }, 0.35, { ease = "out_back" })
    glow.energy = 3
    Tween.to(glow, { energy = 0 }, 1.5)
    local gp = self:global_position() + Vec3(0, 0.8, 0)
    local fwd = self:global_rotation() * Vec3(0, 0, -1)
    self:spawn(function()
      wait(0.2)
      local n = red and 3 or 2
      for i = 1, n do
        local gun = Loot.roll_gun(self.level, { min_rarity = red and (i == 1 and 4 or 3) or (i == 1 and 2 or 1), luck = red and 1 or 0.3 })
        local side = self:global_rotation() * Vec3((i - (n + 1) / 2) * 2, 0, 0)
        G.root:add_child(Loot.gun_pickup(gp, gun, fwd * 3 + side + Vec3(0, 6, 0)))
        Audio.play_at(SFX.pop, gp, { volume = 0.6, pitch = 0.9 + i * 0.1 })
        wait(0.15)
      end
      for _ = 1, red and 6 or 3 do
        G.root:add_child(Loot.cash(gp, math.floor(self.level * rng:float(8, 14) * (red and 2 or 1)), fwd * rng:float(1, 4) + Vec3(rng:float(-2, 2), 6, rng:float(-2, 2))))
      end
      if rng:chance(0.6) then G.root:add_child(Loot.pill(gp, fwd * 2 + Vec3(0, 6, 0))) end
      if red or rng:chance(0.3) then G.root:add_child(Gear.item_pickup(gp, Loot.roll_item(self.level, { min_rarity = red and 3 or 1, luck = red and 1 or 0.3 }), fwd * 2 + Vec3(rng:float(-1, 1), 6, 0))) end
      G.root:add_child(Loot.grenade_ammo(gp, fwd * 2 + Vec3(rng:float(-1, 1), 6, 0)))
    end)
  end
  return c
end

------------------------------------------------------------------ power cell
function Loot.power_cell(pos, id, on_take)
  local n = Node3D { name = "PowerCell", position = pos, groups = { "cells" } }
  local m = n:add_child(MeshInstance3D { mesh = Loot.meshes.cell, material = M.cell, position = Vec3(0, 1, 0) })
  n:add_child(OmniLight3D { color = Color.hex("#4dffa6"), energy = 4, range = 7, position = Vec3(0, 1.2, 0) })
  n:add_child(Particles3D { rate = 12, lifetime = 1.5, speed = 0.6, spread = 25, direction = Vec3(0, 1, 0), size = 0.1, size_end = 0,
    color = Color(0.5, 1, 0.7, 1), color_end = Color(0.5, 1, 0.7, 0), emit_radius = 0.5, position = Vec3(0, 0.6, 0) })
  n:add_child(MeshInstance3D { mesh = Loot.meshes.beam, material = M.beam, tint = Color(0.4, 1, 0.65, 0.3), scale = Vec3(2, 14, 2), cast_shadow = false })
  n.cell_id = id
  n._process = function(self, dt)
    m.rotation = Quat.from_y(Game.time * 1.5)
    m.position = Vec3(0, 1 + math.sin(Game.time * 2) * 0.15, 0)
    local p = G.player
    if p and not p.dead and p.position:distance(self.position + Vec3(0, 0.5, 0)) < 1.6 then
      on_take(self)
      self:queue_free()
    end
  end
  return n
end

------------------------------------------------------------------ vending machine
function Loot.vending(pos, yaw)
  local v = StaticBody3D { name = "Vending", position = pos, rotation = Quat.from_y(yaw or 0), shape = Shape.offset(Shape.box(1.2, 2.1, 0.9), Vec3(0, 1.05, 0)),
    groups = { "interactables" },
    MeshInstance3D { mesh = Loot.meshes.vending, material = M.glossy, position = Vec3(0, 1.05, 0) },
    OmniLight3D { color = Color.hex("#ff7fa8"), energy = 2.5, range = 6, position = Vec3(0, 1.6, -1) },
    Label3D { text = "PROP PILLS", position = Vec3(0, 2.4, 0), size = 20, color = Color.hex("#ffd6e4"), max_distance = 30 },
  }
  v.prompt = "Shop: Prop Pills Vending"
  function v:interact() G.open_shop(self) end
  return v
end

return Loot
