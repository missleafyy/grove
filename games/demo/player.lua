-- Sprig, the player character: a third-person platformer controller with procedural animation,
-- plus the follow camera rig.
local Art = require("art")
local Props = require("props")

local WATER_LEVEL = 0

------------------------------------------------------------------ Player
local Player = CharacterBody3D:extend("Player")

function Player:_setup()
  CharacterBody3D._setup(self)
  self.radius = 0.42
  self.height = 1.25
  self.step_height = 0.3
  self.max_slope = 48
  self.speed = 7
  self.sprint_speed = 11.5
  self.accel = 70
  self.air_accel = 22
  self.jump_velocity = 10.5
  self.gravity = 28
  self.coyote_time = 0.12
  self.buffer_time = 0.15
  self.locked = true
  self:add_to_group("player")
  self._coyote, self._buffer, self._can_double = 0, 0, true
  self._walk, self._squash, self._squash_v = 0, 0, 0
  self._yaw = 0
  self._leaf, self._leaf_v = 0, 0
  self._blink = 3
  self._shoot_cd = 0
  self._was_floor = true
  self._prev_vy = 0
  self._fall_speed = 0
end

function Player:_ready()
  local M = self.materials
  local parts = Art.player_parts()
  self.visual = self:add_child(Node3D { name = "Visual" })
  self.body_pivot = self.visual:add_child(Node3D { name = "BodyPivot", position = Vec3(0, 0.62, 0) })
  self.body_mesh = self.body_pivot:add_child(MeshInstance3D { mesh = parts.body, material = M.player })
  local face = self.body_pivot:add_child(Node3D { name = "Face" })
  self.eyes = {}
  for _, side in ipairs({ -1, 1 }) do
    local eye = face:add_child(MeshInstance3D { mesh = parts.eye, material = M.eye, position = Vec3(side * 0.17, 0.08, -0.43), rotation = Quat.euler(0, side * 0.32, 0) })
    eye:add_child(MeshInstance3D { mesh = parts.shine, material = M.eye_shine, position = Vec3(0.02, 0.04, -0.04), cast_shadow = false })
    self.eyes[#self.eyes + 1] = eye
    face:add_child(MeshInstance3D { mesh = parts.cheek, material = M.player, position = Vec3(side * 0.3, -0.06, -0.37), rotation = Quat.euler(0, side * 0.6, 0), cast_shadow = false })
  end
  self.sprout = self.body_pivot:add_child(MeshInstance3D { mesh = parts.sprout, material = M.player, position = Vec3(0, 0.42, 0.02) })
  self.feet = {}
  for _, side in ipairs({ -1, 1 }) do
    self.feet[#self.feet + 1] = self.visual:add_child(MeshInstance3D { mesh = parts.foot, material = M.player, position = Vec3(side * 0.2, 0.09, 0) })
  end
  self.shadow_blob = nil
  self.safe_position = self.position:copy()
end

-- Called by jump pads.
function Player:launch(strength)
  local v = self.velocity
  self.velocity = Vec3(v.x, strength, v.z)
  self._launched = true
  self._can_double = true
  self._coyote = 0
  self:_kick_squash(-0.35)
end

function Player:_kick_squash(amount) self._squash_v = self._squash_v + amount * 12 end

function Player:_physics_process(dt)
  local rig = self.rig
  local ix, iy = 0, 0
  local controllable = not self.locked and not self._respawning
  if controllable then ix, iy = Input.vector("move_left", "move_right", "move_forward", "move_back") end
  local yaw = rig and rig.yaw or 0
  local fwd = Vec3(-math.sin(yaw), 0, -math.cos(yaw))
  local right = Vec3(math.cos(yaw), 0, -math.sin(yaw))
  local wish = right * ix + fwd * iy
  self.wish = wish

  local on_floor = self:is_on_floor()
  local v = self.velocity
  local sprint = Input.down("sprint")
  local target = wish * (sprint and self.sprint_speed or self.speed)
  local hv = Vec3(v.x, 0, v.z):move_toward(target, (on_floor and self.accel or self.air_accel) * dt)
  local vy = v.y

  if on_floor then
    self._coyote = self.coyote_time
    self._can_double = true
    self._launched = false
    if vy < 0 then vy = 0 end
  else
    self._coyote = self._coyote - dt
    local g = self.gravity
    if vy < 0 then g = g * 1.5
    elseif not Input.down("jump") and not self._launched then g = g * 2.2 end  -- short hop when released
    vy = math.max(vy - g * dt, -45)
  end

  self._buffer = (controllable and Input.pressed("jump")) and self.buffer_time or (self._buffer - dt)
  if self._buffer > 0 and self._coyote > 0 then
    vy = self.jump_velocity
    self._buffer, self._coyote = 0, 0
    Audio.play(SFX.jump, { volume = 0.5, pitch = rng:float(0.95, 1.08) })
    self:_kick_squash(-0.3)
  elseif controllable and Input.pressed("jump") and not on_floor and self._can_double and self._coyote <= 0 then
    vy = self.jump_velocity * 0.92
    self._can_double = false
    self._spin = 1
    Audio.play(SFX.double_jump, { volume = 0.45 })
    self.parent:add_child(Props.burst(self.position + Vec3(0, 0.3, 0), Color.hex("#c8ffe4"), 18, 3))
    self:_kick_squash(-0.25)
  end

  self._prev_vy = vy
  self.velocity = Vec3(hv.x, vy, hv.z)
  self:move_and_slide(dt)

  local now_floor = self:is_on_floor()
  if now_floor and not self._was_floor then
    local impact = -self._fall_speed
    if impact > 6 then
      self:_kick_squash(math.min(impact / 30, 0.45))
      Audio.play(SFX.land, { volume = math.clamp(impact / 25, 0.2, 0.7) })
      self.parent:add_child(Props.dust(self.position + Vec3(0, 0.1, 0)))
    end
  end
  self._fall_speed = self.velocity.y
  self._was_floor = now_floor
  if now_floor and self.position.y > WATER_LEVEL + 1 and self.floor_normal.y > 0.8 then
    self._safe_timer = (self._safe_timer or 0) + dt
    if self._safe_timer > 0.5 then self.safe_position = self.position:copy(); self._safe_timer = 0 end
  end

  -- Fell into the sea or off the world: splash and respawn.
  if self.position.y < WATER_LEVEL - 0.8 and not self._respawning then
    self._respawning = true
    Audio.play(SFX.splash, { volume = 0.7 })
    self.parent:add_child(Props.splash(Vec3(self.position.x, WATER_LEVEL, self.position.z)))
    Game.after(0.6, function()
      self:teleport(self.safe_position + Vec3(0, 0.5, 0))
      self._respawning = false
      self.parent:add_child(Props.burst(self.position + Vec3(0, 0.6, 0), Color.hex("#c8ffe4"), 25, 3))
    end, self)
  end

  -- Throw spark orbs toward where the camera is aiming.
  self._shoot_cd = self._shoot_cd - dt
  if controllable and Input.down("fire") and self._shoot_cd <= 0 and rig and not UI.click_consumed then
    self._shoot_cd = 0.22
    local origin = self.position + Vec3(0, 1.0, 0) + rig:aim_forward():flat():normalized() * 0.7
    local cam = rig.camera:global_position()
    local fwd_dir = rig:aim_forward()
    local hit = Physics.raycast(cam, cam + fwd_dir * 120, self)
    local target_pt = hit and hit.position or (cam + fwd_dir * 120)
    local dir = (target_pt - origin):normalized()
    local orb = Props.spark_orb(origin, dir * 24 + Vec3(0, 2.5, 0) + self.velocity:flat() * 0.4)
    self.parent:add_child(orb)
    Audio.play(SFX.shoot, { volume = 0.35, pitch = rng:float(0.9, 1.1) })
    self:_kick_squash(0.08)
  end
end

function Player:_process(dt)
  if not self.visual then return end
  local hv = self.velocity:flat()
  local speed = hv:length()
  local on_floor = self:is_on_floor()

  -- Face the movement direction.
  if self.wish and self.wish:length() > 0.1 then
    self._yaw = math.lerp_angle(self._yaw, math.atan2(-self.wish.x, -self.wish.z), 1 - math.exp(-14 * dt))
  end
  local spin = 0
  if self._spin then
    self._spin = self._spin - dt * 2.6
    if self._spin <= 0 then self._spin = nil else spin = (1 - self._spin) * math.tau end
  end
  self.visual.rotation = Quat.from_y(self._yaw + spin)

  -- Squash and stretch spring.
  local k, d = 260, 16
  self._squash_v = self._squash_v + (-k * self._squash - d * self._squash_v) * dt
  self._squash = self._squash + self._squash_v * dt
  local air_stretch = on_floor and 0 or math.clamp(self.velocity.y / 60, -0.12, 0.12)
  local s = self._squash - air_stretch
  local breathe = on_floor and speed < 0.5 and math.sin(Game.time * 2.6) * 0.015 or 0
  self.body_pivot.scale = Vec3(1 + s * 0.6, 1 - s + breathe, 1 + s * 0.6)

  -- Walk cycle: feet swing, body bobs and leans into the motion.
  if on_floor and speed > 0.3 then
    local prev = self._walk
    self._walk = self._walk + dt * (4 + speed * 1.15)
    if math.floor(prev / math.pi) ~= math.floor(self._walk / math.pi) then
      Audio.play(SFX.step, { volume = 0.18, pitch = rng:float(0.9, 1.15) })
    end
  else
    self._walk = self._walk + (math.floor(self._walk / math.pi + 0.5) * math.pi - self._walk) * math.min(1, dt * 10)
  end
  local w = self._walk
  local amp = math.clamp(speed / 7, 0, 1.3)
  local bob = on_floor and math.abs(math.sin(w)) * 0.07 * amp or 0
  local lean = math.clamp(speed / self.sprint_speed, 0, 1) * 0.18
  self.body_pivot.position = Vec3(0, 0.62 + bob, 0)
  self.body_pivot.rotation = Quat.euler(-lean, 0, math.sin(w) * 0.05 * amp)
  for i, foot in ipairs(self.feet) do
    local ph = w + (i == 1 and 0 or math.pi)
    local side = i == 1 and -1 or 1
    if on_floor then
      foot.position = Vec3(side * 0.2, 0.09 + math.max(0, math.sin(ph)) * 0.16 * amp, -math.cos(ph) * 0.22 * amp)
    else
      foot.position = Vec3(side * 0.22, 0.2, 0.05)
    end
  end

  -- Leaf sprout wobbles with acceleration.
  local acc = (speed - (self._last_speed or 0)) / math.max(dt, 1e-4)
  self._last_speed = speed
  self._leaf_v = self._leaf_v + (-90 * self._leaf - 6 * self._leaf_v + acc * 0.05 - (on_floor and 0 or self.velocity.y * 0.4)) * dt
  self._leaf = math.clamp(self._leaf + self._leaf_v * dt, -0.7, 0.7)
  self.sprout.rotation = Quat.euler(self._leaf, 0, math.sin(Game.time * 1.7) * 0.06)

  -- Blink.
  self._blink = self._blink - dt
  local eye_y = 1
  if self._blink < 0.12 then eye_y = 0.15 end
  if self._blink < 0 then self._blink = rng:float(2, 5) end
  for _, e in ipairs(self.eyes) do e.scale = Vec3(1, eye_y, 1) end
end

------------------------------------------------------------------ Camera rig
local CameraRig = Node3D:extend("CameraRig")

function CameraRig:_setup()
  Node3D._setup(self)
  self.top_level = true
  self.yaw = 0.4
  self.pitch = -0.32
  self.distance = 7.5
  self.target_distance = 7.5
  self.mode = "orbit"      -- "orbit" (title screen) or "follow"
  self.sensitivity = 0.0026
  self.orbit_center = Vec3(0, 6, 0)
  self.orbit_t = 0
end

function CameraRig:_ready()
  self.camera = self:add_child(Camera3D { fov = 68, position = Vec3(0, 0, self.distance), current = true })
end

function CameraRig:aim_forward() return self.camera:forward() end

function CameraRig:_process(dt)
  if self.mode == "fly" then return end
  if self.mode == "orbit" then
    self.orbit_t = self.orbit_t + dt * 0.05
    local a = self.orbit_t + 2.2
    local pos = self.orbit_center + Vec3(math.sin(a) * 70, 32, math.cos(a) * 70)
    self.position = pos
    self.rotation = Quat.look_rotation(self.orbit_center + Vec3(0, -4, 0) - pos)
    self.camera.position = Vec3(0, 0, 0)
    return
  end

  local p = self.target
  if Input.is_mouse_captured() then
    local dx, dy = Input.mouse_delta()
    self.yaw = self.yaw - dx * self.sensitivity
    self.pitch = self.pitch - dy * self.sensitivity
  end
  local sx, sy = Input.look_stick()
  self.yaw = self.yaw - sx * 2.6 * dt
  self.pitch = self.pitch - sy * 1.8 * dt
  self.pitch = math.clamp(self.pitch, -1.25, 0.55)
  local wheel = Input.mouse_wheel()
  if wheel ~= 0 then self.target_distance = math.clamp(self.target_distance - wheel * 0.8, 3, 16) end

  -- Follow with softer vertical smoothing so jumps don't jerk the view.
  local goal = p.position + Vec3(0, 1.25, 0)
  local f = self.focus or goal
  local fh = Vec3(f.x, 0, f.z):damp(Vec3(goal.x, 0, goal.z), 18, dt)
  local fy = math.damp(f.y, goal.y, (p:is_on_floor() and 10 or 4), dt)
  self.focus = Vec3(fh.x, fy, fh.z)

  local rot = Quat.from_y(self.yaw) * Quat.euler(self.pitch, 0, 0)
  -- Spring arm: pull the camera in when terrain or props are in the way.
  local want = self.target_distance
  local back = rot * Vec3(0, 0, 1)
  local hit = Physics.raycast(self.focus, self.focus + back * (want + 0.4), p)
  if hit and not (hit.node and hit.node.name == "Orb") then want = math.max(1.2, hit.distance - 0.4) end
  if want < self.distance then self.distance = math.damp(self.distance, want, 25, dt)
  else self.distance = math.damp(self.distance, want, 4, dt) end

  self.position = self.focus
  self.rotation = rot
  self.camera.position = Vec3(0, 0, self.distance)
  local sprinting = Input.down("sprint") and p.velocity:flat():length() > 8
  self.camera.fov = math.damp(self.camera.fov, sprinting and 76 or 68, 6, dt)
end

return { Player = Player, CameraRig = CameraRig, WATER_LEVEL = WATER_LEVEL }
