-- Grove boot: loads the C API, the engine library, then the game's main.lua.
local ffi = require("ffi")

package.path = GROVE_ENGINE_DIR .. "/lua/?.lua;" .. GROVE_GAME_DIR .. "/?.lua;" .. GROVE_GAME_DIR .. "/?/init.lua;" .. package.path

-- The C API header is shared with the engine; strip comments before handing it to the FFI.
do
  local f = assert(io.open(GROVE_ENGINE_DIR .. "/api.h", "r"))
  local src = f:read("*a")
  f:close()
  src = src:gsub("/%*.-%*/", "")
  ffi.cdef(src)
end

C = ffi.C

-- Engine modules install their public names as globals (Node3D, Vec3, Input, ...).
require("grove.class")
require("grove.math3d")
require("grove.node")
require("grove.resources")
require("grove.nodes3d")
require("grove.physics")
require("grove.audio")
require("grove.input")
require("grove.tween")
require("grove.ui")
require("grove.save")
require("grove.debug")
require("grove.game")

local main = GROVE_GAME_DIR .. "/main.lua"
local chunk, err = loadfile(main)
if not chunk then error(err, 0) end
chunk()
