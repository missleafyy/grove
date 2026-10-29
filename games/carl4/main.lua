-- CARL 4: BY THE POWER OF NEVADA
-- A cel-shaded looter-shooter action RPG starring Carl (Cracky / Pretend Co.), stranded in the Nevada desert.
-- Shoot White Suits, loot procedural guns, and solve three physics puzzles with the A.S.S. tractor beam
-- to win back the ship's power cells. Then HU-MAN shows up.
World = require("world")
local Art = require("art")
require("art_detail")
local Props = require("props")
local Loot = require("loot")
local Enemies = require("enemies")
local Places = require("places")
local PlayerMod = require("player")
local Hud = require("hud")
local Music = require("music")
local Gear = require("gear")
local Skills = require("skills")
local Combat = Props.Combat

Game.set_title("CARL 4 — By the Power of Nevada")

local function gun_sfx(freq, noise, dur, vol)
  return Sound.synth { wave = "square", freq = freq, freq_end = freq * 0.3, duration = dur, release = dur * 0.8, volume = vol, noise = noise, duty = 0.4,
    layers = { { wave = "noise", freq = 2400, freq_end = 400, duration = dur * 0.7, lowpass = 0.5, lowpass_end = 0.05, volume = vol * 0.8 } } }
end
SFX = {
  jump = Sound.preset("jump"), double_jump = Sound.preset("whoosh"), land = Sound.preset("land"), step = Sound.preset("step"),
  thud = Sound.preset("thud"), coin = Sound.preset("coin"), explosion = Sound.preset("explosion"), hit = Sound.preset("hit"),
  laser = Sound.preset("laser"), chest = Sound.preset("powerup"), pop = Sound.preset("bounce"),
  dash = Sound.synth { wave = "noise", freq = 300, freq_end = 1400, duration = 0.22, lowpass = 0.1, lowpass_end = 0.5, release = 0.15, volume = 0.5 },
  thump_pistol = Sound.synth { wave = "sine", freq = 140, freq_end = 45, duration = 0.12, release = 0.1, volume = 0.7 },
  thump_smg = Sound.synth { wave = "sine", freq = 160, freq_end = 60, duration = 0.07, release = 0.05, volume = 0.5 },
  thump_shotgun = Sound.synth { wave = "sine", freq = 110, freq_end = 30, duration = 0.3, release = 0.25, volume = 0.9, layers = { { wave = "square", freq = 1400, duration = 0.04, delay = 0.32, volume = 0.18 }, { wave = "noise", freq = 600, duration = 0.08, delay = 0.36, lowpass = 0.3, volume = 0.25 } } },
  thump_rifle = Sound.synth { wave = "sine", freq = 120, freq_end = 35, duration = 0.28, release = 0.25, volume = 0.85, echo = 0.35, layers = { { wave = "square", freq = 900, duration = 0.03, delay = 0.42, volume = 0.16 } } },
  thump_launcher = Sound.synth { wave = "sine", freq = 90, freq_end = 30, duration = 0.35, release = 0.3, volume = 0.8 },
  hit_tick = Sound.synth { wave = "square", freq = 1800, freq_end = 1300, duration = 0.03, release = 0.03, volume = 0.3 },
  crit_ding = Sound.synth { wave = "sine", freq = 2200, duration = 0.16, release = 0.14, volume = 0.35, layers = { { wave = "sine", freq = 3300, duration = 0.12, release = 0.1, volume = 0.18 } } },
  kill_crunch = Sound.synth { wave = "noise", freq = 900, freq_end = 120, duration = 0.22, lowpass = 0.5, lowpass_end = 0.05, release = 0.18, volume = 0.6, layers = { { wave = "square", freq = 220, freq_end = 55, duration = 0.18, release = 0.15, volume = 0.35 }, { wave = "sine", freq = 1400, freq_end = 2100, duration = 0.1, delay = 0.03, volume = 0.2 } } },
  tink = Sound.synth { wave = "sine", freq = 3400, freq_end = 3000, duration = 0.05, release = 0.08, volume = 0.25, layers = { { wave = "sine", freq = 4700, duration = 0.04, release = 0.05, volume = 0.12 } } },
  mag_in = Sound.synth { wave = "noise", freq = 1200, duration = 0.05, lowpass = 0.5, release = 0.04, volume = 0.35, layers = { { wave = "square", freq = 380, duration = 0.04, delay = 0.03, volume = 0.25 } } },
  gun_pistol = gun_sfx(700, 0.5, 0.14, 0.45), gun_smg = gun_sfx(900, 0.6, 0.09, 0.35), gun_shotgun = gun_sfx(260, 0.8, 0.35, 0.6),
  gun_rifle = gun_sfx(420, 0.6, 0.4, 0.6), gun_launcher = Sound.synth { wave = "noise", freq = 200, freq_end = 900, duration = 0.4, lowpass = 0.2, release = 0.3, volume = 0.6 },
  enemy_shot = gun_sfx(1100, 0.3, 0.1, 0.25), enemy_shotgun = gun_sfx(330, 0.7, 0.25, 0.4), boss_shot = gun_sfx(180, 0.6, 0.4, 0.6),
  empty = Sound.synth { wave = "square", freq = 1200, duration = 0.04, release = 0.03, volume = 0.3 },
  reload = Sound.synth { wave = "noise", freq = 900, duration = 0.12, lowpass = 0.4, release = 0.08, volume = 0.35, layers = { { wave = "square", freq = 500, duration = 0.05, delay = 0.12, volume = 0.2 } } },
  reload_done = Sound.synth { wave = "square", freq = 700, freq_end = 1000, duration = 0.06, release = 0.04, volume = 0.3 },
  equip = Sound.synth { wave = "triangle", freq = 400, freq_end = 800, duration = 0.08, release = 0.05, volume = 0.35 },
  pickup = Sound.synth { wave = "square", freq = 520, duration = 0.25, arp = { 0, 7, 12 }, arp_speed = 0.06, arp_once = true, release = 0.15, volume = 0.3 },
  pill = Sound.synth { wave = "sine", freq = 600, freq_end = 1200, duration = 0.25, release = 0.2, volume = 0.4 },
  hurt = Sound.synth { wave = "square", freq = 220, freq_end = 110, duration = 0.12, noise = 0.4, release = 0.1, volume = 0.4 },
  shield_break = Sound.synth { wave = "saw", freq = 900, freq_end = 120, duration = 0.35, release = 0.3, volume = 0.4 },
  shield_up = Sound.synth { wave = "sine", freq = 300, freq_end = 900, duration = 0.4, release = 0.3, volume = 0.3 },
  tractor_on = Sound.synth { wave = "sine", freq = 200, freq_end = 600, duration = 0.3, vibrato = 0.06, vibrato_rate = 30, release = 0.2, volume = 0.4 },
  throw = Sound.preset("whoosh"),
  crack = Sound.synth { wave = "noise", freq = 1500, freq_end = 200, duration = 0.3, lowpass = 0.6, release = 0.25, volume = 0.6 },
  zap = Sound.synth { wave = "saw", freq = 1800, freq_end = 600, duration = 0.18, noise = 0.5, release = 0.12, volume = 0.35 },
  curse = Sound.synth { wave = "sine", freq = 500, freq_end = 250, duration = 0.5, vibrato = 0.08, vibrato_rate = 9, release = 0.4, volume = 0.35 },
  alert = Sound.synth { wave = "square", freq = 880, duration = 0.2, arp = { 0, 5 }, arp_speed = 0.1, release = 0.1, volume = 0.25 },
  enemy_die = Sound.synth { wave = "square", freq = 500, freq_end = 80, duration = 0.35, noise = 0.3, release = 0.3, volume = 0.4 },
  boss_die = Sound.synth { wave = "saw", freq = 300, freq_end = 30, duration = 2.0, noise = 0.3, release = 1.5, volume = 0.6, echo = 0.4 },
  boing = Sound.synth { wave = "sine", freq = 200, freq_end = 500, duration = 0.18, vibrato = 0.1, vibrato_rate = 20, release = 0.1, volume = 0.35 },
  creak = Sound.synth { wave = "saw", freq = 140, freq_end = 120, duration = 0.2, lowpass = 0.1, vibrato = 0.05, vibrato_rate = 30, release = 0.1, volume = 0.3 },
  solve = Sound.synth { wave = "square", duty = 0.3, freq = note_freq("C5"), duration = 1.2, arp = { 0, 4, 7, 12, 16, 19, 24 }, arp_speed = 0.09, arp_once = true, release = 0.5, volume = 0.25, echo = 0.3 },
  levelup = Sound.synth { wave = "square", duty = 0.3, freq = note_freq("G4"), duration = 1.4, arp = { 0, 4, 7, 12, 7, 12, 16, 19, 24 }, arp_speed = 0.1, arp_once = true, release = 0.6, volume = 0.3, echo = 0.3 },
  cell = Sound.synth { wave = "sine", freq = note_freq("E5"), duration = 1.4, arp = { 0, 7, 12, 19, 24 }, arp_speed = 0.12, arp_once = true, release = 0.8, volume = 0.35, echo = 0.4 },
  honk = Sound.synth { wave = "square", freq = 330, duration = 0.5, release = 0.1, volume = 0.4, layers = { { wave = "square", freq = 415, duration = 0.5, release = 0.1, volume = 0.3 } } },
  drone_hum = Sound.synth { wave = "saw", freq = 140, duration = 1.0, lowpass = 0.06, volume = 0.3, attack = 0.001, release = 0.001, vibrato = 0.02, vibrato_rate = 40 },
  engine = Sound.synth { wave = "saw", freq = 60, duration = 1.0, lowpass = 0.05, volume = 0.5, attack = 0.001, release = 0.001, vibrato = 0.05, vibrato_rate = 12 },
}
UI.hover_sound = Sound.preset("blip")
UI.click_sound = Sound.preset("select")

local M = Art.materials()
Props.init(M)
Loot.init(M)
Enemies.init(M)
Places.init(M)
Gear.init(M)

------------------------------------------------------------------ global game state
local function xp_for(level) return math.floor(90 * level ^ 1.6) end

G = {
  M = M, level = 1, xp = 0, xp_next = xp_for(1), cash = 40, cells = 0, numbers = {}, objectives = {}, lines = {}, flags = {},
  stats = { kills = 0, guns = 0, legendaries = 0, chests = 0, cash = 0 },
  grenades = 3, skills = {}, skill_points = 0,
  state = "title",
}

function G.add_number(pos, amount, crit, element, eff)
  local col = crit and Color.hex("#ffcf4a") or Color.WHITE
  if element then col = Loot.ELEMENTS[element].color end
  G.numbers[#G.numbers + 1] = { pos = pos:copy(), text = tostring(amount), crit = crit, col = col, t = 0, dx = rng:float(-14, 14), eff = eff }
  if #G.numbers > 40 then table.remove(G.numbers, 1) end
end

function G.add_xp(amount, pos)
  G.xp = G.xp + amount
  if pos then G.numbers[#G.numbers + 1] = { pos = pos, text = "+" .. amount .. " XP", col = Color.hex("#ffcf4a"), t = 0, dx = 0 } end
  while G.xp >= G.xp_next do
    G.xp = G.xp - G.xp_next
    G.level = G.level + 1
    G.xp_next = xp_for(G.level)
    G.levelup_t = Game.real_time
    G.skill_points = G.skill_points + 1
    Audio.play(SFX.levelup, { volume = 0.6 })
    if G.player then
      G.player:recalc_stats(true)
      G.root:add_child(Props.burst(G.player.position + Vec3(0, 1, 0), Color.hex("#ffcf4a"), 60, 7))
    end
  end
end

-- Queue a dialogue line. quick = drop it if something is already being said.
function G.say(who, text, dur, quick)
  -- Reading time: at least ~15 characters a second plus a beat, so long lines stay up long enough.
  local l = { who = who, text = text, dur = math.max((dur or 3) + 0.8, #text / 15 + 1.2), t = 0 }
  if not G.line then G.line = l
  elseif not quick then G.lines[#G.lines + 1] = l end
end

function G.objective(id, text, target, color)
  local o = { id = id, text = text, target = target, color = color }
  G.objectives[#G.objectives + 1] = o
  return o
end
function G.find_objective(id) for _, o in ipairs(G.objectives) do if o.id == id then return o end end end

function G.objective_done(id)
  local o = G.find_objective(id)
  if o then o.done = true end
  local names = { weigh_gate = "Gate open!", vault = "Vault cracked!", lift = "Lift working!" }
  if names[id] then G.hud:toast(names[id], "Puzzle solved", Color.hex("#8dffa0")) end
end

------------------------------------------------------------------ scene
local function build()
  local root = Node3D { name = "Nevada" }
  G.root = root
  World.environment()
  root:add_child(DirectionalLight3D { rotation = Quat.euler_deg(-42, 150, 0), energy = 3.3, color = Color.hex("#fff0d8") })
  root:add_child(World.build(M))
  Places.crash_site(root)

  local cell_targets = {}
  local function on_cell(cell)
    G.cells = G.cells + 1
    Audio.play(SFX.cell, { volume = 0.8 })
    G.add_xp(120 * G.level)
    local ids = { "weigh", "vault", "lift" }
    local o = G.find_objective(ids[cell.cell_id])
    if o then o.done = true end
    G.root:add_child(Props.burst(cell.position + Vec3(0, 1, 0), Color.hex("#4dffa6"), 80, 8))
    if G.cells < 3 then
      G.hud:toast("Power cell " .. G.cells .. " / 3", "The A.S.S. wants all three", Color.hex("#4dffa6"))
      local lines = {
        "One cell. The ship can now power a nightlight.",
        "Two. Somewhere a Sequel Committee intern is filing a form about you.",
      }
      G.say("OLD FACE", lines[G.cells], 3)
    else
      G.hud:toast("All power cells!", "Bring them home to the A.S.S.", Color.hex("#4dffa6"))
      G.say("OLD FACE", "That's all three. Bring them to the ship. Quickly. I'm detecting a lot of focus testing.", 3.6)
      G.objective("ship", "Return the cells to the A.S.S.", Places.ship_pos, Color.hex("#4dffa6"))
    end
    G.player.checkpoint = G.player.position + Vec3(0, 0.5, 0)
  end
  cell_targets.weigh = Places.weigh_station(root, on_cell)
  cell_targets.vault = Places.bank(root, on_cell)
  cell_targets.lift = Places.mesa_lift(root, on_cell)
  Places.camps(root)
  Places.desert_bus(root)

  local player = PlayerMod.Player { position = Places.spawn, materials = M }
  local rig = PlayerMod.CameraRig { target = player }
  rig.orbit_center = Places.ship_pos
  player.rig = rig
  G.player, G.rig = player, rig
  player.guns[1] = Loot.roll_gun(1, { kind = "pistol", rarity = 1, element = false })
  player.guns[1].name = "Courier Special"
  player.shield_item = Gear.default_shield()
  player.grenade_item = Gear.default_grenade()
  root:add_child(player)
  root:add_child(rig)
  rig.yaw = 0

  -- Projectile stepping.
  root:add_child(Node { name = "Projectiles", _physics_process = function(_, dt) Combat.update_projectiles(dt) end })

  local music = root:add_child(AudioPlayer3D { sound = Music.desert(), loop = true, positional = false, volume = 0, autoplay = true })
  Tween.to(music, { volume = 0.4 }, 3, { ease = "linear" })
  G.music = music

  local hud = root:add_child(Hud.hud())
  G.hud = hud
  local title, pause, shop, death, victory
  local function start()
    if G.state ~= "title" then return end
    G.state = "play"
    G.started = Game.time
    G.hint_time = Game.real_time
    G.chapter = "CHAPTER 1  ·  STRANDED"
    Tween.to(title, { opacity = 0 }, 0.4, { on_done = function() title:hide() end })
    rig.mode = "follow"
    player.locked = false
    Input.capture_mouse(true)
    Tween.to(hud, { opacity = 1 }, 0.6)
    G.objective("weigh", "Weigh Station: open the impound gate", cell_targets.weigh, Color.hex("#ffcf4a"))
    G.objective("vault", "Rhyolite Springs: crack the bank vault", cell_targets.vault, Color.hex("#ff8a5a"))
    G.objective("lift", "The Mesa: get the old mine lift working", cell_targets.lift, Color.hex("#7fd0ff"))
    G.say("OLD FACE", "Carl. You're alive. The A.S.S. is not.", 3)
    G.say("CARL", "I'm a normal human. I was just parking.", 2.6)
    G.say("OLD FACE", "The White Suits shot you down and took three power cells. The Sequel Committee is filming out here.", 4.2)
    G.say("CARL", "Filming what?", 1.8)
    G.say("OLD FACE", "CARL 4.", 1.8)
    G.say("CARL", "There's no Carl 3.", 2)
    G.say("OLD FACE", "They skipped ahead. The cells are at the Weigh Station, Rhyolite Springs and the mesa. Hold F for the tractor beam.", 4.6)
  end
  title = root:add_child(Hud.title(start))
  local function resume()
    G.state = "play"
    Game.paused = false
    pause:hide()
    Input.capture_mouse(true)
    music.volume = 0.4
  end
  local skills_menu
  local function open_skills()
    G.ui_open = true
    if G.state == "play" then G.state = "skills"; Game.paused = true end
    pause:hide()
    skills_menu:show()
    Input.capture_mouse(false)
  end
  local function close_skills()
    skills_menu:hide()
    if G.state == "paused" then pause:show() return end
    G.state = "play"
    Game.paused = false
    G.ui_open = false
    Input.capture_mouse(true)
  end
  pause = root:add_child(Hud.pause(resume, open_skills))
  skills_menu = root:add_child(Hud.skills(close_skills))
  G.open_skills = open_skills
  local function close_shop()
    G.ui_open = false
    shop:hide()
    Input.capture_mouse(true)
  end
  shop = root:add_child(Hud.shop(close_shop))
  function G.open_shop(v)
    G.ui_open = true
    G.shop_dir = v:global_rotation() * Vec3(0, 0, -1)
    G.shop_pos = v:global_position() + G.shop_dir * 1.2 + Vec3(0, 1.2, 0)
    shop.refresh()
    shop:show()
    Input.capture_mouse(false)
  end
  death = root:add_child(Hud.death())
  victory = root:add_child(Hud.victory(function()
    Tween.to(victory, { opacity = 0 }, 0.3, { on_done = function() victory:hide() end })
    G.state = "play"
    player.locked = false
    Input.capture_mouse(true)
    G.chapter = "POST-CREDITS  ·  KEEP LOOTING"
  end))

  -- Death: the Prop Pills Re-Delivery service puts you back at the last checkpoint.
  function G.on_player_death()
    G.death_fee = math.floor(G.cash * 0.07)
    G.cash = G.cash - G.death_fee
    death:show()
    Tween.to(death, { opacity = 1 }, 0.4)
    Audio.play(SFX.boss_die, { volume = 0.4, pitch = 1.6 })
    player.visual.visible = false
    root:add_child(Props.burst(player.position + Vec3(0, 0.8, 0), Art.pal.carl_skin, 50, 6))
    Game.after(2.8, function()
      Tween.to(death, { opacity = 0 }, 0.4, { on_done = function() death:hide() end })
      player:teleport(player.checkpoint)
      player.dead = false
      player.hp, player.shield = player.max_hp, player.max_shield
      player.visual.visible = true
      root:add_child(Props.burst(player.position + Vec3(0, 1, 0), Color.hex("#ff5d8a"), 40, 4))
    end)
  end

  -- Checkpoints when you reach each place.
  local checkpoints = {
    { pos = Places.spawn },
    { pos = Places.weigh_center + Vec3(-8, 0.5, -10) },
    { pos = Places.bank_center + Vec3(0, 0.5, -20) },
    { pos = Places.lift_center + Vec3(4, 0.6, 6) },
  }

  -- The finale: cells go in, HU-MAN drops in.
  local function finale()
    G.state = "cutscene"
    G.chapter = "CHAPTER 2  ·  FOCUS-TESTED"
    local o = G.find_objective("ship")
    if o then o.done = true end
    root:spawn(function()
      for i = 1, 3 do
        local s = Places.sockets[i]
        s.cell.visible = true
        s.light.energy = 5
        Audio.play(SFX.cell, { volume = 0.5, pitch = 0.8 + i * 0.15 })
        root:add_child(Props.burst(s.position + Vec3(0, 1, 0), Color.hex("#4dffa6"), 40, 5))
        wait(0.6)
      end
      G.say("OLD FACE", "Cells are in. The A.S.S. is warming up. Ninety seconds.", 3)
      wait(1.5)
      Tween.to(music, { volume = 0 }, 1)
      G.say("HU-MAN", "BY THE POWER OF NEVADA!", 2.4)
      wait(0.6)
      local sp = Places.ship_pos + Vec3(0, 0, -22)
      sp = Vec3(sp.x, World.height(sp.x, sp.z), sp.z)
      local boss = Enemies.spawn("human", sp + Vec3(0, 40, 0), math.max(G.level, 6))
      root:add_child(boss)
      G.boss = boss
      wait_until(function() return boss:is_on_floor() or boss.dead end)
      rig:shake(1)
      Audio.play(SFX.explosion, { volume = 1, pitch = 0.5 })
      root:add_child(Props.dust(boss.position + Vec3(0, 0.5, 0), 60))
      root:add_child(Props.shockwave(boss.position + Vec3(0, 0.3, 0), 14, Color(1, 0.7, 0.4), 0.6))
      G.say("HU-MAN", "I'm the focus-tested Carl. Square jaw. Sunglasses. Ninety-four percent of audiences said: that's a human.", 4.4)
      G.say("CARL", "That's my hoodie.", 2)
      G.say("HU-MAN", "It's OUR hoodie. Test audiences hated your eyes.", 3)
      wait(6)
      music.sound = Music.boss()
      music:play()
      Tween.to(music, { volume = 0.45 }, 1)
      boss.state = "walk"
      G.state = "play"
      G.objective("boss", "Defeat HU-MAN", nil)
      wait_until(function() return boss.dead end)
      G.find_objective("boss").done = true
      Tween.to(music, { volume = 0 }, 2)
      wait(1.5)
      G.say("HU-MAN", "Audiences... loved me...", 2.6)
      G.say("OLD FACE", "The A.S.S. is ready. Get in before the Committee orders a reboot.", 3.4)
      G.say("CARL", "Nobody clip that.", 2.2)
      wait(6)
      player.locked = true
      Input.capture_mouse(false)
      -- Lift-off.
      local ship = Places.ship
      local from = ship.position:copy()
      player.visual.visible = false
      rig.mode = "fixed"
      rig.position = from + Vec3(18, 6, 18)
      rig.camera.position = Vec3()
      Tween.run(5, function(t)
        ship.position = from + Vec3(0, t * t * 60, 0)
        ship.rotation = Quat.euler(0.22 * (1 - t), 0.6 + t * 8, 0.12 * (1 - t))
        rig.rotation = Quat.look_rotation(ship.position - rig.position)
      end, { ease = "in_quad" })
      Audio.play(SFX.shield_up, { volume = 0.8, pitch = 0.4 })
      wait(4)
      G.state = "victory"
      victory:show()
      Tween.to(victory, { opacity = 1 }, 0.6)
      wait(1)
      ship.position = from
      ship.rotation = Quat.euler(0.22, 0.6, 0.12)
      player.visual.visible = true
      rig.mode = "follow"
    end)
  end

  -- Global keys and checks.
  root:add_child(Node {
    name = "Keys", process_mode = "always",
    _process = function()
      if Input.key_pressed("K") or Input.key_pressed("TAB") then
        if skills_menu.visible then close_skills()
        elseif G.state == "play" and not G.ui_open then open_skills() end
      end
      if Input.pressed("pause") then
        if skills_menu.visible then close_skills()
        elseif G.ui_open then close_shop()
        elseif G.state == "play" then
          G.state = "paused"; Game.paused = true; pause:show(); Input.capture_mouse(false); music.volume = 0.15
        elseif G.state == "paused" then resume() end
      end
      if G.state == "title" and Input.pressed("ui_accept") and not UI.focus then start() end
      if G.state == "play" and not G.ui_open and not Input.is_mouse_captured() and Input.mouse_pressed(1) and not UI.mouse_over then
        Input.capture_mouse(true)
      end
      if G.state ~= "play" or player.dead then return end
      for _, cp in ipairs(checkpoints) do
        if not cp.reached and player.position:distance(cp.pos) < 14 then
          cp.reached = true
          player.checkpoint = cp.pos
        end
      end
      if G.cells >= 3 and not G.flags.finale and player.position:distance(Places.ship_pos) < 11 then
        G.flags.finale = true
        finale()
      end
    end,
  })

  if Game.has_arg("--shots") then root:spawn(require("shots"), start) end
  return root
end

Game.start(build)
