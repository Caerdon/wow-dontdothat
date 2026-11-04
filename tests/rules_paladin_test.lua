package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = {}
H.loadSpellTables(ns)
H.load("DontDoThat/Rules/Schema.lua", ns)
H.load("DontDoThat/Rules/Engine.lua", ns)
H.load("DontDoThat/Rules/Data/Paladin.lua", ns)
H.load("DontDoThat/Data/SpellData.lua", ns)

local data = ns.Rules.GetClass("PALADIN")

local function profile(specs, talents)
  return { class = "PALADIN", level = 25, plausibleSpecs = specs, activeTalents = H.talentSet(ns, "PALADIN", talents),
    milestone = { current = 40, state = "active" } }
end
local function eval(name, specs, talents, rank)
  return ns.Rules.Evaluate(profile(specs, talents), { kind = "spell", name = name, familyId = H.fid(ns, "PALADIN", name), rank = rank })
end
local function tier(name, specs, talents) return eval(name, specs, talents).tier end

test("paladin: three specs in the game's tab order, every rotation flagged for review", function()
  eq(data.specs.HOLY.tree, 1); eq(data.specs.PROT.tree, 2); eq(data.specs.RET.tree, 3)
  for key, spec in pairs(data.specs) do truthy(spec.rotation.needsReview, key) end
end)

test("paladin: core spells are kept for every spec", function()
  for _, specs in ipairs({ { "HOLY" }, { "PROT" }, { "RET" }, {} }) do
    for _, n in ipairs({ "Seal of Righteousness", "Judgement", "Holy Light", "Flash of Light", "Blessing of Might",
        "Blessing of Wisdom", "Redemption", "Purify", "Cleanse", "Divine Protection", "Divine Shield", "Hammer of Justice",
        "Seal of the Crusader", "Lay on Hands", "Blessing of Protection", "Blessing of Freedom", "Divine Intervention", "Retribution Aura", "Hammer of Wrath" }) do
      eq(tier(n, specs), "keep", n)
    end
  end
end)

test("paladin: the mounts and Plate Mail are always kept", function()
  for _, n in ipairs({ "Summon Warhorse", "Summon Charger", "Plate Mail" }) do
    local v = eval(n, { "RET" })
    eq(v.tier, "keep", n); eq(v.source, "override", n)
  end
end)

test("paladin: group, raid and endgame spells are deferred with a plain reason", function()
  for _, n in ipairs({ "Blessing of Sacrifice", "Blessing of Light", "Blessing of Salvation",
      "Concentration Aura", "Fire Resistance Aura", "Frost Resistance Aura",
      "Shadow Resistance Aura", "Greater Blessing of Might", "Greater Blessing of Salvation" }) do
    local v = eval(n, { "RET" })
    eq(v.tier, "defer", n)
    truthy(v.reason ~= "" and not v.reason:find("tag", 1, true), n .. " has a plain reason")
  end
end)

test("paladin: PvP and low-value spells are defer-low-value", function()
  for _, n in ipairs({ "Seal of Justice", "Turn Undead", "Sense Undead", "Exorcism", "Holy Wrath", "Divine Favor", "Blessing of Kings", "Blessing of Sanctuary" }) do
    eq(tier(n, { "RET" }), "deferLow", n)
  end
end)

test("paladin: Righteous Fury is kept for Protection and deferred for anyone else", function()
  eq(tier("Righteous Fury", { "PROT" }), "keep")
  eq(tier("Righteous Fury", { "RET" }), "defer")
  eq(tier("Righteous Fury", {}), "keep", "undecided talents never hide it")
end)

test("paladin: situational spells are informational", function()
  for _, n in ipairs({ "Devotion Aura", "Seal of Wisdom", "Seal of Light", "Sanctity Aura" }) do
    eq(tier(n, { "HOLY" }), "info", n)
  end
end)

test("paladin: Hammer of Wrath is core, Exorcism waits, Consecration needs its talent", function()
  eq(tier("Hammer of Wrath", { "RET" }), "keep"); eq(tier("Exorcism", { "RET" }), "deferLow")
  eq(eval("Consecration", { "PROT" }, { Consecration = true }).tier, "keep")
end)

test("paladin: only Hammer of Justice ranks 2 to 4 are skipped (Icy Veins: just rank 1)", function()
  eq(data.skipRanks, { [H.fid(ns, "PALADIN", "Hammer of Justice")] = { 2, 3, 4 } })
  truthy(eval("Hammer of Justice", { "RET" }, nil, 1) and eval("Hammer of Justice", { "RET" }, nil, 1).tier ~= "defer")
  for rank = 2, 4 do eq(eval("Hammer of Justice", { "RET" }, nil, rank).source, "skipRank", "rank " .. rank) end
end)

test("paladin: the nine talent spells are not rotation spells until the talent is active", function()
  eq(#data.talentSpells, 9)
  for _, id in ipairs(data.talentSpells) do
    local n = ns.SpellData.FamilyName("PALADIN", id)
    local without = eval(n, { "HOLY", "PROT", "RET" }, {})
    truthy(without.source ~= "rotation", n .. " without its talent")
  end
  eq(eval("Holy Shock", { "HOLY" }, { ["Holy Shock"] = true }).tier, "keep")
  eq(eval("Seal of Command", { "RET" }, { ["Seal of Command"] = true }).tier, "keep")
  eq(eval("Holy Shield", { "PROT" }, { ["Holy Shield"] = true }).tier, "keep")
  eq(eval("Seal of Command", { "RET" }, {}).tier, "keep", "no other rule applies, so it falls through to keep")
end)

test("paladin: the level 40 milestone is a small target with a note, the level 60 one is left alone", function()
  eq(data.milestones[40].riding + data.milestones[40].mount, 10 * 10000)
  truthy(data.milestones[40].note:find("Light", 1, true))
  eq(data.milestones[60], nil)
end)

test("paladin: every spell family in the bundled table and the Era-only list has been considered", function()
  local considered = {}
  local function add(list) for _, id in ipairs(list or {}) do considered[id] = true end end
  for _, spec in pairs(data.specs) do add(spec.rotation.core); add(spec.rotation.situational) end
  for id in pairs(data.tags) do considered[id] = true end
  for id in pairs(data.overrides) do considered[id] = true end
  add(data.reviewed)

  local families = {}
  for _, row in ipairs(ns.SpellTables.PALADIN.rows) do families[ns.SpellData.FamilyOfId("PALADIN", row.id)] = true end
  -- Families that exist only in the Classic Era tables (see the build comparison in the change design).
  for _, n in ipairs({ "Blessing of Salvation", "Greater Blessing of Salvation", "Greater Blessing of Sanctuary",
      "Sanctity Aura", "Blessing of Sanctuary", "Crusader Strike", "Divine Steed", "Hand of Reckoning",
      "Beacon of Light", "Avenger's Shield", "Righteous Vengeance" }) do families[H.fid(ns, "PALADIN", n)] = true end

  local missing = {}
  for id in pairs(families) do
    if not considered[id] then missing[#missing + 1] = ns.SpellData.FamilyName("PALADIN", id) end
  end
  table.sort(missing)
  eq(missing, {}, "unclassified Paladin spells: " .. table.concat(missing, ", "))
end)

test("paladin: effect spells never count as purchases", function()
  for _, row in ipairs(ns.SpellTables.PALADIN.rows) do
    if row.name:find("^Judgement of ") then eq(row.kind, "effect", row.name) end
  end
end)
