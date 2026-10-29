-- Day/night cycle: moves the sun and moon, blends sky/fog/light colours, drives lamps and fireflies.
local DayNight = Node:extend("DayNight")

-- Keyframes by sun elevation (-1 night .. 1 noon).
local keys = {
  { e = -0.35, top = Color.hex("#0b1230"), hor = Color.hex("#1c2a4f"), fog = Color.hex("#1a2646"), sun = Color.hex("#9fb4ff"), amb = 0.55, stars = 1 },
  { e = -0.05, top = Color.hex("#2a3570"), hor = Color.hex("#d98a6c"), fog = Color.hex("#7a6a8a"), sun = Color.hex("#ff9c5a"), amb = 0.6, stars = 0.35 },
  { e = 0.08, top = Color.hex("#4a74b8"), hor = Color.hex("#ffb27a"), fog = Color.hex("#e3b08f"), sun = Color.hex("#ffb066"), amb = 0.75, stars = 0 },
  { e = 0.3, top = Color.hex("#3f7fd0"), hor = Color.hex("#bcd8ee"), fog = Color.hex("#c3dbea"), sun = Color.hex("#fff1d8"), amb = 0.9, stars = 0 },
  { e = 1.0, top = Color.hex("#2f6fd0"), hor = Color.hex("#a9d0f0"), fog = Color.hex("#b4d4ec"), sun = Color.hex("#fffaf0"), amb = 0.95, stars = 0 },
}

local function sample(e)
  if e <= keys[1].e then return keys[1], keys[1], 0 end
  for i = 1, #keys - 1 do
    local a, b = keys[i], keys[i + 1]
    if e <= b.e then return a, b, (e - a.e) / (b.e - a.e) end
  end
  return keys[#keys], keys[#keys], 0
end

function DayNight:_setup()
  Node._setup(self)
  self.hour = 16.2        -- start in warm late afternoon
  self.day_length = 480   -- real seconds per full day
  self.fast = false
end

function DayNight:_ready()
  self.light = self:add_child(DirectionalLight3D { name = "SunMoon" })
end

function DayNight:night_amount() return self._night or 0 end

function DayNight:clock_text()
  local h = math.floor(self.hour)
  local m = math.floor((self.hour - h) * 60)
  return string.format("%02d:%02d", h, m)
end

function DayNight:_process(dt)
  local speed = 24 / self.day_length
  if self.fast or Input.key_down("T") then speed = speed * 30 end
  self.hour = (self.hour + dt * speed) % 24

  -- Sun travels east to west, tilted so shadows stay interesting at noon.
  local ang = (self.hour - 6) / 24 * math.tau
  local sun_up = Vec3(math.cos(ang) * 0.9, math.sin(ang), 0.35):normalized()
  local elev = sun_up.y
  local a, b, t = sample(elev)
  local top, hor, fog = a.top:lerp(b.top, t), a.hor:lerp(b.hor, t), a.fog:lerp(b.fog, t)
  local sunc = a.sun:lerp(b.sun, t)
  local amb = math.lerp(a.amb, b.amb, t)
  local stars = math.lerp(a.stars, b.stars, t)

  -- Whichever of sun or moon is above the horizon lights the scene and casts shadows.
  local moon_up = -sun_up
  local night = math.smoothstep(0.02, -0.12, elev)
  self._night = night
  local dir_up = night > 0.5 and moon_up or sun_up
  local energy
  if night > 0.5 then energy = 0.45 * math.smoothstep(0.0, 0.25, moon_up.y)
  else energy = 2.7 * math.smoothstep(-0.02, 0.18, elev) end
  self.light.rotation = Quat.look_rotation(-dir_up)
  self.light.energy = energy
  self.light.color = night > 0.5 and Color.hex("#a8bcff") or sunc

  Environment:set {
    sky_top = top, sky_horizon = hor, fog_color = fog,
    ground = hor:lerp(Color.hex("#2d6f8f"), 0.6):darken(0.25),
    ambient_energy = amb, stars = stars,
    moon_dir = -moon_up,
    fog_density = 0.0035 + night * 0.002,
    exposure = 1.0 + night * 0.35,
    bloom_strength = self.bloom_enabled == false and 0 or (0.07 + night * 0.05),
  }

  for _, lamp in ipairs(Game.group("lamps")) do lamp:set_on(math.smoothstep(0.0, 0.6, night + math.smoothstep(0.15, 0.0, elev) * 0.5)) end
  if self.fireflies then self.fireflies.rate = night * 45 end
end

return DayNight
