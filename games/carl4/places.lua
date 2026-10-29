-- Story places: the crash site, the three power-cell puzzles, roadside camps and the Desert Bus.
local Art = require("art")
local Props = require("props")
local Loot = require("loot")
local Enemies = require("enemies")
local P = Art.pal
local Places = {}

local M
local function box_mesh(sx, sy, sz, col) return MeshData.box(sx, sy, sz, col):flat():upload() end

-- Static box with a matching mesh. pos is the box centre.
local function wall(root, pos, size, col, rot, mat)
  return root:add_child(StaticBody3D { position = pos, rotation = rot or Quat(), shape = Shape.box(size.x, size.y, size.z),
    MeshInstance3D { mesh = box_mesh(size.x, size.y, size.z, col), material = mat or M.vertex } })
end

-- Collision only (the look comes from a detailed mesh).
local function solid(root, pos, size, rot)
  return root:add_child(StaticBody3D { position = pos, rotation = rot or Quat(), shape = Shape.box(size.x, size.y, size.z) })
end

-- A chain-link fence run from a to b (flat ends), h tall, with a collider.
local chain_mat
local function fence(root, a, b, h)
  if not chain_mat then
    chain_mat = Material { albedo = Color.WHITE, texture = Art.chainlink_texture(), alpha_cutoff = 0.5, double_sided = true, metallic = 0.5, roughness = 0.4 }
  end
  local d = b - a
  local len = d:flat():length()
  local yaw = math.atan2(-d.z, d.x)
  local rot = Quat.from_y(yaw)
  local node = root:add_child(StaticBody3D { position = a, rotation = rot, shape = Shape.offset(Shape.box(len, h, 0.15), Vec3(len / 2, h / 2, 0)) })
  local q = MeshData()
  local v0 = q:vertex(0, 0.1, 0, 0, 0, 1, 0, h * 1.6)
  local v1 = q:vertex(len, 0.1, 0, 0, 0, 1, len * 1.6, h * 1.6)
  local v2 = q:vertex(len, h, 0, 0, 0, 1, len * 1.6, 0)
  local v3 = q:vertex(0, h, 0, 0, 0, 1, 0, 0)
  q:quad(v0, v1, v2, v3)
  node:add_child(MeshInstance3D { mesh = q:upload(), material = chain_mat, cast_shadow = false })
  node:add_child(MeshInstance3D { mesh = Art.fence_frame(len, h):upload(), material = M.metal })
  return node
end

local function ground(x, z) return World.height(x, z) end
local function at(x, z, dy) return Vec3(x, ground(x, z) + (dy or 0), z) end

-- Sums the mass of rigid bodies inside an area.
local function area_mass(area)
  local total = 0
  for _, b in ipairs(area:get_overlapping_bodies()) do
    if b:is(RigidBody3D) and b.mass and not (b.groups and b.groups.gun_pickups) then total = total + b.mass end
  end
  return total
end

------------------------------------------------------------------ crash site
function Places.crash_site(root)
  local z = World.zones.crash
  local c = Vec3(z.x, z.h, z.z)
  local ship = root:add_child(StaticBody3D { name = "ASS", position = c + Vec3(0, 2.3, 0), rotation = Quat.euler(0.22, 0.6, 0.12),
    shape = Shape.offset(Shape.cylinder(5.6, 2.4), Vec3(0, -0.2, 0)),
    MeshInstance3D { mesh = Art.ship():upload(), material = M.metal },
    MeshInstance3D { mesh = Art.ship_dome():upload(), material = M.glass, position = Vec3(0, 0.9, 0) },
  })
  ship:add_child(MeshInstance3D { mesh = MeshData.torus(2.0, 0.16, 32, 6, Color.WHITE):upload(), material = M.glow, tint = Color.hex("#7dffb0"),
    position = Vec3(0, -1.62, 0), cast_shadow = false })
  ship:add_child(OmniLight3D { color = Color.hex("#4dffa6"), energy = 2.5, range = 6, position = Vec3(0, -2.2, 0) })
  ship:add_child(Label3D { text = "A.S.S.", position = Vec3(0, 2.6, 0), size = 26, color = Color.hex("#9dffcf"), max_distance = 60 })
  ship:add_child(Particles3D { rate = 10, lifetime = 4, speed = 1.5, spread = 15, direction = Vec3(0.2, 1, 0), size = 1, size_end = 3.5, additive = false,
    color = Color(0.25, 0.23, 0.22, 0.55), color_end = Color(0.4, 0.38, 0.36, 0), position = Vec3(3, 1, 2), amount = 60 })
  ship:add_child(Particles3D { rate = 20, lifetime = 0.5, speed = 2, spread = 40, direction = Vec3(0, 1, 0), size = 0.12, size_end = 0,
    color = Color(0.5, 1, 0.7, 1), color_end = Color(0.5, 1, 0.7, 0), position = Vec3(-2, 0.6, 3.5), amount = 30 })
  -- Gouge in the sand behind the ship.
  local trench = MeshData.box(5, 0.1, 30, P.sand_dark)
  root:add_child(MeshInstance3D { mesh = trench:upload(), material = M.vertex, position = c + Vec3(-6, 0.1, 18), rotation = Quat.from_y(0.6), cast_shadow = false })
  Places.ship = ship
  Places.ship_pos = c
  -- Three empty cell sockets that light up as cells come home.
  Places.sockets = {}
  for i = 1, 3 do
    local a = (i - 2) * 0.5
    local sp = c + Vec3(math.sin(a) * 7.5, 0, -math.cos(a) * 7.5)
    local s = root:add_child(Node3D { position = Vec3(sp.x, ground(sp.x, sp.z), sp.z) })
    s:add_child(MeshInstance3D { mesh = MeshData.cylinder(0.5, 0.6, 0.5, 12, P.metal_dark):flat():upload(), material = M.metal, position = Vec3(0, 0.25, 0) })
    s.cell = s:add_child(MeshInstance3D { mesh = Loot.meshes.cell, material = M.cell, position = Vec3(0, 0.95, 0), visible = false })
    s.light = s:add_child(OmniLight3D { color = Color.hex("#4dffa6"), energy = 0, range = 6, position = Vec3(0, 1.4, 0) })
    root:add_child(StaticBody3D { position = s.position + Vec3(0, 0.25, 0), shape = Shape.cylinder(0.6, 0.5) })
    Places.sockets[i] = s
  end
  root:add_child(Loot.vending(at(c.x - 8, c.z + 5), -2.2))
  root:add_child(Loot.chest(at(c.x + 7, c.z - 4), 0.4, 1, 1))
  for i = 1, 5 do root:add_child(Props.crate(at(c.x + 9 + (i % 2) * 1.1, c.z + 4, 0.5 + math.floor(i / 2) * 1.02), 1)) end
  root:add_child(Props.explosive(at(c.x - 5, c.z - 8, 0.6)))
  root:add_child(Props.tire(at(c.x + 4, c.z + 9, 0.5)))
  -- A few cacti on the dunes to the north as a warm-up.
  Enemies.camp(root, Vec3(c.x - 8, 0, c.z - 34), { "cactus", "cactus", "cactus" }, 1, 8)
  Places.spawn = at(c.x + 1, c.z - 9, 0.3)
end

------------------------------------------------------------------ puzzle 1: the Weigh Station
function Places.weigh_station(root, on_cell)
  local z = World.zones.weigh
  local c = Vec3(z.x, z.h, z.z)
  local NEED = 600
  -- Scale plate and its readout.
  solid(root, c + Vec3(0, 0.08, -2), Vec3(6.2, 0.16, 4))
  root:add_child(MeshInstance3D { mesh = Art.scale_deck():upload(), material = M.metal, position = c + Vec3(0, 0.08, -2) })
  local area = root:add_child(Area3D { position = c + Vec3(0, 1.8, -2), shape = Shape.box(5.8, 3.2, 3.8) })
  local post = wall(root, c + Vec3(-4.4, 1.5, -4.4), Vec3(0.2, 3, 0.2), P.metal_dark)
  wall(root, c + Vec3(-4.4, 3.2, -4.4), Vec3(2.8, 1.2, 0.2), P.metal_dark, nil, M.metal)
  wall(root, c + Vec3(-4.4, 3.2, -4.52), Vec3(2.5, 0.9, 0.05), Color.hex("#16120e"))
  wall(root, c + Vec3(-4.4, 3.9, -4.4), Vec3(3.0, 0.12, 0.5), P.red)
  local readout = root:add_child(Label3D { text = "", position = c + Vec3(-4.4, 3.2, -4.6), size = 24, color = Color.hex("#ffe28a"), max_distance = 50 })
  root:add_child(Label3D { text = "NEVADA DOT  WEIGH STATION", position = c + Vec3(-6, 4.6, 4), size = 22, color = Color.WHITE, max_distance = 60 })
  -- Booth.
  solid(root, c + Vec3(-6, 1.5, 4), Vec3(4, 3, 3))
  solid(root, c + Vec3(-6, 3.1, 4), Vec3(4.8, 0.22, 3.8))
  root:add_child(MeshInstance3D { mesh = Art.weigh_booth():upload(), material = M.vertex, position = c + Vec3(-6, 0, 4) })
  -- Impound yard to the east, closed by a sliding gate.
  local yx0, yx1, yz0, yz1 = 5, 16, -7, 7
  fence(root, c + Vec3(yx0, 0, yz0), c + Vec3(yx1, 0, yz0), 3.2)
  fence(root, c + Vec3(yx0, 0, yz1), c + Vec3(yx1, 0, yz1), 3.2)
  fence(root, c + Vec3(yx1, 0, yz0), c + Vec3(yx1, 0, yz1), 3.2)
  fence(root, c + Vec3(yx0, 0, yz0), c + Vec3(yx0, 0, -1.6), 3.2)
  fence(root, c + Vec3(yx0, 0, 1.6), c + Vec3(yx0, 0, yz1), 3.2)
  local gate_closed = c + Vec3(yx0, 1.6, 0)
  -- Sliding gate: red frame with a cross brace, chain-link infill and a KEEP OUT plate.
  local gm = MeshData()
  local red = P.red
  for _, z in ipairs({ -1.5, 1.5 }) do gm:append(MeshData.box(0.16, 3.2, 0.16, red), Vec3(0, 0, z)) end
  for _, y in ipairs({ -1.5, 0, 1.5 }) do gm:append(MeshData.box(0.14, 0.14, 3.2, red), Vec3(0, y, 0)) end
  gm:append(MeshData.box(0.1, 0.12, 4.3, red), Vec3(0, 0, 0), Quat.euler(0.75, 0, 0))
  gm:append(MeshData.box(0.06, 0.6, 1.1, P.white), Vec3(-0.1, 0.6, 0))
  gm:append(MeshData.box(0.07, 0.2, 0.9, red), Vec3(-0.12, 0.6, 0))
  gm:append(MeshData.cylinder(0.2, 0.2, 0.12, 10, P.chrome), Vec3(0, -1.7, -1.2), Quat.euler(0, 0, math.pi / 2))
  gm:append(MeshData.cylinder(0.2, 0.2, 0.12, 10, P.chrome), Vec3(0, -1.7, 1.2), Quat.euler(0, 0, math.pi / 2))
  local gate = root:add_child(AnimatableBody3D { position = gate_closed, shape = Shape.box(0.35, 3.2, 3.2),
    MeshInstance3D { mesh = gm:flat():upload(), material = M.vertex } })
  local gq = MeshData()
  local g0 = gq:vertex(0, -1.5, -1.5, 1, 0, 0, 0, 4.8)
  local g1 = gq:vertex(0, -1.5, 1.5, 1, 0, 0, 4.8, 4.8)
  local g2 = gq:vertex(0, 1.5, 1.5, 1, 0, 0, 4.8, 0)
  local g3 = gq:vertex(0, 1.5, -1.5, 1, 0, 0, 0, 0)
  gq:quad(g0, g1, g2, g3)
  gate:add_child(MeshInstance3D { mesh = gq:upload(), material = chain_mat, cast_shadow = false })
  root:add_child(Label3D { text = "IMPOUND", position = c + Vec3(yx0 - 0.4, 3.6, 0), size = 20, color = Color.hex("#ffd6d0"), max_distance = 40 })
  local cell = Loot.power_cell(c + Vec3(11, 0, 0), 1, on_cell)
  root:add_child(cell)
  root:add_child(Loot.chest(c + Vec3(13.5, 0, 4.5), math.pi, 2, 2))
  -- Heavy stuff to weigh. The cow is up on the booth roof.
  root:add_child(Props.cow(c + Vec3(-6, 4.0, 4)))
  root:add_child(Props.engine(c + Vec3(-10, 0.4, -4)))
  wall(root, c + Vec3(-11, 0.6, -6), Vec3(2.4, 1.2, 4.5), P.metal_dark, nil, M.metal)    -- flatbed
  root:add_child(Props.engine(c + Vec3(-11, 1.6, -6)))
  for i = 0, 2 do root:add_child(Props.barrel(c + Vec3(-2 + i * 1.0, 0.6, 5))) end
  for i = 0, 3 do root:add_child(Props.crate(c + Vec3(4 + (i % 2) * 1.05, 0.5 + math.floor(i / 2) * 1.02, -9), 1)) end
  for i = 0, 3 do root:add_child(Props.cinder(c + Vec3(-3 + i * 0.9, 0.2, 8))) end
  for i = 0, 2 do root:add_child(Props.tire(c + Vec3(2, 0.3 + i * 0.32, 8), Quat.euler(math.pi / 2, 0, 0))) end
  Enemies.camp(root, c + Vec3(-2, 0, -14), { "suit", "suit", "cactus" }, 2, 6)
  Enemies.camp(root, c + Vec3(-14, 0, 10), { "suit", "cactus" }, 2, 5)

  local solved = false
  local ctl = root:add_child(Node {})
  local tick = 0
  ctl._process = function(self, dt)
    tick = tick - dt
    if tick > 0 then return end
    tick = 0.15
    local lb = math.floor(area_mass(area) * 2.2)
    readout.text = solved and "PASS" or string.format("%d / %d LB", lb, NEED)
    readout.color = lb >= NEED and Color.hex("#8dffa0") or Color.hex("#ffe28a")
    G.weigh_lb = lb
    if not solved and lb >= NEED then
      solved = true
      Audio.play_at(SFX.solve, c, { volume = 1 })
      Tween.to(gate, { position = gate_closed + Vec3(0, 3.4, 0) }, 2.2, { ease = "in_out_cubic" })
      G.say("OLD FACE", "Six hundred pounds. The gate thinks you're a truck. Go.", 3)
      G.objective_done("weigh_gate")
      -- Ambush from inside the yard.
      self:spawn(function()
        wait(1.6)
        for _, e in ipairs(Enemies.camp(root, c + Vec3(10, 0, 0), { "suit", "postal", "suit" }, 2, 3)) do e.aggro = true end
        G.say("WHITE SUIT", "He weighed in! Positions!", 2.2, true)
      end)
    end
  end
  Places.weigh_center = c
  return c + Vec3(11, 0, 0)
end

------------------------------------------------------------------ puzzle 2: the Rhyolite bank vault
function Places.bank(root, on_cell)
  local zt = World.zones.town
  local c = Vec3(zt.x, zt.h, zt.z + 27)
  local stone = Color.hex("#c7b394")
  local W, D, H = 10, 8, 5
  -- Side, back walls and roof; the front (facing the street, -Z) is the vault wall.
  solid(root, c + Vec3(-W / 2, H / 2, 0), Vec3(0.6, H, D))
  solid(root, c + Vec3(W / 2, H / 2, 0), Vec3(0.6, H, D))
  solid(root, c + Vec3(0, H / 2, D / 2), Vec3(W, H, 0.6))
  solid(root, c + Vec3(0, H + 0.3, 0), Vec3(W + 0.6, 0.6, D + 0.6))
  solid(root, c + Vec3(0, H + 1.6, -D / 2 + 0.1), Vec3(W + 0.8, 2.4, 0.45))
  for _, sx in ipairs({ -1, 1 }) do solid(root, c + Vec3(sx * (W / 2 + 0.05), H / 2, -D / 2 - 0.1), Vec3(1.1, H, 0.9)) end
  root:add_child(MeshInstance3D { mesh = Art.bank(W, D, H):upload(), material = M.vertex, position = c })
  root:add_child(Label3D { text = "BANK OF RHYOLITE", position = c + Vec3(0, H + 1.3, -D / 2 - 0.35), size = 26, color = Color.hex("#ffd27a"), outline = 2, max_distance = 60 })
  root:add_child(Label3D { text = "SEQUEL COMMITTEE VAULT  ·  ROCKET-RATED", position = c + Vec3(0, H - 0.4, -D / 2 - 0.6), size = 15, color = Color.hex("#ffe9c9"), max_distance = 22 })
  for _, sx in ipairs({ -1, 1 }) do
    root:add_child(OmniLight3D { color = Color.hex("#ffd27a"), energy = 1.5, range = 4, position = c + Vec3(sx * (W / 2 + 0.05), 3.0, -D / 2 - 1.1) })
  end
  local panel_mesh = Art.vault_panel():upload()
  local cols, rows = 4, 3
  local bw, bh = W / cols, H / rows
  local steel = Material { albedo = Color.hex("#8d939e"), roughness = 0.4, metallic = 0.5 }
  local opened = false
  local remaining = cols * rows
  for i = 0, cols - 1 do
    for j = 0, rows - 1 do
      local pos = c + Vec3(-W / 2 + bw * (i + 0.5), bh * (j + 0.5), -D / 2)
      root:add_child(Props.breakable(pos, Vec3(bw - 0.04, bh - 0.04, 0.6), nil, M.metal, panel_mesh, {
        name = "Vault Wall", hp = 1, need_power = 2, pieces = 2, piece_mass = 20, dust_color = Color(0.7, 0.7, 0.7),
        on_break = function()
          remaining = remaining - 1
          if not opened then
            opened = true
            Audio.play_at(SFX.solve, c, { volume = 1 })
            G.say("CARL", "I'm a normal human who has never done a crime. Nobody clip that.", 3.2)
            G.objective_done("vault")
          end
        end }))
    end
  end
  root:add_child(Loot.power_cell(c + Vec3(-1.5, 0, 1.5), 2, on_cell))
  root:add_child(Loot.chest(c + Vec3(2.8, 0, 2.2), math.pi, 3, 2))
  root:add_child(OmniLight3D { color = Color.hex("#ffd27a"), energy = 3, range = 9, position = c + Vec3(0, 3.5, 0) })
  -- Barrels to blow it open, out by the wagon and on the saloon porch.
  local spots = { Vec3(zt.x - 22, 0, zt.z + 18), Vec3(zt.x - 23.2, 0, zt.z + 19), Vec3(zt.x - 18.5, 0, zt.z - 18) }
  local wagon = spots[1] + Vec3(-1, 0, -2.5)
  wall(root, at(wagon.x, wagon.z, 0.8), Vec3(2.2, 0.3, 4), P.wood_dark)
  for _, s in ipairs({ -1, 1 }) do
    for _, w in ipairs({ -1.2, 1.2 }) do
      root:add_child(MeshInstance3D { mesh = MeshData.torus(0.55, 0.07, 16, 6, P.wood_dark):flat():upload(), material = M.vertex,
        position = at(wagon.x + s * 1.15, wagon.z + w, 0.55), rotation = Quat.euler(0, 0, math.pi / 2) })
    end
  end
  local barrels = {}
  local function stock()
    for i, s in ipairs(spots) do
      if not (barrels[i] and barrels[i]:is_valid()) then
        barrels[i] = Props.explosive(at(s.x, s.z, 0.6))
        root:add_child(barrels[i])
      end
    end
  end
  stock()
  -- Restock barrels while the vault is still shut, so it can't softlock.
  Game.every(15, function() if not opened then stock() end end, root)
  Enemies.camp(root, Vec3(zt.x, 0, zt.z), { "suit", "suit", "suit", "postal", "drone" }, 3, 12)
  Enemies.camp(root, Vec3(zt.x, 0, zt.z + 18), { "suit", "drone" }, 3, 5)
  Places.bank_center = c
  return c
end

------------------------------------------------------------------ puzzle 3: the mesa counterweight lift
function Places.mesa_lift(root, on_cell)
  local m = World.lift_mesa
  local z = World.zones.lift
  local base = ground(m.x, -75.6) + 0.2
  local top = ground(m.x, m.z) + 0.05
  local lift_xz = Vec3(m.x, 0, -75.6)
  local NEED = 300   -- kg
  -- Bridge from the lift to the mesa top.
  local mesa_edge = m.z + 16.8
  local bl = -77.4 - mesa_edge
  wall(root, Vec3(m.x, top - 0.2, (mesa_edge + -77.4) / 2), Vec3(3, 0.4, math.abs(bl)), P.wood)
  for _, s in ipairs({ -1, 1 }) do wall(root, Vec3(m.x + s * 1.45, top + 0.5, (mesa_edge + -77.4) / 2), Vec3(0.1, 1, math.abs(bl)), P.wood_dark) end
  -- Lift platform.
  local lift = root:add_child(AnimatableBody3D { position = Vec3(lift_xz.x, base, lift_xz.z), shape = Shape.box(3.4, 0.4, 3.4),
    MeshInstance3D { mesh = box_mesh(3.4, 0.4, 3.4, P.wood), material = M.vertex },
    MeshInstance3D { mesh = box_mesh(3.5, 0.1, 0.2, P.line_yellow), material = M.vertex, position = Vec3(0, 0.22, 1.6) },
  })
  -- Guide posts and the pulley beam.
  for _, sx in ipairs({ -1, 1 }) do
    for _, sz in ipairs({ -1, 1 }) do
      local px, pz = lift_xz.x + sx * 1.95, lift_xz.z + sz * 1.95
      local h = top + 4 - base
      wall(root, Vec3(px, base + h / 2, pz), Vec3(0.3, h, 0.3), P.wood_dark)
    end
  end
  local beam_y = top + 4
  local bin_xz = Vec3(m.x + 8, 0, -74)
  wall(root, Vec3((lift_xz.x + bin_xz.x) / 2, beam_y, lift_xz.z), Vec3(bin_xz.x - lift_xz.x + 4, 0.35, 0.35), P.wood_dark)
  root:add_child(MeshInstance3D { mesh = MeshData.cylinder(0.5, 0.5, 0.3, 14, P.metal):flat():upload(), material = M.metal,
    position = Vec3(lift_xz.x, beam_y + 0.4, lift_xz.z), rotation = Quat.euler(0, 0, math.pi / 2) })
  local rope_mesh = MeshData.cylinder(0.04, 0.04, 1, 6, Color.hex("#c9b38a")):transform(Vec3(0, -0.5, 0)):upload()
  local rope = root:add_child(MeshInstance3D { mesh = rope_mesh, material = M.vertex, position = Vec3(lift_xz.x, beam_y, lift_xz.z), cast_shadow = false })
  local rope2 = root:add_child(MeshInstance3D { mesh = rope_mesh, material = M.vertex, position = Vec3(bin_xz.x, beam_y, bin_xz.z), cast_shadow = false })
  -- Counterweight bin: open box. Fill it with rocks and the lift goes up.
  local by = ground(bin_xz.x, bin_xz.z)
  local bc = Vec3(bin_xz.x, by, bin_xz.z)
  wall(root, bc + Vec3(0, 0.1, 0), Vec3(3.2, 0.2, 3.2), P.wood_dark)
  wall(root, bc + Vec3(-1.55, 0.8, 0), Vec3(0.15, 1.4, 3.2), P.wood)
  wall(root, bc + Vec3(1.55, 0.8, 0), Vec3(0.15, 1.4, 3.2), P.wood)
  wall(root, bc + Vec3(0, 0.8, -1.55), Vec3(3.2, 1.4, 0.15), P.wood)
  wall(root, bc + Vec3(0, 0.8, 1.55), Vec3(3.2, 1.4, 0.15), P.wood)
  local area = root:add_child(Area3D { position = bc + Vec3(0, 1.4, 0), shape = Shape.box(2.9, 2.6, 2.9) })
  root:add_child(Label3D { text = "COUNTERWEIGHT", position = bc + Vec3(0, 2.6, -1.7), size = 18, color = Color.WHITE, max_distance = 40 })
  local readout = root:add_child(Label3D { text = "", position = bc + Vec3(0, 2.1, -1.7), size = 22, color = Color.hex("#ffe28a"), max_distance = 40 })
  -- Boulders scattered around the foot of the mesa.
  local r = Random(77)
  for i = 1, 8 do
    local a = i / 8 * math.pi * 1.4 - 0.2
    local d = r:float(10, 22)
    local x, zz = m.x + 6 + math.cos(a) * d, -66 + math.sin(a) * d * 0.7
    root:add_child(Props.boulder(at(x, zz, 1), r:float(0.62, 0.85)))
  end
  root:add_child(Props.boulder(at(m.x + 18, -62, 1.5), 1.15))   -- too heavy to lift: decoy
  -- Up top: the cell, a lockbox, and guards.
  local cell_pos = Vec3(m.x, top, m.z)
  root:add_child(Loot.power_cell(cell_pos, 3, on_cell))
  root:add_child(Loot.chest(cell_pos + Vec3(4, 0, -3), 0.5, 4, 2))
  Enemies.camp(root, Vec3(m.x, top, m.z), { "suit", "suit", "drone", "drone" }, 4, 9)
  Enemies.camp(root, Vec3(m.x + 10, 0, -60), { "cactus", "cactus", "postal" }, 4, 7)

  local h = base
  local ctl = root:add_child(Node {})
  local tick, mass = 0, 0
  ctl._physics_process = function(self, dt)
    tick = tick - dt
    if tick <= 0 then
      tick = 0.15
      mass = area_mass(area)
      readout.text = string.format("%d / %d LB", math.floor(mass * 2.2), NEED * 2.2)
      readout.color = mass >= NEED and Color.hex("#8dffa0") or Color.hex("#ffe28a")
      if mass >= NEED and not G.flags.lift_up then
        G.flags.lift_up = true
        Audio.play_at(SFX.solve, bc, { volume = 1 })
        G.say("OLD FACE", "Counterweight's full. Step on the lift. Don't look down; you'll learn something.", 3.4)
        G.objective_done("lift")
      end
    end
    local goal = base + (top - base) * math.clamp(mass / NEED, 0, 1)
    local nh = math.move_toward(h, goal, 3.2 * dt)
    if math.abs(nh - h) > 1e-4 and math.floor(Game.time * 4) ~= math.floor((Game.time - dt) * 4) then
      Audio.play_at(SFX.creak, lift.position, { volume = 0.35, pitch = rng:float(0.8, 1.1) })
    end
    h = nh
    lift.position = Vec3(lift_xz.x, h, lift_xz.z)
    rope.scale = Vec3(1, math.max(beam_y - h, 0.1), 1)
    rope2.scale = Vec3(1, math.max(beam_y - by - 1.5 - (h - base) * 0.05, 0.1), 1)
  end
  Places.lift_center = Vec3(lift_xz.x, base, lift_xz.z)
  return cell_pos
end

------------------------------------------------------------------ roadside camps and the Desert Bus
function Places.camps(root)
  local function van(pos, yaw)
    local m = MeshData.box(2.2, 2.2, 5, P.white)
    m:append(MeshData.box(2.0, 0.9, 1.2, Color.hex("#3b4048")), Vec3(0, 0.4, -2.0))
    for _, s in ipairs({ -1, 1 }) do for _, w in ipairs({ -1.6, 1.6 }) do m:append(MeshData.cylinder(0.45, 0.45, 0.3, 12, P.ink), Vec3(s * 1.1, -1.0, w), Quat.euler(0, 0, math.pi / 2)) end end
    m:append(MeshData.box(1.6, 0.4, 0.05, P.ink), Vec3(0, 0.3, 2.53))
    root:add_child(StaticBody3D { position = pos + Vec3(0, 1.4, 0), rotation = Quat.from_y(yaw), shape = Shape.box(2.2, 2.2, 5),
      MeshInstance3D { mesh = m:flat():upload(), material = M.vertex } })
    root:add_child(Label3D { text = "SEQUEL COMMITTEE", position = pos + Vec3(0, 3, 0), size = 14, color = Color.hex("#d8d8d8"), max_distance = 30 })
  end
  local rz = -35
  local rx = World.road_x(rz) + 9
  van(at(rx, rz), 0.1)
  Enemies.camp(root, at(rx, rz), { "suit", "suit", "drone" }, 2, 7)
  root:add_child(Loot.chest(at(rx + 3, rz + 4), 2.5, 2, 1))
  Enemies.camp(root, at(80, 60), { "cactus", "cactus", "cactus", "cactus" }, 2, 9)
  van(at(-60, 70), 1.2)
  Enemies.camp(root, at(-60, 70), { "suit", "postal", "drone" }, 3, 8)
  root:add_child(Loot.chest(at(-63, 74), 1.2, 3, 1))
  Enemies.camp(root, at(40, -60), { "drone", "drone", "cactus" }, 3, 10)
  root:add_child(Loot.chest(at(130, 20), -1, 3, 1))
  root:add_child(Loot.chest(at(-120, -90), 0.8, 4, 1))
  Enemies.camp(root, at(-120, -90), { "cactus", "suit", "suit" }, 4, 7)
  for i = 1, 10 do
    root:add_child(Props.tumbleweed(at(rng:float(-140, 140), rng:float(-140, 140), 1.5)))
  end
end

-- Route 45's Desert Bus. It never stops. You can ride on the roof.
function Places.desert_bus(root)
  local m = MeshData.box(2.6, 2.8, 10, Color.hex("#e8c547"))
  m:paint_fn(function(x, y, z, r, g, b)
    if y > 0.2 and y < 1.0 and math.abs(x) > 1.25 then return 0.2, 0.25, 0.3 end
    if y < -0.9 then return 0.25, 0.25, 0.28 end
    return r, g, b
  end)
  m:append(MeshData.box(2.4, 1.0, 0.05, Color.hex("#2b3540")), Vec3(0, 0.6, -5.02))
  for _, s in ipairs({ -1, 1 }) do for _, w in ipairs({ -3.4, 3.4 }) do m:append(MeshData.cylinder(0.55, 0.55, 0.35, 12, P.ink), Vec3(s * 1.25, -1.3, w), Quat.euler(0, 0, math.pi / 2)) end end
  local bus = root:add_child(AnimatableBody3D { name = "DesertBus", shape = Shape.box(2.6, 2.8, 10),
    MeshInstance3D { mesh = m:flat():upload(), material = M.vertex },
    Label3D { text = "DESERT BUS  ·  ROUTE 45", position = Vec3(0, 2, 0), size = 14, color = Color.hex("#3b2a1d"), outline = 0, max_distance = 25 },
  })
  local z = -190
  local hum = bus:add_child(AudioPlayer3D { sound = SFX.engine, loop = true, volume = 0.35, autoplay = true })
  bus._physics_process = function(self, dt)
    z = z + dt * 9
    if z > 190 then z = -190 end
    local x = World.road_x(z) - 2.2
    local x2 = World.road_x(z + 1) - 2.2
    self.position = Vec3(x, World.height(x, z) + 1.9, z)
    self.rotation = Quat.look_rotation(Vec3(x2 - x, 0, 1))
    -- Bump the player out of the way rather than squashing them.
    local p = G.player
    if p and not p.dead then
      local lp = self:to_local(p.position + Vec3(0, 0.6, 0))
      if math.abs(lp.x) < 1.7 and lp.z < -4.5 and lp.z > -6.5 and math.abs(lp.y) < 1.8 then
        p.velocity = self:forward() * 14 + Vec3(0, 8, 0) + self:right() * 6
        p:take_damage(12, { pos = self.position })
        Audio.play(SFX.honk, { volume = 0.8 })
      end
    end
  end
end

function Places.init(materials) M = materials end

return Places
