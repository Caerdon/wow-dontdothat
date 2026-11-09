package.path = "./tests/?.lua;" .. package.path
local T = require("classtest")

local w = T.new("WARLOCK", "Warlock")

test("warlock: core spells are kept for every spec, and Fear is kept at every rank", function()
  for _, n in ipairs({ "Shadow Bolt", "Corruption", "Immolate", "Curse of Agony", "Bane of Agony", "Life Tap", "Drain Soul",
    "Drain Life", "Health Funnel", "Create Healthstone", "Create Soulstone", "Demon Armor", "Summon Voidwalker", "Summon Succubus" }) do
    for _, spec in ipairs({ "AFFL", "DEMO", "DEST" }) do eq(w.tier(n, { spec }), "keep", n .. " " .. spec) end
  end
  for rank = 1, 3 do eq(w.tier("Fear", { "DEST" }, nil, rank), "keep", "Fear r" .. rank) end
end)

test("warlock: no rank skips, since the expert guide gives none", function()
  eq(next(w.skipRanks()), nil)
  eq(w.tier("Fear", { "DEST" }, nil, 1), "keep")
end)

test("warlock: the minor curses and toys are defer-low-value", function()
  for _, n in ipairs({ "Curse of Weakness", "Curse of Recklessness", "Curse of Idiocy", "Subjugate Demon", "Eye of Kilrogg", "Detect Invisibility", "Detect Lesser Invisibility", "Sense Demons" }) do
    eq(w.tier(n, { "AFFL" }), "deferLow", n)
  end
  eq(w.tier("Curse of Tongues", { "AFFL" }), "deferLow")
end)

test("warlock: rituals and level 60 spells wait", function()
  for _, n in ipairs({ "Portal of Summoning", "Ritual of Doom", "Bane of Doom" }) do eq(w.tier(n, { "AFFL" }), "defer", n) end
  for _, n in ipairs({ "Ritual of Summoning", "Unending Breath", "Howl of Terror", "Death Coil", "Inferno" }) do eq(w.tier(n, { "AFFL" }), "keep", n) end
end)

test("warlock: spec spells follow the spec, and talent spells need their talent", function()
  for _, n in ipairs({ "Searing Pain", "Incinerate", "Soul Fire", "Banish", "Shadow Ward", "Create Firestone", "Create Spellstone", "Fel Armor" }) do eq(w.tier(n, { "DEST" }), "deferLow", n) end
  eq(w.tier("Rain of Fire", { "DEST" }), "keep"); eq(w.tier("Rain of Fire", { "AFFL" }), "deferLow")
  eq(w.tier("Summon Felhunter", { "DEMO" }), "keep")
  truthy(w.eval("Siphon Life", { "AFFL" }, {}).source ~= "rotation")
  eq(w.tier("Siphon Life", { "AFFL" }, { ["Siphon Life"] = true }), "keep")
  eq(w.tier("Shadowburn", { "DEST" }, { Shadowburn = true }), "keep")
end)

test("warlock: group curses and level 60 spells wait", function()
  eq(w.tier("Curse of the Elements", { "AFFL" }), "defer")
  eq(w.tier("Inferno", { "AFFL" }), "keep")
  eq(w.tier("Drain Mana", { "AFFL" }), "deferLow")
end)

test("warlock: the level 40 mount is free with the Felsteed note, and the grimoire rule keeps the experts' picks", function()
  local m = w.data.milestones[40]
  eq(m.riding + m.mount, 0)
  eq(m.note, "Your Felsteed is paid for in souls, not gold.")
  eq(w.data.milestones[60], nil)
  eq(w.data.grimoires.keep, { "Firebolt", "Blood Pact", "Fire Shield", "Phase Shift", "Consume Shadows", "Sacrifice", "Suffering", "Torment", "Lash of Pain", "Seduction", "Lesser Invisibility", "Spell Lock" })
  truthy(w.data.grimoires.reason:find("demon", 1, true))
end)
