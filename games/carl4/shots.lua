-- Automated tour for verification: bin/grove games/carl4 --shots <dir> --frames 9000 --hidden
local Loot = require("loot")
local Places = require("places")
local Props = require("props")

return function(start)
  local dir = Game.arg_value("--shots")
  local function shot(name) Game.screenshot(dir .. "/" .. name .. ".png"); wait_frames(2) end
  local p, rig = G.player, G.rig
  G.god = true
  wait(1.2)
  shot("01_title")
  start()
  wait(1.5)
  local function face(target)
    local d = target - p.position
    rig.yaw = math.atan2(-d.x, -d.z)
  end
  local function tap(a, t) Input.simulate(a, true); wait(t or 0.1); Input.simulate(a, nil) end

  if Game.has_arg("--closeup") then
    -- Model viewer: fixed camera orbiting Carl in several poses, plus each gun kind.
    G.ui_open = true
    wait(0.5)
    if G.hud then G.hud.visible = false end
    for _, n in ipairs(Game.group("enemies")) do n:queue_free() end
    local cam = rig.camera
    local function view(name, off, look_h, fov)
      rig.mode = "fixed"
      local base = p.position + Vec3(0, look_h or 1.0, 0)
      local yawq = Quat.from_y(p._yaw)
      rig.position = base + yawq * off
      rig.rotation = Quat.look_rotation(base - rig.position)
      cam.position = Vec3(); cam.rotation = Quat(); cam.fov = fov or 40
      wait(0.3)
      shot(name)
    end
    rig.yaw = p._yaw
    view("c01_front", Vec3(0, 0.1, -2.6))
    view("c02_face", Vec3(0.15, 0.05, -1.0), 1.15, 35)
    view("c03_side", Vec3(-2.4, 0.2, 0))
    view("c04_back", Vec3(1.2, 0.4, 2.2))
    view("c05_three_q", Vec3(-1.4, 0.0, -1.0), 1.1, 38)
    -- Combat pose and firing.
    p._last_fire = Game.time
    for _, kind in ipairs({ "pistol", "smg", "shotgun", "rifle", "launcher" }) do
      p.guns[1] = Loot.roll_gun(3, { kind = kind, rarity = 4 })
      p:equip(1)
      wait(0.3)
      p.guns[1].ammo = 99
      p:fire()
      wait(0.02)
      view("c1_" .. kind, Vec3(1.3, 0.1, -0.9), 1.0, 38)
      p._last_fire = Game.time
      wait(0.4)
      view("c2_" .. kind .. "_side", Vec3(-1.6, 0.1, -0.2), 1.0, 38)
    end
    p:start_reload()
    wait(0.5)
    view("c3_reload", Vec3(1.2, 0.2, -1.2), 1.0, 40)
    -- Walk cycle.
    Input.simulate("move_forward", true)
    for i = 1, 4 do wait(0.11); view("c4_walk" .. i, Vec3(-2.6, 0.1, 0), 0.9, 40) end
    Input.simulate("move_forward", nil)
    Game.quit()
    return
  end

  if Game.has_arg("--props") then
    -- Fixed views of the detailed set pieces.
    G.ui_open = true
    if G.hud then G.hud.visible = false end
    for _, n in ipairs(Game.group("enemies")) do n:queue_free() end
    local function look(name, from, to, fov)
      rig.mode = "fixed"
      rig.position = from
      rig.rotation = Quat.look_rotation(to - from)
      rig.camera.position = Vec3(); rig.camera.rotation = Quat(); rig.camera.fov = fov or 50
      wait(0.4)
      shot(name)
    end
    local function gy(v, dy) return Vec3(v.x, World.height(v.x, v.z) + (dy or 0), v.z) end
    local c = Places.ship_pos
    p:teleport(c + Vec3(0, 0.5, -30))
    look("p01_ship", gy(c + Vec3(-12, 0, -14), 4), c + Vec3(0, 1, 0), 55)
    for _, n in ipairs(Game.group("interactables")) do
      if n.name == "Vending" then
        local f = n:global_rotation() * Vec3(0, 0, -1)
        look("p02_vending", n.position + f * 3.2 + n:global_rotation() * Vec3(1.2, 0, 0) + Vec3(0, 1.4, 0), n.position + Vec3(0, 1.0, 0), 45)
      elseif n.name == "Chest" and n.position:distance(c) < 15 then
        local f = n:global_rotation() * Vec3(0, 0, -1)
        look("p03_chest", n.position + f * 2.2 + n:global_rotation() * Vec3(0.8, 0, 0) + Vec3(0, 1.2, 0), n.position + Vec3(0, 0.2, 0), 45)
      end
    end
    look("p03_crates_chest", gy(c + Vec3(5, 0, -1), 2.2), gy(c + Vec3(8.5, 0, 1), 0.6), 50)
    local w = Places.weigh_center
    p:teleport(w + Vec3(0, 0.5, -20))
    look("p04_weigh", gy(w + Vec3(-2, 0, -14), 3.5), w + Vec3(-3, 1.5, 2), 55)
    look("p05_impound", gy(w + Vec3(-1, 0, -3), 2.5), w + Vec3(10, 1.5, 0), 55)
    local b = Places.bank_center
    p:teleport(b + Vec3(0, 0.5, -30))
    look("p06_bank", gy(b + Vec3(-6, 0, -16), 3), b + Vec3(0, 3.5, 0), 50)
    look("p07_street", gy(b + Vec3(0, 0, -30), 3), gy(b + Vec3(-12, 0, -50), 2.5), 55)
    Game.quit()
    return
  end

  if Game.has_arg("--bl") then
    -- Borderlands systems: layered + badass enemies, ABDUCT, grenades, melee, FFYL, cards and menus.
    local Enemies = require("enemies")
    local Gear = require("gear")
    local Combat = Props.Combat
    G.say = function() end
    G.lines = {}; G.line = nil
    G.hint_time = -100
    local base = p.position + Vec3(0, 0, -6)
    local function ground(v) return Vec3(v.x, World.height(v.x, v.z) + 0.3, v.z) end
    local foes = {}
    for i, kind in ipairs({ "suit", "postal", "drone", "suit" }) do
      local pos = ground(base + Vec3(-4.5 + i * 2.2, 0, -8))
      if kind == "drone" then pos = pos + Vec3(0, 3, 0) end
      local e = Enemies.spawn(kind, pos, 2, i == 1)
      G.root:add_child(e)
      foes[#foes + 1] = e
    end
    p.guns[2] = Loot.roll_gun(2, { kind = "smg", rarity = 3, element = "static" })
    p:equip(2)
    face(base + Vec3(0, 0, -8))
    rig.pitch = -0.08
    wait(0.6)
    for _, e in ipairs(foes) do e.aggro = false; e.last_hit = Game.time end
    Input.simulate("fire", true); wait(0.5); Input.simulate("fire", nil)
    wait(0.15)
    shot("b01_enemies")
    tap("action_skill")
    wait(1.3)
    shot("b02_abduct")
    wait(1.8)
    shot("b03_slam")
    p.grenade_item = Gear.roll_grenade(2, 4)
    p.grenade_item.kind = "mirv"
    G.grenades = 3
    rig.pitch = 0.1
    tap("grenade")
    wait(1.45)
    shot("b04_grenade")
    wait(1)
    -- Melee whatever's closest.
    local near
    for _, e in ipairs(Game.group("enemies")) do if not e.dead and (not near or e.position:distance(p.position) < near.position:distance(p.position)) then near = e end end
    if near then
      p:teleport(near.position + Vec3(0, 0.3, 1.6))
      face(near.position)
      wait(0.2)
      tap("melee")
      wait(0.12)
      shot("b05_melee")
    end
    -- Fight For Your Life, then a kill for the second wind.
    G.god = false
    p.locked = false
    p._dash_t = 0
    p:take_damage(99999, { pos = p.position + Vec3(3, 0, -3) })
    wait(1)
    shot("b06_ffyl")
    for _, e in ipairs(Game.group("enemies")) do if not e.dead then Combat.damage(e, 1e6, { pos = e:global_position() }) break end end
    wait(0.35)
    shot("b07_second_wind")
    G.god = true
    -- A shield on the ground.
    local it = Gear.item_pickup(p.position + Vec3(0, 1, -1.6), Gear.roll_shield(2, 5), Vec3(0, 1, 0))
    G.root:add_child(it)
    face(p.position + Vec3(0, 0, -2))
    rig.pitch = -0.3
    wait(1.2)
    shot("b08_shield_card")
    -- Menus.
    G.skill_points = 3
    G.skills.damage = 2
    G.skills.cooldown = 1
    G.open_skills()
    Game.paused = false
    wait(0.4)
    shot("b09_skills")
    local vend
    for _, n in ipairs(Game.group("interactables")) do if n.name == "Vending" then vend = n end end
    Input.simulate("pause", true); wait_frames(2); Input.simulate("pause", nil)
    wait(0.1)
    if vend then G.open_shop(vend); Game.paused = false; wait(0.4); shot("b10_shop") end
    Game.quit()
    return
  end

  if not Game.has_arg("--mesa") then
  -- Walk and shoot at the warm-up cacti.
  Input.simulate("move_forward", true)
  wait(1.2)
  Input.simulate("move_forward", nil)
  shot("02_start")
  local cactus
  for _, e in ipairs(Game.group("enemies")) do
    if not cactus or e.position:distance(p.position) < cactus.position:distance(p.position) then cactus = e end
  end
  p:teleport(cactus.position + Vec3(0, 0.5, 9))
  wait(0.3)
  for _ = 1, 30 do
    if cactus.dead then break end
    face(cactus.position)
    rig.pitch = -0.1
    Input.simulate("fire", true)
    Input.simulate("aim", true)
    wait(0.1)
  end
  shot("03_combat")
  Input.simulate("fire", nil); Input.simulate("aim", nil)
  wait(1.5)

  -- Loot: open the tutorial chest and look at a gun.
  local c = Places.ship_pos
  local chest
  for _, n in ipairs(Game.group("interactables")) do if n.name == "Chest" and n.position:distance(c) < 15 then chest = n end end
  p:teleport(chest.position + chest:global_rotation() * Vec3(0, 0.2, -2.2))
  face(chest.position)
  rig.pitch = -0.35
  wait(0.3)
  tap("interact")
  wait(2.5)
  local g = Game.group("gun_pickups")[1]
  if g then
    p:teleport(g.position + Vec3(0, 0.3, 1.5))
    face(g.position)
    wait(0.4)
    shot("04_loot_card")
    tap("interact")
  end
  wait(0.4)
  -- Spawn a few guns of each rarity for a loot shot.
  for i = 1, 5 do
    G.root:add_child(Loot.gun_pickup(p.position + Vec3(-4 + i * 1.6, 1, -5), Loot.roll_gun(3, { rarity = i }), Vec3(0, 2, 0)))
  end
  rig.pitch = -0.25
  face(p.position + Vec3(0, 0, -5))
  wait(1.5)
  shot("05_rarities")

  -- Ship and the crash site.
  p:teleport(c + Vec3(-10, 0.5, -12))
  face(c)
  rig.pitch = -0.1
  wait(1)
  shot("06_crash_site")

  -- Weigh Station: tractor the cow onto the scale.
  local w = Places.weigh_center
  p:teleport(w + Vec3(-4, 0.5, -8))
  wait(0.5)
  local cow
  for _, n in ipairs(Game.group("props")) do if n.name == "Cow" then cow = n end end
  face(cow.position)
  local d = cow.position - (p.position + Vec3(0, 1.4, 0))
  rig.pitch = math.atan2(d.y, d:flat():length())
  wait(0.2)
  Input.simulate("tractor", true)
  wait(0.6)
  Game.log("held: " .. tostring(p.held and p.held.name))
  shot("07_tractor_cow")
  face(w + Vec3(0, 0, -2))
  rig.pitch = -0.3
  wait(1.2)
  Input.simulate("tractor", nil)
  wait(1)
  -- Help it along: drop the engine blocks on too.
  for _, n in ipairs(Game.group("props")) do
    Game.log("cow at " .. tostring(cow.position))
    if n.name == "Engine Block" then n:teleport(w + Vec3(rng:float(-2, 2), 2, -2)) end
  end
  wait(2.5)
  face(w + Vec3(0, 0, -2))
  shot("08_weigh_station")
  wait(3)
  p:teleport(w + Vec3(8, 0.5, 0))
  wait(2)
  shot("09_impound")

  -- Bank vault: throw a barrel at it.
  local b = Places.bank_center
  p:teleport(b + Vec3(0, 0.5, -14))
  face(b)
  rig.pitch = -0.05
  wait(0.6)
  shot("10_bank")
  local barrel = Props.explosive(b + Vec3(0, 1.5, -8))
  G.root:add_child(barrel)
  wait(0.3)
  barrel:set_velocity(Vec3(0, 0, 14))
  barrel.thrown = Game.time
  wait(0.12)
  shot("11_explosion")
  wait(1.5)
  shot("12_vault_open")

  end
  -- Mesa lift: fill the bin with boulders.
  local L = Places.lift_center
  p:teleport(L + Vec3(-6, 0.6, 10))
  face(L + Vec3(4, 3, 0))
  rig.pitch = 0.1
  wait(0.5)
  shot("13_mesa")
  p:teleport(L + Vec3(0, 0.8, 0))
  wait(0.5)
  for _, n in ipairs(Game.group("props")) do
    if n.name == "Boulder" and (n.mass or 0) < 170 then n:teleport(L + Vec3(8 + rng:float(-0.5, 0.5), 2 + rng:float(0, 3), 1.6 + rng:float(-0.5, 0.5))) end
  end
  wait(3)
  for _ = 1, 8 do wait(1); Game.log(string.format("lift ride p=%.1f %.1f %.1f floor=%s", p.position.x, p.position.y, p.position.z, tostring(p:is_on_floor()))) end
  shot("14_lift_up")
  wait(1)
  face(World.lift_mesa and Vec3(World.lift_mesa.x, 0, World.lift_mesa.z) or L)
  Input.simulate("move_forward", true)
  wait(2.5)
  Input.simulate("move_forward", nil)
  Game.log(string.format("mesa top p=%.1f %.1f %.1f ground=%.1f cam=%s", p.position.x, p.position.y, p.position.z, World.height(p.position.x, p.position.z), tostring(rig.camera:global_position())))
  shot("15_mesa_top")
  if Game.has_arg("--mesa") then Game.quit() end

  -- Boss.
  G.cells = 3
  p:teleport(Places.ship_pos + Vec3(0, 0.5, -9))
  wait(9)
  shot("16_boss_intro")
  wait(10)
  local boss = G.boss
  face(boss.position)
  for _ = 1, 40 do
    if boss.dead then break end
    face(boss.position)
    rig.pitch = 0.05
    Input.simulate("fire", true)
    boss.hp = boss.hp - 60
    wait(0.1)
  end
  shot("17_boss_fight")
  Input.simulate("fire", nil)
  wait(1)
  Game.quit()
end
