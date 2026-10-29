-- Physics props, effects, projectiles, explosions and the damage pipeline.
local Art = require("art")
local P = Art.pal
local Props = {}
local Combat = {}
Props.Combat = Combat

local M
local meshes = {}
Props.meshes = meshes

function Props.init(materials)
  M = materials
  meshes.crate = Art.crate():upload()
  meshes.barrel = Art.barrel(Color.hex("#4d6b8a"), P.metal_dark):upload()
  meshes.explosive = Art.explosive_barrel():upload()
  meshes.tumbleweed = Art.tumbleweed():upload()
  meshes.cow = Art.cow():upload()
  meshes.engine = Art.engine_block():upload()
  meshes.tire = Art.tire():upload()
  meshes.cinder = MeshData.box(0.8, 0.4, 0.4, Color.hex("#a8a49c")):flat():upload()
  meshes.plank = MeshData.box(1, 1, 1, P.wood_grey):flat():upload()
  meshes.tracer = MeshData.box(1, 1, 1, Color.WHITE):upload()
  meshes.bolt = MeshData.sphere(0.12, 10, 8, Color.WHITE):upload()
  meshes.rocket = MeshData.capsule(0.09, 0.45, 8, Color.WHITE):transform(nil, Quat.euler(math.pi / 2, 0, 0)):upload()
  meshes.ring = MeshData.torus(1, 0.08, 40, 6, Color.WHITE):upload()
  meshes.sphere = MeshData.sphere(1, 20, 14, Color.WHITE):upload()
  meshes.boulders = {}
  for i = 1, 3 do meshes.boulders[i] = Art.boulder(i, 1):upload() end
  M.bolt_enemy = Material { albedo = Color.hex("#ff4a6a"), unshaded = true }
  M.bolt_drone = Material { albedo = Color.hex("#ffe14a"), unshaded = true }
  M.rocket = Material { albedo = Color.hex("#eeeeee"), emission = Color.hex("#ff8a3a"), emission_energy = 1.5 }
  M.flash = Material { albedo = Color.hex("#ffd07a", 0.8), unshaded = true, transparent = true, no_fog = true }
end

------------------------------------------------------------------ helpers
local function impact_sound(body, sound, min_speed, volume)
  body:connect("body_entered", function(other, info)
    if info.speed < (min_speed or 2) then return end
    if body._last_sound and Game.time - body._last_sound < 0.12 then return end
    body._last_sound = Game.time
    Audio.play_at(sound, info.point, { volume = math.clamp(info.speed / 10, 0.1, 1) * (volume or 1), pitch = rng:float(0.85, 1.15) })
  end)
end

-- Thrown props (from the tractor beam) hurt whatever they slam into.
local function thrown_damage(body)
  body:connect("body_entered", function(other, info)
    if not body.thrown or Game.time - body.thrown > 3 then return end
    if info.speed < 6 then return end
    local target = Combat.target_of(other)
    if target and target.is_enemy then
      local dmg = (body.mass or 20) * info.speed * 0.09 * (1 + (G.level - 1) * 0.12)
      Combat.damage(target, dmg, { pos = info.point, dir = body:get_velocity():normalized(), kind = "physics" })
      body.thrown = nil
    end
  end)
end

local function prop(name, pos, rot, shape, mass, mesh, mat, extra)
  local b = RigidBody3D {
    name = name, position = pos, rotation = rot or Quat(), shape = shape, mass = mass, friction = 0.7,
    groups = { "props" }, angular_damp = 0.3,
    MeshInstance3D { mesh = mesh, material = mat or M.vertex, scale = extra and extra.scale },
  }
  impact_sound(b, SFX.thud, 2, 0.7)
  thrown_damage(b)
  return b
end

------------------------------------------------------------------ physics props
function Props.crate(pos, size, rot)
  size = size or 1
  local c = prop("Crate", pos, rot, Shape.box(size, size, size), 27 * size ^ 3, meshes.crate, nil, { scale = Vec3(size) })
  return c
end
function Props.barrel(pos, rot) return prop("Barrel", pos, rot, Shape.cylinder(0.4, 1.1), 45, meshes.barrel) end
function Props.cow(pos, rot) return prop("Cow", pos, rot, Shape.box(1.6, 1.4, 0.75), 140, meshes.cow) end
function Props.engine(pos, rot) return prop("Engine Block", pos, rot, Shape.box(0.9, 0.6, 0.7), 95, meshes.engine, M.metal) end
function Props.tire(pos, rot) return prop("Tire", pos, rot, Shape.cylinder(0.5, 0.3), 14, meshes.tire) end
function Props.cinder(pos, rot) return prop("Cinder Block", pos, rot, Shape.box(0.8, 0.4, 0.4), 18, meshes.cinder) end

function Props.boulder(pos, r, kind)
  r = r or 0.8
  local b = prop("Boulder", pos, Quat.euler(rng:float(0, 3), rng:float(0, 3), 0), Shape.sphere(r * 0.92), math.floor(160 * r ^ 3),
    meshes.boulders[kind or rng:int(1, 3)], nil, { scale = Vec3(r) })
  b.friction = 0.8
  return b
end

-- Tumbleweeds roll downwind and bounce around. Purely for fun.
function Props.tumbleweed(pos)
  local t = RigidBody3D { name = "Tumbleweed", position = pos, shape = Shape.sphere(0.55), mass = 2, bounce = 0.5, friction = 0.4,
    linear_damp = 0.3, groups = { "props" },
    MeshInstance3D { mesh = meshes.tumbleweed, material = M.vertex },
  }
  t._process = function(self, dt)
    if not self._body then return end
    local v = self:get_velocity()
    if v:length() < 9 then self:apply_force(Vec3(5, 0, 2.5) * (1 + math.sin(Game.time * 0.7 + pos.x) * 0.5)) end
    if self.position.y < -20 then self:teleport(pos + Vec3(0, 3, 0)) end
    -- Wrap round the basin so they keep rolling past forever.
    if self.position.x > 150 then self:teleport(Vec3(-150, World.height(-150, self.position.z) + 1.5, self.position.z)) end
  end
  return t
end

-- Red barrel: explodes when shot enough, or when thrown hard into something.
function Props.explosive(pos, rot)
  local b = prop("Prop Pills Barrel", pos, rot, Shape.cylinder(0.4, 1.1), 40, meshes.explosive)
  b.hp = 25
  b.explosive = true
  function b:take_damage(dmg, info)
    if self.fuse or self.exploded then return end
    self.hp = self.hp - dmg
    if self.hp <= 0 then
      self.fuse = 0.35
      self:add_child(Particles3D { rate = 60, lifetime = 0.5, speed = 2, spread = 30, direction = Vec3(0, 1, 0), size = 0.3, size_end = 0.6,
        color = Color(1, 0.6, 0.2, 0.9), color_end = Color(0.3, 0.3, 0.3, 0), additive = false, position = Vec3(0, 0.6, 0), amount = 60 })
    end
  end
  function b:explode()
    if self.exploded then return end
    self.exploded = true
    Props.explosion(self.position, 6, 140 * (1 + (G.level - 1) * 0.15), 2)
    self:queue_free()
  end
  b._process = function(self, dt)
    if self.fuse then
      self.fuse = self.fuse - dt
      if self.fuse <= 0 then self:explode() end
    end
  end
  b:connect("body_entered", function(other, info)
    if b.thrown and Game.time - b.thrown < 4 and info.speed > 7 then b:explode() end
  end)
  return b
end

-- Static scenery that breaks into rigid pieces. need_power: minimum explosion power (nil = bullets work too).
function Props.breakable(pos, size, rot, mat, mesh, opts)
  opts = opts or {}
  local s = StaticBody3D { name = opts.name or "Breakable", position = pos, rotation = rot or Quat(), shape = Shape.box(size.x, size.y, size.z),
    MeshInstance3D { mesh = mesh or meshes.plank, material = mat or M.vertex, scale = size },
  }
  s.hp = opts.hp or 30
  s.need_power = opts.need_power
  function s:shatter(from)
    if self.broken then return end
    self.broken = true
    local parent = self.parent
    local gp, gr = self:global_transform()
    local pieces = opts.pieces or 2
    for i = 1, pieces do
      local off = gr * Vec3((i - (pieces + 1) / 2) * size.x / pieces, 0, 0)
      local psize = Vec3(size.x / pieces, size.y, size.z)
      local piece = RigidBody3D { position = gp + off, rotation = gr, shape = Shape.box(psize.x, psize.y, psize.z), mass = opts.piece_mass or 8,
        groups = { "props", "debris" },
        MeshInstance3D { mesh = mesh or meshes.plank, material = mat or M.vertex, scale = psize },
      }
      parent:add_child(piece)
      local dir = from and (gp - from):normalized() or Vec3(0, 0, 0)
      piece:set_velocity(dir * rng:float(5, 10) + Vec3(rng:float(-2, 2), rng:float(2, 5), rng:float(-2, 2)),
        Vec3(rng:float(-4, 4), rng:float(-4, 4), rng:float(-4, 4)))
      impact_sound(piece, SFX.thud, 3, 0.4)
      Game.after(12, function() if piece:is_valid() then piece:queue_free() end end, piece)
    end
    parent:add_child(Props.burst(gp, opts.dust_color or P.wood, 25, 5))
    Audio.play_at(SFX.crack, gp, { volume = 0.8 })
    if opts.on_break then opts.on_break(self) end
    self:queue_free()
  end
  function s:take_damage(dmg, info)
    if self.need_power and (not info.power or info.power < self.need_power) then
      if info.power then G.hint_vault = true end
      return
    end
    self.hp = self.hp - dmg
    if self.hp <= 0 then self:shatter(info.from or info.pos) end
  end
  return s
end

------------------------------------------------------------------ effects
function Props.burst(pos, col, count, speed)
  return Particles3D {
    position = pos, one_shot = true, auto_free = true, amount = count or 30, lifetime = 0.7, lifetime_random = 0.4,
    speed = speed or 5, speed_random = 0.5, spread = 180, gravity = Vec3(0, -9, 0), damping = 1.5,
    size = 0.14, size_end = 0, color = col or Color.WHITE, color_end = (col or Color.WHITE):with_alpha(0), stretch = 0.04,
  }
end

function Props.dust(pos, amount)
  return Particles3D {
    position = pos, one_shot = true, auto_free = true, amount = amount or 14, lifetime = 0.7, speed = 1.8, spread = 80,
    direction = Vec3(0, 1, 0), gravity = Vec3(0, -1, 0), damping = 3, additive = false,
    size = 0.3, size_end = 0.7, color = Color(0.93, 0.8, 0.6, 0.6), color_end = Color(0.93, 0.8, 0.6, 0), emit_radius = 0.3,
  }
end

function Props.sparks(pos, normal, col)
  return Particles3D {
    position = pos, one_shot = true, auto_free = true, amount = 8, lifetime = 0.25, speed = 6, spread = 50,
    direction = normal or Vec3(0, 1, 0), gravity = Vec3(0, -12, 0), size = 0.06, size_end = 0, stretch = 0.03,
    color = col or Color(1, 0.85, 0.4, 1), color_end = Color(1, 0.4, 0.1, 0), additive = true,
  }
end

-- A bright streak from a to b that vanishes quickly.
function Props.tracer(a, b, col, width, life)
  local d = b - a
  local len = d:length()
  if len < 0.05 then return nil end
  width = width or 0.045
  local t = MeshInstance3D { mesh = meshes.tracer, material = M.glow, tint = col or Color(1, 0.92, 0.6),
    position = a + d * 0.5, rotation = Quat.look_rotation(d), scale = Vec3(width, width, len), cast_shadow = false }
  local age, total = 0, life or 0.07
  t._process = function(self, dt)
    age = age + dt
    local k = 1 - age / total
    if k <= 0 then self:queue_free() return end
    self.scale = Vec3(width * k, width * k, len)
  end
  return t
end

-- Zig-zag lightning made of short tracers.
function Props.lightning(a, b, root)
  local prev = a
  local n = 6
  for i = 1, n do
    local p = a:lerp(b, i / n)
    if i < n then p = p + Vec3(rng:float(-0.4, 0.4), rng:float(-0.4, 0.4), rng:float(-0.4, 0.4)) end
    local t = Props.tracer(prev, p, Art.pal.static, 0.07, 0.18)
    if t then root:add_child(t) end
    prev = p
  end
end

function Props.shockwave(pos, radius, col, dur)
  local ring = MeshInstance3D { mesh = meshes.ring, material = M.glow, tint = col or Color(1, 0.8, 0.5), position = pos, scale = Vec3(0.1), cast_shadow = false }
  local age = 0
  dur = dur or 0.35
  ring._process = function(self, dt)
    age = age + dt
    local t = age / dur
    if t >= 1 then self:queue_free() return end
    local s = radius * Ease.out_cubic(t)
    self.scale = Vec3(s, 1 + (1 - t) * 3, s)
  end
  return ring
end

------------------------------------------------------------------ explosions
-- power: 1 = rockets, 2 = Prop Pills barrels (the vault needs 2).
-- opts: element (applied to everything hit), self_damage (multiplier on Carl, default 0.25 for his own blasts),
-- small (a lighter effect for express rounds), tint (fireball colour).
function Props.explosion(pos, radius, damage, power, from_enemy, opts)
  opts = opts or {}
  local root = G.root
  local small = opts.small
  local fx = Node3D { position = pos }
  root:add_child(fx)
  local tint = opts.tint or Color(1, 0.75, 0.3, 1)
  fx:add_child(Particles3D { one_shot = true, amount = small and 18 or 70, lifetime = 0.6, lifetime_random = 0.3, speed = radius * 2.2, speed_random = 0.5,
    spread = 180, damping = 4, gravity = Vec3(0, 2, 0), size = 0.9, size_end = 1.8, additive = true,
    color = tint, color_end = Color(tint.r * 0.9, tint.g * 0.3, tint.b * 0.1, 0) })
  fx:add_child(Particles3D { one_shot = true, amount = small and 6 or 30, lifetime = 1.6, lifetime_random = 0.5, speed = radius * 0.8, spread = 180,
    damping = 2, gravity = Vec3(0, 2.5, 0), size = 1.2, size_end = 2.8, additive = false, color = Color(0.3, 0.27, 0.25, 0.7), color_end = Color(0.3, 0.27, 0.25, 0) })
  fx:add_child(Particles3D { one_shot = true, amount = 30, lifetime = 0.9, speed = radius * 3, spread = 180, gravity = Vec3(0, -14, 0),
    size = 0.1, size_end = 0, stretch = 0.05, additive = true, color = Color(1, 0.9, 0.5, 1), color_end = Color(1, 0.4, 0.1, 0) })
  local flash = fx:add_child(MeshInstance3D { mesh = meshes.sphere, material = M.flash, scale = Vec3(radius * 0.3), cast_shadow = false })
  local light = fx:add_child(OmniLight3D { color = Color.hex("#ffb060"), energy = 30, range = radius * 4 })
  local age = 0
  fx._process = function(self, dt)
    age = age + dt
    local t = math.min(age / 0.25, 1)
    flash.scale = Vec3(radius * (0.3 + 0.7 * Ease.out_cubic(t)))
    flash.tint = Color(1, 1, 1, 1 - t)
    flash.visible = t < 1
    light.energy = 30 * math.max(0, 1 - age / 0.4)
    if age > 2.2 then self:queue_free() end
  end
  fx:add_child(Props.shockwave(pos + Vec3(0, 0.2, 0), radius * 1.1, Color(1, 0.85, 0.6), 0.3))
  Audio.play_at(SFX.explosion, pos, { volume = small and 0.35 or 1, pitch = rng:float(0.85, 1.05) * (small and 1.6 or 1) })

  -- Camera kick by distance.
  if G.rig then
    local d = G.rig.camera:global_position():distance(pos)
    G.rig:shake(math.clamp(1 - d / (radius * 6), 0, small and 0.15 or 0.8))
  end
  -- Push every body, hurt everything with hp, chain other barrels.
  for _, node in ipairs(Physics.overlap_sphere(pos, radius * 1.6)) do
    local target = Combat.target_of(node)
    local np = node:global_position()
    local d = np:distance(pos)
    local fall = math.clamp(1 - d / (radius * 1.6), 0.15, 1)
    if node:is(RigidBody3D) and node._body then
      local dir = (np - pos + Vec3(0, 0.8, 0)):normalized()
      node:apply_impulse(dir * (node.mass or 20) * 14 * fall * (small and 0.3 or 1))
      if node.explosive and node ~= target then node:take_damage(999, { power = power }) end
    end
    if target and target ~= G.player and not (from_enemy and target.is_enemy) then
      Combat.damage(target, damage * fall, { pos = np, dir = (np - pos):normalized(), kind = "explosion", power = power, from = pos,
        element = opts.element, elem_type = opts.element, source = opts.source })
    end
  end
  if G.player then
    local pd = G.player.position:distance(pos)
    if pd < radius then
      local push = (G.player.position - pos + Vec3(0, 1.5, 0)):normalized() * 14 * (1 - pd / radius)
      if not small then G.player.velocity = G.player.velocity + push end
      local self_k = from_enemy and 1 or (opts.self_damage or 0.25)
      if self_k > 0 then G.player:take_damage(damage * self_k * (1 - pd / radius), { pos = pos }) end
    end
  end
end

------------------------------------------------------------------ damage pipeline
-- Walk up from a hit body to whatever owns hp.
function Combat.target_of(node)
  local n = node
  while n do
    if n.take_damage then return n end
    n = n.parent
  end
  return nil
end

function Combat.damage(target, amount, info)
  if not target or not target.take_damage or target.dead then return end
  info = info or {}
  amount = math.max(1, math.floor(amount + 0.5))
  -- take_damage may return what it really dealt (after shields, armor and elemental effectiveness).
  local dealt = target:take_damage(amount, info)
  if type(dealt) == "number" then amount = math.max(dealt > 0 and 1 or 0, math.floor(dealt + 0.5)) end
  if target.is_enemy and amount > 0 then
    G.add_number(info.pos or target:global_position() + Vec3(0, 1.6, 0), amount, info.crit, info.elem_type or info.element, info.eff)
  end
end

------------------------------------------------------------------ projectiles
-- Lua-stepped projectiles (enemy bolts and player rockets), swept with raycasts each frame.
Combat.projectiles = {}

function Combat.fire_projectile(p)
  -- p: pos, vel, owner ("player"|"enemy"), damage, gravity, splash, power, mat, scale, exclude, element
  local mesh = p.rocket and meshes.rocket or meshes.bolt
  p.node = MeshInstance3D { mesh = mesh, material = p.mat or M.bolt_enemy, position = p.pos, scale = Vec3(p.scale or 1), cast_shadow = false }
  if p.rocket then
    p.node:add_child(Particles3D { rate = 70, lifetime = 0.5, speed = 0.6, spread = 180, size = 0.25, size_end = 0.7,
      color = Color(0.9, 0.85, 0.8, 0.6), color_end = Color(0.5, 0.5, 0.5, 0), amount = 80, additive = false })
    p.node:add_child(OmniLight3D { color = Color.hex("#ff9a40"), energy = 4, range = 6 })
  end
  p.life = p.life or 4
  G.root:add_child(p.node)
  table.insert(Combat.projectiles, p)
end

local function seg_point_dist(a, b, p)
  local ab = b - a
  local t = math.clamp((p - a):dot(ab) / math.max(ab:length_sq(), 1e-6), 0, 1)
  return (a + ab * t):distance(p), t
end

function Combat.update_projectiles(dt)
  local list = Combat.projectiles
  local player = G.player
  for i = #list, 1, -1 do
    local p = list[i]
    p.life = p.life - dt
    if p.gravity then p.vel = p.vel + Vec3(0, -p.gravity * dt, 0) end
    local np = p.pos + p.vel * dt
    local done, hit_pos, hit_node, hit_normal = false, nil, nil, nil
    local hit = Physics.raycast(p.pos, np, p.exclude)
    if hit and hit.node ~= p.ignore then done, hit_pos, hit_node, hit_normal = true, hit.position, hit.node, hit.normal end
    -- Enemy shots test the player's capsule directly (with a little forgiveness for dodging).
    if p.owner == "enemy" and player and not player.dead then
      local c1 = player.position + Vec3(0, 0.35, 0)
      local c2 = player.position + Vec3(0, 1.0, 0)
      for _, c in ipairs({ c1, c2 }) do
        local d, t = seg_point_dist(p.pos, np, c)
        if d < 0.42 and (not done or t <= 1) then done, hit_pos, hit_node = true, p.pos:lerp(np, t), player end
      end
    end
    if done or p.life <= 0 then
      hit_pos = hit_pos or np
      if p.splash then
        Props.explosion(hit_pos - p.vel:normalized() * 0.3, p.splash, p.damage, p.power or 1, p.owner == "enemy")
      elseif hit_node then
        local target = Combat.target_of(hit_node)
        if p.owner == "enemy" then
          if target == player then player:take_damage(p.damage, { pos = hit_pos, dir = p.vel:normalized() }) end
          if target and target.explosive then target:take_damage(p.damage, {}) end
        elseif target and target ~= player then
          Combat.damage(target, p.damage, { pos = hit_pos, dir = p.vel:normalized(), element = p.element })
        end
        if hit_node.is and hit_node:is(RigidBody3D) and hit_node._body then hit_node:apply_impulse(p.vel:normalized() * p.damage * 0.3, hit_pos) end
        G.root:add_child(Props.sparks(hit_pos, hit_normal, p.mat == M.bolt_drone and Color(1, 0.9, 0.3) or Color(1, 0.4, 0.5)))
      end
      p.node:queue_free()
      table.remove(list, i)
    else
      p.pos = np
      p.node.position = np
      if p.rocket then p.node.rotation = Quat.look_rotation(p.vel) end
    end
  end
end

function Combat.clear()
  for _, p in ipairs(Combat.projectiles) do if p.node:is_valid() then p.node:queue_free() end end
  Combat.projectiles = {}
end

return Props
