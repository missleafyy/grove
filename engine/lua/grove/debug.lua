-- Developer overlay (F3): frame timing, renderer and physics stats, plus debug drawing helpers.
Debug = { visible = false }

local stats = C.gr_stats()
local fps_smooth, ms_smooth = 60, 16
local history = {}

function Debug.line(a, b, c)
  c = c or Color(1, 0.2, 0.2)
  C.gr_debug_line(a.x, a.y, a.z, b.x, b.y, b.z, c.r, c.g, c.b)
end

function Debug.cross(p, size, c)
  size = size or 0.25
  Debug.line(p - Vec3(size, 0, 0), p + Vec3(size, 0, 0), c)
  Debug.line(p - Vec3(0, size, 0), p + Vec3(0, size, 0), c)
  Debug.line(p - Vec3(0, 0, size), p + Vec3(0, 0, size), c)
end

function Debug.box(center, size, c)
  local h = size * 0.5
  local corners = {}
  for i = 0, 7 do
    corners[i] = center + Vec3((i % 2 == 1) and h.x or -h.x, (math.floor(i / 2) % 2 == 1) and h.y or -h.y, (math.floor(i / 4) == 1) and h.z or -h.z)
  end
  local edges = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 }, { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 } }
  for _, e in ipairs(edges) do Debug.line(corners[e[1]], corners[e[2]], c) end
end

function Debug._draw()
  local dt = Game.real_delta or 0.016
  if dt > 0 then
    fps_smooth = fps_smooth + (1 / dt - fps_smooth) * 0.05
    ms_smooth = ms_smooth + (stats.frame_ms - ms_smooth) * 0.05
  end
  history[#history + 1] = dt * 1000
  if #history > 120 then table.remove(history, 1) end
  if not Debug.visible then return end

  local w = 270
  local lines = {
    string.format("FPS  %d   (%.2f ms CPU)", fps_smooth + 0.5, ms_smooth),
    string.format("Draw calls  %d", stats.draw_calls),
    string.format("Triangles  %s", stats.triangles >= 1000 and string.format("%.1fk", stats.triangles / 1000) or stats.triangles),
    string.format("Instances  %d", stats.instances),
    string.format("Lights  %d   Particles  %d", stats.lights, stats.particles),
    string.format("Nodes  %d   Bodies  %d", Game.node_count, Physics.body_count()),
    string.format("Lua memory  %.1f MB", collectgarbage("count") / 1024),
  }
  local h = #lines * 21 + 70
  local x, y = Draw.width() - w - 14, Draw.height() - h - 14
  Draw.rect(x, y, w, h, Color(0.05, 0.07, 0.1, 0.82), 10)
  Draw.text("GROVE  debug", x + 12, y + 8, { size = 14, color = Theme.accent })
  for i, l in ipairs(lines) do
    Draw.text(l, x + 12, y + 10 + i * 21, { size = 15, color = Theme.text, font = Font.regular })
  end
  -- Frame time graph (bar = one frame, line = 16.7 ms).
  local gy, gh = y + h - 34, 26
  Draw.rect(x + 12, gy, w - 24, gh, Color(1, 1, 1, 0.05), 3)
  local bw = (w - 24) / 120
  for i, ms in ipairs(history) do
    local bh = math.min(gh, ms / 33.3 * gh)
    local c = ms > 20 and Theme.danger or Theme.accent
    Draw.rect(x + 12 + (i - 1) * bw, gy + gh - bh, math.max(1, bw - 0.5), bh, c:with_alpha(0.8), 0)
  end
  Draw.rect(x + 12, gy + gh - gh / 2, w - 24, 1, Color(1, 1, 1, 0.3), 0)
end
