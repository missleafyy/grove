-- Resources: MeshData (CPU mesh builder + primitives), Mesh, Material, Texture, Model, Font.
local ffi = require("ffi")
local sin, cos, sqrt, pi, floor = math.sin, math.cos, math.sqrt, math.pi, math.floor

-- Resolve a path relative to the game folder.
function res_path(p)
  if p:sub(1, 1) == "/" then return p end
  return GROVE_GAME_DIR .. "/" .. p
end

local function b(v) return v and 1 or 0 end

------------------------------------------------------------------ Mesh (GPU)
Mesh = class("Mesh")
function Mesh:_init(id)
  self.id = id
  local mn, mx = ffi.new("float[3]"), ffi.new("float[3]")
  C.gr_mesh_aabb(id, mn, mx)
  self.aabb_min = Vec3(mn[0], mn[1], mn[2])
  self.aabb_max = Vec3(mx[0], mx[1], mx[2])
end
function Mesh:size() return self.aabb_max - self.aabb_min end
function Mesh:free() C.gr_mesh_free(self.id); self.id = 0 end

------------------------------------------------------------------ MeshData (CPU)
-- Build meshes in Lua, transform/merge them, then :upload() to the GPU.
-- Colours are per-vertex, so a whole tree (trunk + leaves) can be one mesh and one draw.
MeshData = class("MeshData")

function MeshData:_init()
  self.vcap, self.icap = 64, 192
  self.v = ffi.new("GrVertex[?]", self.vcap)
  self.i = ffi.new("uint32_t[?]", self.icap)
  self.nv, self.ni = 0, 0
  self.cr, self.cg, self.cb, self.ca = 1, 1, 1, 1
end

-- Sets the colour used by subsequent vertex() calls.
function MeshData:color(c)
  self.cr, self.cg, self.cb, self.ca = c.r, c.g, c.b, c.a
  return self
end

function MeshData:vertex(px, py, pz, nx, ny, nz, u, v)
  if self.nv >= self.vcap then
    local nc = self.vcap * 2
    local nvb = ffi.new("GrVertex[?]", nc)
    ffi.copy(nvb, self.v, ffi.sizeof("GrVertex") * self.nv)
    self.v, self.vcap = nvb, nc
  end
  local vt = self.v[self.nv]
  vt.px, vt.py, vt.pz = px, py, pz
  vt.nx, vt.ny, vt.nz = nx or 0, ny or 1, nz or 0
  vt.u, vt.v = u or 0, v or 0
  vt.r, vt.g, vt.b, vt.a = self.cr, self.cg, self.cb, self.ca
  self.nv = self.nv + 1
  return self.nv - 1
end

function MeshData:tri(a, b_, c)
  if self.ni + 3 > self.icap then
    local nc = self.icap * 2
    local ni = ffi.new("uint32_t[?]", nc)
    ffi.copy(ni, self.i, 4 * self.ni)
    self.i, self.icap = ni, nc
  end
  local i = self.i
  i[self.ni], i[self.ni + 1], i[self.ni + 2] = a, b_, c
  self.ni = self.ni + 3
end

function MeshData:quad(a, b_, c, d) self:tri(a, b_, c); self:tri(a, c, d) end

-- Appends another MeshData, optionally transformed.
function MeshData:append(o, pos, rot, scale)
  local base = self.nv
  for k = 0, o.nv - 1 do
    local s = o.v[k]
    local p = Vec3(s.px, s.py, s.pz)
    local n = Vec3(s.nx, s.ny, s.nz)
    if scale then p = p * scale; n = (n / scale):normalized() end
    if rot then p = rot * p; n = rot * n end
    if pos then p = p + pos end
    local idx = self:vertex(p.x, p.y, p.z, n.x, n.y, n.z, s.u, s.v)
    local d = self.v[idx]
    d.r, d.g, d.b, d.a = s.r, s.g, s.b, s.a
  end
  for k = 0, o.ni - 1, 3 do self:tri(o.i[k] + base, o.i[k + 1] + base, o.i[k + 2] + base) end
  return self
end

function MeshData:transform(pos, rot, scale)
  for k = 0, self.nv - 1 do
    local s = self.v[k]
    local p = Vec3(s.px, s.py, s.pz)
    local n = Vec3(s.nx, s.ny, s.nz)
    if scale then
      if type(scale) == "number" then scale = Vec3(scale) end
      p = p * scale; n = (n / scale):normalized()
    end
    if rot then p = rot * p; n = rot * n end
    if pos then p = p + pos end
    s.px, s.py, s.pz, s.nx, s.ny, s.nz = p.x, p.y, p.z, n.x, n.y, n.z
  end
  return self
end

-- Recolours every vertex (or those passing filter(x,y,z)).
function MeshData:paint(c, filter)
  for k = 0, self.nv - 1 do
    local s = self.v[k]
    if not filter or filter(s.px, s.py, s.pz) then s.r, s.g, s.b, s.a = c.r, c.g, c.b, c.a end
  end
  return self
end

-- fn(x, y, z, r, g, b) -> r, g, b : per-vertex colour function.
function MeshData:paint_fn(fn)
  for k = 0, self.nv - 1 do
    local s = self.v[k]
    s.r, s.g, s.b = fn(s.px, s.py, s.pz, s.r, s.g, s.b)
  end
  return self
end

-- fn(x, y, z) -> dx, dy, dz offsets each vertex. Call :smooth_normals() or :flat() afterwards.
function MeshData:displace(fn)
  for k = 0, self.nv - 1 do
    local s = self.v[k]
    local dx, dy, dz = fn(s.px, s.py, s.pz)
    s.px, s.py, s.pz = s.px + (dx or 0), s.py + (dy or 0), s.pz + (dz or 0)
  end
  return self
end

-- Unwelds every triangle and gives it a face normal: the low-poly faceted look.
function MeshData:flat()
  local out = MeshData()
  for k = 0, self.ni - 1, 3 do
    local a, b_, c = self.v[self.i[k]], self.v[self.i[k + 1]], self.v[self.i[k + 2]]
    local e1 = Vec3(b_.px - a.px, b_.py - a.py, b_.pz - a.pz)
    local e2 = Vec3(c.px - a.px, c.py - a.py, c.pz - a.pz)
    local n = e1:cross(e2):normalized()
    local base = out.nv
    for _, s in ipairs({ a, b_, c }) do
      out.cr, out.cg, out.cb, out.ca = s.r, s.g, s.b, s.a
      out:vertex(s.px, s.py, s.pz, n.x, n.y, n.z, s.u, s.v)
    end
    out:tri(base, base + 1, base + 2)
  end
  self.v, self.i, self.nv, self.ni, self.vcap, self.icap = out.v, out.i, out.nv, out.ni, out.vcap, out.icap
  return self
end

-- Recomputes normals by averaging over shared vertices (welds by position).
function MeshData:smooth_normals()
  local acc = {}
  local function key(s) return floor(s.px * 1000 + 0.5) .. ":" .. floor(s.py * 1000 + 0.5) .. ":" .. floor(s.pz * 1000 + 0.5) end
  for k = 0, self.ni - 1, 3 do
    local ia, ib, ic = self.i[k], self.i[k + 1], self.i[k + 2]
    local a, b_, c = self.v[ia], self.v[ib], self.v[ic]
    local n = Vec3(b_.px - a.px, b_.py - a.py, b_.pz - a.pz):cross(Vec3(c.px - a.px, c.py - a.py, c.pz - a.pz))
    for _, s in ipairs({ a, b_, c }) do
      local kk = key(s)
      acc[kk] = (acc[kk] or Vec3(0, 0, 0)) + n
    end
  end
  for k = 0, self.nv - 1 do
    local s = self.v[k]
    local n = acc[key(s)]
    if n then n = n:normalized(); s.nx, s.ny, s.nz = n.x, n.y, n.z end
  end
  return self
end

function MeshData:upload()
  return Mesh(C.gr_mesh_create(self.v, self.nv, self.i, self.ni))
end

function MeshData:positions()
  local p = ffi.new("float[?]", self.nv * 3)
  for k = 0, self.nv - 1 do
    local s = self.v[k]
    p[k * 3], p[k * 3 + 1], p[k * 3 + 2] = s.px, s.py, s.pz
  end
  return p
end

function MeshData:copy()
  local o = MeshData()
  o:append(self)
  return o
end

------------------------------------------------------------------ primitives
-- All primitives are centred on the origin unless noted. Optional colour argument.

function MeshData.box(sx, sy, sz, col)
  if type(sx) == "cdata" then col = sy; sx, sy, sz = sx.x, sx.y, sx.z end
  sy, sz = sy or sx, sz or sx
  local m = MeshData()
  if col then m:color(col) end
  local hx, hy, hz = sx / 2, sy / 2, sz / 2
  local faces = {
    { 1, 0, 0, { hx, -hy, hz }, { hx, -hy, -hz }, { hx, hy, -hz }, { hx, hy, hz }, sz, sy },
    { -1, 0, 0, { -hx, -hy, -hz }, { -hx, -hy, hz }, { -hx, hy, hz }, { -hx, hy, -hz }, sz, sy },
    { 0, 1, 0, { -hx, hy, hz }, { hx, hy, hz }, { hx, hy, -hz }, { -hx, hy, -hz }, sx, sz },
    { 0, -1, 0, { -hx, -hy, -hz }, { hx, -hy, -hz }, { hx, -hy, hz }, { -hx, -hy, hz }, sx, sz },
    { 0, 0, 1, { -hx, -hy, hz }, { hx, -hy, hz }, { hx, hy, hz }, { -hx, hy, hz }, sx, sy },
    { 0, 0, -1, { hx, -hy, -hz }, { -hx, -hy, -hz }, { -hx, hy, -hz }, { hx, hy, -hz }, sx, sy },
  }
  for _, f in ipairs(faces) do
    local nx, ny, nz = f[1], f[2], f[3]
    local u, v = f[8], f[9]
    local a = m:vertex(f[4][1], f[4][2], f[4][3], nx, ny, nz, 0, v)
    local b_ = m:vertex(f[5][1], f[5][2], f[5][3], nx, ny, nz, u, v)
    local c = m:vertex(f[6][1], f[6][2], f[6][3], nx, ny, nz, u, 0)
    local d = m:vertex(f[7][1], f[7][2], f[7][3], nx, ny, nz, 0, 0)
    m:quad(a, b_, c, d)
  end
  return m
end

function MeshData.sphere(r, segments, rings, col)
  segments, rings = segments or 24, rings or 16
  local m = MeshData()
  if col then m:color(col) end
  for y = 0, rings do
    local v = y / rings
    local phi = v * pi
    for x = 0, segments do
      local u = x / segments
      local th = u * 2 * pi
      local nx, ny, nz = sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)
      m:vertex(nx * r, ny * r, nz * r, nx, ny, nz, u, v)
    end
  end
  for y = 0, rings - 1 do
    for x = 0, segments - 1 do
      local a = y * (segments + 1) + x
      local b_ = a + segments + 1
      m:tri(a, a + 1, b_ + 1)
      m:tri(a, b_ + 1, b_)
    end
  end
  return m
end

-- Icosphere: even triangles, great for low-poly rocks and blobs.
function MeshData.icosphere(r, subdiv, col)
  subdiv = subdiv or 1
  local t = (1 + sqrt(5)) / 2
  local verts = { { -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 }, { 0, -1, t }, { 0, 1, t }, { 0, -1, -t }, { 0, 1, -t },
    { t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 } }
  local faces = { { 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 }, { 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 },
    { 8, 2, 9 }, { 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 }, { 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 } }
  for i, v in ipairs(verts) do
    local l = sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
    verts[i] = { v[1] / l, v[2] / l, v[3] / l }
  end
  for _ = 1, subdiv do
    local cache, nf = {}, {}
    local function mid(a, b_)
      local k = a < b_ and (a .. "_" .. b_) or (b_ .. "_" .. a)
      if cache[k] then return cache[k] end
      local va, vb = verts[a], verts[b_]
      local x, y, z = (va[1] + vb[1]) / 2, (va[2] + vb[2]) / 2, (va[3] + vb[3]) / 2
      local l = sqrt(x * x + y * y + z * z)
      verts[#verts + 1] = { x / l, y / l, z / l }
      cache[k] = #verts
      return #verts
    end
    for _, f in ipairs(faces) do
      local a, b_, c = mid(f[1], f[2]), mid(f[2], f[3]), mid(f[3], f[1])
      nf[#nf + 1] = { f[1], a, c }; nf[#nf + 1] = { f[2], b_, a }; nf[#nf + 1] = { f[3], c, b_ }; nf[#nf + 1] = { a, b_, c }
    end
    faces = nf
  end
  local m = MeshData()
  if col then m:color(col) end
  for _, v in ipairs(verts) do m:vertex(v[1] * r, v[2] * r, v[3] * r, v[1], v[2], v[3], 0.5 + math.atan2(v[3], v[1]) / (2 * pi), 0.5 - math.asin(v[2]) / pi) end
  for _, f in ipairs(faces) do
    -- Orient each face outward.
    local a, b_, c = verts[f[1]], verts[f[2]], verts[f[3]]
    local n = Vec3(b_[1] - a[1], b_[2] - a[2], b_[3] - a[3]):cross(Vec3(c[1] - a[1], c[2] - a[2], c[3] - a[3]))
    if n:dot(Vec3(a[1] + b_[1] + c[1], a[2] + b_[2] + c[2], a[3] + b_[3] + c[3])) >= 0 then m:tri(f[1] - 1, f[2] - 1, f[3] - 1)
    else m:tri(f[1] - 1, f[3] - 1, f[2] - 1) end
  end
  return m
end

-- Cylinder / cone / frustum along Y, base at y = -h/2.
function MeshData.cylinder(r_top, r_bottom, h, segments, col, caps)
  segments = segments or 16
  if caps == nil then caps = true end
  local m = MeshData()
  if col then m:color(col) end
  local hh = h / 2
  local slope = (r_bottom - r_top) / h
  for i = 0, segments do
    local u = i / segments
    local a = u * 2 * pi
    local c, s = cos(a), sin(a)
    local n = Vec3(c, slope, s):normalized()
    m:vertex(c * r_bottom, -hh, s * r_bottom, n.x, n.y, n.z, u, 1)
    m:vertex(c * r_top, hh, s * r_top, n.x, n.y, n.z, u, 0)
  end
  for i = 0, segments - 1 do
    local a = i * 2
    m:tri(a, a + 1, a + 3)
    m:tri(a, a + 3, a + 2)
  end
  if caps then
    for side = 0, 1 do
      local y = side == 0 and hh or -hh
      local r = side == 0 and r_top or r_bottom
      if r > 0 then
        local ny = side == 0 and 1 or -1
        local center = m:vertex(0, y, 0, 0, ny, 0, 0.5, 0.5)
        local first = m.nv
        for i = 0, segments do
          local a = i / segments * 2 * pi
          m:vertex(cos(a) * r, y, sin(a) * r, 0, ny, 0, 0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5)
        end
        for i = 0, segments - 1 do
          if side == 0 then m:tri(center, first + i + 1, first + i) else m:tri(center, first + i, first + i + 1) end
        end
      end
    end
  end
  return m
end

function MeshData.cone(r, h, segments, col) return MeshData.cylinder(0, r, h, segments, col) end

-- Capsule along Y, total height h (including the caps), centred on the origin.
function MeshData.capsule(r, h, segments, col)
  segments = segments or 16
  local rings = 8
  local m = MeshData()
  if col then m:color(col) end
  local half = math.max(h / 2 - r, 0)
  local rows = 0
  for y = 0, rings * 2 + 1 do
    local phi, cy
    if y <= rings then phi = y / rings * pi / 2; cy = half
    else phi = pi / 2 + (y - rings - 1) / rings * pi / 2; cy = -half end
    for x = 0, segments do
      local th = x / segments * 2 * pi
      local nx, ny, nz = sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)
      m:vertex(nx * r, ny * r + cy, nz * r, nx, ny, nz, x / segments, y / (rings * 2 + 1))
    end
    rows = rows + 1
  end
  for y = 0, rows - 2 do
    for x = 0, segments - 1 do
      local a = y * (segments + 1) + x
      local b_ = a + segments + 1
      m:tri(a, a + 1, b_ + 1)
      m:tri(a, b_ + 1, b_)
    end
  end
  return m
end

function MeshData.torus(R, r, segments, sides, col)
  segments, sides = segments or 32, sides or 12
  local m = MeshData()
  if col then m:color(col) end
  for i = 0, segments do
    local u = i / segments * 2 * pi
    for j = 0, sides do
      local v = j / sides * 2 * pi
      local nx, ny, nz = cos(u) * cos(v), sin(v), sin(u) * cos(v)
      m:vertex(cos(u) * (R + r * cos(v)), r * sin(v), sin(u) * (R + r * cos(v)), nx, ny, nz, i / segments, j / sides)
    end
  end
  for i = 0, segments - 1 do
    for j = 0, sides - 1 do
      local a = i * (sides + 1) + j
      local b_ = a + sides + 1
      m:tri(a, a + 1, b_ + 1)
      m:tri(a, b_ + 1, b_)
    end
  end
  return m
end

-- Flat XZ plane of w x d, subdivided. heightfn(x, z) -> y (optional), colorfn(x, y, z) -> Color (optional).
function MeshData.grid(w, d, res_x, res_z, heightfn, colorfn)
  res_x, res_z = res_x or 1, res_z or res_x or 1
  local m = MeshData()
  local hw, hd = w / 2, d / 2
  for z = 0, res_z do
    for x = 0, res_x do
      local px, pz = -hw + w * x / res_x, -hd + d * z / res_z
      local py = heightfn and heightfn(px, pz) or 0
      if colorfn then m:color(colorfn(px, py, pz)) end
      m:vertex(px, py, pz, 0, 1, 0, x / res_x, z / res_z)
    end
  end
  for z = 0, res_z - 1 do
    for x = 0, res_x - 1 do
      local a = z * (res_x + 1) + x
      local b_ = a + res_x + 1
      m:tri(a, b_, a + 1)
      m:tri(a + 1, b_, b_ + 1)
    end
  end
  if heightfn then m:smooth_normals() end
  return m
end

function MeshData.plane(w, d, col)
  local m = MeshData.grid(w, d or w, 1, 1)
  if col then m:paint(col) end
  return m
end

------------------------------------------------------------------ Material
local mat_fields = {
  albedo = "color4", emission = "color3", emission_energy = "f", roughness = "f", metallic = "f", rim = "f",
  uv_scale = "vec2", alpha_cutoff = "f", wind = "f", texture = "tex", unshaded = "b", transparent = "b",
  double_sided = "b", vertex_color = "b", effect = "effect", triplanar = "b", no_fog = "b", uv_offset = "vec2o",
}
local effects = { none = 0, water = 1, pulse = 2, sprite = 3 }

Material = {}
local MaterialMT = {}

local function mat_set(self, k, v)
  local ptr = rawget(self, "_ptr")
  local kind = mat_fields[k]
  if not kind then rawset(self, k, v) return end
  rawget(self, "_vals")[k] = v
  if kind == "f" then ptr[k] = v
  elseif kind == "b" then ptr[k] = v and 1 or 0
  elseif kind == "color4" then ptr.albedo[0], ptr.albedo[1], ptr.albedo[2], ptr.albedo[3] = v.r, v.g, v.b, v.a
  elseif kind == "color3" then ptr.emission[0], ptr.emission[1], ptr.emission[2] = v.r, v.g, v.b
  elseif kind == "vec2" then
    if type(v) == "number" then ptr.uv_scale[0], ptr.uv_scale[1] = v, v else ptr.uv_scale[0], ptr.uv_scale[1] = v[1] or v.x, v[2] or v.y end
  elseif kind == "vec2o" then
    if type(v) == "number" then ptr.uv_offset[0], ptr.uv_offset[1] = v, v else ptr.uv_offset[0], ptr.uv_offset[1] = v[1] or v.x, v[2] or v.y end
  elseif kind == "tex" then ptr.albedo_tex = v and v.id or 0
  elseif kind == "effect" then ptr.effect = type(v) == "number" and v or (effects[v] or 0)
  end
end

MaterialMT.__index = function(self, k)
  local vals = rawget(self, "_vals")
  if vals[k] ~= nil then return vals[k] end
  local kind = mat_fields[k]
  if kind == "f" then return rawget(self, "_ptr")[k] end
  if kind == "b" then return rawget(self, "_ptr")[k] ~= 0 end
  if kind == "color4" then local a = rawget(self, "_ptr").albedo; return Color(a[0], a[1], a[2], a[3]) end
  if kind == "color3" then local a = rawget(self, "_ptr").emission; return Color(a[0], a[1], a[2]) end
  return Material[k]
end
MaterialMT.__newindex = mat_set

function Material.new(props)
  local id = C.gr_material_create()
  local m = setmetatable({ id = id, _ptr = C.gr_material_get(id), _vals = {} }, MaterialMT)
  for k, v in pairs(props or {}) do mat_set(m, k, v) end
  if props and props.emission and props.emission_energy == nil then mat_set(m, "emission_energy", 1) end
  return m
end

function Material:clone(overrides)
  local props = {}
  for k, v in pairs(rawget(self, "_vals")) do props[k] = v end
  for k, v in pairs(overrides or {}) do props[k] = v end
  return Material.new(props)
end

function Material:free() C.gr_material_free(self.id) end

setmetatable(Material, { __call = function(_, props) return Material.new(props) end })

------------------------------------------------------------------ Texture
Texture = class("Texture")
function Texture:_init(id)
  self.id = id
  local w, h = ffi.new("int[1]"), ffi.new("int[1]")
  C.gr_texture_size(id, w, h)
  self.width, self.height = w[0], h[0]
end

function Texture.load(path, opts)
  opts = opts or {}
  local id = C.gr_texture_load(res_path(path), opts.nearest and 1 or 0)
  if id == 0 then error("could not load texture " .. path, 2) end
  return Texture(id)
end

-- fn(x, y, u, v) -> r, g, b, a in 0..1 (or a Color).
function Texture.generate(w, h, fn, opts)
  opts = opts or {}
  local px = ffi.new("uint8_t[?]", w * h * 4)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, bl, a = fn(x, y, (x + 0.5) / w, (y + 0.5) / h)
      if type(r) == "cdata" then r, g, bl, a = r.r, r.g, r.b, r.a end
      local o = (y * w + x) * 4
      px[o] = math.clamp(r, 0, 1) * 255
      px[o + 1] = math.clamp(g, 0, 1) * 255
      px[o + 2] = math.clamp(bl, 0, 1) * 255
      px[o + 3] = math.clamp(a or 1, 0, 1) * 255
    end
  end
  return Texture(C.gr_texture_create(w, h, px, opts.nearest and 1 or 0, opts.clamp and 0 or 1))
end

function Texture.checker(size, cells, c1, c2)
  c1, c2 = c1 or Color(0.9), c2 or Color(0.6)
  return Texture.generate(size, size, function(x, y)
    local cs = size / cells
    local odd = (floor(x / cs) + floor(y / cs)) % 2 == 1
    return odd and c1 or c2
  end)
end

function Texture:free() C.gr_texture_free(self.id) end

------------------------------------------------------------------ Model (glTF / OBJ)
Model = {}
-- Returns { {mesh=Mesh, material=Material}, ... }; cached per path.
local model_cache = {}
function Model.load(path)
  path = res_path(path)
  if model_cache[path] then return model_cache[path] end
  local meshes, mats = ffi.new("int[256]"), ffi.new("int[256]")
  local n = C.gr_model_load(path, meshes, mats, 256)
  if n == 0 then error("could not load model " .. path, 2) end
  local parts = {}
  for i = 0, n - 1 do
    local m = setmetatable({ id = mats[i], _ptr = C.gr_material_get(mats[i]), _vals = {} }, MaterialMT)
    parts[#parts + 1] = { mesh = Mesh(meshes[i]), material = m }
  end
  model_cache[path] = parts
  return parts
end

-- A Node3D holding one MeshInstance3D per model part.
function Model.instance(path, props)
  local root = Node3D(props or {})
  for _, p in ipairs(Model.load(path)) do
    root:add_child(MeshInstance3D { mesh = p.mesh, material = p.material })
  end
  return root
end

------------------------------------------------------------------ Font
Font = { regular = 1, bold = 2 }
function Font.load(path)
  local id = C.gr_font_load(res_path(path))
  if id == 0 then error("could not load font " .. path, 2) end
  return id
end
