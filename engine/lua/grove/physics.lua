-- Physics nodes over Jolt: StaticBody3D, RigidBody3D, AnimatableBody3D, CharacterBody3D, Area3D.
-- Bodies are created at their global transform when they enter the tree.
local ffi = require("ffi")

Physics = {
  bodies = setmetatable({}, { __mode = "v" }),  -- body handle -> node
  kinematic = {},
  areas = {},
  gravity = Vec3(0, -9.81, 0),
}

------------------------------------------------------------------ shapes
Shape = {}
local shape_cache = {}
local function cached(key, make)
  local s = shape_cache[key]
  if not s then s = make(); shape_cache[key] = s end
  return s
end

-- Box by full size (Vec3 or three numbers).
function Shape.box(sx, sy, sz)
  if type(sx) == "cdata" then sx, sy, sz = sx.x, sx.y, sx.z end
  sy, sz = sy or sx, sz or sx
  return cached(string.format("box%.4f,%.4f,%.4f", sx, sy, sz), function()
    return { id = C.gr_shape_box(sx / 2, sy / 2, sz / 2), kind = "box", size = Vec3(sx, sy, sz) }
  end)
end
function Shape.sphere(r)
  return cached("sph" .. r, function() return { id = C.gr_shape_sphere(r), kind = "sphere", radius = r } end)
end
-- Capsule along Y with total height (including caps).
function Shape.capsule(r, h)
  return cached("cap" .. r .. "," .. h, function() return { id = C.gr_shape_capsule(math.max(h / 2 - r, 0.001), r), kind = "capsule", radius = r, height = h } end)
end
function Shape.cylinder(r, h)
  return cached("cyl" .. r .. "," .. h, function() return { id = C.gr_shape_cylinder(h / 2, r), kind = "cylinder", radius = r, height = h } end)
end
-- Convex hull around a MeshData or a list of Vec3.
function Shape.convex(src)
  local pts, n
  if type(src) == "table" and src.nv then pts, n = src:positions(), src.nv
  else
    n = #src
    pts = ffi.new("float[?]", n * 3)
    for i, p in ipairs(src) do pts[(i - 1) * 3], pts[(i - 1) * 3 + 1], pts[(i - 1) * 3 + 2] = p.x, p.y, p.z end
  end
  return { id = C.gr_shape_convex(pts, n), kind = "convex" }
end
-- Exact triangle mesh (static bodies only).
function Shape.mesh(md)
  return { id = C.gr_shape_mesh(md:positions(), md.nv, md.i, md.ni), kind = "mesh" }
end
function Shape.offset(shape, v)
  return { id = C.gr_shape_offset(shape.id, v.x, v.y, v.z), kind = "offset" }
end

------------------------------------------------------------------ queries
local hit = ffi.new("GrRayHit")
-- Raycast from 'from' to 'to'. Returns { node, position, normal, distance, fraction } or nil.
function Physics.raycast(from, to, exclude)
  local d = to - from
  local ex = 0
  if exclude then ex = exclude._body or 0 end
  if C.gr_physics_raycast(from.x, from.y, from.z, d.x, d.y, d.z, ex, hit) == 0 then return nil end
  return {
    node = Physics.bodies[hit.body],
    position = Vec3(hit.pos[0], hit.pos[1], hit.pos[2]),
    normal = Vec3(hit.normal[0], hit.normal[1], hit.normal[2]),
    fraction = hit.fraction,
    distance = d:length() * hit.fraction,
  }
end

local overlap_buf = ffi.new("int[256]")
function Physics.overlap_sphere(center, radius)
  local n = C.gr_physics_sphere_overlap(center.x, center.y, center.z, radius, overlap_buf, 256)
  local out = {}
  for i = 0, n - 1 do
    local node = Physics.bodies[overlap_buf[i]]
    if node then out[#out + 1] = node end
  end
  return out
end

function Physics.set_gravity(v)
  Physics.gravity = v:copy()
  C.gr_physics_gravity(v.x, v.y, v.z)
end

function Physics.body_count() return C.gr_physics_body_count() end

------------------------------------------------------------------ PhysicsBody3D
PhysicsBody3D = Node3D:extend("PhysicsBody3D")
local desc = ffi.new("GrBodyDesc")

function PhysicsBody3D:_setup()
  Node3D._setup(self)
  self.friction = 0.6
  self.bounce = 0
end

function PhysicsBody3D:_create(motion, sensor)
  assert(self.shape, tostring(self) .. " needs a shape")
  local gp, gr = self:global_transform()
  desc.shape = self.shape.id
  desc.motion = motion
  desc.sensor = sensor and 1 or 0
  desc.pos[0], desc.pos[1], desc.pos[2] = gp.x, gp.y, gp.z
  desc.rot[0], desc.rot[1], desc.rot[2], desc.rot[3] = gr.x, gr.y, gr.z, gr.w
  desc.friction = self.friction
  desc.restitution = self.bounce
  desc.mass = self.mass or 0
  desc.linear_damping = self.linear_damp or 0.05
  desc.angular_damping = self.angular_damp or 0.05
  desc.gravity_factor = self.gravity_scale or 1
  desc.ccd = self.ccd and 1 or 0
  self._body = C.gr_body_create(desc)
  Physics.bodies[self._body] = self
end

function PhysicsBody3D:__exit()
  if self._body then
    Physics.bodies[self._body] = nil
    C.gr_body_destroy(self._body)
    self._body = nil
  end
end

StaticBody3D = PhysicsBody3D:extend("StaticBody3D")
function StaticBody3D:__enter() self:_create(0) end

-- Moved by code (platforms, doors); pushes dynamic bodies and carries characters.
AnimatableBody3D = PhysicsBody3D:extend("AnimatableBody3D")
function AnimatableBody3D:__enter() self:_create(1); Physics.kinematic[self] = true end
function AnimatableBody3D:__exit() Physics.kinematic[self] = nil; PhysicsBody3D.__exit(self) end
function AnimatableBody3D:_physics_sync(dt)
  local gp, gr = self:global_transform()
  C.gr_body_move_kinematic(self._body, gp.x, gp.y, gp.z, gr.x, gr.y, gr.z, gr.w, dt)
end

------------------------------------------------------------------ RigidBody3D
-- Simulated body. Its position/rotation are global and written back every physics step.
RigidBody3D = PhysicsBody3D:extend("RigidBody3D")
function RigidBody3D:_setup()
  PhysicsBody3D._setup(self)
  self.top_level = true
  self.gravity_scale = 1
end
function RigidBody3D:__enter() self:_create(2); self:_ready_body() end

local lin, ang = ffi.new("float[3]"), ffi.new("float[3]")
function RigidBody3D:get_velocity()
  C.gr_body_get_velocity(self._body, lin, ang)
  return Vec3(lin[0], lin[1], lin[2])
end
function RigidBody3D:get_angular_velocity()
  C.gr_body_get_velocity(self._body, lin, ang)
  return Vec3(ang[0], ang[1], ang[2])
end
function RigidBody3D:set_velocity(v, av)
  if not self._body then self._initial_velocity = v return end
  av = av or self:get_angular_velocity()
  C.gr_body_set_velocity(self._body, v.x, v.y, v.z, av.x, av.y, av.z)
end
function RigidBody3D:set_angular_velocity(av)
  local v = self:get_velocity()
  C.gr_body_set_velocity(self._body, v.x, v.y, v.z, av.x, av.y, av.z)
end
function RigidBody3D:apply_impulse(v, at)
  if at then C.gr_body_impulse(self._body, v.x, v.y, v.z, at.x, at.y, at.z, 1)
  else C.gr_body_impulse(self._body, v.x, v.y, v.z, 0, 0, 0, 0) end
end
function RigidBody3D:apply_force(v) C.gr_body_force(self._body, v.x, v.y, v.z) end
function RigidBody3D:teleport(pos, rot)
  rot = rot or self.rotation
  self.position, self.rotation = pos:copy(), rot:copy()
  if self._body then C.gr_body_set(self._body, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w) end
end
function RigidBody3D:is_sleeping() return C.gr_body_sleeping(self._body) == 1 end
function RigidBody3D:wake() C.gr_body_wake(self._body) end
function RigidBody3D:_ready_body()
  if self._initial_velocity then self:set_velocity(self._initial_velocity); self._initial_velocity = nil end
end

------------------------------------------------------------------ CharacterBody3D
-- Kinematic character controller (Jolt CharacterVirtual). Origin is at the feet.
-- Set .velocity and call move_and_slide() in _physics_process; gravity is up to you.
CharacterBody3D = PhysicsBody3D:extend("CharacterBody3D")
function CharacterBody3D:_setup()
  PhysicsBody3D._setup(self)
  self.top_level = true
  self.radius = 0.4
  self.height = 1.8
  self.max_slope = 50
  self.step_height = 0.35
  self.velocity = Vec3(0, 0, 0)
  self._state = ffi.new("GrCharState")
end
function CharacterBody3D:__enter()
  local gp = self:global_position()
  self._char = C.gr_character_create(self.radius, self.height, gp.x, gp.y, gp.z, self.max_slope, self.step_height)
  self._body = C.gr_character_body(self._char)
  if self._body ~= 0 then Physics.bodies[self._body] = self end
end
function CharacterBody3D:__exit()
  if self._body then Physics.bodies[self._body] = nil end
  C.gr_character_destroy(self._char)
  self._char, self._body = nil, nil
end
function CharacterBody3D:move_and_slide(dt)
  dt = dt or Game.physics_dt
  local v = self.velocity
  local s = self._state
  C.gr_character_move(self._char, v.x, v.y, v.z, dt, s)
  self.position = Vec3(s.pos[0], s.pos[1], s.pos[2])
  self.velocity = Vec3(s.vel[0], s.vel[1], s.vel[2])
  self._on_floor, self._on_wall, self._on_ceiling = s.on_floor == 1, s.on_wall == 1, s.on_ceiling == 1
  self.floor_normal = Vec3(s.floor_normal[0], s.floor_normal[1], s.floor_normal[2])
  self.floor_node = Physics.bodies[s.floor_body]
end
function CharacterBody3D:is_on_floor() return self._on_floor == true end
function CharacterBody3D:is_on_wall() return self._on_wall == true end
function CharacterBody3D:is_on_ceiling() return self._on_ceiling == true end
function CharacterBody3D:teleport(pos)
  self.position = pos:copy()
  self.velocity = Vec3(0, 0, 0)
  if self._char then C.gr_character_teleport(self._char, pos.x, pos.y, pos.z) end
end

------------------------------------------------------------------ Area3D
-- Detects bodies entering/leaving its shape: signals body_entered(node), body_exited(node).
Area3D = PhysicsBody3D:extend("Area3D")
function Area3D:_setup()
  PhysicsBody3D._setup(self)
  self.monitoring = true
  self._inside = {}
end
function Area3D:__enter()
  self:_create(0, true)
  Physics.areas[self] = true
  self._last_pos = self:global_position()
end
function Area3D:__exit()
  Physics.areas[self] = nil
  PhysicsBody3D.__exit(self)
  self._inside = {}
end
function Area3D:get_overlapping_bodies()
  local out = {}
  for n in pairs(self._inside) do out[#out + 1] = n end
  return out
end

local area_buf = ffi.new("int[128]")
function Area3D:_update_overlaps()
  local gp, gr = self:global_transform()
  if gp:distance_sq(self._last_pos) > 1e-8 then
    C.gr_body_set(self._body, gp.x, gp.y, gp.z, gr.x, gr.y, gr.z, gr.w)
    self._last_pos = gp
  end
  if not self.monitoring then return end
  local n = C.gr_body_overlaps(self._body, area_buf, 128)
  local now = {}
  for i = 0, n - 1 do
    local node = Physics.bodies[area_buf[i]]
    if node and not node:is(Area3D) then now[node] = true end
  end
  for node in pairs(now) do
    if not self._inside[node] then self._inside[node] = true; self:emit("body_entered", node) end
  end
  for node in pairs(self._inside) do
    if not now[node] then self._inside[node] = nil; self:emit("body_exited", node) end
  end
end

------------------------------------------------------------------ stepping
local MAX_ACTIVE = 8192
local active_ids = ffi.new("int[?]", MAX_ACTIVE)
local active_xf = ffi.new("float[?]", MAX_ACTIVE * 7)
local contact = ffi.new("GrContact")

function Physics._step(dt)
  for body in pairs(Physics.kinematic) do body:_physics_sync(dt) end
  C.gr_physics_step(dt)

  local n = C.gr_physics_active(active_ids, active_xf, MAX_ACTIVE)
  for i = 0, n - 1 do
    local node = Physics.bodies[active_ids[i]]
    if node and node.top_level and not node._char then
      local o = i * 7
      node.position = Vec3(active_xf[o], active_xf[o + 1], active_xf[o + 2])
      node.rotation = Quat(active_xf[o + 3], active_xf[o + 4], active_xf[o + 5], active_xf[o + 6])
    end
  end

  while C.gr_physics_poll_contact(contact) == 1 do
    local a, b = Physics.bodies[contact.a], Physics.bodies[contact.b]
    if a or b then
      local info
      local function make()
        info = info or { point = Vec3(contact.point[0], contact.point[1], contact.point[2]),
          normal = Vec3(contact.normal[0], contact.normal[1], contact.normal[2]), speed = contact.speed }
        return info
      end
      if a and a:has_listeners("body_entered") then a:emit("body_entered", b, make()) end
      if b and b:has_listeners("body_entered") then b:emit("body_entered", a, make()) end
    end
  end

  for area in pairs(Physics.areas) do area:_update_overlaps() end
end
