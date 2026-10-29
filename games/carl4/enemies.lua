-- Enemies: White Suits, Postal Inspectors, Jumper Cacti, Lemon Drones and the boss HU-MAN.
local Art = require("art")
local Props = require("props")
local Gear = require("gear")
local Skills = require("skills")
local Loot = require("loot")
local SpriteActor = require("sprite_actor")
local Combat = Props.Combat
local P = Art.pal
local Enemies = {}

local M
local meshes = {}

local function recolor(md, from, to)
  return md:copy():paint_fn(function(x, y, z, r, g, b)
    if math.abs(r - from.r) < 0.02 and math.abs(g - from.g) < 0.02 and math.abs(b - from.b) < 0.02 then return to.r, to.g, to.b end
    return r, g, b
  end)
end

function Enemies.init(materials)
  M = materials
  meshes.cactus = Art.cactus_enemy():upload()
  local d = Art.drone_parts()
  meshes.drone, meshes.rotor, meshes.drone_eye = d.body:upload(), d.rotor:upload(), d.eye:upload()
  meshes.pistol = Art.gun_mesh("pistol", P.metal, nil):upload()
  meshes.shotgun = Art.gun_mesh("shotgun", Color.hex("#3d5a8f"), nil):upload()
  M.drone_eye = Material { albedo = Color.hex("#ff3b3b"), unshaded = true }
end

------------------------------------------------------------------ shared behaviour (mixed into each class)
local Base = {}

-- layers: { shield = fraction of hp as a recharging shield, armor = true for a yellow armor bar instead of flesh }.
function Base.init_stats(self, hp, xp, layers)
  local L = self.level or 1
  layers = layers or {}
  if self.badass then
    hp, xp = hp * 2.6, xp * 3
    layers = { shield = math.max(layers.shield or 0, 0.4), armor = layers.armor }
    self.display = "BADASS " .. self.display
    self.loot_luck = (self.loot_luck or 0) + 1.4
  end
  self.max_hp = math.floor(hp * 1.16 ^ (L - 1))
  self.hp = self.max_hp
  self.layer = layers.armor and "armor" or "flesh"
  self.max_eshield = math.floor(self.max_hp * (layers.shield or 0))
  self.eshield = self.max_eshield
  self.xp = math.floor(xp * (1 + (L - 1) * 0.35))
  self.dmg_scale = 1.12 ^ (L - 1)
  self.is_enemy = true
  self.last_hit = -10
  self.burn, self.float_t = nil, 0
  self:add_to_group("enemies")
end

function Base.player_visible(self, from)
  local p = G.player
  if not p or p.dead then return false end
  local to = p.position + Vec3(0, 0.8, 0)
  local hit = Physics.raycast(from, to, self)
  return hit and hit.node == p
end

function Base.take_damage(self, amount, info)
  if self.dead then return 0 end
  if self.on_damage then amount = self:on_damage(amount, info) or amount end
  if amount <= 0 then return 0 end
  -- Abducted enemies are being probed: they take extra damage.
  if self.abducted and self.float_t > 0 then amount = amount * Skills.probe() end
  -- Shield first (static eats it), then armor or flesh, each with its own elemental multiplier.
  local et = info.elem_type or info.element or (info.gun and info.gun.element)
  local dealt = 0
  local m_hp = Gear.mult(et, self.layer)
  if self.eshield > 0 then
    local m_sh = Gear.mult(et, "shield")
    local d = amount * m_sh
    if d < self.eshield then
      self.eshield = self.eshield - d
      dealt = d
      amount = 0
      info.eff = m_sh > 1.2 and "EFFECTIVE" or m_sh < 0.8 and "RESISTED" or nil
    else
      dealt = self.eshield
      amount = (d - self.eshield) / m_sh
      self.eshield = 0
      Audio.play_at(SFX.shield_break, self:global_position(), { volume = 0.45, pitch = 1.3 })
      G.root:add_child(Props.burst(self:global_position() + Vec3(0, 1.2, 0), Gear.LAYER_COLOR.shield, 24, 5))
    end
  end
  if amount > 0 then
    local d = amount * m_hp
    self.hp = self.hp - d
    dealt = dealt + d
    info.eff = m_hp > 1.2 and "EFFECTIVE" or m_hp < 0.8 and "RESISTED" or info.eff
  end
  self._shield_hit = Game.time
  self.last_hit = Game.time
  self.aggro = true
  self._flash = 0.12
  if info.dir and self.velocity and not self.heavy then
    self.velocity = self.velocity + info.dir:flat() * math.min(amount * 0.05, 4)
  end
  local e = info.element
  if e == "fire" then
    self.burn = { t = 3, dps = amount * 0.4 }
  elseif e == "static" then
    local hits = 0
    for _, other in ipairs(Game.group("enemies")) do
      if other ~= self and not other.dead and hits < 2 and other:global_position():distance(self:global_position()) < 9 then
        hits = hits + 1
        Props.lightning(self:global_position() + Vec3(0, 1, 0), other:global_position() + Vec3(0, 1, 0), G.root)
        Combat.damage(other, amount * 0.55, { pos = other:global_position() + Vec3(0, 1.2, 0) })
      end
    end
    Audio.play_at(SFX.zap, self:global_position(), { volume = 0.5 })
  elseif e == "curse" and not self.boss then
    self.float_t = 2.4
    Audio.play_at(SFX.curse, self:global_position(), { volume = 0.5 })
  end
  if self.hp <= 0 then self:die(info) end
  return dealt
end

-- Breaks the visual into rigid pieces that tumble away.
function Base.ragdoll(self, dir)
  local parent = self.parent
  local pieces = {}
  for _, mi in ipairs(self:find_all(MeshInstance3D)) do
    if mi.mesh and mi.ragdoll ~= false then pieces[#pieces + 1] = mi end
  end
  for _, mi in ipairs(pieces) do
    local gp, gr, gs = mi:global_transform()
    local size = mi.mesh:size() * gs
    local centre = (mi.mesh.aabb_min + mi.mesh.aabb_max) * 0.5 * gs
    size = Vec3(math.max(size.x, 0.1), math.max(size.y, 0.1), math.max(size.z, 0.1))
    local body = RigidBody3D { position = gp, rotation = gr, shape = Shape.offset(Shape.box(size.x, size.y, size.z), centre), mass = 6, friction = 0.8,
      groups = { "debris" }, angular_damp = 0.4,
      MeshInstance3D { mesh = mi.mesh, material = mi.material, scale = gs },
    }
    parent:add_child(body)
    body:set_velocity((dir or Vec3(0, 0, 0)) * rng:float(4, 9) + Vec3(rng:float(-2, 2), rng:float(3, 7), rng:float(-2, 2)),
      Vec3(rng:float(-8, 8), rng:float(-8, 8), rng:float(-8, 8)))
    Game.after(7 + rng:float(0, 2), function()
      if body:is_valid() then
        Tween.to(body, { scale = Vec3(0.01) }, 0.4, { on_done = function() body:queue_free() end })
      end
    end, body)
  end
end

function Base.die(self, info)
  self.dead = true
  local pos = self:global_position()
  G.add_xp(self.xp, pos + Vec3(0, 2, 0))
  G.stats.kills = G.stats.kills + 1
  Loot.drop(self.parent, pos, self.level, self.loot_luck or 0, self.badass)
  if G.player then G.player:on_kill(self) end
  Audio.play_at(self.death_sound or SFX.enemy_die, pos, { volume = 0.7, pitch = rng:float(0.9, 1.1) })
  if self.death_line and rng:chance(0.45) then G.say(self.display, self.death_line[rng:int(1, #self.death_line)], 2.2, true) end
  self.parent:add_child(Props.burst(pos + Vec3(0, 1, 0), Color(1, 1, 1), 20, 5))
  if self.sprite then self:corpse(info and info.dir) else self:ragdoll(info and info.dir) end
  if self.on_death then self:on_death() end
  self:queue_free()
end

-- Pixel characters play their death animation on a corpse that slides with the hit, then sinks away.
function Base.corpse(self, dir)
  local spr = self.sprite
  local c = SpriteActor { sheet_name = spr.sheet_name, size = spr.size, position = self:global_position() }
  c.face_yaw = spr.face_yaw
  c._back, c._flip, c._sx = spr._back, spr._flip, spr._sx
  self.parent:add_child(c)
  c:play("die")
  local vel = (dir or Vec3()):flat() * 4
  local age = 0
  local base_process = c._process
  c._process = function(n, dt)
    base_process(n, dt)
    age = age + dt
    vel = vel:move_toward(Vec3(), 10 * dt)
    local p = n.position + vel * dt
    n.position = Vec3(p.x, World.height(p.x, p.z) > p.y - 2 and math.max(p.y, World.height(p.x, p.z)) or p.y, p.z)
    if age > 6 then n.position = n.position - Vec3(0, dt * 0.6, 0) end
    if age > 7.5 then n:queue_free() end
  end
end

-- Burn, float and hit-flash; returns true if the enemy is incapacitated this frame.
function Base.status(self, dt)
  if self.max_eshield > 0 and self.eshield < self.max_eshield and Game.time - (self._shield_hit or -10) > 4 then
    self.eshield = math.min(self.max_eshield, self.eshield + self.max_eshield * 0.25 * dt)
  end
  if self.burn then
    self.burn.t = self.burn.t - dt
    self._burn_tick = (self._burn_tick or 0) - dt
    if self._burn_tick <= 0 then
      self._burn_tick = 0.5
      Combat.damage(self, self.burn.dps * 0.5, { pos = self:global_position() + Vec3(0, 1.4, 0), element = nil, burn = true })
      if self.dead then return true end
      G.root:add_child(Props.burst(self:global_position() + Vec3(0, 1, 0), P.fire, 8, 2))
    end
    if self.burn.t <= 0 then self.burn = nil end
  end
  if self._flash then
    self._flash = self._flash - dt
    local t = self._flash > 0 and Color(1.9, 1.9, 1.9) or Color.WHITE
    for _, mi in ipairs(self._tinted or {}) do mi.tint = t end
    if self.sprite then self.sprite.tint = self._flash > 0 and t or (self.badass and Color(1.15, 0.9, 1.25) or Color.WHITE) end
    if self._flash <= 0 then self._flash = nil end
  end
  if self.float_t > 0 then
    self.float_t = self.float_t - dt
    return true
  end
  return false
end

local function mix(cls)
  for k, f in pairs(Base) do cls[k] = f end
end

local function dist_to_player(pos)
  local p = G.player
  if not p then return 1e9 end
  return pos:distance(p.position)
end

------------------------------------------------------------------ pixel humanoids (suits, inspectors, HU-MAN)
local function build_humanoid(self, sheet, size)
  if self.badass then size = (size or 1) * 1.3 end
  self.sprite = self:add_child(SpriteActor { sheet_name = sheet, size = size or 1 })
  self.visual = self.sprite
  self._walk = 0
  self.sprite.on_frame = function(spr, anim, i)
    if (anim == "walk" or anim == "aimwalk") and (i == 1 or i == 5) and self.position:distance(G.player.position) < 25 then
      Audio.play_at(SFX.step, self.position, { volume = 0.1 * (size or 1), pitch = rng:float(0.8, 1.0) / (size or 1) })
    end
  end
end

-- Chooses the sprite animation from movement and intent. 'action' overrides (slam, throw, flex...).
local function animate_humanoid(self, dt, aiming)
  local spr = self.sprite
  spr.face_yaw = self._yaw or 0
  local speed = self.velocity:flat():length()
  local want
  if self.float_t and self.float_t > 0 then want = "hurt"
  elseif self.action then want = self.action
  elseif Game.time - self.last_hit < 0.16 then want = "hurt"
  elseif spr.anim == "fire" and not spr:done() then want = "fire"
  elseif aiming then want = speed > 0.5 and "aimwalk" or "aim"
  elseif speed > 0.5 then want = "walk"
  elseif self.talking or (G.talker and self.display and string.upper(self.display) == G.talker) then want = "talk"
  else want = "idle" end
  spr:play(want)
  spr.speed = (want == "walk" or want == "aimwalk") and math.clamp(speed / 3.6, 0.6, 1.8) or 1
end

local function face(self, target_yaw, dt, rate)
  self._yaw = math.lerp_angle(self._yaw or 0, target_yaw, 1 - math.exp(-(rate or 8) * dt))
end

local function muzzle_of(self)
  local f = Quat.from_y(self._yaw or 0) * Vec3(0, 0, -1)
  return self.sprite:hand_position() + f * 0.35 * self.sprite.size
end

local function yaw_to(from, to)
  local d = to - from
  return math.atan2(-d.x, -d.z)
end

------------------------------------------------------------------ White Suit / Postal Inspector
local Suit = CharacterBody3D:extend("Suit")
mix(Suit)

function Suit:_setup()
  CharacterBody3D._setup(self)
  self.radius, self.height = 0.38, 1.85
end

function Suit:_ready()
  local postal = self.variant == "postal"
  self.display = postal and "Postal Inspector" or "White Suit"
  self.heavy = postal
  self:init_stats(postal and 210 or 70, postal and 60 or 25, postal and { armor = true } or nil)
  self.head_y = 1.5
  build_humanoid(self, postal and "postal" or "suit", postal and 1.08 or 0.95)
  self.home = self.position:copy()
  self._cd = rng:float(1, 2)
  self._strafe = rng:chance(0.5) and 1 or -1
  self._strafe_t = rng:float(1, 3)
  self.death_line = postal and { "Return... to sender...", "This is federal property.", "I'll need that in writing." }
    or { "File... a form...", "Tell the Committee... I tried.", "This wasn't in the script.", "Cut. Cut!" }
  self.alert_line = postal and { "Postal Inspection Service. Freeze.", "That package is evidence." }
    or { "Sir, this is a closed set.", "Containment breach. It's the green one.", "Mr. Carl, please return to your tube.", "He's off-script!" }
end

function Suit:_physics_process(dt)
  if self.dead then return end
  local held = self:status(dt)
  if self.dead then return end
  local p = G.player
  local pos = self.position
  local dist = dist_to_player(pos)
  local v = self.velocity
  local vy = v.y
  local hv = Vec3(v.x, 0, v.z)
  if held then
    vy = 2.2
    hv = hv * 0.95
  elseif dist > 75 then
    hv = Vec3()
  else
    if not self.aggro and dist < 34 and self:player_visible(pos + Vec3(0, 1.6, 0)) then
      self.aggro = true
      if rng:chance(0.6) then G.say(self.display, self.alert_line[rng:int(1, #self.alert_line)], 2.4, true) end
      Audio.play_at(SFX.alert, pos, { volume = 0.5 })
    end
    local want = Vec3()
    if self.aggro and p and not p.dead then
      local to = (p.position - pos):flat()
      local dir = to:normalized()
      local side = Vec3(-dir.z, 0, dir.x) * self._strafe
      local ideal = self.heavy and 7 or 13
      if dist > ideal + 4 then want = dir
      elseif dist < ideal - 4 then want = -dir * 0.8
      else want = side * 0.7 end
      self._strafe_t = self._strafe_t - dt
      if self._strafe_t < 0 then self._strafe_t = rng:float(1.2, 3); self._strafe = -self._strafe end
      face(self, yaw_to(pos, p.position), dt, 10)
      -- Shooting.
      self._cd = self._cd - dt
      if self._cd <= 0 and dist < 45 then
        local eye = pos + Vec3(0, 1.5, 0)
        if self:player_visible(eye) then self:shoot() end
        self._cd = self.heavy and rng:float(1.6, 2.4) or rng:float(1.3, 2.2)
      end
    else
      local to = (self.home - pos):flat()
      if to:length() > 2 then want = to:normalized() * 0.4; face(self, yaw_to(pos, self.home), dt, 4) end
    end
    hv = hv:move_toward(want * (self.heavy and 3.2 or 4.6), 18 * dt)
    vy = self:is_on_floor() and -1 or vy - 25 * dt
  end
  self.velocity = Vec3(hv.x, vy, hv.z)
  self:move_and_slide(dt)
  animate_humanoid(self, dt, self.aggro and dist < 50)
end

function Suit:shoot()
  self:spawn(function()
    local n = self.heavy and 1 or 3
    for _ = 1, n do
      if self.dead or not G.player then return end
      local muzzle = muzzle_of(self)
      self.sprite:play("fire", true)
      local target = G.player.position + Vec3(0, 0.75, 0) + G.player.velocity * 0.15
      local dir = (target - muzzle):normalized()
      if self.heavy then
        for k = -2, 2 do
          local d = (Quat.from_y(k * 0.08) * dir + Vec3(0, rng:float(-0.03, 0.03), 0)):normalized()
          Combat.fire_projectile({ pos = muzzle, vel = d * 34, owner = "enemy", damage = 6 * self.dmg_scale, exclude = self, life = 1.2 })
        end
        Audio.play_at(SFX.enemy_shotgun, muzzle, { volume = 0.6 })
      else
        dir = (dir + Vec3(rng:float(-0.04, 0.04), rng:float(-0.03, 0.03), rng:float(-0.04, 0.04))):normalized()
        Combat.fire_projectile({ pos = muzzle, vel = dir * 42, owner = "enemy", damage = 5.5 * self.dmg_scale, exclude = self })
        Audio.play_at(SFX.enemy_shot, muzzle, { volume = 0.45, pitch = rng:float(0.95, 1.1) })
      end
      wait(0.13)
    end
  end)
end

------------------------------------------------------------------ Jumper Cactus
local Cactus = CharacterBody3D:extend("Cactus")
mix(Cactus)

function Cactus:_setup()
  CharacterBody3D._setup(self)
  self.radius, self.height = 0.36, 1.3
end

function Cactus:_ready()
  self.display = "Jumper Cactus"
  self:init_stats(48, 16)
  self.head_y = 0.85
  self.visual = self:add_child(Node3D { scale = Vec3(self.badass and 1.35 or 1) })
  self.mesh = self.visual:add_child(MeshInstance3D { mesh = meshes.cactus, material = M.vertex })
  self._tinted = { self.mesh }
  self._hop = rng:float(0.3, 1)
  self._bite = 0
  self._squash = 0
end

function Cactus:_physics_process(dt)
  if self.dead then return end
  local held = self:status(dt)
  if self.dead then return end
  local p = G.player
  local pos = self.position
  local dist = dist_to_player(pos)
  local v = self.velocity
  local on_floor = self:is_on_floor()
  if held then
    self.velocity = Vec3(v.x * 0.95, 2.2, v.z * 0.95)
    self:move_and_slide(dt)
    self.visual.rotation = Quat.euler(Game.time * 4, 0, Game.time * 2)
    return
  end
  if dist > 75 then return end
  if not self.aggro and dist < 22 then self.aggro = true end
  local vy = v.y
  local hv = Vec3(v.x, 0, v.z)
  if on_floor then
    hv = hv:move_toward(Vec3(), 30 * dt)
    if vy < 0 then
      if (self._air or 0) > 0.3 then self._squash = 0.35; self.parent:add_child(Props.dust(pos, 6)) end
      vy = -1
    end
    self._air = 0
    self._hop = self._hop - dt
    if self.aggro and p and not p.dead and self._hop <= 0 then
      local dir = (p.position - pos):flat():normalized()
      local s = math.clamp(dist * 1.2, 4, 9)
      hv = dir * s
      vy = 8
      self._hop = rng:float(0.45, 0.9)
      self._squash = -0.25
      Audio.play_at(SFX.boing, pos, { volume = 0.35, pitch = rng:float(0.9, 1.2) })
    end
  else
    self._air = (self._air or 0) + dt
    vy = vy - 22 * dt
  end
  self.velocity = Vec3(hv.x, vy, hv.z)
  self:move_and_slide(dt)
  if p and self.aggro then
    self._yaw = math.lerp_angle(self._yaw or 0, yaw_to(pos, p.position), 1 - math.exp(-10 * dt))
  end
  self._squash = self._squash * math.exp(-8 * dt)
  self.visual.rotation = Quat.from_y(self._yaw or 0)
  self.visual.scale = Vec3(1 + self._squash * 0.5, 1 - self._squash, 1 + self._squash * 0.5)
  -- Spiky contact damage.
  self._bite = self._bite - dt
  if p and not p.dead and self._bite <= 0 and p.position:distance(pos) < 1.15 then
    self._bite = 0.9
    p:take_damage(11 * self.dmg_scale, { pos = pos })
    p.velocity = p.velocity + (p.position - pos):flat():normalized() * 6 + Vec3(0, 3, 0)
    Audio.play_at(SFX.hit, pos, { volume = 0.6 })
  end
end

------------------------------------------------------------------ Lemon Drone
local Drone = AnimatableBody3D:extend("Drone")
mix(Drone)

function Drone:_ready()
  self.display = "Lemon Drone"
  self.shape = self.shape or Shape.sphere(0.5)
  self:init_stats(36, 18, { shield = 0.8, armor = true })
  self.head_y = -10
  self.visual = self:add_child(Node3D { scale = Vec3(self.badass and 1.35 or 1) })
  local body = self.visual:add_child(MeshInstance3D { mesh = meshes.drone, material = M.glossy })
  self.eye = self.visual:add_child(MeshInstance3D { mesh = meshes.drone_eye, material = M.drone_eye, position = Vec3(0, -0.02, -0.46), ragdoll = false })
  self.rotors = {}
  for i = 0, 3 do
    local a = i / 4 * math.tau + math.pi / 4
    self.rotors[i + 1] = self.visual:add_child(MeshInstance3D { mesh = meshes.rotor, material = M.metal, position = Vec3(math.cos(a) * 0.75, 0.2, math.sin(a) * 0.75), cast_shadow = false, ragdoll = false })
  end
  self._tinted = { body }
  self.home = self.position:copy()
  self.vel3 = Vec3()
  self._cd = rng:float(1, 2.5)
  self._orbit = rng:float(0, math.tau)
  self.hum = self:add_child(AudioPlayer3D { sound = SFX.drone_hum, loop = true, volume = 0.18, autoplay = true })
end

function Drone:_physics_process(dt)
  if self.dead then return end
  local held = self:status(dt)
  if self.dead then return end
  local p = G.player
  local pos = self.position
  local dist = dist_to_player(pos)
  for i, r in ipairs(self.rotors) do r.rotation = Quat.from_y(Game.time * 30 * (i % 2 == 0 and 1 or -1)) end
  if held then
    self.position = pos + Vec3(0, 2.5 * dt, 0)
    self.visual.rotation = Quat.euler(Game.time * 5, Game.time * 3, 0)
    return
  end
  if dist > 80 then return end
  if not self.aggro and dist < 32 then self.aggro = true end
  local goal = self.home
  if self.aggro and p and not p.dead then
    self._orbit = self._orbit + dt * 0.5
    local ground = World.height(p.position.x, p.position.z)
    goal = p.position + Vec3(math.cos(self._orbit) * 11, 0, math.sin(self._orbit) * 11)
    goal = Vec3(goal.x, math.max(ground, p.position.y) + 6 + math.sin(Game.time * 1.3 + self._orbit) * 1.2, goal.z)
    self._cd = self._cd - dt
    if self._cd <= 0 then
      self._cd = rng:float(1.4, 2.4)
      if self:player_visible(pos) then
        local target = p.position + Vec3(0, 0.7, 0) + p.velocity * 0.2
        local dir = (target - pos):normalized()
        Combat.fire_projectile({ pos = pos + dir * 0.6, vel = dir * 30, owner = "enemy", damage = 7 * self.dmg_scale, mat = M.bolt_drone, exclude = self, scale = 1.2 })
        Audio.play_at(SFX.laser, pos, { volume = 0.5 })
      end
    end
  end
  local to = goal - pos
  self.vel3 = self.vel3:move_toward(to:clamp_length(7), 14 * dt)
  self.position = pos + self.vel3 * dt
  local look = p and self.aggro and (p.position - pos) or self.vel3
  if look:flat():length() > 0.1 then
    self._yaw = math.lerp_angle(self._yaw or 0, math.atan2(-look.x, -look.z), 1 - math.exp(-6 * dt))
  end
  self.visual.rotation = Quat.from_y(self._yaw or 0) * Quat.euler(-self.vel3:length() * 0.03, 0, 0)
end

function Drone:on_death()
  -- One last sad little explosion.
  Props.explosion(self.position, 2.5, 20, 0, true)
end

------------------------------------------------------------------ HU-MAN (boss)
local Human = CharacterBody3D:extend("Human")
mix(Human)

function Human:_setup()
  CharacterBody3D._setup(self)
  self.radius, self.height = 1.0, 4.4
end

function Human:_ready()
  self.display = "HU-MAN"
  self.boss = true
  self.heavy = true
  self:init_stats(5200, 900, { shield = 0.3, armor = true })
  self.head_y = 3.6
  build_humanoid(self, "human", 2.2)
  self.action = "flex"
  self.state = "intro"
  self._t = 0
  self._attack = 2.5
  self.phase = 1
  self.summons = 0
  self.aggro = true
  self.death_sound = SFX.boss_die
  self.loot_luck = 3
end

function Human:on_damage(amount, info)
  if self.state == "intro" then return 0 end
  return amount
end

function Human:_physics_process(dt)
  if self.dead then return end
  self:status(dt)
  if self.dead then return end
  local p = G.player
  local pos = self.position
  local v = self.velocity
  local vy = v.y
  local hv = Vec3(v.x, 0, v.z)
  local on_floor = self:is_on_floor()
  self._t = self._t + dt

  -- Summon backup at 66% and 33%.
  local frac = self.hp / self.max_hp
  if (self.summons == 0 and frac < 0.66) or (self.summons == 1 and frac < 0.33) then
    self.summons = self.summons + 1
    self.phase = self.summons + 1
    G.say("HU-MAN", self.summons == 1 and "SEQUEL COMMITTEE! TO SET!" or "BY THE POWER OF NEVADA!", 2.6)
    for i = 1, 3 do
      local a = i / 3 * math.tau + self._t
      local sp = pos + Vec3(math.cos(a) * 9, 0, math.sin(a) * 9)
      sp = Vec3(sp.x, World.height(sp.x, sp.z) + 0.3, sp.z)
      local e = Enemies.spawn(i == 2 and self.summons == 2 and "postal" or "suit", sp, self.level)
      e.aggro = true
      self.parent:add_child(e)
      self.parent:add_child(Props.burst(sp + Vec3(0, 1, 0), P.white, 30, 6))
    end
  end

  if self.state == "intro" then
    hv = Vec3()
    if p then face(self, yaw_to(pos, p.position), dt, 4) end
  elseif self.state == "walk" then
    if p and not p.dead then
      local dist = pos:distance(p.position)
      local dir = (p.position - pos):flat():normalized()
      local want = dist > 10 and dir or (dist < 6 and -dir or Vec3(-dir.z, 0, dir.x))
      hv = hv:move_toward(want * (3 + self.phase * 0.6), 10 * dt)
      face(self, yaw_to(pos, p.position), dt, 5)
      self._attack = self._attack - dt
      if self._attack <= 0 then self:choose_attack(dist) end
    end
  elseif self.state == "slam_up" then
    if on_floor and self._t > 0.3 then self:slam_land() end
  end
  vy = on_floor and math.max(vy, -1) or vy - 30 * dt
  if self._jump then vy = self._jump; self._jump = nil end
  self.velocity = Vec3(hv.x, vy, hv.z)
  self:move_and_slide(dt)
  if self.state ~= "intro" and self.action == "flex" then self.action = nil end
  animate_humanoid(self, dt, self.state == "shoot")
end

function Human:choose_attack(dist)
  local roll = rng:float(0, 1)
  if dist < 14 and roll < 0.4 then self:slam()
  elseif roll < 0.7 or self.phase == 1 then self:volley()
  else self:hurl() end
end

function Human:volley()
  self.state = "shoot"
  self:spawn(function()
    wait(0.4)
    local n = 2 + self.phase
    for _ = 1, n do
      if self.dead or not G.player then return end
      local muzzle = muzzle_of(self)
      self.sprite:play("fire", true)
      local dir = (G.player.position + Vec3(0, 0.7, 0) - muzzle):normalized()
      for k = -2, 2 do
        local d = Quat.from_y(k * 0.12) * dir
        Combat.fire_projectile({ pos = muzzle, vel = d * 26, owner = "enemy", damage = 9 * self.dmg_scale, exclude = self, scale = 2.2, life = 3 })
      end
      Audio.play_at(SFX.boss_shot, muzzle, { volume = 0.7 })
      wait(0.55)
    end
    self.state = "walk"
    self._attack = rng:float(1.4, 2.4) / (0.6 + self.phase * 0.4)
  end)
end

function Human:slam()
  self.state = "slam_up"
  self.action = "slam"
  self.sprite:play("slam", true)
  self._t = 0
  G.say("HU-MAN", rng:pick({ "NORMAL HUMAN JUMP!", "BY THE POWER OF NEVADA!", "Watch this. Focus groups love this." }), 1.8)
  local p = G.player
  local to = p and (p.position - self.position):flat() or Vec3()
  self._jump = 17
  self.velocity = to * 0.9 / 1.1
  Audio.play_at(SFX.jump, self.position, { volume = 0.9, pitch = 0.5 })
end

function Human:slam_land()
  self.state = "walk"
  Game.after(0.35, function() if self:is_valid() and self.action == "slam" then self.action = nil end end, self)
  self._attack = rng:float(1.5, 2.5)
  self.velocity = Vec3()
  local pos = self.position
  Audio.play_at(SFX.explosion, pos, { volume = 1, pitch = 0.6 })
  G.rig:shake(0.9)
  self.parent:add_child(Props.dust(pos + Vec3(0, 0.3, 0), 40))
  -- Expanding shockwave ring: jump over it.
  local ring = Props.shockwave(pos + Vec3(0, 0.3, 0), 18, Color(1, 0.6, 0.3), 1.0)
  self.parent:add_child(ring)
  local hit = false
  local age = 0
  local checker = Node {}
  checker._process = function(n, dt)
    age = age + dt
    local r = 18 * Ease.out_cubic(math.min(age, 1))
    local pl = G.player
    if pl and not hit and pl:is_on_floor() then
      local d = (pl.position - pos):flat():length()
      if math.abs(d - r) < 1.3 and pl.position.y < pos.y + 1.5 then
        hit = true
        pl:take_damage(22 * self.dmg_scale, { pos = pos })
        pl.velocity = pl.velocity + (pl.position - pos):flat():normalized() * 12 + Vec3(0, 8, 0)
      end
    end
    if age > 1 then n:queue_free() end
  end
  self.parent:add_child(checker)
  for _, node in ipairs(Physics.overlap_sphere(pos, 12)) do
    if node:is(RigidBody3D) and node._body then node:apply_impulse(((node.position - pos):normalized() + Vec3(0, 1.5, 0)) * (node.mass or 10) * 6) end
  end
end

-- Picks up a crate or a Prop Pills barrel with his own (pink) tractor beam and throws it.
function Human:hurl()
  self.state = "throw"
  self.action = "throw"
  self.sprite:play("throw", true)
  self.sprite.speed = 0
  self:spawn(function()
    local hand = self.sprite:hand_position()
    local explosive = rng:chance(0.5)
    local obj = explosive and Props.explosive(hand + Vec3(0, 2, 0)) or Props.crate(hand + Vec3(0, 2, 0), 1.4)
    obj.no_grab = false
    self.parent:add_child(obj)
    G.say("HU-MAN", explosive and "Catch! It's a normal human barrel." or "Lift with your legs. Like a human.", 2)
    for _ = 1, 50 do
      if self.dead or not obj:is_valid() or not obj._body then break end
      local h = self.position + Vec3(0, 6.5, 0)
      obj:set_velocity((h - obj.position) * 8)
      wait(0.02)
    end
    if obj:is_valid() and obj._body and G.player and not self.dead then
      local target = G.player.position + Vec3(0, 0.5, 0) + G.player.velocity * 0.5
      local d = target - obj.position
      local t = 1.0
      local vel = Vec3(d.x / t, d.y / t + 0.5 * 26 * t, d.z / t)
      obj:set_velocity(vel, Vec3(3, 2, 1))
      obj.thrown_by_boss = Game.time
      obj:connect("body_entered", function(other, info)
        if obj.thrown_by_boss and Game.time - obj.thrown_by_boss < 3 and other == G.player then
          obj.thrown_by_boss = nil
          G.player:take_damage(20 * self.dmg_scale, { pos = obj.position })
        end
        if explosive and obj.thrown_by_boss and info.speed > 6 then obj.thrown_by_boss = nil; obj:explode() end
      end)
      Audio.play(SFX.throw, { volume = 0.7, pitch = 0.6 })
    end
    wait(0.5)
    self.action = nil
    self.state = "walk"
    self._attack = rng:float(1.5, 2.5)
  end)
end

------------------------------------------------------------------ spawning
function Enemies.spawn(kind, pos, level, badass)
  level = level or 1
  if badass == nil and kind ~= "human" then badass = rng:chance(level >= 3 and 0.12 or 0.07) end
  if kind == "suit" then return Suit { position = pos, level = level, badass = badass }
  elseif kind == "postal" then return Suit { position = pos, level = level, variant = "postal", badass = badass }
  elseif kind == "cactus" then return Cactus { position = pos, level = level, badass = badass }
  elseif kind == "drone" then return Drone { position = pos, level = level, shape = Shape.sphere(0.55), badass = badass }
  elseif kind == "human" then return Human { position = pos, level = level }
  end
end

-- A group of enemies scattered round a point on the ground.
function Enemies.camp(root, center, list, level, radius)
  local out = {}
  for i, kind in ipairs(list) do
    local a = i / #list * math.tau + rng:float(-0.3, 0.3)
    local r = rng:float(radius * 0.4, radius)
    local x, z = center.x + math.cos(a) * r, center.z + math.sin(a) * r
    local y = World.height(x, z) + (kind == "drone" and 6 or 0.3)
    if center.y and center.y > y then y = center.y + (kind == "drone" and 6 or 0.3) end
    local e = Enemies.spawn(kind, Vec3(x, y, z), level)
    root:add_child(e)
    out[#out + 1] = e
  end
  return out
end

Enemies.Human = Human
return Enemies
