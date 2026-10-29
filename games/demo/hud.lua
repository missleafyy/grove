-- HUD, title screen, pause menu and victory panel.
local Hud = {}
local mint = Color.hex("#7ee0b4")
local cream = Color.hex("#fff6e0")

local function crystal_icon(x, y, s, a)
  Draw.circle(x, y, s * 1.6, mint:with_alpha(0.18 * a))
  Draw.rect(x - s * 0.55, y - s, s * 1.1, s * 2, mint:with_alpha(a), s * 0.5)
  Draw.rect(x - s * 0.25, y - s * 0.7, s * 0.3, s * 0.9, Color(1, 1, 1, 0.7 * a), s * 0.15)
end

------------------------------------------------------------------ in-game HUD
function Hud.hud(ctl)
  local hud = Control { name = "HUD", anchor = "full", opacity = 0 }
  hud.toasts = {}
  hud.counter_pop = 0
  hud.hint_alpha = 1

  function hud:toast(text, sub)
    self.toasts[#self.toasts + 1] = { text = text, sub = sub, t = 0 }
  end
  function hud:pop() self.counter_pop = 1 end

  function hud:_draw_ui(r)
    local dt = Game.real_delta or 0.016
    -- Crystal counter.
    self.counter_pop = math.max(0, self.counter_pop - dt * 2.5)
    local pop = Ease.out_back(1 - self.counter_pop) * 0 + self.counter_pop
    local w = 190
    Draw.shadow(24, 24, w, 58, 16, 14, 0.3)
    Draw.rect(24, 24, w, 58, Theme.panel, 16)
    crystal_icon(56, 53, 13 + pop * 5, 1)
    Draw.text(string.format("%d", ctl.collected), 84, 30 - pop * 3, { size = 32 + pop * 6, color = cream, shadow = true })
    Draw.text("/ " .. ctl.total, 84 + Draw.text_width(tostring(ctl.collected), 32, Font.bold) + 8, 41, { size = 20, color = Theme.text_dim })

    -- Clock.
    local dn = ctl.daynight
    local cw = 150
    local cx = r.w - cw - 24
    Draw.shadow(cx, 24, cw, 58, 16, 14, 0.3)
    Draw.rect(cx, 24, cw, 58, Theme.panel, 16)
    local night = dn:night_amount()
    if night > 0.5 then
      Draw.circle(cx + 32, 53, 12, Color.hex("#dfe7ff"))
      Draw.circle(cx + 37, 49, 10, Theme.panel:with_alpha(1))
    else
      Draw.circle(cx + 32, 53, 15, Color.hex("#ffd36b"):with_alpha(0.25))
      Draw.circle(cx + 32, 53, 11, Color.hex("#ffd36b"))
    end
    Draw.text(dn:clock_text(), cx + 56, 34, { size = 28, color = cream, shadow = true })
    if dn.fast or Input.key_down("T") then Draw.text("time-lapse", cx + 56, 82, { size = 14, color = mint }) end

    -- Crosshair.
    if Input.is_mouse_captured() then
      local mx, my = r.w / 2, r.h / 2
      Draw.circle(mx, my, 3.5, Color(1, 1, 1, 0.85))
      Draw.ring(mx, my, 9, Color(1, 1, 1, 0.35), 1.5)
    end

    -- Controls hint, fades out after a while (H to show again).
    if Input.key_pressed("H") then ctl.hint_time = Game.real_time end
    local age = Game.real_time - (ctl.hint_time or 0)
    self.hint_alpha = math.damp(self.hint_alpha, age < 18 and 1 or 0, 3, dt)
    if self.hint_alpha > 0.01 then
      local lines = {
        { "WASD", "move" }, { "Mouse", "look" }, { "Space", "jump (twice!)" }, { "Shift", "sprint" },
        { "Click", "throw spark orb" }, { "T", "time-lapse" }, { "F3", "engine stats" }, { "Esc", "pause" },
      }
      local hx, hy = 24, r.h - 24 - #lines * 26 - 20
      local old = Draw.alpha
      Draw.alpha = Draw.alpha * self.hint_alpha
      Draw.rect(hx, hy, 250, #lines * 26 + 20, Theme.panel, 14)
      for i, l in ipairs(lines) do
        local y = hy + 10 + (i - 1) * 26
        local kw = Draw.text_width(l[1], 15) + 16
        Draw.rect(hx + 12, y + 1, kw, 22, Color(1, 1, 1, 0.1), 6)
        Draw.text(l[1], hx + 20, y + 2, { size = 15, color = cream })
        Draw.text(l[2], hx + 22 + kw, y + 2, { size = 15, color = Theme.text_dim, font = Font.regular })
      end
      Draw.alpha = old
    end

    -- Toasts (newest on top), slide in from above.
    local ty = 104
    for i = #self.toasts, 1, -1 do
      local t = self.toasts[i]
      t.t = t.t + dt
      if t.t > 3.2 then table.remove(self.toasts, i)
      else
        local a = math.min(1, t.t * 5) * math.min(1, (3.2 - t.t) * 2)
        local slide = (1 - Ease.out_cubic(math.min(1, t.t * 4))) * -30
        local tw = math.max(Draw.text_width(t.text, 26), t.sub and Draw.text_width(t.sub, 16, Font.regular) or 0) + 48
        local x = r.w / 2 - tw / 2
        local h = t.sub and 74 or 52
        local old = Draw.alpha
        Draw.alpha = old * a
        Draw.shadow(x, ty + slide, tw, h, 16, 16, 0.35)
        Draw.rect(x, ty + slide, tw, h, Theme.panel, 16)
        Draw.rect(x, ty + slide, tw, 3, mint, 2)
        Draw.text(t.text, r.w / 2, ty + slide + 10, { size = 26, color = cream, align = "center", shadow = true })
        if t.sub then Draw.text(t.sub, r.w / 2, ty + slide + 44, { size = 16, color = Theme.text_dim, align = "center", font = Font.regular }) end
        Draw.alpha = old
        ty = ty + h + 10
      end
    end
  end
  return hud
end

------------------------------------------------------------------ title screen
function Hud.title(ctl)
  local menu = Control { name = "Title", anchor = "full", opacity = 1 }
  local box = VBox { anchor = "bottom", y = -120, spacing = 14,
    Button { text = "Play", w = 260, h = 54, size = 22, on_pressed = function() ctl:start_play() end },
    Button { text = "Fullscreen", w = 260, h = 48, on_pressed = function() Game.set_fullscreen(not Game.is_fullscreen()) end },
    Button { text = "Quit", w = 260, h = 48, on_pressed = function() Game.quit() end },
  }
  menu:add_child(box)
  function menu:_draw_ui(r)
    local t = Game.real_time
    Draw.gradient(0, 0, r.w, r.h * 0.5, Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
    Draw.gradient(0, r.h * 0.55, r.w, r.h * 0.45, Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
    local title = "GROVE"
    local size = 120
    local cx = r.w / 2
    local y = r.h * 0.16 + math.sin(t * 1.3) * 4
    -- Letter-by-letter with a gentle wave.
    local total = 0
    for i = 1, #title do total = total + Draw.text_width(title:sub(i, i), size) + 10 end
    local x = cx - total / 2
    for i = 1, #title do
      local ch = title:sub(i, i)
      local oy = math.sin(t * 2 + i * 0.6) * 5
      Draw.text(ch, x + 4, y + oy + 6, { size = size, color = Color(0, 0, 0, 0.25) })
      Draw.text(ch, x, y + oy, { size = size, color = cream:lerp(mint, (math.sin(t + i) + 1) * 0.25), outline = 4, outline_color = Color.hex("#1d4d3c", 0.6) })
      x = x + Draw.text_width(ch, size) + 10
    end
    Draw.text("a little 3D engine  ·  showcase: Skylight Isle", cx, y + 150, { size = 22, color = cream, align = "center", shadow = true, font = Font.regular })
    Draw.text("Find all 12 crystals. Explore, climb the sky islands, knock things over.", cx, r.h - 70, { size = 17, color = Color(1, 1, 1, 0.8), align = "center", shadow = true, font = Font.regular })
  end
  return menu
end

------------------------------------------------------------------ pause menu
function Hud.pause(ctl)
  local menu = Control { name = "Pause", anchor = "full", visible = false, process_mode = "always" }
  local function toggle_text(label, on) return label .. ":  " .. (on and "On" or "Off") end
  local shadows, bloom = true, true
  local b_shadow, b_bloom, b_fast
  b_shadow = Button { text = toggle_text("Shadows", true), w = 280, on_pressed = function()
    shadows = not shadows
    Environment.sun_shadows = shadows
    ctl.daynight.light.shadows = shadows
    b_shadow.text = toggle_text("Shadows", shadows)
  end }
  b_bloom = Button { text = toggle_text("Bloom", true), w = 280, on_pressed = function()
    bloom = not bloom
    ctl.daynight.bloom_enabled = bloom
    b_bloom.text = toggle_text("Bloom", bloom)
  end }
  b_fast = Button { text = toggle_text("Time-lapse", false), w = 280, on_pressed = function()
    ctl.daynight.fast = not ctl.daynight.fast
    b_fast.text = toggle_text("Time-lapse", ctl.daynight.fast)
  end }
  local panel = Panel { anchor = "center", w = 360, h = 470,
    VBox { anchor = "full", margin = 0, spacing = 12, padding = 24,
      Label { text = "Paused", size = 34, color = cream, align = "center" },
      Button { text = "Resume", w = 280, on_pressed = function() ctl:resume() end },
      b_fast, b_shadow, b_bloom,
      Button { text = "Fullscreen", w = 280, on_pressed = function() Game.set_fullscreen(not Game.is_fullscreen()) end },
      Button { text = "Quit", w = 280, on_pressed = function() Game.quit() end },
    },
  }
  menu:add_child(panel)
  function menu:_draw_ui(r)
    Draw.rect(0, 0, r.w, r.h, Color(0.03, 0.05, 0.08, 0.55), 0)
  end
  return menu
end

------------------------------------------------------------------ victory
function Hud.victory(ctl)
  local panel = Panel { name = "Victory", anchor = "center", w = 520, h = 300, visible = false, opacity = 0,
    VBox { anchor = "full", spacing = 14, padding = 30,
      Label { text = "All crystals found!", size = 38, color = cream, align = "center" },
      Label { name = "Time", text = "", size = 20, color = Theme.text_dim, font = Font.regular, align = "center" },
      Label { text = "Thanks for playing the Grove showcase.", size = 18, color = Theme.text_dim, font = Font.regular, align = "center" },
      Button { text = "Keep exploring", w = 260, on_pressed = function() ctl:close_victory() end },
    },
  }
  return panel
end

return Hud
