-- UI: an immediate Draw API plus retained Control nodes (Panel, Label, Button, ProgressBar,
-- TextureRect, VBox, HBox). Coordinates are virtual pixels on a 1280x720-ish canvas:
-- Game.ui_scale maps them to the real window so the UI scales with resolution.
local ffi = require("ffi")

------------------------------------------------------------------ Draw (immediate)
Draw = { alpha = 1 }
local function S() return Game.ui_scale end

function Draw.width() return Game.width / S() end
function Draw.height() return Game.height / S() end

function Draw.rect(x, y, w, h, c, radius)
  local s = S()
  C.gr_draw_rect(x * s, y * s, w * s, h * s, c.r, c.g, c.b, c.a * Draw.alpha, (radius or 0) * s)
end
function Draw.rect_border(x, y, w, h, c, radius, thickness)
  local s = S()
  C.gr_draw_rect_border(x * s, y * s, w * s, h * s, c.r, c.g, c.b, c.a * Draw.alpha, (radius or 0) * s, (thickness or 2) * s)
end
function Draw.gradient(x, y, w, h, top, bottom, radius)
  local s, a = S(), Draw.alpha
  C.gr_draw_rect_gradient(x * s, y * s, w * s, h * s, top.r, top.g, top.b, top.a * a, bottom.r, bottom.g, bottom.b, bottom.a * a, (radius or 0) * s)
end
function Draw.shadow(x, y, w, h, radius, blur, alpha)
  local s = S()
  C.gr_draw_shadow(x * s, y * s, w * s, h * s, (radius or 0) * s, (blur or 12) * s, (alpha or 0.35) * Draw.alpha)
end
function Draw.circle(x, y, r, c) Draw.rect(x - r, y - r, r * 2, r * 2, c, r) end
function Draw.ring(x, y, r, c, thickness) Draw.rect_border(x - r, y - r, r * 2, r * 2, c, r, thickness or 2) end
function Draw.image(tex, x, y, w, h, c)
  local s = S()
  c = c or Color.WHITE
  C.gr_draw_image(tex.id, x * s, y * s, (w or tex.width) * s, (h or tex.height) * s, 0, 0, 1, 1, c.r, c.g, c.b, c.a * Draw.alpha)
end
function Draw.text_width(text, size, font)
  return C.gr_text_width(font or Font.bold, tostring(text), (size or 20) * S()) / S()
end
-- opts: size, color, font, align ("left"|"center"|"right"), outline, outline_color, shadow
function Draw.text(text, x, y, opts)
  opts = opts or {}
  text = tostring(text)
  local s = S()
  local size = opts.size or 20
  local font = opts.font or Font.bold
  local c = opts.color or Color.WHITE
  if opts.align == "center" then x = x - Draw.text_width(text, size, font) / 2
  elseif opts.align == "right" then x = x - Draw.text_width(text, size, font) end
  local a = Draw.alpha
  if opts.shadow then
    C.gr_draw_text(font, text, (x + 1.5) * s, (y + 2) * s, size * s, 0, 0, 0, 0.45 * c.a * a, 0, 0, 0, 0, 0)
  end
  local o = opts.outline_color or Color(0, 0, 0, 0.85)
  C.gr_draw_text(font, text, x * s, y * s, size * s, c.r, c.g, c.b, c.a * a, (opts.outline or 0) * s, o.r, o.g, o.b, o.a * a)
end

------------------------------------------------------------------ Theme
Theme = {
  panel = Color.hex("#141b26", 0.82),
  panel_border = Color.hex("#ffffff", 0.08),
  text = Color.hex("#f2f5f7"),
  text_dim = Color.hex("#a9b4c2"),
  accent = Color.hex("#7ee0b4"),
  accent_dark = Color.hex("#3c9a76"),
  button = Color.hex("#243042"),
  button_hover = Color.hex("#2f3f57"),
  danger = Color.hex("#ff6b7a"),
  radius = 12,
}

------------------------------------------------------------------ Control
local ANCHORS = {
  top_left = { 0, 0 }, top = { 0.5, 0 }, top_right = { 1, 0 },
  left = { 0, 0.5 }, center = { 0.5, 0.5 }, right = { 1, 0.5 },
  bottom_left = { 0, 1 }, bottom = { 0.5, 1 }, bottom_right = { 1, 1 },
}

Control = Node:extend("Control")
Control._is_control = true
function Control:_setup()
  Node._setup(self)
  self.x, self.y, self.w, self.h = 0, 0, 0, 0
  self.anchor = "top_left"
  self.visible = true
  self.opacity = 1
  self.margin = 0
  self.process_mode = "always"
end
function Control:show() self.visible = true end
function Control:hide() self.visible = false end
function Control:_min_size() return self.w, self.h end

function Control:_compute_rect(p)
  local w, h = self:_min_size()
  if self._layout then
    return { x = self._layout[1], y = self._layout[2], w = self._layout[3] or w, h = self._layout[4] or h }
  end
  if self.anchor == "full" then
    local m = self.margin
    return { x = p.x + m, y = p.y + m, w = p.w - m * 2, h = p.h - m * 2 }
  end
  local a = ANCHORS[self.anchor] or ANCHORS.top_left
  return { x = p.x + p.w * a[1] + self.x - w * a[1], y = p.y + p.h * a[2] + self.y - h * a[2], w = w, h = h }
end

function Control:rect() return self._rect end
function Control:contains(px, py)
  local r = self._rect
  return r and px >= r.x and py >= r.y and px <= r.x + r.w and py <= r.y + r.h
end
function Control:_draw_self(r) end

------------------------------------------------------------------ Panel
Panel = Control:extend("Panel")
function Panel:_setup()
  Control._setup(self)
  self.color = Theme.panel
  self.radius = Theme.radius
  self.border = 1
  self.border_color = Theme.panel_border
  self.shadow = 18
end
function Panel:_draw_self(r)
  if self.shadow and self.shadow > 0 then Draw.shadow(r.x, r.y + 4, r.w, r.h, self.radius, self.shadow, 0.35) end
  if self.gradient then Draw.gradient(r.x, r.y, r.w, r.h, self.color, self.gradient, self.radius)
  else Draw.rect(r.x, r.y, r.w, r.h, self.color, self.radius) end
  if self.border > 0 then Draw.rect_border(r.x, r.y, r.w, r.h, self.border_color, self.radius, self.border) end
end

------------------------------------------------------------------ Label
Label = Control:extend("Label")
function Label:_setup()
  Control._setup(self)
  self.text = ""
  self.size = 20
  self.color = Theme.text
  self.font = Font.bold
  self.align = "left"
  self.outline = 0
  self.shadow = true
end
function Label:_min_size()
  if self.w > 0 then return self.w, self.h > 0 and self.h or self.size * 1.35 end
  local lines = 1
  for _ in tostring(self.text):gmatch("\n") do lines = lines + 1 end
  return Draw.text_width(self.text, self.size, self.font), self.size * 1.35 * lines
end
function Label:_draw_self(r)
  local x = r.x
  if self.align == "center" then x = r.x + r.w / 2 elseif self.align == "right" then x = r.x + r.w end
  Draw.text(self.text, x, r.y, { size = self.size, color = self.color, font = self.font, align = self.align,
    outline = self.outline, outline_color = self.outline_color, shadow = self.shadow })
end

------------------------------------------------------------------ Button
Button = Control:extend("Button")
function Button:_setup()
  Control._setup(self)
  self.text = "Button"
  self.size = 20
  self.w, self.h = 220, 48
  self.color = Theme.button
  self.hover_color = Theme.button_hover
  self.text_color = Theme.text
  self.accent = Theme.accent
  self.radius = 10
  self.disabled = false
  self._hover_t = 0
end
function Button:_draw_self(r, dt)
  local mx, my = Game.ui_mouse()
  local hovered = not self.disabled and not Input.is_mouse_captured() and self:contains(mx, my)
  local focused = UI.focus == self
  if hovered and not self._was_hovered and UI.hover_sound then Audio.play(UI.hover_sound, { volume = 0.25 }) end
  self._was_hovered = hovered
  if hovered then UI.mouse_over = true end
  local target = (hovered or focused) and 1 or 0
  self._hover_t = math.damp(self._hover_t, target, 14, Game.delta)
  local t = self._hover_t
  local grow = t * 3
  local bg = self.color:lerp(self.hover_color, t)
  if self.disabled then bg = bg:with_alpha(bg.a * 0.5) end
  if self._down then grow = -1 end
  local x, y, w, h = r.x - grow, r.y - grow, r.w + grow * 2, r.h + grow * 2
  Draw.shadow(x, y + 3, w, h, self.radius, 10, 0.3)
  Draw.rect(x, y, w, h, bg, self.radius)
  if t > 0.01 then Draw.rect_border(x, y, w, h, self.accent:with_alpha(t), self.radius, 2) end
  local tc = self.disabled and self.text_color:with_alpha(0.4) or self.text_color
  Draw.text(self.text, x + w / 2, y + h / 2 - self.size * 0.68, { size = self.size, color = tc, align = "center", shadow = true })

  if hovered and Input.mouse_pressed(1) then self._down = true; UI.click_consumed = true end
  if self._down and not Input.mouse_down(1) then
    self._down = false
    if hovered then self:_activate() end
  end
  if not self.disabled then UI._focusables[#UI._focusables + 1] = self end
end
function Button:_activate()
  if UI.click_sound then Audio.play(UI.click_sound, { volume = 0.5 }) end
  self:emit("pressed")
  if self.on_pressed then self:on_pressed() end
end

------------------------------------------------------------------ ProgressBar
ProgressBar = Control:extend("ProgressBar")
function ProgressBar:_setup()
  Control._setup(self)
  self.w, self.h = 200, 14
  self.value = 0.5
  self.max = 1
  self.color = Theme.accent
  self.bg = Color(0, 0, 0, 0.45)
  self.radius = 7
  self._shown = nil
end
function ProgressBar:_draw_self(r)
  local v = math.clamp(self.value / self.max, 0, 1)
  self._shown = self._shown and math.damp(self._shown, v, 10, Game.delta) or v
  Draw.rect(r.x, r.y, r.w, r.h, self.bg, self.radius)
  if self._shown > 0.001 then
    local fw = math.max(r.h, r.w * self._shown)
    Draw.gradient(r.x, r.y, fw, r.h, self.color:lighten(0.25), self.color, self.radius)
  end
end

------------------------------------------------------------------ TextureRect
TextureRect = Control:extend("TextureRect")
function TextureRect:_setup()
  Control._setup(self)
  self.color = Color.WHITE
end
function TextureRect:_min_size()
  if self.w > 0 then return self.w, self.h end
  return self.texture and self.texture.width or 0, self.texture and self.texture.height or 0
end
function TextureRect:_draw_self(r)
  if self.texture then Draw.image(self.texture, r.x, r.y, r.w, r.h, self.color) end
end

------------------------------------------------------------------ Boxes
-- Lay out child Controls in a column (VBox) or row (HBox).
VBox = Control:extend("VBox")
VBox._vertical = true
function VBox:_setup()
  Control._setup(self)
  self.spacing = 10
  self.padding = 0
  self.align = "center"   -- cross-axis alignment: "start" | "center" | "end"
end
function VBox:_min_size()
  local main, cross = 0, 0
  local n = 0
  for _, c in ipairs(self.children) do
    if c._is_control and c.visible then
      local w, h = c:_min_size()
      if self._vertical then main = main + h; cross = math.max(cross, w) else main = main + w; cross = math.max(cross, h) end
      n = n + 1
    end
  end
  main = main + math.max(0, n - 1) * self.spacing + self.padding * 2
  cross = cross + self.padding * 2
  local w, h
  if self._vertical then w, h = cross, main else w, h = main, cross end
  return math.max(w, self.w), math.max(h, self.h)
end
function VBox:_layout_children(r)
  local pos = (self._vertical and r.y or r.x) + self.padding
  for _, c in ipairs(self.children) do
    if c._is_control and c.visible then
      local w, h = c:_min_size()
      if self._vertical then
        local cx = r.x + self.padding
        local avail = r.w - self.padding * 2
        if self.align == "center" then cx = r.x + (r.w - w) / 2 elseif self.align == "end" then cx = r.x + r.w - self.padding - w
        elseif self.align == "fill" then w = avail end
        c._layout = { cx, pos, w, h }
        pos = pos + h + self.spacing
      else
        local cy = r.y + self.padding
        if self.align == "center" then cy = r.y + (r.h - h) / 2 elseif self.align == "end" then cy = r.y + r.h - self.padding - h end
        c._layout = { pos, cy, w, h }
        pos = pos + w + self.spacing
      end
    end
  end
end

HBox = VBox:extend("HBox")
HBox._vertical = false

------------------------------------------------------------------ UI pass
UI = { focus = nil, _focusables = {} }

local function draw_tree(node, prect, alpha)
  if node._is_control then
    if not node.visible then return end
    local r = node:_compute_rect(prect)
    node._rect = r
    local old = Draw.alpha
    Draw.alpha = alpha * node.opacity
    node:_draw_self(r)
    if node._draw_ui then node:_draw_ui(r) end
    if node._layout_children then node:_layout_children(r) end
    for _, c in ipairs(node.children) do draw_tree(c, r, Draw.alpha) end
    Draw.alpha = old
    return
  end
  if node.visible == false then return end
  if node._draw_ui then node:_draw_ui() end
  if node._draw_label then node:_draw_label() end
  for _, c in ipairs(node.children) do draw_tree(c, prect, alpha) end
end

function UI._draw(root)
  UI.mouse_over = false
  UI.click_consumed = false
  UI._focusables = {}
  draw_tree(root, { x = 0, y = 0, w = Draw.width(), h = Draw.height() }, 1)

  -- Keyboard / gamepad navigation between visible buttons.
  local list = UI._focusables
  if UI.focus and not (UI.focus.inside_tree and UI.focus.visible) then UI.focus = nil end
  if #list > 0 then
    local idx
    for i, b in ipairs(list) do if b == UI.focus then idx = i end end
    if Input.pressed("ui_down") or Input.pressed("ui_up") then
      local d = Input.pressed("ui_down") and 1 or -1
      idx = idx and ((idx - 1 + d) % #list + 1) or 1
      UI.focus = list[idx]
      if UI.hover_sound then Audio.play(UI.hover_sound, { volume = 0.25 }) end
    elseif UI.focus and idx and Input.pressed("ui_accept") then
      UI.focus:_activate()
    end
  else
    UI.focus = nil
  end
end
