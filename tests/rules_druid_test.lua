package.path = "./tests/?.lua;" .. package.path
local T = require("classtest")
local H = require("harness")

local d = T.new("DRUID", "Druid")

test("druid: forms, healing and Barkskin are kept for every spec", function()
  for _, specs in ipairs({ { "BAL" }, { "FERAL" }, { "RESTO" }, {} }) do
    for _, n in ipairs({ "Mark of the Wild", "Healing Touch", "Rejuvenation", "Regrowth", "Barkskin", "Cat Form", "Bear Form", "Dire Bear Form", "Travel Form" }) do
      eq(d.tier(n, specs), "keep", n)
    end
  end
end)

test("druid: the Feral kit is kept for Feral and undecided talents, but not for Balance", function()
  for _, n in ipairs({ "Claw", "Rake", "Rip", "Shred", "Ferocious Bite", "Maul", "Swipe", "Pounce", "Ravage", "Prowl", "Dash", "Growl", "Enrage" }) do
    eq(d.tier(n, { "FERAL" }), "keep", n); eq(d.tier(n, {}), "keep", n)
    local v = d.eval(n, { "BAL" })
    eq(v.tier, "deferLow", n); eq(v.source, "rotation")
  end
end)

test("druid: Wrath, Moonfire, Starfire and Entangling Roots follow the spec", function()
  for _, n in ipairs({ "Wrath", "Moonfire", "Starfire", "Entangling Roots", "Faerie Fire" }) do
    eq(d.tier(n, { "BAL" }), "keep", n); eq(d.tier(n, {}), "keep", n)
    local v = d.eval(n, { "FERAL" })
    eq(v.tier, "deferLow", n); eq(v.source, "rotation")
  end
end)

test("druid: situational utility is informational", function()
  for _, n in ipairs({ "Thorns", "Cure Poison", "Remove Curse", "Aquatic Form" }) do
    eq(d.eval(n, { "FERAL" }).tier, "info", n)
  end
end)

test("druid: niche utility is defer-low-value and group spells wait", function()
  for _, n in ipairs({ "Soothe Animal", "Hibernate", "Track Humanoids", "Cower" }) do eq(d.tier(n, { "FERAL" }), "deferLow", n) end
  for _, n in ipairs({ "Tranquility", "Gift of the Wild", "Challenging Roar", "Wild Growth" }) do eq(d.tier(n, { "FERAL" }), "defer", n) end
end)

test("druid: only expert-guided ranks are skipped, never rank 1", function()
  local function skip(name) return d.skipRanks()[H.fid(d.ns, "DRUID", name)] end
  eq(skip("Rejuvenation")[1], 11)
  eq(#skip("Rejuvenation"), 1)
  eq(skip("Claw"), nil)
  eq(skip("Healing Touch"), nil)
  eq(skip("Wrath"), nil)
  for id, ranks in pairs(d.skipRanks()) do
    for _, r in ipairs(ranks) do assert(r > 1, id .. " skips rank 1") end
  end
end)

test("druid: single-target resurrections and the interrupt are worth buying", function()
  for _, specs in ipairs({ { "BAL" }, { "FERAL" }, { "RESTO" }, {} }) do
    eq(d.tier("Revive", specs), "keep", "Revive"); eq(d.tier("Rebirth", specs), "keep", "Rebirth")
  end
  eq(d.tier("Skull Bash", { "FERAL" }), "keep"); eq(d.tier("Bash", { "FERAL" }), "keep")
end)
