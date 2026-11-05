package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
H.load("DontDoThat/Intercepts/TrainerFilter.lua", ns)
local Filter = ns.TrainerFilter

-- A menu description with children, like Blizzard's Menu API produces.
local function node(text, children)
  local n = { text = text, children = children or {}, added = {} }
  function n:GetText() return self.text end
  function n:HasElements() return #self.children > 0 end
  function n:EnumerateElementDescriptions()
    local i = 0
    return function() i = i + 1; if self.children[i] then return i, self.children[i] end end
  end
  function n:CreateCheckbox(label) self.added[#self.added + 1] = label; return n end
  return n
end

test("the entry goes into the Filters submenu, found by its label", function()
  local filters = node("Filters", { node("Available"), node("Unavailable") })
  local root = node(nil, { node("Categorize"), filters })
  eq(Filter.FiltersMenu({ FILTERS = "Filters" }, root), filters)
end)

test("without a label match, the first element with children is used", function()
  local filters = node("Filtres", { node("Disponible") })
  local root = node(nil, { node("Categorize"), filters })
  eq(Filter.FiltersMenu({}, root), filters)
end)

test("a flat menu (Classic Era) takes the entry at its top level", function()
  local root = node(nil, { node("Available"), node("Unavailable") })
  eq(Filter.FiltersMenu({ FILTERS = "Filters" }, root), root)
end)

test("a menu that cannot be enumerated falls back to the menu itself", function()
  local root = { CreateCheckbox = function() end }
  eq(Filter.FiltersMenu({}, root), root)
end)
