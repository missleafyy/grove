-- HUD, dialogue, loot cards and every menu (title, pause, shop, skills, death, victory), in the comic-panel style
-- from ui_style.lua.
local Loot = require("loot")
local Gear = require("gear")
local Skills = require("skills")
local S = require("ui_style")
local F = S.font
local Hud = {}

local SPEAKER = {
  ["CARL"] = S.green, ["OLD FACE"] = Color.hex("#e04fb0"), ["HU-MAN"] = S.orange,
  ["WHITE SUIT"] = S.paper, ["POSTAL INSPECTOR"] = Color.hex("#7fb0ff"),
}
local function speaker_color(who)
  local k = string.upper(who):gsub("^BADASS ", "")
  return SPEAKER[k] or S.dim
end

local function to_ui(p)
  local x, y, on = Game.camera:world_to_screen(p)
  local s = Game.ui_scale
  return x / s, y / s, on
end

local function with_alpha(a, fn)
  local old = Draw.alpha
  Draw.alpha = old * a
  fn()
  Draw.alpha = old
end

-- Small pictograms drawn from shapes.
local function icon_ufo(cx, cy, s, col)
  Draw.poly({ cx - s * 0.35, cy + s * 0.1, cx + s * 0.35, cy + s * 0.1, cx + s * 0.6, cy + s * 0.75, cx - s * 0.6, cy + s * 0.75 }, col:with_alpha(0.45))
  Draw.rect(cx - s * 0.62, cy - s * 0.12, s * 1.24, s * 0.3, col, s * 0.15)
  Draw.rect(cx - s * 0.28, cy - s * 0.42, s * 0.56, s * 0.4, col:lighten(0.4), s * 0.2)
end
local function icon_grenade(x, y, s, col, full)
  local c = full and col or Color(1, 1, 1, 0.15)
  Draw.rect(x - s * 0.32, y - s * 0.3, s * 0.64, s * 0.85, c, s * 0.3)
  Draw.rect(x - s * 0.14, y - s * 0.5, s * 0.28, s * 0.22, full and S.paper or c, 2)
  if full then Draw.rect(x - s * 0.32, y + s * 0.02, s * 0.64, s * 0.12, S.yellow, 1) end
end
local function icon_skull(x, y, s, col)
  Draw.rect(x - s * 0.5, y - s * 0.5, s, s * 0.8, col, s * 0.4)
  Draw.rect(x - s * 0.3, y + s * 0.2, s * 0.6, s * 0.35, col, 2)
  Draw.rect(x - s * 0.32, y - s * 0.18, s * 0.24, s * 0.24, S.ink, s * 0.1)
  Draw.rect(x + s * 0.08, y - s * 0.18, s * 0.24, s * 0.24, S.ink, s * 0.1)
end
local function arrow(x, y, up, col)
  if up then Draw.poly({ x, y - 6, x + 6, y + 4, x - 6, y + 4 }, col)
  else Draw.poly({ x - 6, y - 4, x + 6, y - 4, x, y + 6 }, col) end
end

------------------------------------------------------------------ in-game HUD
function Hud.hud()
  local hud = Control { name = "HUD", anchor = "full", opacity = 0 }
  hud.toasts = {}
  hud.hurt_t, hud.hurt_dirs = 0, {}
  hud.hit_t, hud.hit_crit = 0, false
  hud.bloom_v, hud.kill_t = 0, 0
  hud.ghost_hp, hud.ghost_sh = 1, 1

  function hud:toast(text, sub, col)
    self.toasts[#self.toasts + 1] = { text = text, sub = sub, t = 0, col = col }
    if #self.toasts > 4 then table.remove(self.toasts, 1) end
  end
  function hud:banner(text, sub, col) self._banner = { text = text, sub = sub, col = col or S.yellow, t = 0 } end
  function hud:hurt(pos)
    self.hurt_t = 1
    if pos and G.player then self.hurt_dirs[#self.hurt_dirs + 1] = { pos = pos:copy(), t = 1 } end
    if #self.hurt_dirs > 4 then table.remove(self.hurt_dirs, 1) end
  end
  function hud:hitmark(crit, kill) self.hit_t = 1; self.hit_crit = crit; if kill then self.kill_t = 1 end end
  function hud:bloom(a) self.bloom_v = math.min(1.6, self.bloom_v + a) end

  ---------------------------------------------------------------- world-space bits
  function hud:draw_numbers(dt)
    for i = #G.numbers, 1, -1 do
      local n = G.numbers[i]
      n.t = n.t + dt
      if n.t > 1.0 then table.remove(G.numbers, i)
      else
        local x, y, on = to_ui(n.pos + Vec3(0, n.t * 1.3, 0))
        if on then
          local a = math.min(1, (1.0 - n.t) * 4)
          local pop = 1 + math.max(0, 0.12 - n.t) * 5
          local size = (n.crit and 34 or 24) * pop
          with_alpha(a, function()
            local xx = x + n.dx + n.t * n.dx * 0.8
            Draw.text(n.text, xx + 2, y + 3, { size = size, color = Color(0, 0, 0, 0.5), font = F.display, align = "center" })
            Draw.text(n.text, xx, y, { size = size, color = n.col, font = F.display, align = "center", outline = 3, outline_color = S.ink })
            local ty = y + size * 1.05
            if n.crit then Draw.text("CRITICAL!", xx, y - 20, { size = 15, color = S.yellow, font = F.display, align = "center", outline = 2, outline_color = S.ink }) end
            if n.eff then
              Draw.text(n.eff, xx, ty, { size = 12, color = n.eff == "EFFECTIVE" and n.col or S.mute, font = F.display, align = "center", outline = 2, outline_color = S.ink })
            end
          end)
        end
      end
    end
  end

  function hud:draw_enemy_bars()
    local p = G.player
    for _, e in ipairs(Game.group("enemies")) do
      local near = e.badass and e:global_position():distance(p.position) < 32
      if not e.dead and not e.boss and (Game.time - e.last_hit < 4 or near) then
        local x, y, on = to_ui(e:global_position() + Vec3(0, (e.head_y and e.head_y > 0 and e.head_y or 0.5) * (e.badass and 1.3 or 1) + 0.8, 0))
        if on then
          local w = e.badass and 120 or 90
          local name = e.display .. "  " .. e.level
          local nx = x - w / 2
          if e.badass then icon_skull(nx + 6, y - 14, 13, S.orange); nx = nx + 16 end
          Draw.text(name, nx, y - 24, { size = 14, color = e.badass and S.orange or S.paper, font = F.display, outline = 2, outline_color = S.ink })
          local hp_col = e.layer == "armor" and S.armor or S.hp
          S.bar(x - w / 2, y, w, 8, e.hp / e.max_hp, hp_col)
          if e.max_eshield > 0 then S.bar(x - w / 2 + 4, y - 7, w - 8, 4, e.eshield / e.max_eshield, S.shield) end
          local ix = x + w / 2 + 12
          if e.burn then Draw.circle(ix, y + 4, 5, Loot.ELEMENTS.fire.color); ix = ix + 13 end
          if e.float_t > 0 then Draw.circle(ix, y + 4, 5, e.abducted and S.green or Loot.ELEMENTS.curse.color) end
        end
      end
    end
  end

  ---------------------------------------------------------------- overlays
  function hud:draw_vignettes(r, dt, t)
    local p = G.player
    self.hurt_t = math.max(0, self.hurt_t - dt * 2.5)
    local low = p.hp / p.max_hp < 0.3 and (0.25 + math.sin(t * 6) * 0.1) or 0
    local ha = math.max(self.hurt_t * 0.45, low, p.downed and 0.55 or 0)
    if ha > 0 then
      Draw.gradient(0, 0, r.w, 110, Color(0.8, 0, 0.05, ha), Color(0.8, 0, 0.05, 0))
      Draw.gradient(0, r.h - 110, r.w, 110, Color(0.8, 0, 0.05, 0), Color(0.8, 0, 0.05, ha))
    end
    -- Where the hits came from: red chevrons round the crosshair.
    local cx, cy = r.w / 2, r.h / 2
    local fwd = G.rig.camera:forward():flat():normalized()
    local right = G.rig.camera:right():flat():normalized()
    for i = #self.hurt_dirs, 1, -1 do
      local hd = self.hurt_dirs[i]
      hd.t = hd.t - dt * 1.2
      if hd.t <= 0 then table.remove(self.hurt_dirs, i)
      else
        local d = (hd.pos - p.position):flat()
        if d:length() > 0.5 then
          d = d:normalized()
          local a = math.atan2(d:dot(right), d:dot(fwd))
          local function at(rad, off) return cx + math.sin(a + off) * rad, cy - math.cos(a + off) * rad end
          local x1, y1 = at(150, -0.18)
          local x2, y2 = at(172, 0)
          local x3, y3 = at(150, 0.18)
          local x4, y4 = at(158, 0)
          Draw.poly({ x1, y1, x2, y2, x3, y3, x4, y4 }, Color(1, 0.2, 0.15, hd.t * 0.9))
        end
      end
    end
  end

  function hud:draw_crosshair(r, dt)
    local p = G.player
    if not Input.is_mouse_captured() or G.ui_open then return end
    local cx, cy = r.w / 2, r.h / 2
    local g = p:gun()
    self.bloom_v = math.max(0, self.bloom_v - dt * 4)
    local gap = 6 + (g and g.spread or 1) * 2.5 * (Input.down("aim") and 0.45 or 1) + self.bloom_v * 14
    local cc = Color(1, 1, 1, 0.95)
    if p.held then
      Draw.ring(cx, cy, 15, S.ink, 4)
      Draw.ring(cx, cy, 14, S.green, 2)
      local w = Draw.text_width("LMB  THROW      F  DROP", 13, F.display) + 24
      S.panel_box(cx - w / 2, cy + 26, w, 22, { skew = 6, accent = false, sheen = false, border = 2 })
      Draw.text("LMB  THROW      F  DROP", cx, cy + 28, { size = 13, color = S.green, font = F.display, align = "center" })
      return
    end
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local x = cx + d[1] * (gap + 4) - (d[1] ~= 0 and 4 or 1)
      local y = cy + d[2] * (gap + 4) - (d[2] ~= 0 and 4 or 1)
      local w, h = d[1] ~= 0 and 8 or 2, d[2] ~= 0 and 8 or 2
      Draw.rect(x - 1, y - 1, w + 2, h + 2, Color(0, 0, 0, 0.6), 1)
      Draw.rect(x, y, w, h, cc, 1)
    end
    Draw.circle(cx, cy, 2.2, Color(0, 0, 0, 0.6))
    Draw.circle(cx, cy, 1.4, cc)
    self.kill_t = math.max(0, self.kill_t - dt * 3)
    if self.kill_t > 0 then
      local k = self.kill_t
      local sz = 14 + (1 - k) * 4 + (k > 0.85 and (k - 0.85) * 60 or 0)
      local kc = S.hp:with_alpha(math.min(1, k * 2))
      for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local x0, y0 = cx + d[1] * sz * 0.4, cy + d[2] * sz * 0.4
        local x1, y1 = cx + d[1] * sz, cy + d[2] * sz
        Draw.poly({ x0 - 2.5, y0, x0, y0 - 2.5 * d[1] * d[2], x1 + 2.5, y1, x1, y1 + 2.5 * d[1] * d[2] }, kc)
        Draw.poly({ x0, y0 + 2.5 * d[1] * d[2], x0 + 2.5, y0, x1, y1 - 2.5 * d[1] * d[2], x1 - 2.5, y1 }, kc)
      end
    end
    self.hit_t = math.max(0, self.hit_t - dt * 6)
    if self.hit_t > 0 then
      local hc = (self.hit_crit and S.yellow or Color.WHITE):with_alpha(self.hit_t)
      for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        Draw.rect(cx + d[1] * 10 - 2, cy + d[2] * 10 - 2, 4, 4, hc, 1)
        Draw.rect(cx + d[1] * 14 - 2, cy + d[2] * 14 - 2, 4, 4, hc, 1)
      end
    end
  end

  ---------------------------------------------------------------- bottom left: vitals, action skill, grenades
  function hud:draw_vitals(r, dt, t)
    local p = G.player
    local y0 = r.h - 118
    S.panel_box(24, y0, 372, 92, { accent = S.green })
    -- Level badge (hexagon).
    local bx, by = 70, y0 + 50
    local function hex(rad, col)
      local pts = {}
      for i = 0, 5 do
        local a = i * math.pi / 3 + math.pi / 6
        pts[#pts + 1] = bx + math.cos(a) * rad
        pts[#pts + 1] = by + math.sin(a) * rad
      end
      Draw.poly(pts, col)
    end
    hex(36, S.ink)
    hex(32, S.yellow)
    hex(26, Color.hex("#ffe08a"))
    Draw.text("LV", bx, by - 24, { size = 11, color = S.ink, font = F.black, align = "center" })
    Draw.text(tostring(G.level), bx, by - 15, { size = 30, color = S.ink, font = F.display, align = "center" })
    if G.skill_points > 0 then
      local pulse = 0.6 + math.sin(t * 6) * 0.4
      Draw.circle(bx + 26, by - 24, 11, S.ink)
      Draw.circle(bx + 26, by - 24, 9, S.green:with_alpha(pulse))
      Draw.text("+", bx + 26, by - 35, { size = 18, color = S.ink, font = F.display, align = "center" })
    end
    -- Shield, health, XP.
    local sx, w = 118, 256
    self.ghost_sh = math.max(p.shield / math.max(p.max_shield, 1), self.ghost_sh - dt * 0.6)
    self.ghost_hp = math.max(p.hp / p.max_hp, self.ghost_hp - dt * 0.5)
    S.bar(sx + 6, y0 + 12, w - 6, 15, p.shield / math.max(p.max_shield, 1), S.shield, { ghost = self.ghost_sh, segments = 8 })
    S.bar(sx, y0 + 35, w, 24, p.hp / p.max_hp, S.hp, { ghost = self.ghost_hp, segments = 10 })
    Draw.text(string.format("%d", p.shield), sx + w, y0 + 10, { size = 16, color = S.paper, font = F.display, align = "right", outline = 2, outline_color = S.ink })
    Draw.text(string.format("%d", math.ceil(p.hp)), sx + w - 6, y0 + 34, { size = 22, color = S.paper, font = F.display, align = "right", outline = 2, outline_color = S.ink })
    S.bar(sx - 4, y0 + 68, w, 6, G.xp / G.xp_next, S.yellow, { skew = 3 })
    Draw.text(string.format("XP  %d / %d", G.xp, G.xp_next), sx - 2, y0 + 75, { size = 11, color = S.dim, font = F.body })
    -- Hover fuel.
    if p.hovering or p._hover < 1 then S.bar(sx + 150, y0 + 77, 100, 5, p._hover, S.green, { skew = 3 }) end

    -- ABDUCT.
    local ax, ay = 452, y0 + 44
    local ready = Skills.abduct_ready()
    Draw.circle(ax + 3, ay + 4, 36, Color(0, 0, 0, 0.45))
    Draw.circle(ax, ay, 36, S.ink)
    Draw.circle(ax, ay, 32, ready and Color.hex("#163a2a") or S.ink2)
    icon_ufo(ax, ay - 2, 30, ready and S.green or S.mute)
    if not ready and G.abduct_cd and G.abduct_cd > 0 then
      S.pie(ax, ay, 32, G.abduct_cd / (G.abduct_max or 22), Color(0, 0, 0, 0.6))
      Draw.text(string.format("%d", math.ceil(G.abduct_cd)), ax, ay - 14, { size = 24, color = S.paper, font = F.display, align = "center", outline = 2, outline_color = S.ink })
    elseif G.abduct_active then
      Draw.ring(ax, ay, 33, S.green, 3)
    else
      local pulse = 0.5 + math.sin(t * 4) * 0.5
      Draw.ring(ax, ay, 34 + pulse * 3, S.green:with_alpha(0.3 + pulse * 0.5), 2)
    end
    S.tag("ABDUCT", ax - 34, ay + 38, ready and S.green or S.mute, { size = 11 })
    S.key("X", ax + 30, ay + 37, 18)

    -- Grenades.
    local gx, gy = 512, y0 + 22
    local gi = p.grenade_item
    local gcol = gi and gi.element and Loot.ELEMENTS[gi.element].color or S.yellow
    for i = 1, p:max_grenades() do icon_grenade(gx + (i - 1) * 20, gy + 8, 22, gcol, i <= G.grenades) end
    S.key("G", gx + p:max_grenades() * 20 + 2, gy, 18)
    if gi then Draw.text(gi.name, gx - 8, gy + 26, { size = 12, color = Loot.RARITY[gi.rarity].color, font = F.display, outline = 2, outline_color = S.ink }) end
    local si = p.shield_item
    if si then Draw.text(si.name, gx - 8, gy + 42, { size = 12, color = S.shield, font = F.display, outline = 2, outline_color = S.ink }) end
  end

  ---------------------------------------------------------------- bottom right: weapon
  function hud:draw_weapon(r, t)
    local p = G.player
    local g = p:gun()
    local w, h = 392, 96
    local x, y = r.w - 28 - w, r.h - 24 - h
    -- Slots above the panel.
    for i = 1, 4 do
      local gg = p.guns[i]
      local sel = i == p.slot
      local cx = x + 14 + (i - 1) * 96
      local cy = y - 34 + (sel and -4 or 0)
      local cw = 88
      Draw.slant(cx - 2, cy - 2, cw + 4, 26, 7, S.ink)
      Draw.slant(cx, cy, cw, 22, 6, sel and S.panel2:lerp(S.paper, 0.15) or S.panel)
      if gg then
        local rc = Loot.RARITY[gg.rarity].color
        Draw.slant(cx + 4, cy + 18, cw - 6, 4, 1, rc)
        Draw.text(i .. "  " .. string.upper(gg.label), cx + 12, cy + 1, { size = 14, color = sel and S.paper or S.dim, font = F.display })
      else
        Draw.text(i .. "  —", cx + 12, cy + 1, { size = 14, color = S.mute, font = F.display })
      end
    end
    if not g then return end
    local rc = Loot.RARITY[g.rarity].color
    S.panel_box(x, y, w, h, { accent = rc, accent_h = 5 })
    S.title(g.name, x + 20, y + 10, 22, rc, { outline = 2 })
    local mk = Gear.MAKERS[g.maker]
    local tx = x + 22
    tx = tx + S.tag(string.upper(g.maker), tx, y + 42, mk and mk.color or S.dim, { size = 10 }) + 8
    if g.element then
      local e = Loot.ELEMENTS[g.element]
      tx = tx + S.tag(string.upper(e.name), tx, y + 42, e.color, { size = 10 }) + 8
    end
    Draw.text(string.upper(g.label) .. "  ·  LV " .. g.level, tx, y + 42, { size = 12, color = S.dim, font = F.display })
    -- Ammo.
    local ammo = tostring(g.ammo)
    local ac = g.ammo == 0 and S.hp or (g.ammo <= g.mag * 0.25 and S.yellow or S.paper)
    local magw = Draw.text_width("/" .. g.mag, 18, F.display)
    S.title(ammo, x + w - 26 - magw, y + 26, 48, ac, { align = "right", outline = 3 })
    Draw.text("/" .. g.mag, x + w - 20, y + 54, { size = 18, color = S.dim, font = F.display, align = "right" })
    -- Pips or reload bar.
    local py = y + 70
    if p._reload then
      local k = 1 - p._reload / (p._reload_max or g.reload)
      S.bar(x + 22, py, 220, 10, k, S.paper)
      Draw.text("RELOADING", x + 250, py - 4, { size = 14, color = S.paper, font = F.display })
    elseif g.mag <= 40 then
      local pw = math.min(10, 220 / g.mag)
      for i = 1, g.mag do
        local px = x + 22 + (i - 1) * pw
        local on = i <= g.ammo
        Draw.slant(px, py, math.max(2, pw - 2), 10, 3, on and ac or Color(1, 1, 1, 0.12))
      end
    else
      S.bar(x + 22, py, 220, 10, g.ammo / g.mag, ac)
    end
  end

  ---------------------------------------------------------------- top: objectives, compass, cash, boss
  function hud:draw_top(r, t)
    local p = G.player
    -- Objectives.
    local oy = 22
    if G.chapter then S.tag(G.chapter, 24, oy, S.yellow, { size = 13 }); oy = oy + 32 end
    for _, o in ipairs(G.objectives) do
      if not o.hidden then
        local c = o.done and S.mute or S.paper
        local tw = Draw.text_width(o.text, 16, F.body)
        Draw.slant(20, oy - 2, tw + 46, 24, 6, Color(0, 0, 0, o.done and 0.25 or 0.45))
        local dc = o.done and S.cash or (o.color or S.yellow)
        Draw.poly({ 36, oy + 4, 43, oy + 11, 36, oy + 18, 29, oy + 11 }, S.ink)
        Draw.poly({ 36, oy + 6, 41, oy + 11, 36, oy + 16, 31, oy + 11 }, o.done and dc or dc:with_alpha(0.35))
        Draw.text(o.text, 52, oy + 1, { size = 16, color = c, font = F.body, outline = 2, outline_color = S.ink })
        if o.done then Draw.rect(52, oy + 12, tw, 2, S.mute, 1) end
        oy = oy + 28
      end
    end

    -- Compass.
    local cw, cxm = 540, r.w / 2
    Draw.slant(cxm - cw / 2 - 3, 15, cw + 6, 34, 10, S.ink)
    Draw.slant(cxm - cw / 2, 18, cw, 28, 9, S.panel)
    local yaw = G.rig.yaw
    local span = math.pi * 0.55
    local function bearing_x(ang)
      local d = math.wrap_angle(ang - yaw)
      return cxm - d / span * cw / 2, math.abs(d) < span
    end
    for i = 0, 23 do
      local a = i * math.pi / 12
      local x, on = bearing_x(a)
      if on and i % 6 ~= 0 then Draw.rect(x - 1, i % 3 == 0 and 30 or 36, 2, i % 3 == 0 and 12 or 6, Color(1, 1, 1, 0.3), 1) end
    end
    for i, lbl in ipairs({ "N", "W", "S", "E" }) do
      local x, on = bearing_x((i - 1) * math.pi / 2)
      if on then Draw.text(lbl, x, 19, { size = 20, color = lbl == "N" and S.yellow or S.paper, font = F.display, align = "center" }) end
    end
    Draw.poly({ cxm - 7, 48, cxm + 7, 48, cxm, 56 }, S.yellow)
    for _, o in ipairs(G.objectives) do
      if o.target and not o.done and not o.hidden then
        local d = o.target - p.position
        local x = bearing_x(math.atan2(-d.x, -d.z))
        x = math.clamp(x, cxm - cw / 2 + 10, cxm + cw / 2 - 10)
        local oc = o.color or S.green
        Draw.poly({ x, 50, x + 8, 58, x, 66, x - 8, 58 }, S.ink)
        Draw.poly({ x, 52, x + 6, 58, x, 64, x - 6, 58 }, oc)
        Draw.text(string.format("%dm", d:length()), x, 67, { size = 12, color = S.paper, font = F.display, align = "center", outline = 2, outline_color = S.ink })
        local sx3, sy3, onscr = to_ui(o.target + Vec3(0, 3, 0))
        if onscr and d:length() > 12 then
          local bob = math.sin(t * 3) * 3
          Draw.poly({ sx3, sy3 - 12 + bob, sx3 + 10, sy3 + bob, sx3, sy3 + 12 + bob, sx3 - 10, sy3 + bob }, S.ink)
          Draw.poly({ sx3, sy3 - 8 + bob, sx3 + 7, sy3 + bob, sx3, sy3 + 8 + bob, sx3 - 7, sy3 + bob }, oc)
        end
      end
    end

    -- Cash, cells, skill points.
    S.title("$" .. G.cash, r.w - 28, 18, 32, S.cash, { align = "right" })
    for i = 1, 3 do
      local cx = r.w - 44 - (3 - i) * 28
      Draw.slant(cx - 11, 60, 22, 32, 4, S.ink)
      Draw.slant(cx - 8, 63, 16, 26, 3, i <= G.cells and S.green or Color(1, 1, 1, 0.1))
      if i <= G.cells then Draw.slant(cx - 6, 65, 5, 22, 2, Color(1, 1, 1, 0.45)) end
    end
    Draw.text("POWER CELLS", r.w - 26, 96, { size = 11, color = S.dim, font = F.display, align = "right" })
    if G.skill_points > 0 then
      local pulse = 0.75 + math.sin(t * 5) * 0.25
      with_alpha(pulse, function()
        local w = S.tag(G.skill_points .. " SKILL POINT" .. (G.skill_points > 1 and "S" or ""), r.w - 28, 118, S.green, { size = 13, align = "right" })
        S.key("K", r.w - 28 - w - 26, 119, 18)
      end)
    end

    -- Boss bar.
    local boss = G.boss
    if boss and not boss.dead and boss.state ~= "intro" then
      local bw = 660
      local bx = r.w / 2 - bw / 2
      S.title("HU-MAN", r.w / 2, 84, 26, S.orange, { align = "center" })
      Draw.text("FOCUS-TESTED  ·  SQUARE JAW  ·  94% APPROVAL", r.w / 2, 114, { size = 12, color = S.dim, font = F.display, align = "center" })
      if boss.max_eshield > 0 then S.bar(bx + 10, 134, bw - 20, 7, boss.eshield / boss.max_eshield, S.shield) end
      S.bar(bx, 144, bw, 16, boss.hp / boss.max_hp, S.armor, { segments = 3 })
    end
  end

  ---------------------------------------------------------------- dialogue
  function hud:draw_dialogue(r, dt, t)
    local line = G.line
    G.talker = nil
    if not line then return end
    line.t = line.t + dt
    if line.t > line.dur then
      G.line = table.remove(G.lines, 1)
      return
    end
    local a = math.min(1, line.t * 7, (line.dur - line.t) * 5)
    local size = 22
    local w = math.min(860, r.w - 120)
    local textw = w - 150
    if not line.wrapped then line.wrapped = S.wrap(line.text, size, F.body, textw) end
    local nl = #line.wrapped
    local h = math.max(96, 46 + nl * 29)
    local x = r.w / 2 - w / 2
    local y = r.h - 176 - h
    local col = speaker_color(line.who)
    local chars = math.floor(line.t * 48)
    local typing = chars < #line.text
    if typing then G.talker = string.upper(line.who) end
    with_alpha(a, function()
      local slide = (1 - math.min(1, line.t * 6)) * 24
      S.panel_box(x, y + slide, w, h, { fill = Color.hex("#140c1c", 0.94), accent = col, accent_h = 4 })
      -- Portrait in an ink frame, breaking out of the panel's top edge.
      local ps = 100
      local px, py = x + 18, y + slide - 18
      Draw.slant(px - 4 + 5, py - 4 + 5, ps + 8, ps + 8, 6, Color(0, 0, 0, 0.5))
      Draw.slant(px - 4, py - 4, ps + 8, ps + 8, 6, S.ink)
      Draw.slant(px, py, ps, ps, 5, col:lerp(S.ink, 0.72))
      if not S.portrait(line.who, px + 4, py + 2, ps - 6, typing, t) then
        S.title(string.sub(line.who, 1, 1), px + ps / 2, py + 20, 56, col, { align = "center" })
      end
      -- Speaker name tag.
      S.tag(string.upper(line.who), x + 134, y + slide - 13, col, { size = 15 })
      -- Typed text.
      local budget = chars
      for i, l in ipairs(line.wrapped) do
        if budget <= 0 then break end
        Draw.text(l:sub(1, budget), x + 136, y + slide + 22 + (i - 1) * 29, { size = size, color = S.paper, font = F.body, outline = 1, outline_color = S.ink })
        budget = budget - #l - 1
      end
      -- More-to-come marker and queue dots.
      if not typing and math.floor(t * 3) % 2 == 0 then
        local mx, my = x + w - 30, y + slide + h - 22
        Draw.poly({ mx - 7, my - 4, mx + 7, my - 4, mx, my + 5 }, col)
      end
      for i = 1, math.min(#G.lines, 5) do Draw.circle(x + w - 40 - i * 12, y + slide + h - 18, 3, S.mute) end
    end)
  end

  ---------------------------------------------------------------- toasts, banners, FFYL, hints
  function hud:draw_toasts(r, dt)
    local ty = 176
    for i = #self.toasts, 1, -1 do
      local tt = self.toasts[i]
      tt.t = tt.t + dt
      if tt.t > 3 then table.remove(self.toasts, i)
      else
        local a = math.min(1, tt.t * 6) * math.min(1, (3 - tt.t) * 2)
        local tw = math.max(Draw.text_width(tt.text, 24, F.display), tt.sub and Draw.text_width(tt.sub, 15, F.body) or 0) + 54
        local hgt = tt.sub and 62 or 40
        local slide = (1 - math.min(1, tt.t * 5)) * 40
        with_alpha(a, function()
          S.panel_box(r.w / 2 - tw / 2 + slide, ty, tw, hgt, { accent = tt.col or S.yellow })
          Draw.text(string.upper(tt.text), r.w / 2 + slide + 5, ty + 6, { size = 24, color = tt.col or S.paper, font = F.display, align = "center" })
          if tt.sub then Draw.text(tt.sub, r.w / 2 + slide + 2, ty + 36, { size = 15, color = S.dim, font = F.body, align = "center" }) end
        end)
        ty = ty + hgt + 12
      end
    end
  end

  function hud:draw_banners(r, dt, t)
    local b = self._banner
    if G.levelup_t then
      self:banner("LEVEL UP!", "Level " .. G.level .. "  ·  +1 skill point  ·  press K", S.yellow)
      G.levelup_t = nil
    end
    if b then
      b.t = b.t + dt
      if b.t > 2.6 then self._banner = nil return end
      local k = b.t
      local s = 1 + math.max(0, 0.25 - k) * 2.4
      local a = math.min(1, (2.6 - k) * 3)
      with_alpha(a, function()
        local y = r.h * 0.26
        local sw = math.min(1, k * 5) * (r.w * 0.62)
        Draw.slant(r.w / 2 - sw / 2 - 4, y - 8, sw + 8, 110, 30, S.ink)
        Draw.slant(r.w / 2 - sw / 2, y - 4, sw, 102, 28, b.col:with_alpha(0.22))
        S.title(b.text, r.w / 2, y, 64 * s, b.col, { align = "center" })
        if b.sub then Draw.text(b.sub, r.w / 2, y + 74, { size = 18, color = S.paper, font = F.display, align = "center", outline = 2, outline_color = S.ink }) end
      end)
    end
  end

  function hud:draw_ffyl(r, t)
    local p = G.player
    if not p.downed then return end
    local k = p.ffyl_t / p.ffyl_max
    local y = r.h * 0.2
    local pulse = 1 + math.sin(t * 8) * 0.03
    S.title("FIGHT FOR YOUR LIFE", r.w / 2, y, 46 * pulse, S.hp, { align = "center" })
    S.bar(r.w / 2 - 220, y + 64, 440, 16, k, S.hp, { segments = 8 })
    Draw.text("GET A KILL TO GET BACK UP", r.w / 2, y + 88, { size = 16, color = S.paper, font = F.display, align = "center", outline = 2, outline_color = S.ink })
  end

  local HINTS = {
    { "WASD", "Move" }, { "SPACE", "Jump · hold to hover" }, { "SHIFT", "Sprint" }, { "C", "Dash" },
    { "LMB", "Shoot" }, { "RMB", "Aim" }, { "R", "Reload" }, { "F", "Tractor beam (hold)" }, { "V", "Melee" },
    { "G", "Grenade" }, { "X", "ABDUCT" }, { "E", "Pick up · use" }, { "1-4", "Weapons" }, { "K", "Skills" }, { "ESC", "Pause" },
  }
  function hud:draw_hints(r)
    local age = Game.real_time - (G.hint_time or 0)
    if Input.key_pressed("H") then G.hint_time = Game.real_time end
    if age >= 26 then return end
    local f = G.player.focus
    if f and f:is_valid() and (f.gun or f.item) then return end
    local a = math.clamp(26 - age, 0, 1)
    with_alpha(a, function()
      local hx, hy = r.w - 270, 158
      S.panel_box(hx - 8, hy - 12, 244, #HINTS * 23 + 20, { accent = S.yellow })
      for i, l in ipairs(HINTS) do
        local ky = hy + (i - 1) * 23
        S.key(l[1], hx + 4, ky, 18)
        Draw.text(l[2], hx + 82, ky, { size = 15, color = S.paper, font = F.body })
      end
      Draw.text("H  shows this again", hx + 4, hy + #HINTS * 23 + 10, { size = 11, color = S.mute, font = F.body })
    end)
  end

  ---------------------------------------------------------------- interaction prompt + loot card
  function hud:draw_focus(r)
    local p = G.player
    local f = p.focus
    if not (f and f:is_valid() and (f.gun or f.item or f.prompt)) then return end
    if f.gun then self:card(r, f.gun, p:gun(), "gun")
    elseif f.item then self:card(r, f.item, f.item.type == "shield" and p.shield_item or p.grenade_item, f.item.type)
    else
      local txt = string.upper(f.prompt)
      local tw = Draw.text_width(txt, 18, F.display) + 64
      local x, y = r.w / 2 - tw / 2, r.h * 0.62
      S.panel_box(x, y, tw, 36, { accent = S.yellow })
      S.key("E", x + 14, y + 8, 20)
      Draw.text(txt, x + 44, y + 6, { size = 18, color = S.paper, font = F.display })
    end
  end

  function hud:card(r, item, cur, kind)
    local rr = Loot.RARITY[item.rarity]
    local rc = rr.color
    local rows, extra = {}, {}
    if kind == "gun" then
      rows = {
        { "DAMAGE", item.damage * item.pellets, cur and cur.damage * cur.pellets, item.pellets > 1 and string.format("%d x%d", item.damage, item.pellets) or string.format("%d", item.damage) },
        { "FIRE RATE", item.rate, cur and cur.rate, string.format("%.1f/s", item.rate) },
        { "MAGAZINE", item.mag, cur and cur.mag, tostring(item.mag) },
        { "RELOAD", -item.reload, cur and -cur.reload, string.format("%.1fs", item.reload) },
        { "DPS", item.dps, cur and cur.dps, string.format("%d", item.dps) },
      }
      local mk = Gear.MAKERS[item.maker]
      if mk then extra[#extra + 1] = { mk.tag .. ":  " .. mk.desc, mk.color } end
      if item.element then
        local e = Loot.ELEMENTS[item.element]
        extra[#extra + 1] = { string.upper(e.name) .. ":  " .. e.desc .. " (" .. math.floor(item.element_chance * 100) .. "%)", e.color }
      end
      if item.flavour then extra[#extra + 1] = { item.flavour, S.hp, true } end
    elseif kind == "shield" then
      rows = {
        { "CAPACITY", item.capacity, cur and cur.capacity, tostring(item.capacity) },
        { "RECHARGE DELAY", -item.delay, cur and -cur.delay, string.format("%.1fs", item.delay) },
        { "RECHARGE RATE", item.rate, cur and cur.rate, string.format("%d/s", item.capacity * item.rate) },
      }
      if item.desc then extra[#extra + 1] = { item.desc, S.shield } end
    else
      rows = {
        { "DAMAGE", item.damage, cur and cur.damage, tostring(item.damage) },
        { "RADIUS", item.radius, cur and cur.radius, string.format("%.1fm", item.radius) },
      }
      if item.desc then extra[#extra + 1] = { item.desc, S.yellow } end
      if item.element then extra[#extra + 1] = { string.upper(Loot.ELEMENTS[item.element].name) .. " blast", Loot.ELEMENTS[item.element].color } end
    end
    local cw = 360
    local wrapped = {}
    for _, e in ipairs(extra) do
      for _, l in ipairs(S.wrap(e[1], 14, F.body, cw - 40)) do wrapped[#wrapped + 1] = { l, e[2], e[3] } end
    end
    local ch = 96 + #rows * 24 + #wrapped * 18 + 46
    local x = r.w / 2 + 90
    local y = math.max(140, math.min(r.h / 2 - ch / 2 - 10, r.h - 310 - ch))
    S.panel_box(x, y, cw, ch, { fill = Color.hex("#140c1c", 0.95), skew = 12 })
    -- Rarity header.
    Draw.slant(x + 4, y, cw - 4, 26, 12 * 26 / ch, rc)
    local kind_lbl = kind == "gun" and item.label or (kind == "shield" and "Shield" or "Grenade Mod")
    Draw.text(string.upper(rr.name .. " " .. kind_lbl), x + 22, y + 2, { size = 16, color = S.ink, font = F.display })
    Draw.text("LV " .. item.level, x + cw - 14, y + 2, { size = 16, color = S.ink, font = F.display, align = "right" })
    S.title(item.name, x + 20, y + 34, 26, rc, { outline = 2 })
    Draw.text(item.maker or "", x + 22, y + 68, { size = 13, color = S.dim, font = F.body })
    local ry = y + 92
    for _, row in ipairs(rows) do
      Draw.slant(x + 16, ry - 1, cw - 36, 21, 4, Color(1, 1, 1, 0.04))
      Draw.text(row[1], x + 24, ry, { size = 14, color = S.dim, font = F.display })
      Draw.text(row[4], x + cw - 56, ry - 1, { size = 17, color = S.paper, font = F.display, align = "right" })
      if row[3] then
        if row[2] > row[3] * 1.001 then arrow(x + cw - 36, ry + 10, true, S.cash)
        elseif row[2] < row[3] * 0.999 then arrow(x + cw - 36, ry + 10, false, S.hp) end
      end
      ry = ry + 24
    end
    ry = ry + 6
    for _, l in ipairs(wrapped) do
      Draw.text(l[1], x + 22, ry, { size = 14, color = l[2], font = l[3] and F.display or F.body })
      ry = ry + 18
    end
    local full = kind == "gun" and G.player.guns[4] ~= nil or kind ~= "gun"
    local label = kind == "gun" and (full and "SWAP FOR CURRENT GUN" or "PICK UP") or "EQUIP"
    S.key("E", x + cw - 30 - Draw.text_width(label, 15, F.display) - 28, y + ch - 32, 20)
    Draw.text(label, x + cw - 24, y + ch - 30, { size = 15, color = S.paper, font = F.display, align = "right" })
  end

  ---------------------------------------------------------------- frame
  function hud:_draw_ui(r)
    local dt = Game.real_delta or 0.016
    local p = G.player
    if not p then return end
    local t = Game.real_time
    self:draw_numbers(dt)
    self:draw_enemy_bars()
    self:draw_vignettes(r, dt, t)
    self:draw_crosshair(r, dt)
    self:draw_vitals(r, dt, t)
    self:draw_weapon(r, t)
    self:draw_top(r, t)
    if G.ui_open or G.state == "paused" then return end
    self:draw_focus(r)
    self:draw_dialogue(r, dt, t)
    self:draw_toasts(r, dt)
    self:draw_banners(r, dt, t)
    self:draw_ffyl(r, t)
    self:draw_hints(r)
  end
  return hud
end

------------------------------------------------------------------ shared menu backdrop
local function backdrop(r, a)
  Draw.rect(0, 0, r.w, r.h, Color(0.05, 0.02, 0.07, a or 0.6), 0)
  -- Diagonal hazard stripes along the bottom edge.
  for i = -2, math.ceil(r.w / 40) do
    local x = i * 40
    Draw.poly({ x, r.h - 10, x + 20, r.h - 10, x + 30, r.h, x + 10, r.h }, Color(1, 0.81, 0.29, 0.25))
  end
end

local function menu_button(text, on, opts)
  opts = opts or {}
  return StyledButton { text = text, w = opts.w or 320, h = opts.h or 50, size = opts.size or 22, on_pressed = on, sub = opts.sub, accent = opts.accent }
end

------------------------------------------------------------------ title
function Hud.title(on_play)
  local menu = Control { name = "Title", anchor = "full" }
  menu:add_child(VBox { anchor = "bottom_left", x = 80, y = -70, spacing = 16,
    menu_button("Play", on_play, { h = 58, size = 28, sub = "Nevada awaits. So does the Committee.", accent = S.green }),
    menu_button("Fullscreen", function() Game.set_fullscreen(not Game.is_fullscreen()) end),
    menu_button("Quit", function() Game.quit() end, { accent = S.hp }),
  })
  function menu:_draw_ui(r)
    local t = Game.real_time
    Draw.gradient(0, 0, r.w, r.h * 0.6, Color(0.1, 0.03, 0.12, 0.6), Color(0, 0, 0, 0))
    Draw.gradient(0, r.h * 0.45, r.w, r.h * 0.55, Color(0, 0, 0, 0), Color(0.05, 0.02, 0.06, 0.8))
    -- Logo.
    local x, y = 80, r.h * 0.1 + math.sin(t * 1.2) * 3
    S.title("CARL", x, y, 168, S.green, { font = F.display, outline = 9 })
    local s4 = 1 + math.sin(t * 3) * 0.04
    local bx = x + Draw.text_width("CARL", 168, F.display) + 20
    Draw.slant(bx + 8, y + 18, 150, 170, 26, Color(0, 0, 0, 0.5))
    Draw.slant(bx - 6, y + 4, 162, 178, 28, S.ink)
    Draw.slant(bx, y + 10, 150, 166, 26, S.yellow)
    S.title("4", bx + 88, y - 6, 176 * s4, S.ink, { align = "center", outline = 0 })
    S.tag("BY THE POWER OF NEVADA", x + 8, y + 196, S.paper, { size = 24 })
    Draw.text("There was no Carl 1, 2 or 3. The Sequel Committee skipped ahead.", x + 10, y + 244, { size = 17, color = S.dim, font = F.body, outline = 2, outline_color = S.ink })
    -- Carl himself, big, idling on the right.
    local meta = require("sprites.carl")
    if not menu._tex then menu._tex = Texture.load("sprites/carl.png", { nearest = true }) end
    local a = meta.anims["se_idle"]
    local fi = a.frames[math.floor(t * 6) % #a.frames + 1]
    local col, row = fi % meta.cols, math.floor(fi / meta.cols)
    local sc = math.floor(r.h / 72)
    local cw, ch = meta.w * sc, meta.h * sc
    local cx, cy = r.w - cw - 60, r.h - ch - 40
    Draw.rect(cx + cw * 0.18, cy + ch - sc * 4, cw * 0.6, sc * 4, Color(0, 0, 0, 0.35), sc * 2)
    Draw.image_region(menu._tex, cx, cy, cw, ch, col / meta.cols, row / meta.rows, (col + 1) / meta.cols, (row + 1) / meta.rows)
    local blink = (math.floor(t * 2) % 2 == 0) and 1 or 0.4
    Draw.text("PRESS ENTER", r.w / 2, r.h - 46, { size = 16, color = S.paper:with_alpha(blink), font = F.display, align = "center" })
  end
  return menu
end

------------------------------------------------------------------ pause
function Hud.pause(on_resume, on_skills)
  local menu = Control { name = "Pause", anchor = "full", visible = false }
  menu:add_child(VBox { anchor = "left", x = 90, y = 30, spacing = 14,
    menu_button("Resume", on_resume, { accent = S.green }),
    menu_button("Skills", on_skills, { sub = "Spend skill points" }),
    menu_button("Fullscreen", function() Game.set_fullscreen(not Game.is_fullscreen()) end),
    menu_button("Restart", function() Game.paused = false; Game.restart() end),
    menu_button("Quit", function() Game.quit() end, { accent = S.hp }),
  })
  function menu:_draw_ui(r)
    backdrop(r, 0.6)
    S.title("PAUSED", 90, r.h / 2 - 230, 72, S.yellow)
    -- Loadout summary on the right.
    local p = G.player
    if not p then return end
    local x, y, w = r.w - 470, r.h / 2 - 200, 400
    S.panel_box(x, y, w, 380, { accent = S.green })
    S.tag("LOADOUT", x + 18, y + 16, S.green, { size = 14 })
    local ly = y + 54
    for i = 1, 4 do
      local g = p.guns[i]
      if g then
        local rc = Loot.RARITY[g.rarity].color
        Draw.slant(x + 18, ly, 6, 30, 2, rc)
        Draw.text(g.name, x + 34, ly - 2, { size = 18, color = rc, font = F.display })
        Draw.text(g.maker .. "  ·  " .. g.label .. "  ·  " .. math.floor(g.dps) .. " DPS", x + 34, ly + 18, { size = 12, color = S.dim, font = F.body })
      else
        Draw.text(i .. "  —  empty slot", x + 34, ly + 4, { size = 14, color = S.mute, font = F.body })
      end
      ly = ly + 46
    end
    for _, it in ipairs({ p.shield_item, p.grenade_item }) do
      if it then
        local rc = Loot.RARITY[it.rarity].color
        Draw.slant(x + 18, ly, 6, 30, 2, rc)
        Draw.text(it.name, x + 34, ly - 2, { size = 18, color = rc, font = F.display })
        local sub = it.type == "shield" and (it.capacity .. " capacity  ·  " .. string.format("%.1fs delay", it.delay))
          or (it.damage .. " damage  ·  " .. it.kind)
        Draw.text((it.type == "shield" and "Shield  ·  " or "Grenade  ·  ") .. sub, x + 34, ly + 18, { size = 12, color = S.dim, font = F.body })
        ly = ly + 46
      end
    end
  end
  return menu
end

------------------------------------------------------------------ skills
function Hud.skills(on_close)
  local menu = Control { name = "Skills", anchor = "full", visible = false }
  local cards = {}
  for ti, tree in ipairs(Skills.TREES) do
    for si, sk in ipairs(tree.skills) do
      local b = StyledButton { text = sk.name, w = 330, h = 76, size = 20, accent = tree.color, sub = sk.desc }
      b.on_pressed = function()
        if Skills.buy(sk.id) then Audio.play(SFX.levelup, { volume = 0.35, pitch = 1.5 })
        else Audio.play(SFX.empty, { volume = 0.4 }) end
      end
      b._skill, b._tree = sk, ti
      cards[#cards + 1] = b
    end
  end
  local cols = HBox { anchor = "center", y = 30, spacing = 34 }
  menu:add_child(cols)
  for ti = 1, 3 do
    local vb = VBox { spacing = 18 }
    cols:add_child(vb)
    for _, b in ipairs(cards) do if b._tree == ti then vb:add_child(b) end end
  end
  menu:add_child(VBox { anchor = "bottom", y = -40, menu_button("Done", on_close, { w = 260, accent = S.green }) })
  function menu:_draw_ui(r)
    backdrop(r, 0.72)
    S.title("SKILLS", r.w / 2, 40, 64, S.yellow, { align = "center" })
    S.tag(G.skill_points .. " POINT" .. (G.skill_points == 1 and "" or "S") .. " TO SPEND", r.w / 2, 120, G.skill_points > 0 and S.green or S.mute, { size = 16, align = "center" })
    for _, b in ipairs(cards) do
      local rr = b:rect()
      if rr then
        if b._skill == Skills.TREES[b._tree].skills[1] then
          S.tag(Skills.TREES[b._tree].name, rr.x, rr.y - 40, Skills.TREES[b._tree].color, { size = 16 })
        end
        local rank = Skills.rank(b._skill.id)
        b.disabled = not Skills.can_buy(b._skill.id) and rank < Skills.MAX_RANK
        b.right_text = rank .. "/" .. Skills.MAX_RANK
      end
    end
    -- ABDUCT summary.
    Draw.text(string.format("ABDUCT  ·  cooldown %ds  ·  abducted take +%d%%  ·  slam +%d%%", math.floor(Skills.abduct_cooldown()), math.floor((Skills.probe() - 1) * 100), Skills.rank("slam") * 25),
      r.w / 2, r.h - 150, { size = 15, color = S.green, font = F.display, align = "center", outline = 2, outline_color = S.ink })
  end
  return menu
end

------------------------------------------------------------------ shop
function Hud.shop(on_close)
  local menu = Control { name = "Shop", anchor = "full", visible = false }
  local vb = VBox { anchor = "center", y = 40, spacing = 12 }
  menu:add_child(vb)
  local function price_heal() return 20 * G.level end
  local function price_gun() return 60 * G.level end
  local function price_lucky() return 240 * G.level end
  local function price_shield() return 90 * G.level end
  local function price_nade() return 80 * G.level end
  local function price_refill() return 12 * G.level end
  local b_heal, b_gun, b_lucky, b_shield, b_nade, b_refill, b_sell
  local function refresh()
    local p = G.player
    local g = p:gun()
    b_heal.right_text = "$" .. price_heal()
    b_gun.right_text = "$" .. price_gun()
    b_lucky.right_text = "$" .. price_lucky()
    b_shield.right_text = "$" .. price_shield()
    b_nade.right_text = "$" .. price_nade()
    b_refill.right_text = "$" .. price_refill()
    b_sell.text = g and p.guns[2] and ("Sell " .. g.name) or "Can't sell your only gun"
    b_sell.right_text = g and p.guns[2] and ("+$" .. Loot.value(g)) or nil
    b_heal.disabled = G.cash < price_heal() or p.hp >= p.max_hp
    b_gun.disabled = G.cash < price_gun()
    b_lucky.disabled = G.cash < price_lucky()
    b_shield.disabled = G.cash < price_shield()
    b_nade.disabled = G.cash < price_nade()
    b_refill.disabled = G.cash < price_refill() or G.grenades >= p:max_grenades()
    b_sell.disabled = not p.guns[2]
  end
  local function buy(cost)
    G.cash = G.cash - cost
    Audio.play(SFX.coin, { volume = 0.6, pitch = 0.8 })
  end
  local function spit(node) G.root:add_child(node) end
  local W = 520
  b_heal = StyledButton { text = "Prop Pills", sub = "Full heal. Side effects include being a prop.", w = W, h = 60, accent = S.pink, on_pressed = function() buy(price_heal()); G.player.hp = G.player.max_hp; refresh() end }
  b_gun = StyledButton { text = "Random gun", sub = "Level " .. "?" .. ", any rarity", w = W, h = 60, on_pressed = function()
    buy(price_gun())
    spit(Loot.gun_pickup(G.shop_pos, Loot.roll_gun(G.level, { luck = 0.3 }), G.shop_dir * 4 + Vec3(0, 4, 0)))
    refresh()
  end }
  b_lucky = StyledButton { text = "Lucky gun", sub = "Rare or better, guaranteed", w = W, h = 60, accent = Color.hex("#c77dff"), on_pressed = function()
    buy(price_lucky())
    spit(Loot.gun_pickup(G.shop_pos, Loot.roll_gun(G.level, { min_rarity = 3, luck = 1.5 }), G.shop_dir * 4 + Vec3(0, 4, 0)))
    refresh()
  end }
  b_shield = StyledButton { text = "Shield", sub = "A fresh shield at your level", w = W, h = 60, accent = S.shield, on_pressed = function()
    buy(price_shield())
    spit(require("gear").item_pickup(G.shop_pos, Loot.roll_item(G.level, { kind = "shield", luck = 0.5 }), G.shop_dir * 4 + Vec3(0, 4, 0)))
    refresh()
  end }
  b_nade = StyledButton { text = "Grenade mod", sub = "Standard, MIRV, singularity or transfusion", w = W, h = 60, accent = S.orange, on_pressed = function()
    buy(price_nade())
    spit(require("gear").item_pickup(G.shop_pos, Loot.roll_item(G.level, { kind = "grenade", luck = 0.5 }), G.shop_dir * 4 + Vec3(0, 4, 0)))
    refresh()
  end }
  b_refill = StyledButton { text = "Grenade refill", sub = "Top up to full", w = W, h = 60, accent = S.yellow, on_pressed = function()
    buy(price_refill()); G.grenades = G.player:max_grenades(); refresh()
  end }
  b_sell = StyledButton { w = W, h = 50, accent = S.cash, on_pressed = function()
    local p = G.player
    local g = p:gun()
    G.cash = G.cash + Loot.value(g)
    Audio.play(SFX.coin, { volume = 0.6 })
    table.remove(p.guns, p.slot)
    p.slot = math.min(p.slot, #p.guns)
    p:equip(p.slot)
    refresh()
  end }
  for _, b in ipairs({ b_heal, b_gun, b_lucky, b_shield, b_nade, b_refill, b_sell }) do vb:add_child(b) end
  vb:add_child(menu_button("Close", on_close, { w = W, h = 46, accent = S.hp }))
  menu.refresh = function()
    b_gun.sub = "Level " .. G.level .. ", any rarity"
    refresh()
  end
  function menu:_draw_ui(r)
    backdrop(r, 0.5)
    S.title("PROP PILLS VENDING", r.w / 2, r.h / 2 - 330, 46, S.pink, { align = "center" })
    Draw.text("\"Ask your doctor if Prop Pills are a prop.\"", r.w / 2, r.h / 2 - 274, { size = 16, color = S.dim, font = F.body, align = "center" })
    S.title("$" .. G.cash, r.w / 2 + 300, r.h / 2 - 240, 34, S.cash)
  end
  return menu
end

------------------------------------------------------------------ death + victory
function Hud.death()
  local c = Control { name = "Death", anchor = "full", visible = false, opacity = 0 }
  function c:_draw_ui(r)
    Draw.rect(0, 0, r.w, r.h, Color(0.18, 0, 0.04, 0.6), 0)
    local y = r.h * 0.34
    -- A slanted "stamp".
    Draw.slant(r.w / 2 - 330, y - 14, 660, 108, 24, S.ink)
    Draw.slant(r.w / 2 - 322, y - 8, 644, 96, 22, S.hp)
    S.title("PACKAGE LOST", r.w / 2, y, 72, S.paper, { align = "center", outline = 4 })
    Draw.text("Prop Pills Re-Delivery is on its way.   -$" .. (G.death_fee or 0), r.w / 2, y + 112, { size = 20, color = S.paper, font = F.display, align = "center", outline = 2, outline_color = S.ink })
  end
  return c
end

function Hud.victory(on_again)
  local c = Control { name = "Victory", anchor = "full", visible = false, opacity = 0 }
  c:add_child(VBox { anchor = "bottom", y = -50, spacing = 12,
    menu_button("Keep looting", on_again, { accent = S.green }),
    menu_button("Quit", function() Game.quit() end, { accent = S.hp }),
  })
  function c:_draw_ui(r)
    backdrop(r, 0.65)
    local cx = r.w / 2
    S.title("CARL 4", cx, r.h * 0.07, 96, S.green, { align = "center" })
    S.tag("THE END  (STILL IN TRANSIT)", cx, r.h * 0.07 + 110, S.yellow, { size = 22, align = "center" })
    local s = G.stats
    local secs = math.floor(Game.time - (G.started or 0))
    local lines = {
      { "TIME", string.format("%d:%02d", math.floor(secs / 60), secs % 60) },
      { "LEVEL", tostring(G.level) },
      { "WHITE SUITS AND FRIENDS", tostring(s.kills) },
      { "GUNS PICKED UP", tostring(s.guns) },
      { "LEGENDARIES", tostring(s.legendaries) },
      { "LOCKBOXES OPENED", tostring(s.chests) },
      { "CASH COLLECTED", "$" .. s.cash },
    }
    local w = 520
    local y0 = r.h * 0.33
    S.panel_box(cx - w / 2, y0 - 16, w, #lines * 34 + 30, { accent = S.green })
    for i, l in ipairs(lines) do
      local y = y0 + (i - 1) * 34
      Draw.text(l[1], cx - w / 2 + 30, y, { size = 18, color = S.dim, font = F.display })
      Draw.text(l[2], cx + w / 2 - 30, y - 2, { size = 22, color = S.paper, font = F.display, align = "right" })
    end
    Draw.text("The Sequel Committee has already greenlit CARL 5.", cx, y0 + #lines * 34 + 28, { size = 16, color = S.dim, font = F.body, align = "center" })
  end
  return c
end

return Hud
