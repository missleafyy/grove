-- 3D nodes: Node3D, MeshInstance3D, MultiMeshInstance3D, Camera3D, lights, particles, Label3D, Environment.
local ffi = require("ffi")

------------------------------------------------------------------ Node3D
-- position/rotation/scale are local to the parent Node3D (rotation is a Quat;
-- a Vec3 of euler radians is accepted in constructors). top_level ignores the parent.
Node3D = Node:extend("Node3D")
Node3D._is3d = true

function Node3D:_init(props)
  Node._init(self, props)
  if Vec3.is(self.rotation) then self.rotation = Quat.euler(self.rotation) end
  if type(self.scale) == "number" then self.scale = Vec3(self.scale) end
  if self.rotation_degrees then self.rotation = Quat.euler_deg(self.rotation_degrees.x, self.rotation_degrees.y, self.rotation_degrees.z); self.rotation_degrees = nil end
end

function Node3D:_setup()
  Node._setup(self)
  self.position = Vec3(0, 0, 0)
  self.rotation = Quat()
  self.scale = Vec3(1, 1, 1)
  self.visible = true
end

local function parent3d(n)
  if n.top_level then return nil end
  local p = n.parent
  if p and p._is3d then return p end
end

-- Global transform computed on demand (exact, even mid-frame).
function Node3D:global_transform()
  local p = parent3d(self)
  if not p then return self.position, self.rotation, self.scale end
  local pp, pr, ps = p:global_transform()
  return pp + pr * (ps * self.position), pr * self.rotation, ps * self.scale
end
function Node3D:global_position() local p = self:global_transform(); return p end
function Node3D:global_rotation() local _, r = self:global_transform(); return r end
function Node3D:global_scale() local _, _, s = self:global_transform(); return s end

function Node3D:set_global_position(v)
  local p = parent3d(self)
  if not p then self.position = v:copy() return end
  local pp, pr, ps = p:global_transform()
  self.position = (pr:inverse() * (v - pp)) / ps
end

function Node3D:set_global_rotation(q)
  local p = parent3d(self)
  if not p then self.rotation = q:copy() return end
  self.rotation = p:global_rotation():inverse() * q
end

function Node3D:to_global(local_point)
  local gp, gr, gs = self:global_transform()
  return gp + gr * (gs * local_point)
end
function Node3D:to_local(global_point)
  local gp, gr, gs = self:global_transform()
  return (gr:inverse() * (global_point - gp)) / gs
end

-- Global basis directions (Godot convention: -Z is forward).
function Node3D:forward() return self:global_rotation() * Vec3(0, 0, -1) end
function Node3D:right() return self:global_rotation() * Vec3(1, 0, 0) end
function Node3D:up() return self:global_rotation() * Vec3(0, 1, 0) end

function Node3D:look_at(target, up)
  local gp = self:global_position()
  if target:distance_sq(gp) < 1e-8 then return end
  self:set_global_rotation(Quat.look_rotation(target - gp, up))
end

function Node3D:rotate(axis, angle) self.rotation = (Quat.axis_angle(axis, angle) * self.rotation):normalized() end
function Node3D:rotate_local(axis, angle) self.rotation = (self.rotation * Quat.axis_angle(axis, angle)):normalized() end
function Node3D:rotate_y(a) self:rotate(Vec3.UP, a) end
function Node3D:rotate_x(a) self:rotate_local(Vec3.RIGHT, a) end
function Node3D:translate(v) self.position = self.position + v end
function Node3D:translate_local(v) self.position = self.position + self.rotation * v end
function Node3D:show() self.visible = true end
function Node3D:hide() self.visible = false end

------------------------------------------------------------------ MeshInstance3D
local default_material
local function material_id(m)
  if m then return m.id end
  default_material = default_material or Material { albedo = Color(0.8, 0.8, 0.8) }
  return default_material.id
end

MeshInstance3D = Node3D:extend("MeshInstance3D")
function MeshInstance3D:_setup()
  Node3D._setup(self)
  self.cast_shadow = true
end
function MeshInstance3D:__enter()
  self._inst = C.gr_instance_create(self.mesh and self.mesh.id or 0, material_id(self.material))
  self._st = nil
end
function MeshInstance3D:__exit()
  C.gr_instance_free(self._inst)
  self._inst = nil
end
function MeshInstance3D:__sync(vis, gp, gr, gs)
  local mesh_id = self.mesh and self.mesh.id or 0
  local mat = material_id(self.material)
  local shadow = self.cast_shadow and 1 or 0
  local v = vis and 1 or 0
  local st = self._st
  if not st then st = {}; self._st = st end
  if st[1] ~= mesh_id or st[2] ~= mat or st[3] ~= v or st[4] ~= shadow then
    C.gr_instance_set(self._inst, mesh_id, mat, v, shadow)
    st[1], st[2], st[3], st[4] = mesh_id, mat, v, shadow
  end
  if vis then
    C.gr_instance_xform(self._inst, gp.x, gp.y, gp.z, gr.x, gr.y, gr.z, gr.w, gs.x, gs.y, gs.z)
    local t = self.tint
    if t then C.gr_instance_tint(self._inst, t.r, t.g, t.b, t.a); self._tinted = true
    elseif self._tinted then C.gr_instance_tint(self._inst, 1, 1, 1, 1); self._tinted = false end
  end
end

------------------------------------------------------------------ MultiMeshInstance3D
-- Many copies of one mesh in a single draw call. Instance transforms are in world space.
MultiMeshInstance3D = Node3D:extend("MultiMeshInstance3D")
function MultiMeshInstance3D:_setup()
  Node3D._setup(self)
  self.cast_shadow = true
  self.count = 0
  self._data = {}
end
function MultiMeshInstance3D:set_instance(i, pos, rot, scale, col)
  rot = rot or Quat()
  if type(scale) == "number" then scale = Vec3(scale) end
  scale = scale or Vec3(1)
  col = col or Color.WHITE
  local d = { pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w, scale.x, scale.y, scale.z, col.r, col.g, col.b, col.a }
  self._data[i] = d
  if i > self.count then self.count = i end
  if self._mm then C.gr_multimesh_set(self._mm, i - 1, unpack(d)) end
end
function MultiMeshInstance3D:set_visible_count(n)
  self.visible_count = n
  if self._mm then C.gr_multimesh_commit(self._mm, n) end
end
function MultiMeshInstance3D:__enter()
  self._mm = C.gr_multimesh_create(self.mesh.id, material_id(self.material), self.count)
  for i, d in pairs(self._data) do C.gr_multimesh_set(self._mm, i - 1, unpack(d)) end
  C.gr_multimesh_commit(self._mm, self.visible_count or self.count)
end
function MultiMeshInstance3D:__exit() C.gr_multimesh_free(self._mm); self._mm = nil end
function MultiMeshInstance3D:__sync(vis)
  C.gr_multimesh_options(self._mm, vis and 1 or 0, self.cast_shadow and 1 or 0)
end

------------------------------------------------------------------ Camera3D
Camera3D = Node3D:extend("Camera3D")
function Camera3D:_setup()
  Node3D._setup(self)
  self.fov = 70
  self.near = 0.05
  self.far = 1500
  self.trauma = 0      -- camera shake amount 0..1, decays over time
end
function Camera3D:__enter()
  if self.current or not (Game.camera and Game.camera.inside_tree) then Game.camera = self end
end
function Camera3D:__exit()
  if Game.camera == self then Game.camera = nil end
end
function Camera3D:make_current() Game.camera = self end
function Camera3D:shake(amount) self.trauma = math.min(1, self.trauma + amount) end

-- Returns screen x, y and whether the point is in front of the camera and on screen.
local sx, sy = ffi.new("float[1]"), ffi.new("float[1]")
function Camera3D:world_to_screen(p)
  local on = C.gr_world_to_screen(p.x, p.y, p.z, sx, sy)
  return sx[0], sy[0], on == 1
end
local ro, rd = ffi.new("float[3]"), ffi.new("float[3]")
function Camera3D:screen_ray(x, y)
  C.gr_screen_ray(x, y, ro, rd)
  return Vec3(ro[0], ro[1], ro[2]), Vec3(rd[0], rd[1], rd[2])
end

function Camera3D:_push(dt)
  local gp, gr = self:global_transform()
  if self.trauma > 0 then
    local t = Game.time * 23
    local s = self.trauma * self.trauma
    local shake = Quat.euler(Noise.perlin2(t, 1.3) * 0.06 * s, Noise.perlin2(t, 7.1) * 0.06 * s, Noise.perlin2(t, 13.7) * 0.04 * s)
    gr = gr * shake
    self.trauma = math.max(0, self.trauma - dt * 1.5)
  end
  C.gr_camera(gp.x, gp.y, gp.z, gr.x, gr.y, gr.z, gr.w, self.fov, self.near, self.far)
  local f = gr * Vec3(0, 0, -1)
  C.gr_listener(gp.x, gp.y, gp.z, f.x, f.y, f.z)
end

------------------------------------------------------------------ Environment
-- Global proxy over the renderer's environment: Environment.sky_top = Color(...)
local env_ptr = C.gr_environment()
local env_colors = { sky_top = true, sky_horizon = true, ground = true, sun_color = true, fog_color = true, clear_color = true, outline_color = true }
local env_vecs = { sun_dir = true, moon_dir = true }
local env_bools = { sun_shadows = true, sky_enabled = true }

Environment = setmetatable({}, {
  __index = function(_, k)
    if env_colors[k] then local a = env_ptr[k]; return Color(a[0], a[1], a[2]) end
    if env_vecs[k] then local a = env_ptr[k]; return Vec3(a[0], a[1], a[2]) end
    if env_bools[k] then return env_ptr[k] ~= 0 end
    if k == "set" then return function(_, t) for kk, vv in pairs(t) do Environment[kk] = vv end end end
    return env_ptr[k]
  end,
  __newindex = function(_, k, v)
    if env_colors[k] then local a = env_ptr[k]; a[0], a[1], a[2] = v.r, v.g, v.b
    elseif env_vecs[k] then local a = env_ptr[k]; local n = v:normalized(); a[0], a[1], a[2] = n.x, n.y, n.z
    elseif env_bools[k] then env_ptr[k] = v and 1 or 0
    else env_ptr[k] = v end
  end,
})

-- A node that applies environment settings when it enters the tree.
WorldEnvironment = Node:extend("WorldEnvironment")
function WorldEnvironment:__enter()
  for k, v in pairs(self.settings or {}) do Environment[k] = v end
end

------------------------------------------------------------------ Lights
-- The sun. Its forward (-Z) is the direction the light travels.
DirectionalLight3D = Node3D:extend("DirectionalLight3D")
function DirectionalLight3D:_setup()
  Node3D._setup(self)
  self.color = Color(1, 0.96, 0.9)
  self.energy = 2.5
  self.shadows = true
  self.rotation = Quat.euler_deg(-50, 30, 0)
end
function DirectionalLight3D:__sync(vis, gp, gr)
  local d = gr * Vec3(0, 0, -1)
  local e = env_ptr
  e.sun_dir[0], e.sun_dir[1], e.sun_dir[2] = d.x, d.y, d.z
  e.sun_color[0], e.sun_color[1], e.sun_color[2] = self.color.r, self.color.g, self.color.b
  e.sun_energy = vis and self.energy or 0
  e.sun_shadows = self.shadows and 1 or 0
end
function DirectionalLight3D:__exit() env_ptr.sun_energy = 0 end

OmniLight3D = Node3D:extend("OmniLight3D")
function OmniLight3D:_setup()
  Node3D._setup(self)
  self.color = Color(1, 0.9, 0.75)
  self.energy = 2
  self.range = 8
end
function OmniLight3D:__enter()
  self._id = C.gr_light_create()
  self._ptr = C.gr_light_get(self._id)
end
function OmniLight3D:__exit() C.gr_light_free(self._id); self._ptr = nil end
function OmniLight3D:__sync(vis, gp, gr)
  local l = self._ptr
  l.type = self._spot and 1 or 0
  l.enabled = (vis and self.energy > 0) and 1 or 0
  l.color[0], l.color[1], l.color[2] = self.color.r, self.color.g, self.color.b
  l.energy = self.energy
  l.pos[0], l.pos[1], l.pos[2] = gp.x, gp.y, gp.z
  l.range = self.range
  if self._spot then
    local d = gr * Vec3(0, 0, -1)
    l.dir[0], l.dir[1], l.dir[2] = d.x, d.y, d.z
    l.spot_angle = self.angle
    l.spot_softness = self.softness
  end
end

SpotLight3D = OmniLight3D:extend("SpotLight3D")
SpotLight3D._spot = true
function SpotLight3D:_setup()
  OmniLight3D._setup(self)
  self.angle = 30
  self.softness = 0.35
  self.range = 15
end

------------------------------------------------------------------ Particles3D
-- CPU-simulated billboard particles. Positions are in world space; the emitter follows the node.
Particles3D = Node3D:extend("Particles3D")
local pdefaults = {
  emitting = true, additive = true, amount = 200, rate = 30, lifetime = 1.5, lifetime_random = 0.3,
  emit_box = Vec3(0, 0, 0), emit_radius = 0, direction = Vec3(0, 1, 0), spread = 30, speed = 2, speed_random = 0.3,
  gravity = Vec3(0, 0, 0), damping = 0, color = Color(1, 1, 1, 1), color_end = Color(1, 1, 1, 0),
  size = 0.15, size_end = 0.05, turbulence = 0, stretch = 0, one_shot = false, auto_free = false,
}
function Particles3D:_setup()
  Node3D._setup(self)
  for k, v in pairs(pdefaults) do self[k] = (type(v) == "cdata") and v:copy() or v end
end
function Particles3D:__enter()
  self._id = C.gr_particles_create(self.amount)
  self._cfg = C.gr_particles_config(self._id)
  if self.one_shot then
    self._pending_burst = self.burst_count or self.amount
    self.emitting = false
  end
end
function Particles3D:__exit() C.gr_particles_free(self._id); self._cfg = nil end
function Particles3D:burst(n) if self._id then C.gr_particles_burst(self._id, n or self.amount) else self._pending_burst = n end end
function Particles3D:alive() return self._id and C.gr_particles_alive(self._id) or 0 end
function Particles3D:__sync(vis, gp)
  local c = self._cfg
  c.emitting = (self.emitting and vis) and 1 or 0
  c.additive = self.additive and 1 or 0
  c.texture = self.texture and self.texture.id or 0
  c.world_space = 1
  c.rate, c.lifetime, c.lifetime_random = self.rate, self.lifetime, self.lifetime_random
  c.pos[0], c.pos[1], c.pos[2] = gp.x, gp.y, gp.z
  c.emit_box[0], c.emit_box[1], c.emit_box[2] = self.emit_box.x, self.emit_box.y, self.emit_box.z
  c.emit_radius = self.emit_radius
  c.dir[0], c.dir[1], c.dir[2] = self.direction.x, self.direction.y, self.direction.z
  c.spread, c.speed, c.speed_random = self.spread, self.speed, self.speed_random
  c.gravity[0], c.gravity[1], c.gravity[2] = self.gravity.x, self.gravity.y, self.gravity.z
  c.damping = self.damping
  local a, b = self.color, self.color_end
  c.color_start[0], c.color_start[1], c.color_start[2], c.color_start[3] = a.r, a.g, a.b, a.a
  c.color_end[0], c.color_end[1], c.color_end[2], c.color_end[3] = b.r, b.g, b.b, b.a
  c.size_start, c.size_end = self.size, self.size_end
  c.turbulence, c.stretch = self.turbulence, self.stretch
  if self._pending_burst then
    C.gr_particles_burst(self._id, self._pending_burst)
    self._pending_burst = nil
    self._burst_time = Game.time
  end
  if self.auto_free and self._burst_time and Game.time - self._burst_time > 0.2 and C.gr_particles_alive(self._id) == 0 then
    self:queue_free()
  end
end

------------------------------------------------------------------ Label3D
-- Text anchored to a point in the world, drawn on the UI layer.
Label3D = Node3D:extend("Label3D")
function Label3D:_setup()
  Node3D._setup(self)
  self.text = ""
  self.size = 28
  self.color = Color(1, 1, 1)
  self.outline = 3
  self.outline_color = Color(0, 0, 0, 0.8)
  self.font = Font.bold
  self.max_distance = 40
  self.fixed_size = false   -- if false, text shrinks with distance (size is at 10 m)
end
function Label3D:__sync(vis) self._vis = vis end
function Label3D:_draw_label()
  if not self._vis or not Game.camera or self.text == "" then return end
  local p = self:global_position()
  local cam = Game.camera:global_position()
  local dist = p:distance(cam)
  if dist > self.max_distance then return end
  local x, y, on = Game.camera:world_to_screen(p)
  if not on then return end
  local size = self.fixed_size and self.size or math.clamp(self.size * 10 / math.max(dist, 0.1), 8, self.size * 3)
  local fade = 1 - math.smoothstep(self.max_distance * 0.75, self.max_distance, dist)
  local w = C.gr_text_width(self.font, self.text, size)
  local c, o = self.color, self.outline_color
  C.gr_draw_text(self.font, self.text, x - w / 2, y - size / 2, size, c.r, c.g, c.b, c.a * fade,
    self.outline * size / self.size, o.r, o.g, o.b, o.a * fade)
end
