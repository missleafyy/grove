-- Tweens and easing.
--   Tween.to(node, { position = Vec3(0, 3, 0), scale = Vec3(2) }, 0.5, { ease = "out_back" })
--   Tween.to(mat, { emission_energy = 4 }, 1, { loop = true, yoyo = true })
-- Works with numbers, Vec3, Quat (slerp) and Color fields on any table or node.

local pow, sin, cos, pi, sqrt = math.pow or function(a, b) return a ^ b end, math.sin, math.cos, math.pi, math.sqrt

Ease = {
  linear = function(t) return t end,
  in_quad = function(t) return t * t end,
  out_quad = function(t) return 1 - (1 - t) * (1 - t) end,
  in_out_quad = function(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end,
  in_cubic = function(t) return t * t * t end,
  out_cubic = function(t) return 1 - (1 - t) ^ 3 end,
  in_out_cubic = function(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end,
  out_quart = function(t) return 1 - (1 - t) ^ 4 end,
  in_out_sine = function(t) return -(cos(pi * t) - 1) / 2 end,
  out_sine = function(t) return sin(t * pi / 2) end,
  in_back = function(t) local c = 1.70158; return (c + 1) * t * t * t - c * t * t end,
  out_back = function(t) local c = 1.70158; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end,
  out_elastic = function(t)
    if t == 0 or t == 1 then return t end
    return 2 ^ (-10 * t) * sin((t * 10 - 0.75) * (2 * pi) / 3) + 1
  end,
  out_bounce = function(t)
    local n, d = 7.5625, 2.75
    if t < 1 / d then return n * t * t
    elseif t < 2 / d then t = t - 1.5 / d; return n * t * t + 0.75
    elseif t < 2.5 / d then t = t - 2.25 / d; return n * t * t + 0.9375
    else t = t - 2.625 / d; return n * t * t + 0.984375 end
  end,
}

local function interp(a, b, t)
  if type(a) == "number" then return a + (b - a) * t end
  if Quat.is(a) then return a:slerp(b, t) end
  return a:lerp(b, t)
end

Tween = {}
local active = {}

-- opts: ease, delay, loop, yoyo, on_done, on_update(t), always (keeps running while paused)
function Tween.to(target, props, duration, opts)
  opts = opts or {}
  local tw = {
    target = target, props = props, duration = math.max(duration, 1e-4), elapsed = -(opts.delay or 0),
    ease = type(opts.ease) == "function" and opts.ease or Ease[opts.ease or "out_cubic"],
    loop = opts.loop, yoyo = opts.yoyo, always = opts.always, on_done = opts.on_done, on_update = opts.on_update,
    from = nil, alive = true, owner = (type(target) == "table" and target.children) and target or opts.owner,
  }
  assert(tw.ease, "unknown ease " .. tostring(opts.ease))
  function tw:cancel() self.alive = false end
  active[#active + 1] = tw
  return tw
end

-- Calls fn(t) with t going 0..1 over duration.
function Tween.run(duration, fn, opts)
  local holder = {}
  opts = opts or {}
  local user = opts.on_update
  opts.on_update = function(t) fn(t); if user then user(t) end end
  return Tween.to(holder, {}, duration, opts)
end

function Tween.cancel_all(target)
  for _, tw in ipairs(active) do if tw.target == target then tw.alive = false end end
end

function Tween._update(dt, real_dt)
  local i = 1
  while i <= #active do
    local tw = active[i]
    if tw.owner and (tw.owner._queued or tw.owner.freed) then tw.alive = false end
    if tw.alive then
      tw.elapsed = tw.elapsed + (tw.always and (real_dt or dt) or dt)
      if tw.elapsed >= 0 then
        if not tw.from then
          tw.from = {}
          for k, _ in pairs(tw.props) do
            local v = tw.target[k]
            tw.from[k] = type(v) == "cdata" and v:copy() or v
          end
        end
        local raw = math.min(tw.elapsed / tw.duration, 1)
        local t = tw.ease(raw)
        for k, to in pairs(tw.props) do tw.target[k] = interp(tw.from[k], to, t) end
        if tw.on_update then tw.on_update(t) end
        if raw >= 1 then
          if tw.loop then
            tw.elapsed = tw.elapsed - tw.duration
            if tw.yoyo then
              local f = tw.from
              tw.from = tw.props
              tw.props = f
            end
          else
            tw.alive = false
            if tw.on_done then tw.on_done() end
          end
        end
      end
    end
    if tw.alive then i = i + 1 else table.remove(active, i) end
  end
end

function Tween._clear() active = {} end
