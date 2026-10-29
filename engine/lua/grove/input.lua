-- Input: named actions over keyboard, mouse and gamepad.
--   Input.bind("fire", { "mouse1", "F", "pad_rt" })
--   if Input.pressed("jump") then ... end
--   local x, y = Input.vector("move_left", "move_right", "move_forward", "move_back")
local ffi = require("ffi")

Key = {
  SPACE = 32, APOSTROPHE = 39, COMMA = 44, MINUS = 45, PERIOD = 46, SLASH = 47,
  ["0"] = 48, ["1"] = 49, ["2"] = 50, ["3"] = 51, ["4"] = 52, ["5"] = 53, ["6"] = 54, ["7"] = 55, ["8"] = 56, ["9"] = 57,
  ESCAPE = 256, ENTER = 257, TAB = 258, BACKSPACE = 259, INSERT = 260, DELETE = 261,
  RIGHT = 262, LEFT = 263, DOWN = 264, UP = 265, PAGE_UP = 266, PAGE_DOWN = 267, HOME = 268, END = 269,
  F1 = 290, F2 = 291, F3 = 292, F4 = 293, F5 = 294, F6 = 295, F7 = 296, F8 = 297, F9 = 298, F10 = 299, F11 = 300, F12 = 301,
  LSHIFT = 340, LCTRL = 341, LALT = 342, RSHIFT = 344, RCTRL = 345, RALT = 346,
}
for c = string.byte("A"), string.byte("Z") do Key[string.char(c)] = c end

local PAD_BUTTONS = { a = 0, b = 1, x = 2, y = 3, lb = 4, rb = 5, back = 6, start = 7, guide = 8, ls = 9, rs = 10,
  up = 11, right = 12, down = 13, left = 14 }
local PAD_AXES = { lx = 0, ly = 1, rx = 2, ry = 3, lt = 4, rt = 5 }

Input = { deadzone = 0.2, mouse_sensitivity = 1 }
local actions = {}      -- name -> list of parsed bindings
local state = {}        -- name -> { down, pressed, released, strength }
local forced = {}       -- simulated actions (for demos/tests)

-- Binding strings: "SPACE", "W", "mouse1" (left) / "mouse2" (right) / "mouse3",
-- "pad_a", "pad_start", "pad_lx-" / "pad_lx+" (stick direction), "pad_rt" (trigger).
local function parse(b)
  local m = b:match("^mouse(%d)$")
  if m then return { kind = "mouse", code = tonumber(m) - 1 } end
  local pb = b:match("^pad_(%a+)$")
  if pb and PAD_BUTTONS[pb] then return { kind = "padbtn", code = PAD_BUTTONS[pb] } end
  local ax, sign = b:match("^pad_(%a+)([%+%-]?)$")
  if ax and PAD_AXES[ax] then
    local trig = ax == "lt" or ax == "rt"
    return { kind = "axis", code = PAD_AXES[ax], sign = sign == "-" and -1 or 1, trigger = trig }
  end
  local k = Key[b:upper()]
  assert(k, "unknown input binding '" .. b .. "'")
  return { kind = "key", code = k }
end

function Input.bind(action, bindings)
  local list = {}
  for _, b in ipairs(bindings) do list[#list + 1] = parse(b) end
  actions[action] = list
  state[action] = state[action] or { down = false, pressed = false, released = false, strength = 0 }
end

function Input.add_binding(action, b)
  if not actions[action] then Input.bind(action, {}) end
  table.insert(actions[action], parse(b))
end

local function binding_strength(b)
  if b.kind == "key" then return C.gr_key_down(b.code) == 1 and 1 or 0
  elseif b.kind == "mouse" then return C.gr_mouse_down(b.code) == 1 and 1 or 0
  elseif b.kind == "padbtn" then
    for p = 0, 3 do if C.gr_gamepad_button(p, b.code) == 1 then return 1 end end
    return 0
  elseif b.kind == "axis" then
    local best = 0
    for p = 0, 3 do
      if C.gr_gamepad_connected(p) == 1 then
        local v = C.gr_gamepad_axis(p, b.code)
        if b.trigger then v = (v + 1) / 2 else v = v * b.sign end
        if v > best then best = v end
      end
    end
    if best < Input.deadzone then return 0 end
    return (best - Input.deadzone) / (1 - Input.deadzone)
  end
  return 0
end

function Input._update()
  for name, list in pairs(actions) do
    local s = 0
    for _, b in ipairs(list) do
      local v = binding_strength(b)
      if v > s then s = v end
    end
    if forced[name] ~= nil then s = forced[name] and 1 or 0 end
    local st = state[name]
    local down = s > 0.5
    st.pressed = down and not st.down
    st.released = st.down and not down
    st.down = down
    st.strength = s
  end
  local mx, my = ffi.new("float[1]"), ffi.new("float[1]")
  C.gr_mouse_delta(mx, my)
  Input._mdx, Input._mdy = mx[0], my[0]
  C.gr_mouse_pos(mx, my)
  Input._mx, Input._my = mx[0], my[0]
end

function Input.down(action) local s = state[action]; return s ~= nil and s.down end
function Input.pressed(action) local s = state[action]; return s ~= nil and s.pressed end
function Input.released(action) local s = state[action]; return s ~= nil and s.released end
function Input.strength(action) local s = state[action]; return s and s.strength or 0 end
function Input.axis(neg, pos) return Input.strength(pos) - Input.strength(neg) end

-- 2D movement vector, length clamped to 1. Returns x (right) and y (forward).
function Input.vector(left, right, forward, back)
  local x = Input.strength(right) - Input.strength(left)
  local y = Input.strength(forward) - Input.strength(back)
  local l = math.sqrt(x * x + y * y)
  if l > 1 then x, y = x / l, y / l end
  return x, y
end

-- Raw device access.
function Input.key_down(name) return C.gr_key_down(Key[name] or name) == 1 end
function Input.key_pressed(name) return C.gr_key_pressed(Key[name] or name) == 1 end
function Input.mouse_delta() return Input._mdx or 0, Input._mdy or 0 end
function Input.mouse_position() return Input._mx or 0, Input._my or 0 end
function Input.mouse_pressed(b) return C.gr_mouse_pressed((b or 1) - 1) == 1 end
function Input.mouse_down(b) return C.gr_mouse_down((b or 1) - 1) == 1 end
function Input.mouse_wheel() return C.gr_mouse_wheel() end
function Input.capture_mouse(on) C.gr_set_mouse_captured(on and 1 or 0) end
function Input.is_mouse_captured() return C.gr_get_mouse_captured() == 1 end
-- Right stick for camera look, already dead-zoned.
function Input.look_stick()
  local x, y = 0, 0
  for p = 0, 3 do
    if C.gr_gamepad_connected(p) == 1 then
      x, y = C.gr_gamepad_axis(p, 2), C.gr_gamepad_axis(p, 3)
      break
    end
  end
  if math.abs(x) < Input.deadzone then x = 0 end
  if math.abs(y) < Input.deadzone then y = 0 end
  return x, y
end

-- Force an action on/off (nil releases control back to the devices). Handy for scripted demos.
function Input.simulate(action, down) forced[action] = down end

-- Default action map; games can rebind or add to it.
Input.bind("move_left", { "A", "LEFT", "pad_lx-", "pad_left" })
Input.bind("move_right", { "D", "RIGHT", "pad_lx+", "pad_right" })
Input.bind("move_forward", { "W", "UP", "pad_ly-", "pad_up" })
Input.bind("move_back", { "S", "DOWN", "pad_ly+", "pad_down" })
Input.bind("jump", { "SPACE", "pad_a" })
Input.bind("sprint", { "LSHIFT", "pad_ls", "pad_lb" })
Input.bind("interact", { "E", "pad_x" })
Input.bind("fire", { "mouse1", "pad_rt" })
Input.bind("aim", { "mouse2", "pad_lt" })
Input.bind("pause", { "ESCAPE", "pad_start" })
Input.bind("ui_accept", { "ENTER", "pad_a" })
Input.bind("ui_cancel", { "ESCAPE", "pad_b" })
Input.bind("ui_up", { "UP", "W", "pad_up" })
Input.bind("ui_down", { "DOWN", "S", "pad_down" })
Input.bind("debug", { "F3" })
