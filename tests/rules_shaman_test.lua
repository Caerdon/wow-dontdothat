package.path = "./tests/?.lua;" .. package.path
local T = require("classtest")
local H = require("harness")

local s = T.new("SHAMAN", "Shaman")

test("shaman: shared core spells, imbues and totems are kept", function()
  for _, n in ipairs({ "Lightning Bolt", "Earth Shock", "Flame Shock", "Healing Wave", "Lightning Shield", "Ghost Wolf",
    "Rockbiter Weapon", "Searing Totem", "Stoneclaw Totem", "Earthbind Totem", "Ancestral Spirit", "Reincarnation", "Astral Recall" }) do
    for _, spec in ipairs({ "ELEM", "ENH", "RESTO" }) do eq(s.tier(n, { spec }), "keep", n .. " " .. spec) end
  end
end)

test("shaman: Enhancement keeps its imbues, Stormstrike and buff totems", function()
  for _, n in ipairs({ "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Strength of Earth Totem", "Grace of Air Totem",
    "Chain Lightning", "Fire Nova", "Magma Totem", "Frost Shock" }) do eq(s.tier(n, { "ENH" }), "keep", n) end
  eq(s.tier("Stormstrike", { "ENH" }, { Stormstrike = true }), "keep")
end)

test("shaman: Elemental keeps Chain Lightning, Flametongue and the fire totems", function()
  for _, n in ipairs({ "Chain Lightning", "Fire Nova", "Magma Totem", "Flametongue Weapon", "Frost Shock" }) do
    eq(s.tier(n, { "ELEM" }), "keep", n)
  end
end)

test("shaman: Restoration keeps its healing spells and totems", function()
  for _, n in ipairs({ "Lesser Healing Wave", "Chain Heal", "Riptide", "Healing Stream Totem", "Mana Spring Totem" }) do
    eq(s.tier(n, { "RESTO" }), "keep", n)
  end
  for _, n in ipairs({ "Water Shield", "Earth Shield", "Lava Lash", "Shamanistic Rage" }) do eq(s.tier(n, { "RESTO", "ENH" }), "info", n) end
  eq(s.tier("Earth Shock", { "ENH" }), "keep"); eq(s.tier("Ancestral Spirit", { "ENH" }), "keep")
end)

test("shaman: spec-aware tiers", function()
  eq(s.tier("Windfury Weapon", { "ELEM" }), "deferLow")
  eq(s.tier("Windfury Weapon", { "ENH", "ELEM" }), "keep")
  eq(s.tier("Chain Heal", { "ENH" }), "deferLow")
  eq(s.tier("Chain Lightning", { "RESTO" }), "info")
  eq(s.tier("Chain Lightning", {}), "keep")
end)

test("shaman: the redundant totems are defer-low-value", function()
  for _, n in ipairs({ "Stoneskin Totem", "Windwall Totem", "Flametongue Totem", "Frost Resistance Totem", "Disease Cleansing Totem", "Sentry Totem" }) do
    eq(s.tier(n, { "ENH" }), "deferLow", n)
  end
  eq(s.tier("Windfury Totem", { "ENH" }), "defer"); eq(s.tier("Purge", { "ENH" }), "deferLow")
end)

test("shaman: ranks that add nothing are skipped, the rest are not", function()
  eq(s.data.skipRanks[H.fid(s.ns, "SHAMAN", "Frost Shock")], { 2, 3, 4 })
  eq(s.data.skipRanks[H.fid(s.ns, "SHAMAN", "Healing Wave")], { 10 })
  eq(s.data.skipRanks[H.fid(s.ns, "SHAMAN", "Rockbiter Weapon")], { 5, 6, 7 })
  eq(s.data.skipRanks[H.fid(s.ns, "SHAMAN", "Strength of Earth Totem")], { 5 })
  eq(s.data.skipRanks[H.fid(s.ns, "SHAMAN", "Lightning Bolt")], nil)
  for name, ranks in pairs(s.data.skipRanks) do
    truthy(ranks[1] ~= 1, name .. " rank 1 is never skipped")
  end
  eq(s.tier("Healing Wave", { "ELEM" }, nil, 10), "defer")
  truthy(s.tier("Healing Wave", { "ELEM" }, nil, 9) ~= "defer", "Healing Wave r9")
  eq(s.tier("Frost Shock", { "ELEM" }, nil, 2), "defer")
  truthy(s.tier("Frost Shock", { "ELEM" }, nil, 1) ~= "defer", "Frost Shock r1")
  truthy(s.tier("Lightning Bolt", { "ELEM" }, nil, 7) ~= "defer", "Lightning Bolt r7")
  truthy(s.tier("Earth Shock", { "ELEM" }, nil, 7) ~= "defer", "Earth Shock r7")
end)

test("shaman: Mail and Dual Wield are kept", function()
  eq(s.eval("Mail", {}).source, "override"); eq(s.eval("Dual Wield", {}).source, "override")
end)
