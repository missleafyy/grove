-- Node: the base of the scene tree. Lifecycle, children, groups and signals.
--
-- Script callbacks (define on a subclass or pass in the constructor):
--   _ready()               once, after the node and its children entered the tree
--   _process(dt)           every frame
--   _physics_process(dt)   every physics step (60 Hz or faster)
--   _enter_tree() / _exit_tree()
--
-- Constructor sugar: array entries become children, `groups` adds groups,
-- `on = { signal = fn }` connects signals, every other key is assigned.
--   Node3D{ name = "Pivot", position = Vec3(0, 1, 0), MeshInstance3D{ mesh = m } }

Node = class("Node")

function Node:_init(props)
  self:_setup()
  self:set(props)
end

function Node:_setup()
  self.name = getmetatable(self).__name
  self.children = {}
  self.process_mode = "inherit"   -- "inherit" | "always" | "pausable" | "disabled"
end

function Node:set(props)
  for k, v in pairs(props) do
    if type(k) ~= "number" then
      if k == "children" then
        for _, c in ipairs(v) do self:add_child(c) end
      elseif k == "groups" then
        for _, g in ipairs(v) do self:add_to_group(g) end
      elseif k == "on" then
        for sig, fn in pairs(v) do self:connect(sig, fn) end
      else
        self[k] = v
      end
    end
  end
  for _, c in ipairs(props) do self:add_child(c) end
  return self
end

------------------------------------------------------------------ hierarchy
function Node:add_child(child)
  assert(type(child) == "table" and child.children, "add_child expects a Node")
  if child.parent then child.parent:remove_child(child) end
  child.parent = self
  local ch = self.children
  ch[#ch + 1] = child
  if self.inside_tree then
    child:_tree_enter()
    child:_tree_ready()
  end
  return child
end

function Node:remove_child(child)
  local ch = self.children
  for i = 1, #ch do
    if ch[i] == child then
      table.remove(ch, i)
      if child.inside_tree then child:_tree_exit() end
      child.parent = nil
      return child
    end
  end
end

function Node:reparent(new_parent, keep_global)
  local gp, gr
  if keep_global and self.global_position then gp, gr = self:global_position(), self:global_rotation() end
  -- Move without the full exit/enter cycle so physics bodies and resources survive.
  local old = self.parent
  if old then
    for i, c in ipairs(old.children) do if c == self then table.remove(old.children, i) break end end
  end
  self.parent = new_parent
  new_parent.children[#new_parent.children + 1] = self
  if gp then self:set_global_position(gp); self:set_global_rotation(gr) end
end

function Node:_tree_enter()
  self.inside_tree = true
  Game._node_entered(self)
  if self.__enter then self:__enter() end
  if self._enter_tree then self:_enter_tree() end
  local ch = self.children
  for i = 1, #ch do ch[i]:_tree_enter() end
end

function Node:_tree_ready()
  local ch = self.children
  for i = 1, #ch do ch[i]:_tree_ready() end
  if not self._is_ready then
    self._is_ready = true
    if self._ready then self:_ready() end
    self:emit("ready")
  end
end

function Node:_tree_exit()
  local ch = self.children
  for i = #ch, 1, -1 do ch[i]:_tree_exit() end
  if self._exit_tree then self:_exit_tree() end
  if self.__exit then self:__exit() end
  self.inside_tree = false
  Game._node_exited(self)
end

-- Deferred removal at the end of the frame (safe to call from callbacks).
function Node:queue_free()
  if self._queued then return end
  self._queued = true
  Game._free_queue[#Game._free_queue + 1] = self
end

function Node:free()
  self._queued = true
  self.freed = true
  if self.parent then self.parent:remove_child(self) elseif self.inside_tree then self:_tree_exit() end
end

function Node:is_valid() return not self._queued and not self.freed end

function Node:get_children() return self.children end
function Node:child(i) return self.children[i] end

-- get("Body/Head") looks up by child names; ".." goes to the parent.
function Node:get(path)
  local node = self
  for part in path:gmatch("[^/]+") do
    if part == ".." then node = node.parent
    else
      local found
      for _, c in ipairs(node.children) do if c.name == part then found = c break end end
      node = found
    end
    if not node then return nil end
  end
  return node
end

-- Depth-first search by name (string) or by class.
function Node:find(what)
  for _, c in ipairs(self.children) do
    if (type(what) == "string" and c.name == what) or (type(what) == "table" and c:is(what)) then return c end
    local r = c:find(what)
    if r then return r end
  end
end

function Node:find_all(what, out)
  out = out or {}
  for _, c in ipairs(self.children) do
    if (type(what) == "string" and c.name == what) or (type(what) == "table" and c:is(what)) then out[#out + 1] = c end
    c:find_all(what, out)
  end
  return out
end

function Node:ancestor(cls)
  local p = self.parent
  while p do
    if p:is(cls) then return p end
    p = p.parent
  end
end

------------------------------------------------------------------ groups
function Node:add_to_group(g)
  self.groups = self.groups or {}
  self.groups[g] = true
  if self.inside_tree then Game._group_add(g, self) end
end

function Node:remove_from_group(g)
  if self.groups then self.groups[g] = nil end
  Game._group_remove(g, self)
end

function Node:is_in_group(g) return self.groups ~= nil and self.groups[g] == true end

------------------------------------------------------------------ signals
function Node:connect(sig, fn)
  self._signals = self._signals or {}
  local list = self._signals[sig]
  if not list then list = {}; self._signals[sig] = list end
  list[#list + 1] = fn
  return fn
end

function Node:connect_once(sig, fn)
  local wrapper
  wrapper = function(...)
    self:disconnect(sig, wrapper)
    return fn(...)
  end
  return self:connect(sig, wrapper)
end

function Node:disconnect(sig, fn)
  local list = self._signals and self._signals[sig]
  if not list then return end
  for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
end

function Node:has_listeners(sig)
  local list = self._signals and self._signals[sig]
  return list ~= nil and #list > 0
end

function Node:emit(sig, ...)
  local list = self._signals and self._signals[sig]
  if not list then return end
  -- Copy so listeners may disconnect themselves while we iterate.
  local n = #list
  if n == 1 then return list[1](...) end
  local copy = { unpack(list, 1, n) }
  for i = 1, n do copy[i](...) end
end

------------------------------------------------------------------ helpers
-- Runs fn as a coroutine owned by this node: it stops when the node is freed.
function Node:spawn(fn, ...)
  return Game.spawn(fn, self, ...)
end

function Node:print_tree(indent)
  indent = indent or ""
  print(indent .. tostring(self))
  for _, c in ipairs(self.children) do c:print_tree(indent .. "  ") end
end
