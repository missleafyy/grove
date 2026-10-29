-- Game: the scene tree runner (like Godot's SceneTree) plus coroutines and timers.
local ffi = require("ffi")

Game = {
  time = 0,            -- scaled game time (stops while paused)
  real_time = 0,
  delta = 0,
  physics_dt = 1 / 60,
  physics_rate = 60,   -- minimum physics steps per second
  frame = 0,
  paused = false,
  time_scale = 1,
  width = 1280, height = 720,
  ui_scale = 1,
  ui_reference_height = 720,
  camera = nil,
  node_count = 0,
  _free_queue = {},
  _groups = {},
  _tasks = {},
}

Game.root = Node { name = "root" }
Game.root.inside_tree = true
Game.root._is_ready = true

------------------------------------------------------------------ registry
function Game._node_entered(n)
  Game.node_count = Game.node_count + 1
  if n.groups then for g in pairs(n.groups) do Game._group_add(g, n) end end
end
function Game._node_exited(n)
  Game.node_count = Game.node_count - 1
  if n.groups then for g in pairs(n.groups) do Game._group_remove(g, n) end end
end
function Game._group_add(g, n)
  local set = Game._groups[g]
  if not set then set = {}; Game._groups[g] = set end
  set[n] = true
end
function Game._group_remove(g, n)
  local set = Game._groups[g]
  if set then set[n] = nil end
end

-- All live nodes in a group (as an array).
function Game.group(g)
  local out = {}
  local set = Game._groups[g]
  if set then for n in pairs(set) do if not n._queued then out[#out + 1] = n end end end
  return out
end
function Game.first_in_group(g)
  local set = Game._groups[g]
  if set then for n in pairs(set) do if not n._queued then return n end end end
end
function Game.find(name) return Game.root:find(name) end

------------------------------------------------------------------ scenes
-- scene: a Node, or a function returning one.
function Game.change_scene(scene)
  if Game.scene then
    local old = Game.scene
    Game.scene = nil
    old:free()
  end
  Tween._clear()
  -- Coroutines owned by nodes of the old scene stop on their own; unowned ones keep running.
  Game.paused = false
  Game.time_scale = 1
  if type(scene) == "function" then scene = scene() end
  Game.scene = scene
  Game.root:add_child(scene)
  return scene
end
Game.start = Game.change_scene

------------------------------------------------------------------ coroutines & timers
-- Game.spawn(function() wait(1); print("one second later") end)
function Game.spawn(fn, owner, ...)
  local co = coroutine.create(fn)
  local task = { co = co, owner = owner, args = { ... }, started = false }
  Game._tasks[#Game._tasks + 1] = task
  return task
end

function wait(seconds) coroutine.yield("time", seconds or 0) end
function wait_real(seconds) coroutine.yield("real", seconds or 0) end
function wait_frames(n) coroutine.yield("frames", n or 1) end
function wait_until(cond) coroutine.yield("until", cond) end
function wait_signal(node, sig)
  local fired, result = false, nil
  node:connect_once(sig, function(...) fired = true; result = { ... } end)
  coroutine.yield("until", function() return fired end)
  return unpack(result)
end

function Game.after(seconds, fn, owner)
  return Game.spawn(function() wait(seconds); fn() end, owner)
end
function Game.every(seconds, fn, owner)
  return Game.spawn(function() while true do wait(seconds); if fn() == false then return end end end, owner)
end
function Game.cancel(task) if task then task.dead = true end end

local function resume_task(t)
  local ok, kind, arg = coroutine.resume(t.co, unpack(t.args))
  t.args = {}
  if not ok then error(debug.traceback(t.co, kind), 0) end
  if coroutine.status(t.co) == "dead" then t.dead = true return end
  t.kind = kind
  if kind == "time" then t.wake = Game.time + arg
  elseif kind == "real" then t.wake = Game.real_time + arg
  elseif kind == "frames" then t.wake = Game.frame + arg
  elseif kind == "until" then t.cond = arg
  else t.kind = "frames"; t.wake = Game.frame + 1 end
end

local function run_tasks()
  local tasks = Game._tasks
  local i = 1
  while i <= #tasks do
    local t = tasks[i]
    if t.owner and (t.owner._queued or t.owner.freed) then t.dead = true end
    if not t.dead then
      local ready
      if not t.started then ready = true; t.started = true
      elseif t.kind == "time" then ready = Game.time >= t.wake
      elseif t.kind == "real" then ready = Game.real_time >= t.wake
      elseif t.kind == "frames" then ready = Game.frame >= t.wake
      elseif t.kind == "until" then ready = t.cond() end
      if ready then resume_task(t) end
    end
    if t.dead then table.remove(tasks, i) else i = i + 1 end
  end
end

------------------------------------------------------------------ misc API
function Game.quit() C.gr_quit() end
function Game.restart() C.gr_restart() end
function Game.set_title(t) C.gr_set_title(t) end
function Game.set_fullscreen(on) C.gr_set_fullscreen(on and 1 or 0) end
function Game.is_fullscreen() return C.gr_get_fullscreen() == 1 end
function Game.set_vsync(on) C.gr_set_vsync(on and 1 or 0) end
function Game.screenshot(path) C.gr_screenshot(res_path(path)) end
function Game.log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  C.gr_log(table.concat(parts, " "))
end
print = Game.log

Game.args = {}
for i = 0, C.gr_argc() - 1 do Game.args[#Game.args + 1] = ffi.string(C.gr_argv(i)) end
function Game.has_arg(a)
  for _, v in ipairs(Game.args) do if v == a then return true end end
  return false
end
function Game.arg_value(a)
  for i, v in ipairs(Game.args) do if v == a then return Game.args[i + 1] end end
end

function Game.ui_mouse()
  local x, y = Input.mouse_position()
  return x / Game.ui_scale, y / Game.ui_scale
end

------------------------------------------------------------------ frame
local function processing(node, paused, parent_mode)
  local mode = node.process_mode
  if mode == "inherit" then mode = parent_mode end
  if mode == "disabled" then return false, mode end
  if paused and mode ~= "always" then return false, mode end
  return true, mode
end

local function walk_process(node, method, dt, paused, parent_mode)
  local run, mode = processing(node, paused, parent_mode)
  local fn = node[method]
  if run and fn and not node._queued then fn(node, dt) end
  local ch = node.children
  local i = 1
  while i <= #ch do
    local c = ch[i]
    walk_process(c, method, dt, paused, mode)
    if ch[i] == c then i = i + 1 end   -- tolerate removals during iteration
  end
end

local function walk_sync(node, pp, pr, ps, vis)
  local gp, gr, gs
  if node._is3d then
    if node.top_level or not pp then gp, gr, gs = node.position, node.rotation, node.scale
    else
      gp = pp + pr * (ps * node.position)
      gr = pr * node.rotation
      gs = ps * node.scale
    end
    vis = vis and node.visible
    if node.__sync then node:__sync(vis, gp, gr, gs) end
  end
  local ch = node.children
  for i = 1, #ch do walk_sync(ch[i], gp, gr, gs, vis) end
end

local wbuf, hbuf = ffi.new("int[1]"), ffi.new("int[1]")

function grove_frame(real_dt)
  Game.frame = Game.frame + 1
  Game.real_time = Game.real_time + real_dt
  C.gr_window_size(wbuf, hbuf)
  Game.width, Game.height = wbuf[0], hbuf[0]
  Game.ui_scale = math.max(0.5, Game.height / Game.ui_reference_height)

  Input._update()
  if Input.pressed("debug") then Debug.visible = not Debug.visible end

  local paused = Game.paused
  local dt = paused and 0 or real_dt * Game.time_scale
  Game.delta = dt
  Game.real_delta = real_dt

  if not paused and dt > 0 then
    Game.time = Game.time + dt
    local steps = math.max(1, math.ceil(dt * Game.physics_rate - 1e-6))
    local sdt = dt / steps
    Game.physics_dt = sdt
    for _ = 1, steps do
      walk_process(Game.root, "_physics_process", sdt, false, "pausable")
      Physics._step(sdt)
    end
  end

  -- Nodes marked process_mode = "always" keep running (with real time) while paused.
  walk_process(Game.root, "_process", paused and real_dt or dt, paused, "pausable")
  Tween._update(dt, real_dt)
  run_tasks()

  local q = Game._free_queue
  if #q > 0 then
    Game._free_queue = {}
    for _, n in ipairs(q) do
      if not n.freed then
        n.freed = true
        if n.parent then n.parent:remove_child(n) end
      end
    end
  end

  walk_sync(Game.root, nil, nil, nil, true)
  if Game.camera and Game.camera.inside_tree then Game.camera:_push(real_dt) end
end

function grove_draw_ui()
  UI._draw(Game.root)
  Debug._draw()
end

-- Engine self-test: repeatedly hot-restart (exercises full teardown/rebuild).
if Game.has_arg("--restart-loop") then
  Game.spawn(function() wait_real(1.0); print("[grove] self-test restart"); Game.restart() end)
end
