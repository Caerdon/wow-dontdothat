package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = {}
H.loadSpellTables(ns)
H.load("DontDoThat/Rules/Schema.lua", ns)
H.load("DontDoThat/Rules/Engine.lua", ns)
H.load("DontDoThat/Rules/Data/Hunter.lua", ns)

local function profile(specs, pts)
  return { class = "HUNTER", level = 25, treePoints = pts or { BM = 21, MM = 0, SV = 0 }, plausibleSpecs = specs,
    milestone = { current = 40, state = "active" }, rules = { skipRevision = 1 } }
end
local function tier(name, specs, extra)
  local a = { kind = "spell", name = name, familyId = H.fid(ns, "HUNTER", name) }
  for k, v in pairs(extra or {}) do a[k] = v end
  return ns.Rules.Evaluate(profile(specs), a).tier
end

test("hunter: BM core abilities are kept", function()
  for _, n in ipairs({ "Hunter's Mark", "Serpent Sting", "Summon Hawk", "Arcane Shot", "Auto Shot", "Multi-Shot", "Mend Pet", "Intimidation" }) do
    eq(tier(n, { "BM" }), "keep", n)
  end
end)

test("hunter: BM situational abilities are info", function()
  for _, n in ipairs({ "Aimed Shot", "Raptor Strike", "Aspect of the Pack" }) do
    eq(tier(n, { "BM" }), "info", n)
  end
end)

test("hunter: PvP tag is deferLow", function()
  for _, n in ipairs({ "Viper Sting", "Scorpid Sting", "Scatter Shot", "Flare", "Enchanted Flare", "Track Hidden", "Counterattack" }) do
    eq(tier(n, { "BM" }), "deferLow", n)
  end
end)

test("hunter: raid/group abilities are defer", function()
  for _, n in ipairs({ "Distracting Shot", "Tranquilizing Shot", "Volley", "Aspect of the Wild" }) do
    eq(tier(n, { "BM" }), "defer", n)
  end
end)

test("hunter: low-value abilities are deferLow", function()
  for _, n in ipairs({ "Beast Lore", "Eagle Eye", "Eyes of the Beast", "Scare Beast", "Track Demons", "Track Giants",
    "Track Dragonkin", "Track Elementals", "Arcane Resistance", "Fire Resistance", "Frost Resistance",
    "Nature Resistance", "Shadow Resistance" }) do
    eq(tier(n, { "BM" }), "deferLow", n)
  end
end)

test("hunter: keep overrides", function()
  for _, n in ipairs({ "Serpent Sting", "Hunter's Mark", "Freezing Trap", "Immolation Trap",
    "Explosive Trap", "Deterrence", "Disengage" }) do
    local v = ns.Rules.Evaluate(profile({ "BM" }), { kind = "spell", name = n, familyId = H.fid(ns, "HUNTER", n) })
    eq(v.tier, "keep", n); eq(v.source, "override", n)
  end
end)

test("hunter: Survival-only ability for a BM-only profile is flagged with reason", function()
  local v = ns.Rules.Evaluate(profile({ "BM" }), { kind = "spell", name = "Mongoose Bite", familyId = H.fid(ns, "HUNTER", "Mongoose Bite") })
  eq(v.tier, "deferLow")
  eq(v.reason, "Mostly used by Survival players, and your talents lean another way.")
end)

test("hunter: ambiguous specs are conservative", function()
  eq(tier("Mongoose Bite", {}), "keep")
  eq(tier("Mongoose Bite", { "BM", "MM", "SV" }), "keep")
end)

test("hunter: MM and SV rotations need review, BM does not", function()
  local d = ns.Rules.GetClass("HUNTER")
  truthy(d.specs.MM.rotation.needsReview); truthy(d.specs.SV.rotation.needsReview)
  falsy(d.specs.BM.rotation.needsReview)
end)

test("hunter: Serpent Sting rank table", function()
  local rows = ns.Rules.GetClass("HUNTER").ranks[H.fid(ns, "HUNTER", "Serpent Sting")]
  local levels, mana = {}, {}
  for i, r in ipairs(rows) do levels[i] = r.unlockLevel; mana[i] = r.manaCost end
  truthy(H.deepEqual(levels, { 4, 10, 18, 26, 34, 42, 50, 58, 60 }))
  truthy(H.deepEqual(mana, { 15, 30, 50, 80, 115, 150, 190, 230, 250 }))
end)

test("hunter: not needed until 60 means a full defer", function()
  for _, n in ipairs({ "Distracting Shot", "Wyvern Sting", "Aspect of the Beast" }) do
    eq(tier(n, { "BM" }), "defer", n)
    eq(tier(n, {}), "defer", n .. " with ambiguous spec")
  end
end)

test("hunter: all tracking is low value", function()
  for _, n in ipairs({ "Track Beasts", "Track Humanoids", "Track Undead", "Track Hidden", "Track Elementals",
    "Track Demons", "Track Giants", "Track Dragonkin" }) do
    eq(tier(n, { "BM" }), "deferLow", n)
  end
end)

test("hunter: Trueshot Aura and Dual Wield are kept", function()
  for _, n in ipairs({ "Trueshot Aura", "Dual Wield" }) do
    eq(tier(n, { "BM" }), "keep", n)
    eq(tier(n, { "SV" }), "keep", n)
  end
end)

local function rankTier(name, rank, specs)
  return ns.Rules.Evaluate(profile(specs or { "BM" }), { kind = "spell", name = name, familyId = H.fid(ns, "HUNTER", name), rank = rank }).tier
end

test("hunter: Wing Clip rank 1 is kept for every spec, later ranks are skipped", function()
  for _, specs in ipairs({ { "BM" }, { "MM" }, { "SV" }, {} }) do
    eq(rankTier("Wing Clip", 1, specs), "keep", "rank 1")
    for rank = 2, 3 do eq(rankTier("Wing Clip", rank, specs), "defer", "rank " .. rank) end
  end
end)

test("hunter: skipped ranks are deferred, neighbouring ranks are not", function()
  local cases = {
    { "Arcane Shot", {}, { 1, 2, 3, 4, 5, 6, 7, 8 } },   -- the experts recommend rank 7, so it is not skipped
    { "Serpent Sting", {}, { 2, 3, 4, 5, 6, 7, 8 } },
    { "Mend Pet", { 6 }, { 1, 2, 3, 4, 5, 7 } },
    { "Raptor Strike", { 5, 6, 8 }, { 3, 4, 7 } },
    { "Disengage", { 2, 3 }, { 1 } },
    { "Wing Clip", { 2, 3 }, { 1 } },
    { "Freezing Trap", { 2, 3 }, { 1 } },
    { "Great Stamina", { 5, 7, 9 }, { 1, 2, 3, 4, 6, 8, 10 } },
    { "Natural Armor", { 6, 8, 10 }, { 1, 2, 3, 4, 5, 7, 9 } },
  }
  for _, c in ipairs(cases) do
    for _, rank in ipairs(c[2]) do eq(rankTier(c[1], rank), "defer", c[1] .. " r" .. rank) end
    for _, rank in ipairs(c[3]) do truthy(rankTier(c[1], rank) ~= "defer", c[1] .. " r" .. rank .. " is not skipped") end
  end
end)

test("hunter: a skipped rank overrides the family keep, and says why in plain words", function()
  local v = ns.Rules.Evaluate(profile({ "BM" }), { kind = "spell", name = "Mend Pet", familyId = H.fid(ns, "HUNTER", "Mend Pet"), rank = 6, cost = 36000 })
  eq(v.tier, "defer"); eq(v.source, "skipRank"); eq(v.cost, 36000)
  eq(v.reason, "An earlier version of this list judged this rank a small upgrade.")
end)

test("hunter: a rank number alone never flags a spell with no skip rule", function()
  eq(rankTier("Multi-Shot", 7), "keep")
  eq(rankTier("Wing Clip", 7), "keep")
end)

test("hunter: a talent spell is not part of a rotation until its talent is active", function()
  local function withTalents(talents, name)
    local p = profile({ "BM" })
    p.activeTalents = H.talentSet(ns, "HUNTER", talents)
    return ns.Rules.Evaluate(p, { kind = "spell", name = name, familyId = H.fid(ns, "HUNTER", name) }).tier
  end
  eq(withTalents({}, "Intimidation"), "keep", "Intimidation has no other rule, so it is kept by default")
  eq(withTalents({ Intimidation = true }, "Intimidation"), "keep")
  eq(withTalents({}, "Aimed Shot"), "keep")
  eq(withTalents({ ["Aimed Shot"] = true }, "Aimed Shot"), "info")
  eq(withTalents(nil, "Aimed Shot"), "info", "an unknown talent list never hides a spell")
end)

test("hunter: a talent spell without its talent is judged by later rules, not the rotation", function()
  local p = profile({ "BM" })
  p.activeTalents = {}
  local v = ns.Rules.Evaluate(p, { kind = "spell", name = "Scatter Shot", familyId = H.fid(ns, "HUNTER", "Scatter Shot") })
  eq(v.source, "tag", "PvP tag decides")
  p.activeTalents = nil
  eq(ns.Rules.Evaluate(p, { kind = "spell", name = "Aimed Shot", familyId = H.fid(ns, "HUNTER", "Aimed Shot") }).source, "rotation")
  p.activeTalents = {}
  eq(ns.Rules.Evaluate(p, { kind = "spell", name = "Aimed Shot", familyId = H.fid(ns, "HUNTER", "Aimed Shot") }).source, "default")
end)

test("hunter: Aspect of the Pack and Frost Trap are optional, and the spells Hunters rely on are worth buying", function()
  for _, specs in ipairs({ { "BM" }, { "MM" }, { "SV" }, {} }) do
    eq(tier("Aspect of the Pack", specs), "info", "Aspect of the Pack")
    eq(tier("Frost Trap", specs), "info", "Frost Trap")
    for _, n in ipairs({ "Aspect of the Hawk", "Aspect of the Cheetah", "Feign Death", "Concussive Shot", "Growl", "Great Stamina", "Natural Armor", "Multi-Shot" }) do
      eq(tier(n, specs), "keep", n)
    end
  end
  eq(tier("Bestial Wrath", { "BM" }), "keep"); eq(tier("Rapid Fire", { "MM" }), "keep"); eq(tier("Aimed Shot", { "MM" }), "keep")
end)
