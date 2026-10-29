-- Save: persist plain Lua tables (numbers, strings, booleans, nested tables).
-- Files live in ~/.local/share/grove/<game folder name>/<name>.save (on Windows: %APPDATA%/grove/<game>/).
Save = {}

local function dir()
  local game = GROVE_GAME_DIR:match("([^/]+)/*$") or "game"
  if jit.os == "Windows" then
    local root = (os.getenv("APPDATA") or os.getenv("USERPROFILE") or "."):gsub("\\", "/")
    local base = root .. "/grove/" .. game
    os.execute('mkdir "' .. (root .. "/grove"):gsub("/", "\\") .. '" 2>nul')
    os.execute('mkdir "' .. base:gsub("/", "\\") .. '" 2>nul')
    return base
  end
  local base = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/grove/" .. game
  os.execute('mkdir -p "' .. base .. '"')
  return base
end

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "table" then
    local parts = {}
    local inner = indent .. "  "
    for k, val in pairs(v) do
      local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. serialize(k) .. "]")
      parts[#parts + 1] = inner .. key .. " = " .. serialize(val, inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  elseif t == "cdata" and Vec3.is(v) then return string.format("{ x = %.17g, y = %.17g, z = %.17g }", v.x, v.y, v.z)
  end
  return "nil"
end

function Save.write(name, data)
  local path = dir() .. "/" .. name .. ".save"
  local f = assert(io.open(path, "w"))
  f:write("return " .. serialize(data))
  f:close()
  return path
end

function Save.read(name)
  local f = io.open(dir() .. "/" .. name .. ".save", "r")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  local chunk = loadstring(src)
  if not chunk then return nil end
  setfenv(chunk, {})
  local ok, data = pcall(chunk)
  return ok and data or nil
end

function Save.exists(name)
  local f = io.open(dir() .. "/" .. name .. ".save", "r")
  if f then f:close() return true end
  return false
end
