-- Minimal single-inheritance classes.
--   local Player = CharacterBody3D:extend("Player")
--   function Player:_ready() ... end
--   local p = Player{ position = Vec3(0, 2, 0) }

local function make_class(name, parent)
  local cls = { __name = name, super = parent }
  cls.__index = cls
  cls.__tostring = function(self) return name .. (self.name and ("(" .. tostring(self.name) .. ")") or "") end

  function cls.new(props)
    local obj = setmetatable({}, cls)
    if obj._init then obj:_init(props or {}) end
    return obj
  end

  function cls:extend(child_name)
    return make_class(child_name, self)
  end

  function cls:is(other)
    local c = getmetatable(self)
    while c do
      if c == other then return true end
      c = c.super
    end
    return false
  end

  setmetatable(cls, {
    __index = parent,
    __call = function(c, props) return c.new(props) end,
    __tostring = function() return "class " .. name end,
  })
  return cls
end

function class(name, parent)
  return make_class(name, parent)
end
