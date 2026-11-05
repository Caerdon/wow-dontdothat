package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
H.load("DontDoThat/Intercepts/TrainerFilter.lua", ns)
local Filter = ns.TrainerFilter

-- Tree nodes shaped like Forever's: data, children, a parent, and Remove on the parent.
local function node(data, children)
  local n = { data = data, children = children or {} }
  function n:GetData() return self.data end
  function n:GetNodes() return self.children end
  function n:GetParent() return self.parent end
  function n:Remove(child)
    for i, c in ipairs(self.children) do if c == child then table.remove(self.children, i); child.parent = nil; return end end
  end
  for _, c in ipairs(n.children) do c.parent = n end
  return n
end
local function service(i) return node({ skillIndex = i, displayIndex = i }) end
-- Every node below root in the order the ScrollBox enumerates them.
local function flatten(root, out)
  out = out or {}
  for _, c in ipairs(root.children) do out[#out + 1] = c; flatten(c, out) end
  return out
end
local function indexes(parent)
  local out = {}
  for _, c in ipairs(parent.children) do out[#out + 1] = c.data and c.data.skillIndex or "category" end
  return out
end

test("hidden services are removed from a flat tree, the rest keep their indexes", function()
  local root = node(nil, { service(1), service(2), service(3), service(4) })
  eq(Filter.PruneNodes(flatten(root), { [2] = true, [4] = true }), 2)
  eq(indexes(root), { 1, 3 })
end)

test("a category left empty goes, one with a service left stays", function()
  local a = node({ name = "A" }, { service(1), service(2) })
  local b = node({ name = "B" }, { service(3) })
  local root = node(nil, { a, b })
  Filter.PruneNodes(flatten(root), { [1] = true, [2] = true })
  eq(#root.children, 1)
  eq(root.children[1] == b, true)
end)

test("nothing hidden changes nothing", function()
  local root = node(nil, { service(1), node({}, { service(2) }) })
  eq(Filter.PruneNodes(flatten(root), {}), 0)
  eq(#root.children, 2)
end)

test("RenderModern hides the rows the verdicts defer, through the ScrollBox's own nodes", function()
  local root = node(nil, { service(1), service(2), service(3) })
  local updated
  local box = {
    ForEachElementData = function(_, fn) for _, n in ipairs(flatten(root)) do fn(n) end end,
    FullUpdate = function() updated = true end,
  }
  local frame = { ScrollBox = box }
  local rows = { { index = 1 }, { index = 2 }, { index = 3 } }
  Filter.RenderModern({}, frame, { visible = { rows[1], rows[3] } }, rows)
  eq(indexes(root), { 1, 3 })
  eq(frame.DontDoThatFiltered, true)
  eq(updated, true)
end)

test("RenderModern raises when the list cannot be enumerated, so the caller degrades", function()
  local ok = pcall(Filter.RenderModern, {}, { ScrollBox = {} }, { visible = {} }, {})
  eq(ok, false)
end)

test("a node with no parent to remove it raises", function()
  local orphan = service(1)
  local ok = pcall(Filter.PruneNodes, { orphan }, { [1] = true })
  eq(ok, false)
end)
