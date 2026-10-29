-- Skills: three trees with one point per level, plus Carl's action skill ABDUCT (the A.S.S. beams down,
-- lifts everything in a circle, holds it helpless, then drops it from a great height).
local Props = require("props")
local Combat = Props.Combat
local Skills = {}

Skills.TREES = {
  { name = "ABDUCTOR", color = Color.hex("#4dffa6"), skills = {
    { id = "cooldown", name = "Tractor Science", desc = "ABDUCT cooldown -8% per rank" },
    { id = "probe", name = "Probe Everything", desc = "Abducted enemies take +12% damage per rank" },
    { id = "slam", name = "Crash Landing", desc = "Slam damage +25% and lift radius +5% per rank" },
  } },
  { name = "GUNSLINGER", color = Color.hex("#ff9a3c"), skills = {
    { id = "damage", name = "Nobody Clip That", desc = "Gun damage +5% per rank" },
    { id = "hands", name = "Fast Hands", desc = "Reload speed +8% and fire rate +3% per rank" },
    { id = "crit", name = "Spoilers", desc = "Critical hit damage +12% per rank" },
  } },
  { name = "SURVIVOR", color = Color.hex("#5fd6ff"), skills = {
    { id = "wrap", name = "Bubble Wrap", desc = "Shield capacity +8% per rank" },
    { id = "human", name = "Normal Human", desc = "Max health +8% and +1s Fight For Your Life per rank" },
    { id = "pills", name = "Prop Pills Habit", desc = "Kills heal 2% of max health per rank" },
  } },
}
Skills.MAX_RANK = 5

function Skills.reset()
  G.skills = {}
  G.skill_points = 0
end

function Skills.rank(id) return (G.skills and G.skills[id]) or 0 end

function Skills.can_buy(id) return G.skill_points > 0 and Skills.rank(id) < Skills.MAX_RANK end
function Skills.buy(id)
  if not Skills.can_buy(id) then return false end
  G.skills[id] = Skills.rank(id) + 1
  G.skill_points = G.skill_points - 1
  if G.player then G.player:recalc_stats(false) end
  return true
end

-- Multipliers the rest of the game asks for.
function Skills.gun_damage() return 1 + Skills.rank("damage") * 0.05 end
function Skills.reload_speed() return 1 + Skills.rank("hands") * 0.08 end
function Skills.fire_rate() return 1 + Skills.rank("hands") * 0.03 end
function Skills.crit() return 1 + Skills.rank("crit") * 0.12 end
function Skills.shield() return 1 + Skills.rank("wrap") * 0.08 end
function Skills.health() return 1 + Skills.rank("human") * 0.08 end
function Skills.ffyl_time() return 8 + Skills.rank("human") end
function Skills.kill_heal() return Skills.rank("pills") * 0.02 end
function Skills.probe() return 1 + Skills.rank("probe") * 0.12 end
function Skills.abduct_cooldown() return 22 * (1 - Skills.rank("cooldown") * 0.08) end

------------------------------------------------------------------ ABDUCT
local HOLD = 2.8

function Skills.abduct_ready() return (G.abduct_cd or 0) <= 0 and not G.abduct_active end

function Skills.cast_abduct(player)
  if not Skills.abduct_ready() then return false end
  local hit, far, fwd = player:aim_ray(0)
  local p = hit and hit.position or far
  local flat = (p - player.position):flat()
  if flat:length() > 32 then p = player.position + flat:normalized() * 32 end
  -- Snap to the enemy closest to the crosshair line, so the beam lands where the fight is.
  local cam = G.rig.camera:global_position()
  local best, best_d = nil, 7
  for _, e in ipairs(Game.group("enemies")) do
    local ep = e:global_position() + Vec3(0, 1, 0)
    local to = ep - cam
    local along = to:dot(fwd)
    if not e.dead and along > 2 and along < 45 then
      local perp = (to - fwd * along):length()
      if perp < best_d then best, best_d = e, perp end
    end
  end
  if best then p = best:global_position() end
  p = Vec3(p.x, World.height(p.x, p.z), p.z)
  local radius = 7 * (1 + Skills.rank("slam") * 0.05)
  G.abduct_active = true
  G.abduct_cd = Skills.abduct_cooldown()
  G.abduct_max = G.abduct_cd
  Audio.play(SFX.tractor_on, { volume = 0.8, pitch = 0.45 })
  Audio.play(SFX.cell, { volume = 0.35, pitch = 0.6 })

  local fx = G.root:add_child(Node3D { name = "Abduct", position = p })
  local beam = fx:add_child(MeshInstance3D { mesh = require("loot").meshes.beam, material = G.M.beam, tint = Color(0.35, 1, 0.65, 0.0),
    scale = Vec3(radius * 8, 40, radius * 8), cast_shadow = false })
  G.root:add_child(Props.shockwave(p + Vec3(0, 0.15, 0), radius, Color(0.4, 1, 0.7), 0.5))
  local motes = fx:add_child(Particles3D { rate = 140, lifetime = 1.6, speed = 4, spread = 10, direction = Vec3(0, 1, 0), size = 0.16, size_end = 0,
    color = Color(0.6, 1, 0.8, 1), color_end = Color(0.4, 1, 0.7, 0), emit_radius = radius, additive = true, position = Vec3(0, 0.2, 0) })
  local light = fx:add_child(OmniLight3D { color = Color.hex("#4dffa6"), energy = 0, range = radius * 3, position = Vec3(0, 4, 0) })

  -- Who gets lifted.
  local victims, props = {}, {}
  for _, e in ipairs(Game.group("enemies")) do
    if not e.dead and (e:global_position() - p):flat():length() < radius then
      victims[#victims + 1] = e
      if not e.boss then
        e.float_t = HOLD
        e.abducted = true
      end
    end
  end
  for _, n in ipairs(Physics.overlap_sphere(p + Vec3(0, 1, 0), radius)) do
    if n:is(RigidBody3D) and n._body and not n.gravity_held and (n.mass or 0) < 400 then
      props[#props + 1] = n
      n:wake()
    end
  end
  G.hud:toast("ABDUCT", #victims > 0 and (#victims .. " abducted") or "Nobody home", Color.hex("#4dffa6"))

  fx:spawn(function()
    local t = 0
    while t < HOLD do
      local dt = Game.delta
      t = t + dt
      local k = math.min(1, t / 0.25)
      beam.tint = Color(0.35, 1, 0.65, 0.22 * k + math.sin(t * 25) * 0.03)
      light.energy = 6 * k
      for _, b in ipairs(props) do
        if b:is_valid() and b._body then
          local want = p + Vec3(0, 4.5, 0) + (b.position - p):flat() * 0.6
          b:set_velocity((want - b.position) * 3, b:get_angular_velocity() * 0.9 + Vec3(0, 2, 0))
        end
      end
      wait(0)
    end
    -- Drop everything.
    Audio.play(SFX.thump_launcher, { volume = 0.9, pitch = 0.6 })
    local L = G.level
    local slam = 45 * 1.13 ^ (L - 1) * (1 + Skills.rank("slam") * 0.25)
    for _, e in ipairs(victims) do
      if e:is_valid() and not e.dead then
        e.float_t = 0
        e.abducted = nil
        if e.velocity then e.velocity = Vec3(0, -26, 0) end
        Combat.damage(e, slam * (e.boss and 0.6 or 1), { pos = e:global_position() + Vec3(0, 1, 0), kind = "slam", dir = Vec3(0, -1, 0) })
      end
    end
    for _, b in ipairs(props) do
      if b:is_valid() and b._body then b:set_velocity(Vec3(0, -30, 0)); b.thrown = Game.time end
    end
    G.rig:shake(0.5)
    G.root:add_child(Props.shockwave(p + Vec3(0, 0.2, 0), radius * 1.2, Color(0.5, 1, 0.75), 0.35))
    G.root:add_child(Props.dust(p + Vec3(0, 0.2, 0), 40))
    motes.rate = 0
    Tween.to(light, { energy = 0 }, 0.4)
    Tween.run(0.4, function(k) beam.tint = Color(0.35, 1, 0.65, 0.22 * (1 - k)) end)
    G.abduct_active = false
    wait(1.8)
    fx:queue_free()
  end)
  return true
end

function Skills.update(dt)
  if G.abduct_cd and G.abduct_cd > 0 then
    G.abduct_cd = G.abduct_cd - dt
    if G.abduct_cd <= 0 then Audio.play(SFX.reload_done, { volume = 0.5, pitch = 0.7 }) end
  end
end

return Skills
