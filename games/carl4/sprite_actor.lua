-- Pixel-art billboard characters in the cel-shaded world.
-- Each sheet (sprites/<name>.png + .lua from tools/export.py) has two drawn facings: 'se' (front three-quarter)
-- and 'ne' (back three-quarter), both facing screen-right; screen-left is the mirror. The quad turns with the
-- camera (cylindrical billboard), picks front/back from the angle between the character and the camera, and
-- does a Paper-Mario-style squash-flip when it turns around. An optional gun overlay is pinned to the hand.
local SpriteActor = Node3D:extend("SpriteActor")
local PX = 0.041                    -- metres per sprite pixel (one pixel pitch for the whole cast)
SpriteActor.PX = PX

local sheets = {}
local function sheet(name)
  if not sheets[name] then
    local meta = require("sprites." .. name)
    meta.tex = Texture.load("sprites/" .. name .. ".png", { nearest = true })
    sheets[name] = meta
  end
  return sheets[name]
end
SpriteActor.sheet = sheet

-- Unit quad with its pivot at pixel (ox, oy) of a w x h cell, facing +Z.
local quads = {}
local function quad(w, h, ox, oy)
  local key = w .. "x" .. h .. ":" .. ox .. "," .. oy
  if not quads[key] then
    local m = MeshData()
    local x0, x1 = -ox * PX, (w - ox) * PX
    local y0, y1 = (oy - h) * PX, oy * PX
    local a = m:vertex(x0, y0, 0, 0, 0, 1, 0, 1)
    local b = m:vertex(x1, y0, 0, 0, 0, 1, 1, 1)
    local c = m:vertex(x1, y1, 0, 0, 0, 1, 1, 0)
    local d = m:vertex(x0, y1, 0, 0, 0, 1, 0, 0)
    m:quad(a, b, c, d)
    quads[key] = m:upload()
  end
  return quads[key]
end

local function sprite_material(tex)
  return Material { albedo = Color.WHITE, texture = tex, alpha_cutoff = 0.5, effect = "sprite", double_sided = true, roughness = 1 }
end

function SpriteActor:_setup()
  Node3D._setup(self)
  self.sheet_name = self.sheet_name or "carl"
  self.size = self.size or 1
  self.face_yaw = 0
  self.anim = "idle"
  self.speed = 1
  self._t, self._i = 0, 1
  self._flip, self._sx = false, 1
  self._back = false
  self.tint = Color.WHITE
end

function SpriteActor:_ready()
  local s = sheet(self.sheet_name)
  self.meta = s
  self.pivot = self:add_child(Node3D { scale = Vec3(self.size) })
  self.mat = sprite_material(s.tex)
  self.mat.uv_scale = { 1 / s.cols, 1 / s.rows }
  self.quad = self.pivot:add_child(MeshInstance3D { mesh = quad(s.w, s.h, s.origin[1], s.origin[2]), material = self.mat })
  if self.gun_overlay then
    local g = sheet("guns")
    self.gmeta = g
    self.gmat = sprite_material(g.tex)
    self.gmat.uv_scale = { 1 / g.cols, 1 / g.rows }
    self.gun_quad = self.pivot:add_child(MeshInstance3D { mesh = quad(g.w, g.h, g.grip[1], g.grip[2]), material = self.gmat, visible = false })
  end
  self:_apply()
end

-- play("run") picks se_/ne_ by facing; restart = true rewinds a looping anim; on_end fires for one-shots.
function SpriteActor:play(name, restart, on_end)
  if name == self.anim and not restart then return end
  self.anim = name
  self._t, self._i = 0, 1
  self._done = false
  self.on_end = on_end
end

function SpriteActor:current() return (self._back and "ne_" or "se_") .. self.anim end
function SpriteActor:has(name) return self.meta.anims["se_" .. name] ~= nil end

function SpriteActor:set_gun(gun)
  self.gun = gun
end

local function wrap(a) return (a + math.pi) % math.tau - math.pi end

function SpriteActor:_process(dt)
  -- Billboard toward the camera position (works for the follow rig, fixed cutscene views and anything else).
  local cam = G and G.rig
  local cyaw = cam and cam.yaw or 0
  local face_q
  if cam and cam.camera then
    local d = cam.camera:global_position() - self:global_position()
    if d.x * d.x + d.z * d.z > 1e-4 then
      d = Vec3(d.x, 0, d.z):normalized()
      face_q = Quat.look_rotation(-d)      -- -Z away from the camera, so the +Z quad faces it
      cyaw = math.atan2(d.x, d.z)
    end
  end
  -- Facing relative to the camera, with a little hysteresis so it doesn't flicker on the boundary.
  local rel = wrap(self.face_yaw - cyaw)
  local c, s = math.cos(rel), -math.sin(rel)
  if self._back and c < -0.15 then self._back = false elseif not self._back and c > 0.15 then self._back = true end
  local want_flip = s < 0
  if math.abs(s) > 0.12 and want_flip ~= self._flip then self._flip = want_flip end
  -- Flip squash: scale x passes through zero when turning around.
  local target = self._flip and -1 or 1
  self._sx = math.move_toward(self._sx, target, dt * 16)
  self:set_global_rotation(face_q or Quat.from_y(cyaw))

  -- Advance the animation.
  local a = self.meta.anims[self:current()] or self.meta.anims["se_" .. self.anim]
  if a then
    self._t = self._t + dt * 1000 * self.speed
    while self._t >= a.ms[self._i] and not self._done do
      self._t = self._t - a.ms[self._i]
      if self._i < #a.frames then
        self._i = self._i + 1
        if self.on_frame then self.on_frame(self, self.anim, self._i) end
      elseif a.loop then
        self._i = 1
        if self.on_frame then self.on_frame(self, self.anim, self._i) end
      else
        self._done = true
        local cb = self.on_end; self.on_end = nil
        if cb then cb(self) end
      end
    end
    self._frame = a.frames[math.min(self._i, #a.frames)]
  end
  self:_apply()
end

function SpriteActor:done() return self._done end

function SpriteActor:_apply()
  local m = self.meta
  local fr = self._frame or 0
  local col, row = fr % m.cols, math.floor(fr / m.cols)
  local mirrored = self._sx < 0
  if mirrored then
    self.mat.uv_scale = { -1 / m.cols, 1 / m.rows }
    self.mat.uv_offset = { (col + 1) / m.cols, row / m.rows }
  else
    self.mat.uv_scale = { 1 / m.cols, 1 / m.rows }
    self.mat.uv_offset = { col / m.cols, row / m.rows }
  end
  local sx = math.max(math.abs(self._sx), 0.05)
  self.pivot.scale = Vec3(self.size * sx, self.size, self.size)
  self.mat.albedo = self.tint
  -- Hand anchor (gun hand) for muzzles and beams.
  local hh = m.hands[fr]
  if hh then
    self.hand_local = Vec3((hh.x + 0.5 - m.origin[1]) * PX, (m.origin[2] - hh.y - 0.5) * PX, 0.02)
  else
    self.hand_local = nil
  end
  -- Gun overlay on the hand.
  if self.gun_quad then
    local h = m.hands[fr]
    local gun = self.gun
    if h and gun and h.pose ~= "none" then
      local g = self.gmeta
      local key = (gun.maker or "Pretend Co.") .. "|" .. gun.kind .. "|" .. h.pose
      local gi = g.index[key] or 0
      local gc, gr = gi % g.cols, math.floor(gi / g.cols)
      if mirrored then
        self.gmat.uv_scale = { -1 / g.cols, 1 / g.rows }
        self.gmat.uv_offset = { (gc + 1) / g.cols, gr / g.rows }
      else
        self.gmat.uv_scale = { 1 / g.cols, 1 / g.rows }
        self.gmat.uv_offset = { gc / g.cols, gr / g.rows }
      end
      local hx = (h.x + 0.5 - m.origin[1]) * PX
      local hy = (m.origin[2] - h.y - 0.5) * PX
      self.gun_quad.position = Vec3(hx, hy, 0.02)
      self.gun_quad.visible = true
      self.gmat.albedo = self.tint
    else
      self.gun_quad.visible = false
    end
  end
end

-- World position of the gun hand (falls back to chest height).
function SpriteActor:hand_position()
  if self.hand_local then
    local l = self.hand_local
    return self.pivot:to_global(l)
  end
  return self:global_position() + Vec3(0, 0.8 * self.size, 0)
end

return SpriteActor
