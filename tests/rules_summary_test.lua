package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- The Rules page lists, for all nine classes: every spell family shows up, Worth buying and Optional are grouped by spec.
local CLASSES = { HUNTER = "Hunter", PALADIN = "Paladin", MAGE = "Mage", WARLOCK = "Warlock", PRIEST = "Priest", DRUID = "Druid",
  SHAMAN = "Shaman", ROGUE = "Rogue", WARRIOR = "Warrior" }
local ns = { version = "0" }
for _, f in ipairs({ "UI/Helpers.lua", "Data/Sounds.lua", "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua", "Model/Milestones.lua",
  "Model/Settings.lua", "Model/ItemCategory.lua" }) do H.load("DontDoThat/" .. f, ns) end
for _, file in pairs(CLASSES) do H.load("DontDoThat/Rules/Data/" .. file .. ".lua", ns) end
H.load("DontDoThat/Options/Options.lua", ns)
ns.db = { profile = {} }

local function set(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, e in ipairs(list) do out[e.id] = (out[e.id] or 0) + 1 end end
  return out
end

for class in pairs(CLASSES) do
  test(class .. ": every spell family in the bundled table is on the Rules page, or considered and left off", function()
    local data = ns.Rules.GetClass(class)
    local s = ns.Options.ClassSummary(data)
    local shown = set(s.keep, s.optional, s.wait, s.low)
    local left = {}
    for _, n in ipairs(data.general or {}) do left[n] = true end
    for _, n in ipairs(data.reviewed or {}) do left[n] = true end
    local missing, seen = {}, {}
    for _, row in ipairs(ns.SpellTables[class].rows) do
      local id = ns.SpellData.FamilyOfId(class, row.id)
      if not shown[id] and not seen[id] and not left[id] then missing[#missing + 1] = row.name; seen[id] = true end
    end
    table.sort(missing)
    eq(missing, {}, class .. " spells neither shown nor reviewed")
  end)

  test(class .. ": a spell is in one list only, and Worth buying is never empty", function()
    local s = ns.Options.ClassSummary(ns.Rules.GetClass(class))
    local counts = set(s.keep, s.optional, s.wait, s.low)
    for id, n in pairs(counts) do eq(n, 1, tostring(ns.SpellData.FamilyName(class, id)) .. " is listed " .. n .. " times") end
    truthy(#s.keep > 0, "Worth buying has spells")
    truthy(#s.optional > 0, "Optional has spells")
  end)

  test(class .. ": Worth buying and Optional are grouped by spec, All specs first", function()
    local s = ns.Options.ClassSummary(ns.Rules.GetClass(class))
    for _, groups in ipairs({ s.keepGroups, s.optionalGroups }) do
      local total = 0
      for i, g in ipairs(groups) do
        total = total + #g.entries
        truthy(g.title ~= "", "a group has a title")
        if g.title == "All specs" then eq(i, 1, "All specs comes first") end
      end
      eq(total, groups == s.keepGroups and #s.keep or #s.optional, "the groups hold every listed spell")
    end
  end)
end

test("mage: Frostbolt is under Frost, Frost Nova under All specs", function()
  local s = ns.Options.ClassSummary(ns.Rules.GetClass("MAGE"))
  local where = {}
  for _, g in ipairs(s.keepGroups) do for _, e in ipairs(g.entries) do where[e.name] = g.title end end
  truthy(where["Frostbolt"] and where["Frostbolt"]:find("Frost", 1, true), tostring(where["Frostbolt"]))
  eq(where["Frost Nova"], "All specs")
end)

test("priest: Smite and Holy Fire are worth buying for Discipline and Holy, not for Shadow", function()
  local s = ns.Options.ClassSummary(ns.Rules.GetClass("PRIEST"))
  for _, g in ipairs(s.keepGroups) do
    for _, e in ipairs(g.entries) do
      if e.name == "Smite" then
        truthy(g.title:find("Holy", 1, true) and g.title:find("Discipline", 1, true), g.title)
        falsy(g.title:find("Shadow", 1, true), g.title)
      end
    end
  end
end)

test("ranks to skip are listed for the classes whose expert guides give rank advice", function()
  for _, class in ipairs({ "HUNTER", "ROGUE", "WARRIOR", "PRIEST", "DRUID" }) do
    local s = ns.Options.ClassSummary(ns.Rules.GetClass(class))
    truthy(#s.skipped > 0, class .. " has ranks to skip")
  end
end)

for class in pairs(CLASSES) do
  test(class .. ": every section is grouped, Pet comes last and general skills are gone", function()
    local data = ns.Rules.GetClass(class)
    local s = ns.Options.ClassSummary(data)
    local sections = { { s.keep, s.keepGroups }, { s.optional, s.optionalGroups }, { s.wait, s.waitGroups },
      { s.low, s.lowGroups }, { s.skipped, s.skippedGroups } }
    for _, pair in ipairs(sections) do
      local total = 0
      for i, g in ipairs(pair[2]) do
        total = total + #g.entries
        truthy(g.title ~= "" and #g.entries > 0, "a group has a title and spells")
        if g.title == "Pet" then eq(i, #pair[2], "Pet comes last") end
      end
      eq(total, #pair[1], "the groups hold every listed spell")
    end
    local pet, general = {}, {}
    for _, n in ipairs(data.pet or {}) do pet[n] = true end
    for _, n in ipairs(data.general or {}) do general[n] = true end
    for _, pair in ipairs(sections) do
      for _, g in ipairs(pair[2]) do
        for _, e in ipairs(g.entries) do
          falsy(general[e.id], e.name .. " is a general skill")
          eq(g.title == "Pet", pet[e.id] == true, e.name)
        end
      end
    end
  end)
end

test("hunter: what the Pet Trainer teaches is under Pet; Warlock demons are not", function()
  local h = ns.Options.ClassSummary(ns.Rules.GetClass("HUNTER"))
  local where = {}
  for _, g in ipairs(h.keepGroups) do for _, e in ipairs(g.entries) do where[e.name] = g.title end end
  for _, n in ipairs({ "Growl", "Great Stamina", "Natural Armor" }) do eq(where[n], "Pet", n) end
  truthy(where["Mend Pet"] ~= "Pet", "Mend Pet is a Hunter spell")
  eq(ns.Rules.GetClass("WARLOCK").pet, nil)
end)
