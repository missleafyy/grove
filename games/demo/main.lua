-- Grove showcase: Skylight Isle.
-- A small third-person exploration game that exercises most of the engine:
-- procedural terrain + meshes, instancing, PBR lighting, cascaded shadows, day/night sky,
-- bloom, particles, Jolt physics (rigid bodies, character, areas, moving platforms),
-- positional audio with synthesized SFX and music, tweens, coroutines and UI.
local Art = require("art")
local Props = require("props")
local World = require("world")
local PlayerMod = require("player")
local DayNight = require("sky")
local Hud = require("hud")
local Music = require("music")

Game.set_title("Grove — Skylight Isle")

-- Sound bank, all synthesized at startup.
SFX = {
  jump = Sound.preset("jump"),
  double_jump = Sound.preset("whoosh"),
  land = Sound.preset("land"),
  step = Sound.preset("step"),
  thud = Sound.preset("thud"),
  bounce = Sound.preset("bounce"),
  bounce_pad = Sound.synth { wave = "sine", freq = 180, freq_end = 900, curve = 0.5, duration = 0.45, release = 0.3, volume = 0.5, vibrato = 0.04, vibrato_rate = 18 },
  shoot = Sound.synth { wave = "sine", freq = 900, freq_end = 300, duration = 0.16, release = 0.12, volume = 0.4, layers = { { wave = "noise", freq = 3000, duration = 0.05, lowpass = 0.4, volume = 0.15 } } },
  chime = Sound.preset("chime"),
  collect = Sound.preset("powerup"),
  splash = Sound.synth { wave = "noise", freq = 1200, freq_end = 200, duration = 0.7, lowpass = 0.5, lowpass_end = 0.05, release = 0.6, volume = 0.6 },
  fanfare = Sound.synth { wave = "square", duty = 0.3, freq = note_freq("C5"), duration = 1.4, arp = { 0, 4, 7, 12, 7, 12, 16, 19, 24 }, arp_speed = 0.11, arp_once = true, release = 0.6, volume = 0.25, echo = 0.3, echo_delay = 0.14 },
}
UI.hover_sound = Sound.preset("blip")
UI.click_sound = Sound.preset("select")

local M = Art.materials()
Props.init(M)

------------------------------------------------------------------ scene
local function build()
  local root = Node3D { name = "SkylightIsle" }
  local ctl = { collected = 0, total = 0, state = "title" }
  root.ctl = ctl

  local island = World.build(M)
  root:add_child(island)
  ctl.total = #island:find_all("Crystal")

  local daynight = root:add_child(DayNight {})
  daynight.fireflies = World.fireflies
  ctl.daynight = daynight

  local spawn = Vec3(0, World.height(0, 30) + 0.5, 30)
  local player = PlayerMod.Player { position = spawn, materials = M }
  local rig = PlayerMod.CameraRig { target = player }
  player.rig = rig
  root:add_child(player)
  root:add_child(rig)
  ctl.player, ctl.rig = player, rig

  local music = root:add_child(AudioPlayer3D { sound = Music.build(), loop = true, positional = false, volume = 0, autoplay = true })

  local hud = root:add_child(Hud.hud(ctl))
  local title = root:add_child(Hud.title(ctl))
  local pause = root:add_child(Hud.pause(ctl))
  local victory = root:add_child(Hud.victory(ctl))
  ctl.hud = hud
  Tween.to(music, { volume = 0.55 }, 4, { ease = "linear" })

  function ctl:start_play()
    if self.state ~= "title" then return end
    self.state = "play"
    self.started_at = Game.time
    self.hint_time = Game.real_time
    Tween.to(title, { opacity = 0 }, 0.4, { on_done = function() title:hide() end })
    -- Fly the camera from the orbit view down behind the player.
    local from_pos, from_rot = rig.position:copy(), rig.rotation:copy()
    rig.mode = "follow"
    rig.yaw = 0.0
    rig.focus = nil
    rig:_process(0.016)
    local to_pos, to_rot = rig.position:copy(), rig.rotation:copy()
    rig.mode = "fly"
    Tween.run(1.6, function(t)
      rig.position = from_pos:lerp(to_pos, t)
      rig.rotation = from_rot:slerp(to_rot, t)
      rig.camera.position = Vec3(0, 0, rig.distance * t)
    end, { ease = "in_out_cubic", on_done = function()
      rig.mode = "follow"
      player.locked = false
      Input.capture_mouse(true)
      Tween.to(hud, { opacity = 1 }, 0.5)
      hud:toast("Find all " .. ctl.total .. " crystals", "Glowing mint crystals are hidden around the island and up in the sky")
    end })
  end

  function ctl:pause()
    if self.state ~= "play" then return end
    self.state = "paused"
    Game.paused = true
    pause:show()
    Input.capture_mouse(false)
    music.volume = 0.25
  end

  function ctl:resume()
    if self.state ~= "paused" then return end
    self.state = "play"
    Game.paused = false
    pause:hide()
    Input.capture_mouse(true)
    music.volume = 0.55
  end

  function ctl:close_victory()
    Tween.to(victory, { opacity = 0 }, 0.3, { on_done = function() victory:hide() end })
    Input.capture_mouse(true)
    player.locked = false
  end

  root:connect("crystal_collected", function(crystal)
    ctl.collected = ctl.collected + 1
    hud:pop()
    rig.camera:shake(0.25)
    if ctl.collected >= ctl.total then
      Audio.play(SFX.fanfare, { volume = 0.6 })
      local secs = Game.time - (ctl.started_at or 0)
      victory:get("VBox/Time").text = string.format("Time: %d:%02d", math.floor(secs / 60), math.floor(secs % 60))
      victory:show()
      Tween.to(victory, { opacity = 1 }, 0.5)
      Input.capture_mouse(false)
      player.locked = true
      -- Fireworks over the island.
      root:spawn(function()
        for i = 1, 14 do
          local p = player.position + Vec3(rng:float(-18, 18), rng:float(12, 20), rng:float(-18, 18))
          root:add_child(Props.burst(p, Color.hsv(rng:float(), 0.6, 1), 90, 9))
          Audio.play_at(SFX.thud, p, { volume = 0.6, pitch = 0.6 })
          wait(0.35)
        end
      end)
    elseif crystal.big then
      hud:toast("Sky Crystal!", ctl.collected .. " of " .. ctl.total .. " found")
    else
      hud:toast("Crystal " .. ctl.collected .. " / " .. ctl.total)
    end
  end)

  -- Global keys that must work while paused.
  root:add_child(Node {
    name = "Keys", process_mode = "always",
    _process = function()
      if Input.pressed("pause") then
        if ctl.state == "play" then ctl:pause() elseif ctl.state == "paused" then ctl:resume() end
      end
      if ctl.state == "title" and Input.pressed("ui_accept") and not UI.focus then ctl:start_play() end
      -- Clicking back into the window recaptures the mouse.
      if ctl.state == "play" and not Input.is_mouse_captured() and Input.mouse_pressed(1) and not UI.mouse_over and not victory.visible then
        Input.capture_mouse(true)
      end
    end,
  })

  if Game.has_arg("--shots") then root:spawn(require("shots"), ctl) end
  return root
end

Game.start(build)
