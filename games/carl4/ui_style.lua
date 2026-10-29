-- CARL 4's UI look: slanted comic-book panels with an ink border and a hard offset shadow, condensed black
-- italic display type, segmented bars, key caps and cooldown pies. Everything in hud.lua is drawn with these.
local S = {}

S.font = {
  display = Font.load("fonts/NotoSans-CondensedBlackItalic.ttf"),
  black = Font.load("fonts/NotoSans-CondensedBlack.ttf"),
  body = Font.load("fonts/NotoSans-SemiCondensedSemiBold.ttf"),
}
local F = S.font

S.ink = Color.hex("#120a18")
S.ink2 = Color.hex("#241830")
S.paper = Color.hex("#fff3dc")
S.dim = Color.hex("#c9b9d0")
S.mute = Color.hex("#8a7a96")
S.panel = Color.hex("#1c1226", 0.9)
S.panel2 = Color.hex("#2c1f3a", 0.92)
S.yellow = Color.hex("#ffcf4a")
S.green = Color.hex("#4dffa6")
S.pink = Color.hex("#ff5d8a")
S.orange = Color.hex("#ff9a3c")
S.shield = Color.hex("#5fd6ff")
S.hp = Color.hex("#ff5a52")
S.armor = Color.hex("#ffcf4a")
S.cash = Color.hex("#7dff6a")
S.SKEW = 10

------------------------------------------------------------------ primitives
-- A comic panel: hard shadow, ink border, fill, optional accent strip on top.
function S.panel_box(x, y, w, h, opts)
  opts = opts or {}
  local k = opts.skew or S.SKEW
  local b = opts.border or 3
  if opts.shadow ~= false then Draw.slant(x + 6, y + 6, w, h, k, Color(0, 0, 0, 0.45)) end
  Draw.slant(x - b, y - b, w + b * 2, h + b * 2, k, opts.border_color or S.ink)
  Draw.slant(x, y, w, h, k, opts.fill or S.panel)
  if opts.accent then
    local ah = opts.accent_h or 4
    Draw.slant(x + k * (1 - ah / h), y, w, ah, k * ah / h, opts.accent)
  end
  -- Halftone-ish highlight band near the top for a printed feel.
  if opts.sheen ~= false then Draw.slant(x + k * 0.6, y + h * 0.06, w * 0.97, h * 0.34, k * 0.34, Color(1, 1, 1, 0.035)) end
end

-- Slanted bar with a lagging "ghost" (damage taken shows as a pale chunk that drains), segment ticks and a gloss line.
function S.bar(x, y, w, h, frac, col, opts)
  opts = opts or {}
  local k = opts.skew or h * 0.6
  frac = math.clamp(frac, 0, 1)
  Draw.slant(x - 2, y - 2, w + 4, h + 4, k, S.ink)
  Draw.slant(x, y, w, h, k, opts.back or Color(0, 0, 0, 0.55))
  local ghost = opts.ghost
  if ghost and ghost > frac then
    local gw = w * ghost
    Draw.poly({ x + k, y, x + k + gw, y, x + gw, y + h, x, y + h }, Color(1, 1, 1, 0.55))
  end
  if frac > 0 then
    local fw = w * frac
    Draw.poly({ x + k, y, x + k + fw, y, x + fw, y + h, x, y + h }, col)
    Draw.poly({ x + k, y, x + k + fw, y, x + k * 0.7 + fw, y + h * 0.3, x + k * 0.7, y + h * 0.3 }, col:lighten(0.35))
  end
  local seg = opts.segments
  if seg and seg > 1 then
    for i = 1, seg - 1 do
      local sx = x + w * i / seg
      Draw.poly({ sx + k - 1, y, sx + k + 1, y, sx + 1, y + h, sx - 1, y + h }, Color(0, 0, 0, 0.35))
    end
  end
end

-- A small slanted tag with display type.
function S.tag(text, x, y, col, opts)
  opts = opts or {}
  local size = opts.size or 14
  local font = opts.font or F.display
  local tw = Draw.text_width(text, size, font)
  local h = size * 1.35
  local w = tw + size * 1.1
  local ax = x
  if opts.align == "right" then ax = x - w elseif opts.align == "center" then ax = x - w / 2 end
  Draw.slant(ax - 2, y - 2, w + 4, h + 4, h * 0.35, S.ink)
  Draw.slant(ax, y, w, h, h * 0.35, col)
  Draw.text(text, ax + size * 0.55 + h * 0.17, y + h * 0.06, { size = size, color = opts.text_color or S.ink, font = font })
  return w
end

-- Keyboard key cap, e.g. [E].
function S.key(label, x, y, size)
  size = size or 18
  local w = math.max(size, Draw.text_width(label, size * 0.66, F.black) + size * 0.5)
  Draw.rect(x, y + 2, w, size, Color(0, 0, 0, 0.6), 4)
  Draw.rect(x, y, w, size, S.paper, 4)
  Draw.rect(x + 1, y + size - 4, w - 2, 3, Color.hex("#c9b49a"), 2)
  Draw.text(label, x + w / 2, y + size * 0.08, { size = size * 0.66, color = S.ink, font = F.black, align = "center" })
  return w
end

-- Filled pie slice (cooldown sweeps). frac 0..1 clockwise from 12 o'clock.
function S.pie(cx, cy, r, frac, col)
  if frac <= 0 then return end
  frac = math.min(frac, 1)
  local function wedge(a0, a1)
    local pts = { cx, cy }
    local n = math.max(2, math.ceil((a1 - a0) / 0.2))
    for i = 0, n do
      local a = a0 + (a1 - a0) * i / n
      pts[#pts + 1] = cx + math.sin(a) * r
      pts[#pts + 1] = cy - math.cos(a) * r
    end
    Draw.poly(pts, col)
  end
  local total = frac * math.tau
  local a = 0
  while total > 0.0001 do
    local step = math.min(total, math.pi * 0.5)
    wedge(a, a + step)
    a, total = a + step, total - step
  end
end

-- Display text with a thick ink outline and a hard drop shadow.
function S.title(text, x, y, size, col, opts)
  opts = opts or {}
  local f = opts.font or F.display
  Draw.text(text, x + size * 0.06, y + size * 0.08, { size = size, color = Color(0, 0, 0, 0.5), font = f, align = opts.align })
  Draw.text(text, x, y, { size = size, color = col, font = f, align = opts.align, outline = opts.outline or math.max(2, size * 0.07), outline_color = S.ink })
end

-- Word wrap to a pixel width.
function S.wrap(text, size, font, maxw)
  local lines, cur = {}, ""
  for word in tostring(text):gmatch("%S+") do
    local try = cur == "" and word or (cur .. " " .. word)
    if Draw.text_width(try, size, font) > maxw and cur ~= "" then
      lines[#lines + 1] = cur
      cur = word
    else cur = try end
  end
  lines[#lines + 1] = cur
  return lines
end

------------------------------------------------------------------ portraits
local pmeta, ptex
function S.portrait(who, x, y, size, talking, t)
  if not pmeta then
    pmeta = require("sprites.portraits")
    ptex = Texture.load("sprites/portraits.png", { nearest = true })
  end
  local key = string.upper(who)
  local row = pmeta.index[key]
  if not row then return false end
  local col = 0
  if talking and math.floor(t * 9) % 2 == 0 then col = 1 end
  if not talking and (t % 3.2) > 3.05 then col = 2 end
  local cw, ch = 1 / pmeta.cols, 1 / pmeta.rows
  Draw.image_region(ptex, x, y, size, size, col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
  return true
end

------------------------------------------------------------------ styled button
StyledButton = Button:extend("StyledButton")
function StyledButton:_setup()
  Button._setup(self)
  self.h = 50
  self.accent = S.yellow
  self.sub = nil
end
function StyledButton:_draw_self(r, dt)
  local mx, my = Game.ui_mouse()
  local hovered = not self.disabled and not Input.is_mouse_captured() and self:contains(mx, my)
  local focused = UI.focus == self
  if hovered and not self._was_hovered and UI.hover_sound then Audio.play(UI.hover_sound, { volume = 0.25 }) end
  self._was_hovered = hovered
  if hovered then UI.mouse_over = true end
  self._hover_t = math.damp(self._hover_t, (hovered or focused) and 1 or 0, 16, Game.delta)
  local t = self._hover_t
  local push = self._down and 3 or 0
  local x, y, w, h = r.x + t * 8 + push, r.y + push, r.w, r.h
  local k = h * 0.32
  Draw.slant(x + 6 - push, y + 6 - push, w, h, k, Color(0, 0, 0, 0.5))
  Draw.slant(x - 3, y - 3, w + 6, h + 6, k, S.ink)
  local fill = self.disabled and Color.hex("#2a2233") or S.panel2:lerp(self.accent, t)
  Draw.slant(x, y, w, h, k, fill)
  -- Accent block on the left edge.
  Draw.poly({ x + k, y, x + k + 8 + t * 6, y, x + 8 + t * 6, y + h, x, y + h }, self.disabled and S.mute or self.accent)
  local tc = self.disabled and S.mute or (t > 0.5 and S.ink or S.paper)
  local size = self.size or 20
  local ty = self.sub and (y + h * 0.5 - size * 0.95) or (y + h / 2 - size * 0.7)
  Draw.text(string.upper(self.text), x + 28, ty, { size = size, color = tc, font = F.display })
  if self.sub then Draw.text(self.sub, x + 30, ty + size * 1.12, { size = size * 0.62, color = t > 0.5 and S.ink2 or S.dim, font = F.body }) end
  if self.right_text then
    Draw.text(self.right_text, x + w - 14, y + h / 2 - size * 0.7, { size = size, color = self.disabled and S.mute or (t > 0.5 and S.ink or S.cash), font = F.display, align = "right" })
  end
  if hovered and Input.mouse_pressed(1) then self._down = true; UI.click_consumed = true end
  if self._down and not Input.mouse_down(1) then
    self._down = false
    if hovered then self:_activate() end
  end
  if not self.disabled then UI._focusables[#UI._focusables + 1] = self end
end

return S
