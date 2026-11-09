local H = require("harness")

local function fresh()
  local ns = {}
  H.load("DontDoThat/Data/SpellData.lua", ns)
  H.load("DontDoThat/Model/SpellData.lua", ns)
  return ns
end

local function scrambled() return { GetSpellInfo = function(id) return "Z" .. id end } end

test("a family is named by its lowest ID and any rank of it resolves to that family", function()
  local ns = fresh()
  local SD = ns.SpellData
  eq(SD.FamilyId("HUNTER", "Arcane Shot"), 3044)
  eq(SD.FamilyOfId("HUNTER", 14283), 3044, "rank 4 belongs to the family")
  eq(SD.FamilyName("HUNTER", 3044), "Arcane Shot")
  eq(SD.FamilyId("HUNTER", "No Such Spell"), nil)
  eq(SD.FamilyOfId("HUNTER", 1), nil)
end)

test("rows that share a name and have no rank still form one family, and alternates resolve to it", function()
  local ns = fresh()
  local SD = ns.SpellData
  local family = SD.FamilyId("PALADIN", "Holy Light")
  truthy(family, "Holy Light is a family")
  eq(SD.FamilyOfId("PALADIN", 1313348), family)
  for _, row in ipairs(SD.Rows("PALADIN")) do
    if row.name == "Holy Light" then
      truthy(family <= row.id, "the family ID is the lowest row ID")
      for _, id in ipairs(SD.Ids(row)) do eq(SD.FamilyOfId("PALADIN", id), family) end
    end
  end
end)

test("every bundled row resolves to a family whose English name is the row's name", function()
  local ns = fresh()
  local SD = ns.SpellData
  for classKey in pairs(ns.SpellTables) do
    if type(ns.SpellTables[classKey]) == "table" then
      for _, row in ipairs(SD.Rows(classKey)) do
        local family = SD.FamilyOfId(classKey, row.id)
        truthy(family, classKey .. " " .. row.name)
        eq(SD.FamilyName(classKey, family), row.name)
      end
    end
  end
end)

test("the name map resolves a client that shows every spell under another name", function()
  local ns = fresh()
  local SD = ns.SpellData
  local env = scrambled()
  local map = SD.NameMap("HUNTER", env)
  for _, row in ipairs(SD.Rows("HUNTER")) do
    eq(map["Z" .. row.id], SD.FamilyOfId("HUNTER", row.id), "row " .. row.id)
  end
  eq(map["Arcane Shot"], nil, "English names are not used when the client names the spells")
  eq(SD.DisplayName("HUNTER", 3044, env), "Z3044")
end)

test("a name two families share is ambiguous, never guessed", function()
  local ns = { SpellTables = { X = { rows = {
    { id = 1, name = "A", level = 1, kind = "class" }, { id = 2, name = "B", level = 1, kind = "class" },
  } } } }
  H.load("DontDoThat/Model/SpellData.lua", ns)
  local map = ns.SpellData.NameMap("X", { GetSpellInfo = function() return "Same" end })
  eq(map["Same"], false)
end)

test("without a usable client the name map holds the English names", function()
  local ns = fresh()
  local SD = ns.SpellData
  eq(SD.NameMap("HUNTER", {})["Arcane Shot"], 3044)
  eq(SD.NameMap("HUNTER", { GetSpellInfo = function() error("no") end })["Arcane Shot"], 3044)
  eq(SD.DisplayName("HUNTER", 3044, {}), "Arcane Shot")
end)

test("C_Spell.GetSpellName is used when the client has it", function()
  local ns = fresh()
  local env = { C_Spell = { GetSpellName = function(id) return "C" .. id end } }
  eq(ns.SpellData.NameMap("HUNTER", env)["C14283"], 3044)
end)

-- Every spell name a rule file writes has an ID, so the engine can work in IDs.
local function ruleData()
  local ns = {}
  H.load("DontDoThat/Data/SpellData.lua", ns)
  H.load("DontDoThat/Data/RuleSpells.lua", ns)
  H.load("DontDoThat/Model/SpellData.lua", ns)
  local classes = {}
  ns.Rules = { Load = function(d) classes[#classes + 1] = d end }
  for _, c in ipairs({ "Hunter", "Paladin", "Mage", "Warlock", "Priest", "Druid", "Shaman", "Rogue", "Warrior" }) do
    H.load("DontDoThat/Rules/Data/" .. c .. ".lua", ns)
  end
  return ns, classes
end

local function ruleNames(d)
  local out = {}
  local function add(where, n) out[#out + 1] = { where = where, name = n } end
  for key, spec in pairs(d.specs) do
    for _, n in ipairs(spec.rotation.core) do add("specs." .. key .. ".core", n) end
    for _, n in ipairs(spec.rotation.situational or {}) do add("specs." .. key .. ".situational", n) end
  end
  for _, field in ipairs({ "tags", "overrides", "why", "ranks", "abilityLevels" }) do
    for n in pairs(d[field] or {}) do add(field, n) end
  end
  for _, field in ipairs({ "talentSpells", "reviewed", "general", "pet" }) do
    for _, n in ipairs(d[field] or {}) do add(field, n) end
  end
  return out
end

test("every spell name in the rule files resolves to a family", function()
  local ns, classes = ruleData()
  eq(#classes, 9)
  for _, d in ipairs(classes) do
    for _, item in ipairs(ruleNames(d)) do
      local name = item.name
      if name:sub(1, 1) == "~" then
        truthy(#ns.SpellData.FamiliesWithPrefix(d.class, name:sub(2)) > 0, d.class .. " " .. item.where .. " " .. name)
      else
        truthy(ns.SpellData.FamilyId(d.class, name), d.class .. " " .. item.where .. " " .. name)
      end
    end
  end
end)

test("a spell the Forever tables name differently resolves through its Classic Era name", function()
  local ns = ruleData()
  local SD = ns.SpellData
  truthy(SD.FamilyId("WARLOCK", "Curse of Agony"), "Era name")
  eq(SD.FamilyId("WARLOCK", "Curse of Agony"), SD.FamilyId("WARLOCK", "Bane of Agony"), "same spell, same family")
  eq(SD.FamilyOfId("WARLOCK", 980), SD.FamilyId("WARLOCK", "Curse of Agony"))
end)

test("a localized client name resolves for a spell only the rule files list", function()
  local ns = ruleData()
  local SD = ns.SpellData
  local map = SD.NameMap("HUNTER", { GetSpellInfo = function(id) return "Z" .. id end })
  eq(map["Z" .. SD.FamilyId("HUNTER", "Aimed Shot")], SD.FamilyId("HUNTER", "Aimed Shot"))
end)

test("every talent-granted spell the rules name is reachable from a talent hyperlink, for all nine classes", function()
  local ns = {}
  H.loadSpellTables(ns)
  H.load("DontDoThat/Rules/Schema.lua", ns)
  H.load("DontDoThat/Rules/Engine.lua", ns)
  for _, c in ipairs({ "Hunter", "Paladin", "Mage", "Warlock", "Priest", "Druid", "Shaman", "Rogue", "Warrior" }) do
    H.load("DontDoThat/Rules/Data/" .. c .. ".lua", ns)
  end
  for _, class in ipairs(ns.Rules.ListClasses()) do
    local reached = {}
    for _, ranks in pairs(ns.TalentSpells) do
      for _, spellId in ipairs(ranks) do
        local family = ns.SpellData.FamilyOfId(class, spellId)
        if family then reached[family] = true end
      end
    end
    for _, id in ipairs(ns.Rules.GetClass(class).talentSpells or {}) do
      truthy(reached[id], class .. " " .. tostring(ns.SpellData.FamilyName(class, id)) .. " has no talent that leads to it")
    end
  end
end)
