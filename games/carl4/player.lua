-- Carl: third-person shooter controller (guns, dash, alien hover, A.S.S. tractor beam) and the shoulder camera.
local Art = require("art")
local Props = require("props")
local Loot = require("loot")
local SpriteActor = require("sprite_actor")
local GunArt = require("gun_art")
local Gear = require("gear")
local Skills = require("skills")
local Combat = Props.Combat
local P = Art.pal

Input.bind("reload", { "R", "pad_y" })
Input.bind("dash", { "C", "LCTRL", "pad_b" })
Input.bind("tractor", { "F", "mouse3", "pad_rb" })
Input.bind("next_weapon", { "Q", "pad_lb" })
for i = 1, 4 do Input.bind("slot" .. i, { tostring(i) }) end
Input.bind("melee", { "V", "pad_rs" })
Input.bind("grenade", { "G", "pad_right" })
Input.bind("action_skill", { "X", "pad_back" })

local TWO_HANDED = { smg = true, shotgun = true, rifle = true, launcher = true }
local TRACTOR_RANGE, TRACTOR_MAX_MASS = 22, 170
-- How hard each gun kicks: camera pitch/yaw, arm recoil, screen shake, FOV punch, crosshair bloom, flash size.
KICK = {
  pistol = { pitch = 0.016, yaw = 0.006, arm = 0.55, shake = 0.12, fov = 1.5, bloom = 0.35, flash = 0.8 },
  smg = { pitch = 0.008, yaw = 0.006, arm = 0.22, shake = 0.06, fov = 0.6, bloom = 0.18, flash = 0.65 },
  shotgun = { pitch = 0.05, yaw = 0.012, arm = 1.0, shake = 0.45, fov = 5, bloom = 0.9, flash = 1.5 },
  rifle = { pitch = 0.04, yaw = 0.006, arm = 0.9, shake = 0.3, fov = 3.5, bloom = 0.7, flash = 1.2 },
  launcher = { pitch = 0.05, yaw = 0.01, arm = 1.0, shake = 0.5, fov = 6, bloom = 1, flash = 1.8 },
}

------------------------------------------------------------------ Player
local Player = CharacterBody3D:extend("Player")

function Player:_setup()
  CharacterBody3D._setup(self)
  self.radius = 0.33
  self.height = 1.3
  self.step_height = 0.35
  self.max_slope = 50
  self.speed = 6.5
  self.sprint_speed = 10
  self.accel = 60
  self.air_accel = 20
  self.jump_velocity = 9.5
  self.gravity = 26
  self.locked = true
  self:add_to_group("player")
  self.guns = {}
  self.slot = 1
  self._yaw = 0
  self._walk = 0
  self._coyote, self._buffer = 0, 0
  self._fire_cd = 0
  self._reload = nil
  self._last_fire = -10
  self._dash_cd = 0
  self._dash_t = 0
  self._hover = 1
  self._can_double = true
  self._hurt_t = -10
  self._recoil = 0
  self.hp, self.shield = 1, 1
end

function Player:_ready()
  local M = self.materials
  if not Player.flash_mesh then
    Player.flash_mesh = GunArt.flash():upload()
    Player.casings = { small = GunArt.casing("pistol"):upload(), shotgun = GunArt.casing("shotgun"):upload() }
    Player.hole_mesh = MeshData.cylinder(0.05, 0.05, 0.004, 8, Color.hex("#1a1214")):upload()
    Player.hole_ring = MeshData.cylinder(0.075, 0.075, 0.003, 8, Color.hex("#6b5a4a")):upload()
  end
  -- Carl is a pixel-art billboard; the gun is a pixel overlay pinned to his hand.
  self.sprite = self:add_child(SpriteActor { sheet_name = "carl", gun_overlay = true })
  self.visual = self.sprite
  self.sprite.on_frame = function(spr, anim, i)
    if (anim == "run" or anim == "aimrun") and (i == 1 or i == 5) and self:is_on_floor() then
      Audio.play(SFX.step, { volume = 0.14, pitch = rng:float(0.9, 1.2) })
      if self.velocity:flat():length() > 7 then self.parent:add_child(Props.dust(self.position + Vec3(0, 0.05, 0), 3)) end
    end
  end
  self.flash = self:add_child(MeshInstance3D { mesh = Player.flash_mesh, material = M.glow, tint = Color(1, 0.85, 0.4), visible = false, cast_shadow = false, top_level = true })
  self._flash_t = 0
  self._land_t = 0
  self.debris = {}
  self.holes = {}
  self.muzzle_light = self:add_child(OmniLight3D { color = Color.hex("#ffcf7a"), energy = 0, range = 5, position = Vec3(0.3, 1, -0.6) })
  -- Tractor beam visuals.
  self.beam = self:add_child(MeshInstance3D { mesh = MeshData.cylinder(0.06, 0.18, 1, 10, Color.WHITE, false):transform(nil, Quat.euler(math.pi / 2, 0, 0)):transform(Vec3(0, 0, -0.5)):upload(),
    material = M.tractor, top_level = true, visible = false, cast_shadow = false })
  self.beam_fx = self:add_child(Particles3D { rate = 0, lifetime = 0.5, speed = 0.8, spread = 180, size = 0.12, size_end = 0, amount = 80,
    color = Color(0.5, 1, 0.7, 0.9), color_end = Color(0.5, 1, 0.7, 0), top_level = true, emit_radius = 0.5 })
  self:recalc_stats(true)
  self.checkpoint = self.position:copy()
  self:equip(self.slot)
end

------------------------------------------------------------------ stats + damage
function Player:recalc_stats(full)
  local L = G.level
  local si = self.shield_item
  self.max_hp = math.floor(100 * 1.12 ^ (L - 1) * Skills.health() * (si and si.kind == "turtle" and 0.9 or 1))
  self.max_shield = math.floor((si and si.capacity or 60) * Skills.shield())
  if full then self.hp, self.shield = self.max_hp, self.max_shield end
  self.hp = math.min(self.hp, self.max_hp)
  self.shield = math.min(self.shield, self.max_shield)
end

function Player:max_grenades() return 3 + (self.grenade_item and self.grenade_item.rarity >= 4 and 1 or 0) end

-- Swap in a new shield or grenade mod; returns the old one to drop.
function Player:equip_item(item)
  local old
  if item.type == "shield" then
    old = self.shield_item
    self.shield_item = item
    self:recalc_stats(false)
    self._hurt_t = math.min(self._hurt_t, Game.time - 10)
  else
    old = self.grenade_item
    self.grenade_item = item
  end
  return old
end

-- Kills: Fight For Your Life second wind, Prop Pills Habit heals.
function Player:on_kill(enemy)
  if self.downed then self:second_wind() end
  local heal = Skills.kill_heal()
  if heal > 0 and not self.dead then self:heal(self.max_hp * heal) end
end

function Player:heal(a) self.hp = math.min(self.max_hp, self.hp + a) end

function Player:take_damage(amount, info)
  if self.dead or self._dash_t > 0 or self.locked or G.god then return end
  self._hurt_t = Game.time
  local a = amount
  if self.shield > 0 then
    local s = math.min(self.shield, a)
    self.shield = self.shield - s
    a = a - s
    if self.shield <= 0 then Audio.play(SFX.shield_break, { volume = 0.6 }) end
  end
  if self.shield <= 0 and a > 0 and self.shield_item and self.shield_item.kind == "nova" and not self._nova_spent then
    -- Static nova: the shield goes out with a bang.
    self._nova_spent = true
    Props.explosion(self.position + Vec3(0, 1, 0), 6, self.max_shield * 1.2, 0.6, false, { self_damage = 0, element = "static", tint = Color(0.5, 0.85, 1, 1) })
  end
  if self.downed then return end
  self.hp = self.hp - a
  G.hud:hurt(info and info.pos)
  Audio.play(SFX.hurt, { volume = 0.4, pitch = rng:float(0.9, 1.1) })
  if self.hp <= 0 then
    self.hp = 0
    self:go_down()
  end
end

-- Fight For Your Life: Carl drops to one knee with a few seconds to get a kill.
function Player:go_down()
  self.downed = true
  self.ffyl_max = Skills.ffyl_time()
  self.ffyl_t = self.ffyl_max
  self:drop_held()
  self._reload = nil
  Audio.play(SFX.shield_break, { volume = 0.7, pitch = 0.5 })
end

function Player:second_wind()
  self.downed = false
  self.hp = math.floor(self.max_hp * 0.5)
  self._hurt_t = Game.time
  Audio.play(SFX.levelup, { volume = 0.6, pitch = 1.3 })
  G.hud:banner("SECOND WIND!", "Back on your feet", Color.hex("#4dffa6"))
  G.root:add_child(Props.burst(self.position + Vec3(0, 1, 0), Color.hex("#4dffa6"), 50, 6))
end

function Player:bleed_out()
  self.downed = false
  self.dead = true
  G.on_player_death()
end

------------------------------------------------------------------ weapons
function Player:gun() return self.guns[self.slot] end

function Player:equip(i)
  if not self.guns[i] then return end
  if self.slot ~= i then Audio.play(SFX.equip, { volume = 0.4 }) end
  self.slot = i
  self._reload = nil
  local g = self:gun()
  self.gun_parts = Loot.gun_parts(g)
  self._fire_cd = math.max(self._fire_cd, 0.25)
end

function Player:give_gun(gun)
  for i = 1, 4 do
    if not self.guns[i] then
      self.guns[i] = gun
      self:equip(i)
      return nil
    end
  end
  -- Full: swap with the current one, which gets dropped.
  local old = self.guns[self.slot]
  self.guns[self.slot] = gun
  self:equip(self.slot)
  return old
end

function Player:start_reload()
  local g = self:gun()
  if not g or self._reload or g.ammo >= g.mag then return end
  self._reload = g.reload / Skills.reload_speed()
  self._reload_max = self._reload
  self._mag_back = false
  Audio.play(SFX.reload, { volume = 0.4 })
  if g.throw_reload then self:throw_gun(g) return end
  -- Old mag tumbles out of the gun.
  if self.gun_parts then
    self:spawn_debris(self.gun_parts.mag, self.sprite:hand_position(), Quat.from_y(self._yaw),
      Vec3(rng:float(-0.5, 0.5), -1, 0) + self.velocity * 0.5, 4, 3)
  end
end

function Player:muzzle_pos()
  local g = self:gun()
  local len = ({ pistol = 0.3, smg = 0.4, shotgun = 0.55, rifle = 0.7, launcher = 0.6 })[g and g.kind or "pistol"]
  return self.sprite:hand_position() + self.rig.camera:forward() * len
end

-- Point the crosshair is on, from the camera, ignoring Carl.
function Player:aim_ray(spread_deg)
  local rig = self.rig
  local cam = rig.camera:global_position()
  local fwd = rig.camera:forward()
  if spread_deg and spread_deg > 0 then
    local right, upv = rig.camera:right(), rig.camera:up()
    local a, rad = rng:float(0, math.tau), math.rad(spread_deg) * math.sqrt(rng:float(0, 1))
    fwd = (fwd + right * math.cos(a) * math.tan(rad) + upv * math.sin(a) * math.tan(rad)):normalized()
  end
  local start = cam + fwd * math.max(0, (self.position + Vec3(0, 1, 0) - cam):dot(fwd))
  local hit = Physics.raycast(start, start + fwd * 250, self)
  return hit, start + fwd * 250, fwd
end

function Player:fire()
  local g = self:gun()
  if g.ammo <= 0 then
    Audio.play(SFX.empty, { volume = 0.4 })
    self:start_reload()
    self._fire_cd = 0.3
    return
  end
  g.ammo = g.ammo - 1
  if g.trait == "bottomless" and rng:chance(0.5) then g.ammo = g.ammo + 1 end
  self._fire_cd = 1 / (g.rate * Skills.fire_rate())
  -- Mall of the Future guns tighten up the longer the trigger is held.
  if Game.time - self._last_fire > 0.45 then self._streak = 0 end
  self._streak = (self._streak or 0) + 1
  self._last_fire = Game.time
  local muzzle = self:muzzle_pos()
  local spread = g.spread * (Input.down("aim") and 0.45 or 1) * (self:is_on_floor() and 1 or 1.6) * (self.velocity:flat():length() > 7 and 1.3 or 1)
  if g.smart then spread = spread * math.max(0.2, 1 - (self._streak - 1) * 0.12) end
  if self.downed then spread = spread * 1.5 end
  local s = SFX["gun_" .. g.sound]
  Audio.play(s, { volume = 0.45, pitch = rng:float(0.93, 1.07) * (g.element and 0.95 or 1) })
  local thump = SFX["thump_" .. g.kind]
  if thump then Audio.play(thump, { volume = 0.5, pitch = rng:float(0.9, 1.1) }) end
  self.muzzle_light.energy = g.kind == "smg" and 5 or 9
  local punch = KICK[g.kind]
  self._recoil = math.min(1.4, self._recoil + punch.arm)
  self._flash_t = 0.05
  self.flash.visible = true
  self.flash.position = muzzle
  self.flash.rotation = Quat.look_rotation(self.rig.camera:forward()) * Quat.euler(0, 0, rng:float(0, math.tau))
  self.flash.scale = Vec3(punch.flash * rng:float(0.8, 1.2))
  self.sprite:play("fire", true)
  self.rig:kick(punch.pitch, rng:float(-1, 1) * punch.yaw)
  self.rig:shake(punch.shake)
  self.rig:punch_fov(punch.fov)
  G.hud:bloom(punch.bloom)
  self.parent:add_child(Props.burst(muzzle, Color(1, 0.85, 0.45), g.kind == "shotgun" and 10 or 4, 4))
  -- Spent brass flips out of the ejection port (launchers don't eject).
  if g.kind ~= "launcher" then
    local right = self.rig.camera:right()
    self:spawn_debris(Player.casings[g.kind == "shotgun" and "shotgun" or "small"], self.sprite:hand_position() + Vec3(0, 0.05, 0),
      Quat.from_y(self._yaw), right * rng:float(2.5, 3.5) + Vec3(0, rng:float(2.5, 3.5), 0) + self.velocity * 0.8, 15, 1.6)
  end
  local elem_col = g.element and Loot.ELEMENTS[g.element].color or nil

  if g.kind == "launcher" then
    local hit, far = self:aim_ray(spread)
    local target = hit and hit.position or far
    local dir = (target - muzzle):normalized()
    local n = g.trait == "cluster" and 3 or 1
    for i = 1, n do
      local d = n > 1 and (dir + self.rig.camera:right() * (i - 2) * 0.06):normalized() or dir
      Combat.fire_projectile({ pos = muzzle, vel = d * 38, owner = "player", damage = g.damage * Skills.gun_damage() * (n > 1 and 0.6 or 1), splash = g.splash, power = 1,
        rocket = true, mat = G.M.rocket, exclude = self, gravity = 2, element = g.element })
    end
    return
  end

  local pellets = g.pellets
  for i = 1, pellets do
    self._pellet = i
    local hit, far = self:aim_ray(spread)
    local endp = hit and hit.position or far
    G.root:add_child(Props.tracer(muzzle, endp, elem_col or Color(1, 0.92, 0.6), pellets > 1 and 0.03 or 0.05))
    if hit then
      self:apply_hit(hit, g, endp - muzzle)
      if g.trait == "pierce" and hit.node and Combat.target_of(hit.node) then
        -- Rifle shot keeps going through the first target.
        local d = (endp - muzzle):normalized()
        local hit2 = Physics.raycast(endp + d * 0.8, endp + d * 120, hit.node)
        if hit2 then self:apply_hit(hit2, g, d) end
      end
    end
  end
end

function Player:apply_hit(hit, g, dir)
  dir = dir:normalized()
  local node = hit.node
  local target = node and Combat.target_of(node)
  if target and target ~= self then
    local crit = target.is_enemy and target.head_y and hit.position.y > target.position.y + target.head_y
    local dmg = g.damage * Skills.gun_damage() * (crit and g.crit * Skills.crit() or 1)
    local elem = nil
    if g.element and rng:chance(g.element_chance) then elem = g.element end
    Combat.damage(target, dmg, { pos = hit.position, dir = dir, crit = crit, element = elem, elem_type = g.element, gun = g })
    if target.is_enemy then
      G.hud:hitmark(crit, target.dead)
      if target.dead and not target._kill_fx then
        target._kill_fx = true
        self:kill_feedback(hit.position, target.is_boss)
      elseif not self._tick_t or Game.time - self._tick_t > 0.04 then
        self._tick_t = Game.time
        Audio.play(crit and SFX.crit_ding or SFX.hit_tick, { volume = crit and 0.45 or 0.3, pitch = rng:float(0.95, 1.08) })
      end
    end
    G.root:add_child(Props.sparks(hit.position, hit.normal, target.is_enemy and Color(1, 0.95, 0.6) or nil))
  else
    G.root:add_child(Props.sparks(hit.position, hit.normal))
    if node and node.groups and node.groups.ground then G.root:add_child(Props.dust(hit.position, 5)) end
    if node and not node:is(RigidBody3D) and hit.normal then self:bullet_hole(hit.position, hit.normal, node) end
  end
  if node and node:is(RigidBody3D) and node._body then
    node:apply_impulse(dir * g.damage * 0.35, hit.position)
  end
  -- Postal Service express rounds: every delivery explodes (one blast per shotgun shell).
  if g.express and (self._pellet or 1) == 1 then
    Props.explosion(hit.position + (hit.normal or Vec3()) * 0.2, 1.5, g.damage * Skills.gun_damage() * 0.6 * math.max(1, g.pellets * 0.4), 0.3, false,
      { small = true, self_damage = 0, element = g.element })
  end
end

-- Pretend Co.: the empty-ish gun is thrown like a grenade (more ammo left = bigger bang) and a new one digistructs.
function Player:throw_gun(g)
  local left = g.ammo
  g.ammo = 0
  local fwd = self.rig.camera:forward()
  local b = RigidBody3D { name = "ThrownGun", position = self:muzzle_pos(), shape = Shape.box(0.25, 0.25, 0.6), mass = 3, bounce = 0.3,
    MeshInstance3D { mesh = Loot.gun_mesh(g), material = self.materials.metal, scale = Vec3(1.2) } }
  G.root:add_child(b)
  b:set_velocity(fwd * 19 + Vec3(0, 4, 0) + self.velocity * 0.5, Vec3(rng:float(-12, 12), rng:float(-12, 12), rng:float(-12, 12)))
  Audio.play(SFX.throw, { volume = 0.5, pitch = 1.2 })
  local dmg = g.damage * g.pellets * Skills.gun_damage() * (0.8 + left * 0.45)
  local boom = function()
    if b.boomed or not b:is_valid() then return end
    b.boomed = true
    Props.explosion(b.position, 2.6 + math.min(left, 12) * 0.08, dmg, 0.6, false, { self_damage = 0, element = g.element, tint = Color(0.75, 0.6, 1, 1) })
    b:queue_free()
  end
  b:connect("body_entered", function(other)
    if other ~= self and Game.time - b.born > 0.05 then boom() end
  end)
  b.born = Game.time
  Game.after(1.4, boom, b)
end

-- Fake-physics bits (casings, dropped mags): fall, bounce off the terrain, settle, fade out.
function Player:spawn_debris(mesh, pos, rot, vel, spin, life)
  local n = MeshInstance3D { mesh = mesh, material = self.materials.gun, top_level = true, position = pos, rotation = rot, cast_shadow = false }
  G.root:add_child(n)
  table.insert(self.debris, { node = n, vel = vel, spin = Vec3(rng:float(-spin, spin), rng:float(-spin, spin), rng:float(-spin, spin)), life = life, bounced = 0 })
  if #self.debris > 40 then
    local old = table.remove(self.debris, 1)
    if old.node:is_valid() then old.node:queue_free() end
  end
end

function Player:update_debris(dt)
  for i = #self.debris, 1, -1 do
    local d = self.debris[i]
    d.life = d.life - dt
    local n = d.node
    if d.life <= 0 or not n:is_valid() then
      if n:is_valid() then n:queue_free() end
      table.remove(self.debris, i)
    else
      d.vel = d.vel + Vec3(0, -18, 0) * dt
      local p = n.position + d.vel * dt
      local gy = World.height(p.x, p.z) + 0.02
      if p.y < gy then
        p = Vec3(p.x, gy, p.z)
        if d.vel.y < -1.5 and d.bounced < 3 then
          d.bounced = d.bounced + 1
          if d.bounced == 1 and SFX.tink then Audio.play_at(SFX.tink, p, { volume = 0.12, pitch = rng:float(0.8, 1.3) }) end
          d.vel = Vec3(d.vel.x * 0.5, -d.vel.y * 0.35, d.vel.z * 0.5)
          d.spin = d.spin * 0.5
        else
          d.vel = Vec3(); d.spin = d.spin * 0.8
        end
      end
      n.position = p
      local sl = d.spin:length()
      if sl > 0.01 then n.rotation = Quat.axis_angle(d.spin / sl, sl * dt) * n.rotation end
      if d.life < 0.4 then n.scale = Vec3(d.life / 0.4) end
    end
  end
end

function Player:bullet_hole(pos, normal, node)
  local h = MeshInstance3D { mesh = Player.hole_mesh, material = self.materials.vertex, cast_shadow = false,
    position = pos + normal * 0.012, rotation = Quat.look_rotation(normal) * Quat.euler(math.pi / 2, 0, 0) }
  h:add_child(MeshInstance3D { mesh = Player.hole_ring, material = self.materials.vertex, cast_shadow = false, position = Vec3(0, -0.002, 0), scale = Vec3(rng:float(0.8, 1.3), 1, rng:float(0.8, 1.3)) })
  G.root:add_child(h)
  table.insert(self.holes, h)
  if #self.holes > 70 then
    local old = table.remove(self.holes, 1)
    if old:is_valid() then old:queue_free() end
  end
end

-- Kills feel heavy: a crunch, a red X marker, a pop of confetti-gore (green goo for cacti), and a few frames of hit-stop.
function Player:kill_feedback(pos, boss)
  Audio.play(SFX.kill_crunch, { volume = 0.6, pitch = rng:float(0.9, 1.05) })
  G.root:add_child(Props.burst(pos, Color(1, 0.9, 0.5), 18, 7))
  self.rig:shake(boss and 1 or 0.25)
  if G._hitstop then return end
  G._hitstop = true
  Game.spawn(function()
    Game.time_scale = 0.08
    wait_real(boss and 0.25 or 0.055)
    Game.time_scale = 1
    G._hitstop = nil
  end)
end

------------------------------------------------------------------ tractor beam
function Player:drop_held()
  if self.held and self.held:is_valid() then self.held.gravity_held = nil end
  self.held = nil
  self.beam.visible = false
  self.beam_fx.rate = 0
end

function Player:update_tractor(dt, controllable)
  local rig = self.rig
  if controllable and Input.pressed("tractor") and not self.held then
    local hit = self:aim_ray(0)
    if hit and hit.node and hit.node:is(RigidBody3D) and hit.distance < TRACTOR_RANGE + 6 then
      local body = hit.node
      if (body.mass or 0) <= TRACTOR_MAX_MASS and not body.no_grab then
        self.held = body
        body:wake()
        Audio.play(SFX.tractor_on, { volume = 0.5 })
      else
        G.hud:toast("Too heavy for the beam", math.floor((body.mass or 0) * 2.2) .. " lb")
        Audio.play(SFX.empty, { volume = 0.5 })
      end
    else
      Audio.play(SFX.empty, { volume = 0.3, pitch = 0.7 })
    end
  end
  local body = self.held
  if body and (not body:is_valid() or not body._body) then self:drop_held() return end
  if not body then return end
  if not Input.down("tractor") or not controllable then self:drop_held() return end
  local cam = rig.camera:global_position()
  local fwd = rig.camera:forward()
  local reach = 3.2 + math.clamp((body.mass or 20) / 60, 0, 1.5)
  local hold = self.position + Vec3(0, 1.3, 0) + fwd * reach
  local to = hold - body.position
  if to:length() > TRACTOR_RANGE + 8 then self:drop_held() return end
  local heavy = math.clamp(60 / math.max(body.mass or 20, 1), 0.35, 1)
  body:set_velocity(to * 10 * heavy, body:get_angular_velocity() * 0.85)
  -- Throw with fire.
  if controllable and Input.pressed("fire") then
    local speed = 34 * math.clamp(70 / (body.mass or 20), 0.45, 1)
    body:set_velocity(fwd * speed + Vec3(0, 2, 0), Vec3(rng:float(-4, 4), rng:float(-4, 4), rng:float(-4, 4)))
    body.thrown = Game.time
    self._fire_cd = 0.4
    Audio.play(SFX.throw, { volume = 0.6 })
    rig:kick(0.02)
    self:drop_held()
    return
  end
  -- Beam from the left hand to the object.
  local hand = self.sprite:hand_position()
  local d = body.position - hand
  self.beam.visible = true
  self.beam.position = hand
  self.beam.rotation = Quat.look_rotation(d)
  self.beam.scale = Vec3(1 + math.sin(Game.time * 30) * 0.15, 1 + math.sin(Game.time * 30) * 0.15, d:length())
  self.beam_fx.position = body.position
  self.beam_fx.rate = 40
end

------------------------------------------------------------------ interaction
function Player:find_focus()
  local best, best_score = nil, 1e9
  local cam_fwd = self.rig.camera:forward():flat():normalized()
  local here = self.position + Vec3(0, 0.6, 0)
  local function consider(n, range)
    local np = n:global_position()
    local d = np:distance(here)
    if d > range then return end
    local to = (np - here):flat():normalized()
    local facing = to:dot(cam_fwd)
    local score = d - facing * 1.5
    if facing > -0.2 and score < best_score then best, best_score = n, score end
  end
  for _, n in ipairs(Game.group("gun_pickups")) do consider(n, 2.6) end
  for _, n in ipairs(Game.group("interactables")) do if n.prompt then consider(n, 3.2) end end
  return best
end

function Player:interact(target)
  if target.item then
    local old = self:equip_item(target.item)
    Audio.play(SFX.pickup, { volume = 0.6, pitch = 0.9 })
    G.hud:toast(target.item.name, target.item.type == "shield" and "Shield equipped" or "Grenade mod equipped", require("loot").RARITY[target.item.rarity].color)
    local pos = target.position
    target:queue_free()
    if old then G.root:add_child(Gear.item_pickup(pos + Vec3(0, 0.6, 0), old, self.rig.camera:forward():flat() * 2 + Vec3(0, 4, 0))) end
    return
  end
  if target.gun then
    local old = self:give_gun(target.gun)
    Audio.play(SFX.pickup, { volume = 0.6 })
    G.stats.guns = G.stats.guns + 1
    if target.gun.rarity == 5 then G.stats.legendaries = G.stats.legendaries + 1 end
    local pos = target.position
    target:queue_free()
    if old then G.root:add_child(Loot.gun_pickup(pos + Vec3(0, 0.6, 0), old, self.rig.camera:forward():flat() * 2 + Vec3(0, 4, 0))) end
  elseif target.interact then
    target:interact(self)
  end
end

------------------------------------------------------------------ physics process
function Player:_physics_process(dt)
  local rig = self.rig
  local controllable = not self.locked and not self.dead and not G.ui_open
  local ix, iy = 0, 0
  if controllable then ix, iy = Input.vector("move_left", "move_right", "move_forward", "move_back") end
  local yaw = rig.yaw
  local fwd = Vec3(-math.sin(yaw), 0, -math.cos(yaw))
  local right = Vec3(math.cos(yaw), 0, -math.sin(yaw))
  local wish = right * ix + fwd * iy
  if wish:length() > 1 then wish = wish:normalized() end
  self.wish = wish
  local on_floor = self:is_on_floor()
  local aiming = controllable and Input.down("aim")
  local sprint = Input.down("sprint") and not aiming and iy < 0.2
  local v = self.velocity
  local vy = v.y
  local target_speed = (sprint and self.sprint_speed or self.speed) * (aiming and 0.6 or 1)
  if self.downed then
    target_speed = 1.2
    self.ffyl_t = self.ffyl_t - dt
    if self.ffyl_t <= 0 then self:bleed_out() end
  end
  local hv = Vec3(v.x, 0, v.z)

  -- Dash.
  self._dash_cd = self._dash_cd - dt
  self._dash_t = math.max(0, self._dash_t - dt)
  if controllable and Input.pressed("dash") and self._dash_cd <= 0 and not self.downed then
    local dir = wish:length() > 0.1 and wish:normalized() or fwd
    self._dash_t = 0.22
    self._dash_cd = 0.9
    self._dash_dir = dir
    Audio.play(SFX.dash, { volume = 0.5 })
    self.parent:add_child(Props.dust(self.position + Vec3(0, 0.2, 0), 10))
  end
  if self._dash_t > 0 then
    hv = self._dash_dir * 22
    vy = math.max(vy, 0)
  else
    hv = hv:move_toward(wish * target_speed, (on_floor and self.accel or self.air_accel) * dt)
  end

  if on_floor then
    self._coyote = 0.12
    self._can_double = true
    self._hover = 1
    if vy < 0 then vy = 0 end
  else
    self._coyote = self._coyote - dt
    local g = self.gravity * (vy < 0 and 1.35 or 1)
    -- Alien hover: hold jump while falling to drift.
    if controllable and Input.down("jump") and vy < 0 and self._hover > 0 then
      self._hover = self._hover - dt / 1.4
      g = 3
      vy = math.max(vy, -2.5)
      self.hovering = true
    else
      self.hovering = false
    end
    vy = math.max(vy - g * dt, -50)
  end
  self._buffer = (controllable and Input.pressed("jump")) and 0.14 or (self._buffer - dt)
  if self.downed then self._buffer = 0 end
  if self._buffer > 0 and self._coyote > 0 then
    vy = self.jump_velocity
    self._buffer, self._coyote = 0, 0
    Audio.play(SFX.jump, { volume = 0.4, pitch = rng:float(0.95, 1.1) })
  elseif controllable and Input.pressed("jump") and not on_floor and self._can_double and self._coyote <= 0 and not self.downed then
    vy = self.jump_velocity * 0.85
    self._can_double = false
    Audio.play(SFX.double_jump, { volume = 0.4 })
    self.parent:add_child(Props.burst(self.position + Vec3(0, 0.2, 0), Color.hex("#9dffcf"), 16, 3))
  end
  self.velocity = Vec3(hv.x, vy, hv.z)
  self:move_and_slide(dt)
  local landed = self:is_on_floor() and not on_floor
  if landed then self._land_t = (self._fall or 0) < -9 and 0.15 or 0 end
  if landed and (self._fall or 0) < -12 then
    Audio.play(SFX.land, { volume = 0.5 })
    self.parent:add_child(Props.dust(self.position + Vec3(0, 0.1, 0)))
  end
  self._fall = self.velocity.y
  if self:is_on_floor() and self.floor_normal and self.floor_normal.y > 0.8 then
    self._safe = (self._safe or 0) + dt
    if self._safe > 1 then self.safe_position = self.position:copy(); self._safe = 0 end
  end
  if self.position.y < -40 then self:teleport(self.safe_position or self.checkpoint) end

  -- Shield regen after a few seconds out of damage (delay and rate come from the equipped shield).
  local si = self.shield_item
  if not self.dead and not self.downed and Game.time - self._hurt_t > (si and si.delay or 3.5) and self.shield < self.max_shield then
    if self.shield <= 0 then Audio.play(SFX.shield_up, { volume = 0.4 }); self._nova_spent = false end
    self.shield = math.min(self.max_shield, self.shield + self.max_shield * (si and si.rate or 0.3) * dt)
  end

  -- Melee, grenade, action skill.
  self._melee_cd = (self._melee_cd or 0) - dt
  self._melee_t = math.max(0, (self._melee_t or 0) - dt)
  if controllable and not self.downed then
    if Input.pressed("melee") and self._melee_cd <= 0 and not self.held then self:melee() end
    if Input.pressed("grenade") then self:throw_grenade() end
    if Input.pressed("action_skill") then
      if not Skills.cast_abduct(self) then Audio.play(SFX.empty, { volume = 0.4, pitch = 0.6 }) end
    end
  end
  Skills.update(dt)

  -- Weapons.
  if controllable then
    for i = 1, 4 do if Input.pressed("slot" .. i) then self:equip(i) end end
    if Input.pressed("next_weapon") or Input.mouse_wheel() ~= 0 then
      local dirw = Input.mouse_wheel() > 0 and -1 or 1
      for k = 1, 4 do
        local i = (self.slot - 1 + dirw * k) % 4 + 1
        if self.guns[i] then self:equip(i) break end
      end
    end
    if Input.pressed("reload") then self:start_reload() end
  end
  self:update_tractor(dt, controllable)
  self._fire_cd = self._fire_cd - dt
  local g = self:gun()
  if self._reload then
    self._reload = self._reload - dt
    if self._reload <= 0 then
      self._reload = nil
      g.ammo = g.mag
      Audio.play(SFX.reload_done, { volume = 0.45 })
    end
  elseif controllable and g and not self.held and self._melee_t <= 0 and Input.down("fire") and self._fire_cd <= 0 and not UI.click_consumed and Input.is_mouse_captured() then
    self:fire()
  elseif g and g.ammo <= 0 and self._fire_cd <= 0 then
    self:start_reload()
  end

  -- Interaction focus.
  self.focus = controllable and self:find_focus() or nil
  if self.focus and Input.pressed("interact") and not self.downed then self:interact(self.focus) end
end

------------------------------------------------------------------ melee + grenades
function Player:melee()
  self._melee_cd = 0.55
  self._melee_t = 0.32
  self._yaw = self.rig.yaw
  self.sprite:play("melee", true)
  Audio.play(SFX.dash, { volume = 0.4, pitch = 1.4 })
  local fwd = self.rig.camera:forward():flat():normalized()
  local base = 50 * 1.13 ^ (G.level - 1)
  local roid = self.shield_item and self.shield_item.kind == "roid" and self.shield <= 0
  if roid then base = base * 3 end
  self:spawn(function()
    wait(0.08)
    local here = self.position + Vec3(0, 1, 0)
    local hit_any = false
    for _, e in ipairs(Game.group("enemies")) do
      local to = e:global_position() + Vec3(0, 1, 0) - here
      if not e.dead and to:length() < 2.6 and to:flat():normalized():dot(fwd) > 0.25 then
        hit_any = true
        Combat.damage(e, base, { pos = e:global_position() + Vec3(0, 1.2, 0), dir = fwd, kind = "melee" })
        if e.velocity and not e.heavy then e.velocity = e.velocity + fwd * 9 + Vec3(0, 4, 0) end
        G.hud:hitmark(false, e.dead)
        if e.dead then self:kill_feedback(e:global_position() + Vec3(0, 1, 0), e.boss) end
      end
    end
    for _, n in ipairs(Physics.overlap_sphere(here + fwd * 1.3, 1.3)) do
      if n:is(RigidBody3D) and n._body and n ~= self then
        n:apply_impulse((fwd + Vec3(0, 0.4, 0)) * math.min(n.mass or 20, 120) * 9)
        n.thrown = Game.time
        hit_any = true
      end
    end
    if hit_any then
      Audio.play(SFX.thump_shotgun, { volume = 0.7, pitch = roid and 0.7 or 1.1 })
      self.rig:shake(roid and 0.5 or 0.25)
      G.root:add_child(Props.burst(here + fwd * 1.2, roid and Color.hex("#ff5a52") or Color(1, 0.95, 0.7), 14, 5))
    end
  end)
end

function Player:throw_grenade()
  if (G.grenades or 0) <= 0 then
    Audio.play(SFX.empty, { volume = 0.4 })
    G.hud:toast("No grenades", "Enemies and lockboxes drop more")
    return
  end
  G.grenades = G.grenades - 1
  local item = self.grenade_item or Gear.default_grenade()
  local fwd = self.rig.camera:forward()
  self:spawn_grenade(item, self.sprite:hand_position() + Vec3(0, 0.3, 0), fwd * 20 + Vec3(0, 5.5, 0) + self.velocity * 0.4, true)
  Audio.play(SFX.throw, { volume = 0.6 })
  self.sprite:play("melee", true)
  self._melee_t = 0.2
end

function Player:spawn_grenade(item, pos, vel, primary)
  local b = RigidBody3D { name = "Grenade", position = pos, shape = Shape.sphere(0.16), mass = 1.5, bounce = 0.35, friction = 0.6, angular_damp = 0.5 }
  b:add_child(Gear.grenade_node { scale = Vec3(primary and 1 or 0.7) })
  local col = item.element and Loot.ELEMENTS[item.element].color or Color.hex("#ffcf4a")
  b:add_child(OmniLight3D { color = col, energy = 1.5, range = 2.5 })
  G.root:add_child(b)
  b:set_velocity(vel, Vec3(rng:float(-8, 8), rng:float(-8, 8), rng:float(-8, 8)))
  local fuse = primary and 1.3 or rng:float(0.5, 0.9)
  local damage = item.damage * (primary and 1 or 0.45)
  b:connect("body_entered", function(other)
    local t = Combat.target_of(other)
    if t and t.is_enemy and not b.boomed then fuse = 0 end
  end)
  b._process = function(n, dt)
    fuse = fuse - dt
    if fuse > 0 or n.boomed then return end
    n.boomed = true
    local at = n.position
    if item.kind == "singularity" and primary then
      -- Pull everyone in for a moment first.
      n:spawn(function()
        local t = 0
        local swirl = n:add_child(Particles3D { rate = 120, lifetime = 0.5, speed = -6, spread = 180, size = 0.12, size_end = 0, emit_radius = 4,
          color = Color(0.6, 0.4, 1, 1), color_end = Color(0.3, 0.1, 0.6, 0), additive = true })
        while t < 0.9 do
          t = t + Game.delta
          n:set_velocity(Vec3(0, 0.3, 0), Vec3())
          for _, e in ipairs(Game.group("enemies")) do
            local d = at - e:global_position()
            if not e.dead and not e.boss and d:length() < 9 and e.velocity then e.velocity = d:normalized() * 9 + Vec3(0, 1.5, 0) end
          end
          wait(0)
        end
        Props.explosion(at, item.radius, damage, 0.8, false, { self_damage = 0.1, element = item.element })
        n:queue_free()
      end)
      return
    end
    Props.explosion(at, item.radius * (primary and 1 or 0.7), damage, 0.8, false, { self_damage = 0.1, element = item.element, small = not primary })
    if item.kind == "mirv" and primary then
      for i = 1, 4 do
        local a = i * math.tau / 4 + rng:float(-0.3, 0.3)
        self:spawn_grenade(item, at + Vec3(0, 0.5, 0), Vec3(math.cos(a) * 5, 7, math.sin(a) * 5), false)
      end
    elseif item.kind == "transfusion" and primary then
      -- Green motes fly back to Carl and heal him.
      local heal = damage * 0.25
      for i = 1, 4 do
        local mote = MeshInstance3D { mesh = Loot.meshes.pill, material = G.M.glow, tint = Color(0.4, 1, 0.6), position = at + Vec3(rng:float(-1, 1), 1, rng:float(-1, 1)), scale = Vec3(0.6) }
        G.root:add_child(mote)
        local age = 0
        mote._process = function(m, d2)
          age = age + d2
          local to = self.position + Vec3(0, 1, 0) - m.position
          m.position = m.position + to:normalized() * math.min(to:length(), d2 * (6 + age * 14))
          if to:length() < 0.5 then
            self:heal(heal / 4)
            Audio.play(SFX.pill, { volume = 0.2, pitch = 1.4 })
            m:queue_free()
          end
        end
      end
    end
    n:queue_free()
  end
end

------------------------------------------------------------------ animation
function Player:_process(dt)
  if not self.sprite then return end
  local rig = self.rig
  local hv = self.velocity:flat()
  local speed = hv:length()
  local on_floor = self:is_on_floor()
  local combat = Input.down("aim") or Game.time - self._last_fire < 1.2 or self.held
  if combat and not self.locked then
    self._yaw = math.lerp_angle(self._yaw, rig.yaw, 1 - math.exp(-20 * dt))
  elseif self.wish and self.wish:length() > 0.1 then
    self._yaw = math.lerp_angle(self._yaw, math.atan2(-self.wish.x, -self.wish.z), 1 - math.exp(-12 * dt))
  end
  local spr = self.sprite
  spr.face_yaw = self._yaw
  spr:set_gun(self:gun())
  self._land_t = math.max(0, self._land_t - dt)

  -- Pick the animation from what Carl is doing, most urgent first.
  local want
  if self.dead then want = "die"
  elseif self.downed then want = (Game.time - self._last_fire < 0.25) and "fire" or "hurt"
  elseif (self._melee_t or 0) > 0 then want = "melee"
  elseif Game.time - self._hurt_t < 0.2 then want = "hurt"
  elseif self._dash_t > 0 then want = "dash"
  elseif self.held then want = "tractor"
  elseif self._reload then want = "reload"
  elseif self.hovering then want = "hover"
  elseif not on_floor then want = (self.velocity.y > 1 and not (spr.anim == "jump" and spr:done())) and "jump" or "air"
  elseif self._land_t > 0 then want = "land"
  elseif spr.anim == "fire" and not spr:done() then want = "fire"
  elseif combat then want = speed > 0.6 and "aimrun" or "aim"
  elseif speed > 0.6 then want = "run"
  elseif G.talker == "CARL" then want = "talk"
  else want = "idle" end
  if want == "air" and spr.anim == "jump" and not spr:done() and self.velocity.y > 1 then want = "jump" end
  spr:play(want)
  if want == "run" or want == "aimrun" then spr.speed = math.clamp(speed / 6.5, 0.7, 1.6)
  elseif want == "reload" then
    spr.speed = 0.59 / math.max(self._reload_max or 1, 0.3)
  elseif self.downed and want == "hurt" then spr.speed = 0.25
  else spr.speed = 1 end
  -- Hurt flash and shield tint.
  local hurt = math.clamp(1 - (Game.time - self._hurt_t) / 0.15, 0, 1)
  spr.tint = self.downed and Color(1.3, 0.75, 0.75) or Color(1 + hurt * 0.8, 1 - hurt * 0.4, 1 - hurt * 0.4)
  -- Dash afterimages.
  if self._dash_t > 0 then
    self._ghost_t = (self._ghost_t or 0) - dt
    if self._ghost_t <= 0 then self._ghost_t = 0.035; self:ghost() end
  end
  -- Reload: the fresh mag clicks in partway through.
  if self._reload then
    local g = self:gun()
    local t = 1 - self._reload / (self._reload_max or g.reload)
    if t > 0.6 and not self._mag_back then self._mag_back = true; Audio.play(SFX.mag_in, { volume = 0.35 }) end
  end
  self._recoil = math.max(0, self._recoil - dt * 7)
  self._flash_t = self._flash_t - dt
  if self._flash_t <= 0 then self.flash.visible = false end
  self:update_debris(dt)
  self.muzzle_light.energy = math.max(0, self.muzzle_light.energy - dt * 60)
  self.muzzle_light.position = Vec3(0.3, 1, -0.7)
  spr.visible = not (self.rig.distance < 0.9)
end

-- A fading cyan copy of the current frame (dash trail).
function Player:ghost()
  local spr = self.sprite
  local m = Material { albedo = Color(0.5, 1, 0.85, 0.55), texture = spr.mat.texture, transparent = true, unshaded = true, double_sided = true,
    uv_scale = spr.mat.uv_scale, uv_offset = spr.mat.uv_offset }
  local g = MeshInstance3D { mesh = spr.quad.mesh, material = m, cast_shadow = false, top_level = true }
  G.root:add_child(g)
  local gp, gr, gs = spr.quad:global_transform()
  g.position, g.rotation, g.scale = gp, gr, gs
  local age = 0
  g._process = function(n, d)
    age = age + d
    m.albedo = Color(0.5, 1, 0.85, 0.55 * (1 - age / 0.25))
    if age > 0.25 then n:queue_free() end
  end
end

------------------------------------------------------------------ camera
local CameraRig = Node3D:extend("CameraRig")

function CameraRig:_setup()
  Node3D._setup(self)
  self.top_level = true
  self.yaw, self.pitch = 0, -0.15
  self.distance = 3.8
  self.mode = "orbit"
  self.sensitivity = 0.0024
  self.orbit_t = 0
  self._kick = 0
end

function CameraRig:_ready()
  self.camera = self:add_child(Camera3D { fov = 70, current = true, far = 900 })
end

function CameraRig:kick(a, yaw)
  self._kick = self._kick + a
  self._kick_recover = (self._kick_recover or 0) + a * 0.6   -- most of the climb settles back
  self.yaw = self.yaw + (yaw or 0)
end
function CameraRig:shake(a) self._trauma = math.min(1, (self._trauma or 0) + a) end
function CameraRig:punch_fov(a) self._fov_punch = (self._fov_punch or 0) + a end

function CameraRig:_process(dt)
  local p = self.target
  if self.mode == "orbit" then
    self.orbit_t = self.orbit_t + dt * 0.06
    local c = self.orbit_center or Vec3(0, 0, 0)
    local a = self.orbit_t
    local pos = c + Vec3(math.sin(a) * 18, 7, math.cos(a) * 18)
    self.position = pos
    self.rotation = Quat.look_rotation(c + Vec3(0, 1.5, 0) - pos)
    self.camera.position = Vec3()
    return
  end
  if self.mode == "fixed" then return end
  if Input.is_mouse_captured() and not G.ui_open then
    local dx, dy = Input.mouse_delta()
    local sens = self.sensitivity * (Input.down("aim") and 0.6 or 1)
    self.yaw = self.yaw - dx * sens
    self.pitch = self.pitch - dy * sens
  end
  local sx, sy = Input.look_stick()
  self.yaw = self.yaw - sx * 2.8 * dt
  self.pitch = self.pitch - sy * 2.0 * dt
  -- Recoil climbs and settles.
  self.pitch = self.pitch + self._kick
  self._kick = 0
  if (self._kick_recover or 0) > 0 then
    local r = math.min(self._kick_recover, self._kick_recover * 9 * dt + 0.0005)
    self.pitch = self.pitch - r
    self._kick_recover = self._kick_recover - r
  end
  self.pitch = math.clamp(self.pitch, -1.2, 1.0)

  local aiming = Input.down("aim") and not p.locked and not G.ui_open
  local g = p:gun()
  local zoom = aiming and g and g.zoom
  local want_dist = aiming and 2.1 or 3.8
  local shoulder = aiming and 0.75 or 0.85
  local rot = Quat.from_y(self.yaw) * Quat.euler(self.pitch, 0, 0)
  local pivot = p.position + Vec3(0, 1.35, 0) + (Quat.from_y(self.yaw) * Vec3(shoulder, 0, 0))
  self._pivot = self._pivot and self._pivot:damp(pivot, 25, dt) or pivot
  local back = rot * Vec3(0, 0, 1)
  local hit = Physics.raycast(p.position + Vec3(0, 1.35, 0), self._pivot + back * (want_dist + 0.3), p)
  local d = want_dist
  if hit and not (hit.node and (hit.node.groups and (hit.node.groups.debris or hit.node.groups.gun_pickups) or hit.node == p.held)) then
    local total = (self._pivot + back * (want_dist + 0.3) - (p.position + Vec3(0, 1.35, 0))):length()
    d = math.max(0.3, want_dist - (total - hit.distance) - 0.3)
  end
  self.distance = d < self.distance and math.damp(self.distance, d, 30, dt) or math.damp(self.distance, d, 6, dt)
  self.position = self._pivot
  self.rotation = rot
  -- Screen shake from trauma (squared so small shakes stay subtle).
  self._trauma = math.max(0, (self._trauma or 0) - dt * 2.2)
  local tr = self._trauma ^ 2
  local t = Game.real_time * 40
  self.camera.position = Vec3(Noise.perlin2(t, 1.3) * 0.12 * tr, Noise.perlin2(t, 7.1) * 0.12 * tr, self.distance)
  self.camera.rotation = Quat.euler(Noise.perlin2(t, 3.7) * 0.03 * tr, Noise.perlin2(t, 5.2) * 0.03 * tr, Noise.perlin2(t, 9.9) * 0.05 * tr)
  local fov = zoom and 32 or (aiming and 55 or 70)
  if Input.down("sprint") and p.velocity:flat():length() > 8 then fov = 78 end
  self._fov_base = math.damp(self._fov_base or 70, fov, 10, dt)
  self._fov_punch = math.damp(self._fov_punch or 0, 0, 12, dt)
  self.camera.fov = self._fov_base + self._fov_punch
end

return { Player = Player, CameraRig = CameraRig }
