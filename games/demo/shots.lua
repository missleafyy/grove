-- Automated screenshot tour for verifying the showcase: run with
--   grove games/demo --shots <dir> --frames 2400 --hidden
return function(ctl)
  local dir = Game.arg_value("--shots")
  local function shot(name) Game.screenshot(dir .. "/" .. name .. ".png"); wait_frames(2) end
  local p, rig = ctl.player, ctl.rig
  wait(1.5)
  shot("01_title")
  ctl:start_play()
  wait(2.5)
  Input.simulate("move_forward", true)
  wait(1.0)
  Input.simulate("jump", true); wait(0.1); Input.simulate("jump", false)
  wait(0.25)
  shot("02_run_jump")
  Input.simulate("move_forward", nil)
  wait(1.2)
  -- Physics playground: throw orbs at the crate wall.
  local zp = require("world").zones.plaza
  p:teleport(Vec3(zp.x - 4, zp.h + 1, zp.z + 2))
  rig.yaw = math.atan2(-(zp.x + 6 - (zp.x - 4)), -(zp.z - 6 - (zp.z + 2))) + math.pi
  rig.yaw = math.atan2(-(10), (8))
  rig.pitch = -0.2
  wait(0.6)
  for i = 1, 6 do Input.simulate("fire", true); wait(0.25); Input.simulate("fire", false); wait(0.05) end
  wait(0.4)
  shot("03_playground")
  wait(1.5)
  shot("04_playground_after")
  -- Sky islands view.
  p:teleport(Vec3(zp.x + 8, zp.h + 1, zp.z + 8))
  rig.yaw = 0.6; rig.pitch = 0.35
  wait(1.5)
  shot("05_sky_islands")
  -- Ruins at golden hour.
  local zr = require("world").zones.ruins
  p:teleport(Vec3(zr.x + 6, zr.h + 1, zr.z + 12))
  rig.yaw = 0.3; rig.pitch = -0.25
  ctl.daynight.hour = 18.4
  wait(1.5)
  shot("06_ruins_sunset")
  -- Night at the campfire.
  local zc = require("world").zones.camp
  p:teleport(Vec3(zc.x + 4, zc.h + 1, zc.z - 5))
  rig.yaw = -2.4; rig.pitch = -0.2
  ctl.daynight.hour = 22.5
  wait(2)
  shot("07_campfire_night")
  p:teleport(Vec3(0, require("world").height(0, 30) + 1, 30))
  rig.yaw = 0; rig.pitch = -0.15
  wait(2)
  shot("08_meadow_night")
  ctl.daynight.hour = 9
  Debug.visible = true
  rig.pitch = -0.3
  wait(1.5)
  shot("09_morning_debug")
  Game.quit()
end
