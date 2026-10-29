-- Reusable scene pieces ("prefabs") for the showcase. Each function returns a Node tree.
local Art = require("art")
local P = Art.pal
local Props = {}

local M        -- materials, set by Props.init
local meshes = {}

function Props.init(materials)
  M = materials
  meshes.crate = MeshData.box(1, 1, 1):upload()
  meshes.barrel = Art.barrel():upload()
  meshes.orb = MeshData.sphere(0.28, 16, 12):upload()
  meshes.crystal = Art.crystal_mesh(1.4):upload()
  meshes.crystal_big = Art.crystal_mesh(2.6):upload()
  meshes.pad = MeshData.cylinder(1.1, 1.25, 0.3, 24, Color.WHITE):upload()
  meshes.pad_ring = MeshData.torus(1.15, 0.09, 32, 8, P.white):upload()
  meshes.lamp = Art.lamp_post():upload()
  meshes.lamp_bulb = MeshData.sphere(0.2, 12, 8, Color.WHITE):upload()
  meshes.platform = MeshData.box(4, 0.5, 4, Color.WHITE):flat():upload()
  meshes.log = MeshData.cylinder(0.14, 0.14, 1.3, 8, P.bark):flat():upload()
  meshes.fire_stone = Art.rock(9, 0.22):upload()
  meshes.pillar = MeshData.cylinder(0.55, 0.62, 1, 10, P.stone):flat():upload()
  meshes.pillar_cap = MeshData.box(1.5, 0.35, 1.5, P.stone_dark):upload()
  meshes.sign_post = MeshData.box(0.14, 1.6, 0.14, P.wood_dark):upload()
  meshes.sign_board = MeshData.box(1.6, 0.6, 0.1, P.wood):upload()
end
Props.meshes = meshes

local function impact_sound(body, sound, min_speed, volume)
  body:connect("body_entered", function(other, info)
    if info.speed < (min_speed or 1.5) then return end
    if body._last_sound and Game.time - body._last_sound < 0.12 then return end
    body._last_sound = Game.time
    local v = math.clamp(info.speed / 10, 0.1, 1) * (volume or 1)
    Audio.play_at(sound, info.point, { volume = v, pitch = rng:float(0.85, 1.15) })
  end)
end

------------------------------------------------------------------ physics props
function Props.crate(pos, size, rot)
  size = size or 1
  local c = RigidBody3D {
    name = "Crate", position = pos, rotation = rot or Quat(), shape = Shape.box(size, size, size),
    mass = 12 * size ^ 3, friction = 0.7, groups = { "props" },
    MeshInstance3D { mesh = meshes.crate, material = M.crate, scale = Vec3(size) },
  }
  impact_sound(c, SFX.thud, 2, 0.8)
  return c
end

function Props.barrel(pos, rot)
  local b = RigidBody3D {
    name = "Barrel", position = pos, rotation = rot or Quat(), shape = Shape.cylinder(0.45, 1.1),
    mass = 20, friction = 0.5, groups = { "props" },
    MeshInstance3D { mesh = meshes.barrel, material = M.vertex },
  }
  impact_sound(b, SFX.thud, 2, 0.6)
  return b
end

-- Glowing ball the player throws. Lights up the world and knocks things over.
local orbs = {}
function Props.spark_orb(pos, vel)
  local orb = RigidBody3D {
    name = "Orb", position = pos, shape = Shape.sphere(0.28), mass = 6, bounce = 0.55, friction = 0.4,
    ccd = true, linear_damp = 0.1, angular_damp = 0.3,
    MeshInstance3D { mesh = meshes.orb, material = M.orb, cast_shadow = false },
    OmniLight3D { color = Color.hex("#ffbe5c"), energy = 3, range = 7 },
    Particles3D { rate = 40, lifetime = 0.5, speed = 0.3, spread = 180, size = 0.16, size_end = 0,
      color = Color(1, 0.75, 0.35, 0.9), color_end = Color(1, 0.4, 0.1, 0), amount = 64 },
  }
  orb:set_velocity(vel)
  impact_sound(orb, SFX.bounce, 1.5, 0.7)
  orb.born = Game.time
  orb._process = function(self, dt)
    local age = Game.time - self.born
    if age > 7 then
      local t = math.clamp((age - 7) / 1, 0, 1)
      self:get("MeshInstance3D").scale = Vec3(1 - t)
      self:get("OmniLight3D").energy = 3 * (1 - t)
      if t >= 1 then self:queue_free() end
    end
  end
  orbs[#orbs + 1] = orb
  -- Keep the number of live orbs bounded.
  while #orbs > 24 do
    local old = table.remove(orbs, 1)
    if old:is_valid() then old.born = math.min(old.born, Game.time - 7) end
  end
  return orb
end

------------------------------------------------------------------ effects
function Props.burst(pos, col, count, speed)
  return Particles3D {
    position = pos, one_shot = true, auto_free = true, amount = count or 40, lifetime = 0.9, lifetime_random = 0.4,
    speed = speed or 5, speed_random = 0.5, spread = 180, gravity = Vec3(0, -6, 0), damping = 1.5,
    size = 0.14, size_end = 0.0, color = col or Color(1, 1, 1, 1), color_end = (col or Color.WHITE):with_alpha(0), stretch = 0.04,
  }
end

function Props.dust(pos)
  return Particles3D {
    position = pos, one_shot = true, auto_free = true, amount = 14, lifetime = 0.6, speed = 1.6, spread = 80,
    direction = Vec3(0, 1, 0), gravity = Vec3(0, -1, 0), damping = 3, additive = false,
    size = 0.22, size_end = 0.45, color = Color(0.95, 0.92, 0.85, 0.55), color_end = Color(0.95, 0.92, 0.85, 0),
    emit_radius = 0.3,
  }
end

function Props.splash(pos)
  local n = Node3D { position = pos }
  n:add_child(Particles3D {
    one_shot = true, auto_free = true, amount = 60, lifetime = 1.0, speed = 6, speed_random = 0.4, spread = 35,
    gravity = Vec3(0, -14, 0), additive = false, size = 0.16, size_end = 0.05,
    color = Color(0.85, 0.95, 1, 0.9), color_end = Color(0.85, 0.95, 1, 0), emit_radius = 0.4,
  })
  Game.after(1.5, function() n:queue_free() end, n)
  return n
end

------------------------------------------------------------------ gameplay pieces
-- Collectible crystal. Emits "collected" on the world when the player touches it.
function Props.crystal(pos, big)
  local visual = Node3D {
    name = "Visual",
    MeshInstance3D { mesh = big and meshes.crystal_big or meshes.crystal, material = big and M.crystal_big or M.crystal, position = Vec3(0, big and -0.6 or -0.3, 0) },
    OmniLight3D { color = big and Color.hex("#8fe3ff") or P.mint_glow, energy = big and 5 or 2.5, range = big and 9 or 6, position = Vec3(0, 0.3, 0) },
    Particles3D { rate = 6, lifetime = 2, speed = 0.4, spread = 60, size = 0.06, size_end = 0, emit_radius = 0.6,
      color = (big and Color.hex("#bff1ff") or P.mint_glow):with_alpha(0.9), color_end = Color(1, 1, 1, 0), turbulence = 2 },
  }
  local area = Area3D {
    name = "Crystal", position = pos, shape = Shape.sphere(big and 1.6 or 1.0), groups = { "crystals" },
    visual,
    Label3D { text = big and "Sky Crystal" or "", position = Vec3(0, 2.6, 0), size = 26, color = Color.hex("#bff1ff") },
  }
  area.big = big
  area.phase = rng:float(0, 6.28)
  area._process = function(self, dt)
    if self.taken then return end
    visual:rotate_y(dt * 1.2)
    visual.position = Vec3(0, math.sin(Game.time * 2 + self.phase) * 0.18 + 0.2, 0)
  end
  area:connect("body_entered", function(body)
    if area.taken or not body:is_in_group("player") then return end
    area.taken = true
    local p = area:global_position()
    Audio.play(SFX.chime, { volume = 0.7 })
    Audio.play(SFX.collect, { volume = 0.5 })
    area.parent:add_child(Props.burst(p + Vec3(0, 0.4, 0), area.big and Color.hex("#bff1ff") or P.mint_glow, 70, 7))
    Tween.to(visual, { scale = Vec3(1.6), position = Vec3(0, 1.5, 0) }, 0.18, { ease = "out_quad",
      on_done = function() Tween.to(visual, { scale = Vec3(0.01) }, 0.25, { ease = "in_back", on_done = function() area:queue_free() end }) end })
    Game.scene:emit("crystal_collected", area)
  end)
  return area
end

-- Bouncy launch pad.
function Props.jump_pad(pos, strength)
  local ring = MeshInstance3D { mesh = meshes.pad_ring, material = M.stone, position = Vec3(0, 0.16, 0) }
  local pad = Area3D {
    name = "JumpPad", position = pos, shape = Shape.cylinder(1.1, 0.8),
    StaticBody3D { shape = Shape.cylinder(1.25, 0.3), position = Vec3(0, -0.05, 0),
      MeshInstance3D { mesh = meshes.pad, material = M.pad } },
    ring,
    OmniLight3D { color = Color.hex("#ff6fa5"), energy = 2, range = 5, position = Vec3(0, 0.8, 0) },
    Particles3D { rate = 14, lifetime = 1.2, speed = 3, spread = 8, emit_radius = 0.8, size = 0.08, size_end = 0,
      color = Color.hex("#ffb3cf"), color_end = Color(1, 0.5, 0.7, 0) },
  }
  pad:connect("body_entered", function(body)
    if body.launch then
      body:launch(strength or 22)
      Audio.play_at(SFX.bounce_pad, pad:global_position(), { volume = 0.9 })
      ring.scale = Vec3(1.3, 3, 1.3)
      Tween.to(ring, { scale = Vec3(1) }, 0.5, { ease = "out_elastic" })
    end
  end)
  return pad
end

-- Platform that drifts between two points; carries the player and pushes crates.
function Props.moving_platform(a, b, period, phase)
  local plat = AnimatableBody3D {
    name = "Platform", position = a, shape = Shape.box(4, 0.5, 4),
    MeshInstance3D { mesh = meshes.platform, material = M.platform },
    MeshInstance3D { mesh = meshes.crystal, material = M.crystal, position = Vec3(0, -0.55, 0), rotation = Quat.euler(math.pi, 0, 0), scale = Vec3(0.7), cast_shadow = false },
  }
  plat._physics_process = function(self, dt)
    local t = (math.sin((Game.time / period + (phase or 0)) * math.tau) + 1) / 2
    t = t * t * (3 - 2 * t)
    self.position = a:lerp(b, t)
  end
  return plat
end

-- Street lamp that switches on at dusk.
function Props.lamp(pos)
  local light = OmniLight3D { color = Color.hex("#ffc874"), energy = 0, range = 11, position = Vec3(0, 3.0, 0) }
  local bulb_mat = M.lamp_glow:clone()
  local lamp = StaticBody3D {
    name = "Lamp", position = pos, shape = Shape.offset(Shape.cylinder(0.12, 3), Vec3(0, 1.5, 0)), groups = { "lamps" },
    MeshInstance3D { mesh = meshes.lamp, material = M.vertex },
    MeshInstance3D { mesh = meshes.lamp_bulb, material = bulb_mat, position = Vec3(0, 3.0, 0), cast_shadow = false },
    light,
  }
  function lamp:set_on(t)
    light.energy = 3.5 * t
    bulb_mat.emission_energy = 0.2 + 5 * t
  end
  return lamp
end

function Props.campfire(pos)
  local light = OmniLight3D { color = Color.hex("#ff9a3c"), energy = 4, range = 12, position = Vec3(0, 1, 0) }
  local fire = Node3D { name = "Campfire", position = pos, light,
    Particles3D { name = "Fire", rate = 70, lifetime = 0.9, lifetime_random = 0.4, speed = 1.6, spread = 12, emit_radius = 0.25,
      size = 0.38, size_end = 0.05, color = Color(1, 0.7, 0.25, 0.9), color_end = Color(1, 0.2, 0.05, 0), turbulence = 3, position = Vec3(0, 0.15, 0), amount = 120 },
    Particles3D { name = "Sparks", rate = 10, lifetime = 1.6, speed = 3, spread = 25, size = 0.04, size_end = 0,
      color = Color(1, 0.8, 0.4, 1), color_end = Color(1, 0.3, 0, 0), turbulence = 6, stretch = 0.03, position = Vec3(0, 0.3, 0) },
    Particles3D { name = "Smoke", rate = 8, lifetime = 3.5, speed = 1.2, spread = 10, additive = false,
      size = 0.4, size_end = 1.6, color = Color(0.35, 0.35, 0.38, 0.35), color_end = Color(0.5, 0.5, 0.52, 0), turbulence = 1.5, position = Vec3(0, 1.0, 0) },
  }
  for i = 0, 4 do
    local a = i / 5 * math.tau
    fire:add_child(MeshInstance3D { mesh = meshes.log, material = M.vertex, position = Vec3(math.cos(a) * 0.3, 0.2, math.sin(a) * 0.3),
      rotation = Quat.from_y(-a) * Quat.euler(0, 0, 1.1) })
  end
  for i = 0, 9 do
    local a = i / 10 * math.tau
    fire:add_child(MeshInstance3D { mesh = meshes.fire_stone, material = M.vertex, position = Vec3(math.cos(a) * 0.85, 0.05, math.sin(a) * 0.85) })
  end
  fire:add_child(StaticBody3D { shape = Shape.cylinder(0.9, 0.4), position = Vec3(0, 0.2, 0) })
  fire._process = function(self, dt)
    local t = Game.time
    light.energy = 3.5 + math.sin(t * 13) * 0.4 + math.sin(t * 7.3) * 0.5 + Noise.perlin2(t * 4, 0) * 0.8
  end
  return fire
end

function Props.pillar(pos, height, broken)
  local p = StaticBody3D {
    name = "Pillar", position = pos, shape = Shape.offset(Shape.cylinder(0.6, height), Vec3(0, height / 2, 0)),
    MeshInstance3D { mesh = meshes.pillar, material = M.vertex, position = Vec3(0, height / 2, 0), scale = Vec3(1, height, 1) },
  }
  if not broken then
    p:add_child(MeshInstance3D { mesh = meshes.pillar_cap, material = M.vertex, position = Vec3(0, height + 0.17, 0) })
  end
  return p
end

function Props.sign(pos, yaw, text)
  return StaticBody3D {
    name = "Sign", position = pos, rotation = Quat.from_y(yaw), shape = Shape.offset(Shape.box(0.2, 1.6, 0.2), Vec3(0, 0.8, 0)),
    MeshInstance3D { mesh = meshes.sign_post, material = M.vertex, position = Vec3(0, 0.8, 0) },
    MeshInstance3D { mesh = meshes.sign_board, material = M.vertex, position = Vec3(0, 1.4, 0.08) },
    Label3D { text = text, position = Vec3(0, 2.15, 0), size = 24, max_distance = 28, color = Color.hex("#fff4d6") },
  }
end

return Props
