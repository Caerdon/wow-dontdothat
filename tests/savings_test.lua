package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = {}
for _, f in ipairs({ "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua", "Data/TrainerPrices.lua", "Model/SpellData.lua",
  "Model/Ledger.lua", "Model/Savings.lua", "Model/Settings.lua", "Model/Milestones.lua", "UI/Helpers.lua", "Data/Sounds.lua" }) do
  H.load("DontDoThat/" .. f, ns)
end
for _, c in ipairs({ "Hunter", "Mage", "Warrior", "Warlock", "Paladin", "Priest", "Druid", "Shaman", "Rogue" }) do
  H.load("DontDoThat/Rules/Data/" .. c .. ".lua", ns)
end
H.load("DontDoThat/Options/Options.lua", ns)

local function profile(class, specs, rules)
  return { class = class, plausibleSpecs = specs, rules = rules }
end

test("trainer prices: Wowhead's list agrees with every price seen at a Hunter trainer", function()
  local checked = 0
  for _, row in ipairs(ns.SpellData.Rows("HUNTER")) do
    local listed = ns.TrainerPrices.HUNTER[row.id]
    if row.cost and listed then eq(listed, row.cost, row.name .. " " .. tostring(row.rank)); checked = checked + 1 end
  end
  truthy(checked > 100, "compared " .. checked)
end)

test("trainer prices: a seen price wins, then the listed one, then the level estimate", function()
  local seen = { id = 3044, name = "Arcane Shot", rank = 1, level = 6, kind = "class", cost = 100 }
  eq({ ns.SpellData.Cost("HUNTER", seen) }, { 100, false })
  local frostbolt
  for _, row in ipairs(ns.SpellData.Rows("MAGE")) do if row.name == "Frostbolt" and row.rank == 1 then frostbolt = row end end
  eq({ ns.SpellData.Cost("MAGE", frostbolt) }, { 100, true })
  local unlisted = { id = 1, name = "Nothing", rank = 1, level = 20, kind = "class" }
  local cost, estimate = ns.SpellData.Cost("MAGE", unlisted)
  truthy(cost and estimate, "estimated from the level")
end)

test("savings: every class keeps some gold, split across the three groups", function()
  for _, class in ipairs({ "HUNTER", "MAGE", "WARRIOR", "WARLOCK", "PALADIN", "PRIEST", "DRUID", "SHAMAN", "ROGUE" }) do
    local r = ns.Savings.Compute(profile(class, nil), 60)
    truthy(r.total > 0, class .. " total")
    eq(r.total, r.wait + r.low + r.skip, class .. " groups add up")
    truthy(r.count > 0)
  end
end)

test("savings: a lower stop level saves less", function()
  local at40 = ns.Savings.Compute(profile("MAGE", { "FROST" }), 40).total
  local at60 = ns.Savings.Compute(profile("MAGE", { "FROST" }), 60).total
  truthy(at40 > 0 and at40 < at60)
end)

test("savings: a Worth buying spell adds nothing, a deferred rank adds its price", function()
  local r = ns.Savings.Compute(profile("ROGUE", { "COM" }, { offKinds = { skipRank = true } }), 60)
  local on = ns.Savings.Compute(profile("ROGUE", { "COM" }), 60)
  truthy(on.skip > 0 and r.skip == 0, "skipped ranks count only while that rule is on")
  eq(on.total - r.total, on.skip - r.skip + (on.wait - r.wait) + (on.low - r.low))
end)

test("savings: switching off a tag or an ability lowers the total", function()
  local base = ns.Savings.Compute(profile("HUNTER", { "BM" }), 60)
  local noRaid = ns.Savings.Compute(profile("HUNTER", { "BM" }, { offTags = { RaidGroup = true } }), 60)
  truthy(noRaid.total < base.total)
  local noOne = ns.Savings.Compute(profile("HUNTER", { "BM" }, { offAbilities = { [H.fid(ns, "HUNTER", "Distracting Shot")] = true } }), 60)
  truthy(noOne.total < base.total)
end)

test("savings: a price seen at the player's trainer replaces the listed one", function()
  local base = ns.Savings.Compute(profile("HUNTER", { "BM" }), 60)
  local cache = { [ns.Ledger.CostKey(H.fid(ns, "HUNTER", "Distracting Shot"), 1)] = 999999 }
  local r = ns.Savings.Compute(profile("HUNTER", { "BM" }), 60, cache)
  truthy(r.total > base.total)
end)

test("savings: unconfirmed prices are flagged", function()
  truthy(ns.Savings.Compute(profile("MAGE", { "FROST" }), 60).unconfirmed)
end)

test("savings: each spec of a class gets its own total, whatever the settings", function()
  local m = ns.Savings.Max("MAGE", 60)
  eq(#m.specs, 3)
  for _, s in ipairs(m.specs) do truthy(s.total > 0, s.name) end
  eq(m.specs[1].name, "Arcane")
end)

test("progress page: the projected savings box shows a total and the three groups", function()
  ns.db = { profile = {}, char = { costCache = {} } }
  ns.Context = { Profile = function() return { class = "MAGE", plausibleSpecs = { "FROST" }, milestone = { current = 40, state = "active" } } end }
  local savings = ns.Options.Progress().args.savings
  truthy(savings.inline)
  local function text(w) local n = w.name; if type(n) == "function" then n = n() end; return n end
  for _, key in ipairs({ "total", "wait", "low", "skip" }) do
    truthy(text(savings.args[key]):find("%d"), key)
    eq(savings.args[key].width, "full", "one line per figure")
  end
  truthy(text(savings.args.wait):find("\226\128\162 ", 1, true), "bulleted")
  truthy(text(savings.args.intro):find("level 60", 1, true))
  truthy(savings.args.totalHeader and savings.args.fromHeader, "sections")
  truthy(savings.args.waitNote and savings.args.lowNote and savings.args.skipNote, "each group is explained")
  ns.Context = { Profile = function() return nil end }
  truthy(text(savings.args.intro):find("Log in", 1, true))
end)

test("class page: the overview gives each spec's savings", function()
  ns.db = { profile = {} }
  local mage = ns.Options.Rules().args.MAGE
  local function text(w) local n = w.name; if type(n) == "function" then n = n() end; return n end
  truthy(mage.args.specHeader.name:find("by spec", 1, true) and not mage.args.best, "no single best spec")
  local arcane = text(mage.args.spec1)
  truthy(mage.args.specHeader.name:find("level 40 / level 60", 1, true) and arcane:find(" / ", 1, true), "level 40 and level 60 side by side")
  for i, spec in ipairs({ "Arcane", "Fire", "Frost" }) do
    truthy(text(mage.args["spec" .. i]):find("\226\128\162 ", 1, true), "a bullet for " .. spec)
    truthy(text(mage.args["spec" .. i]):find(spec, 1, true) and text(mage.args["spec" .. i]):find("%dg"), spec)
  end
  truthy(text(mage.args.count_keep):find("Worth buying", 1, true) and text(mage.args.count_keep):find("%d"))
  ns.db.profile.ruleOff = { kinds = { skipRank = true } }
  local before = text(mage.args.spec1)
  eq(text(ns.Options.Rules().args.MAGE.args.spec1), before, "player settings do not change the totals")
end)

test("switch worth: a rule kind, a tag and an ability are each worth their savings", function()
  local p = profile("HUNTER", { "BM" }, { skipRevision = 1 })
  local stop = 60
  local skip = ns.Savings.Worth(p, stop, nil, "offKinds", "skipRank")
  eq(skip, ns.Savings.Compute(p, stop).skip, "skipped ranks are worth exactly what they save")
  -- Revision 2 skips some ranks other rules would defer anyway, so switching the kind off gives back at most what it saves.
  local newest = profile("HUNTER", { "BM" })
  truthy(ns.Savings.Worth(newest, stop, nil, "offKinds", "skipRank") <= ns.Savings.Compute(newest, stop).skip)
  truthy(ns.Savings.Worth(p, stop, nil, "offTags", "RaidGroup") > 0)
  local byFamily = ns.Savings.ByAbility(p, stop)
  local shot = H.fid(ns, "HUNTER", "Distracting Shot")
  truthy(byFamily[shot] and byFamily[shot] > 0)
  eq(ns.Savings.Worth(p, stop, nil, "offKinds", "nothing"), 0)
end)

test("switch worth: switches show their gold, and a switched-off ability still shows its value", function()
  ns.db = { profile = {}, char = { costCache = {} } }
  ns.Context = { Profile = function() return { class = "HUNTER", plausibleSpecs = { "BM" }, milestone = { current = 40, state = "active" }, rules = { skipRevision = 1 } } end }
  local function desc(w) local d = w.desc; if type(d) == "function" then d = d() end; return d end
  local tuning = ns.Options.Tuning().args
  truthy(desc(tuning.kind_skipRank):find("Worth about", 1, true), "rule kinds show gold")
  local hunter = ns.Options.Rules().args.HUNTER.args
  truthy(desc(hunter.choices.args.tag_RaidGroup):find("Worth about", 1, true), "tags show gold")
  local function find(cat)
    for _, g in pairs(cat.args) do
      if g.type == "group" then for _, w in pairs(g.args) do if w.name == "Distracting Shot" then return w end end end
    end
  end
  local line = find(hunter.wait)
  truthy(line and desc(line):find("Worth about", 1, true), "abilities show gold")
  ns.db.profile.ruleOff = { abilities = { HUNTER = { [H.fid(ns, "HUNTER", "Distracting Shot")] = true } } }
  truthy(desc(line):find("Worth about", 1, true), "still shows what it is worth when switched off")
end)

test("savings: a rank-less row never takes another spell's seen price, and a missing price is flagged", function()
  local r = ns.Savings.Compute(profile("PALADIN", nil), 60, { [ns.Ledger.CostKey(H.fid(ns, "PALADIN", "Holy Light"), nil)] = 5 })
  local base = ns.Savings.Compute(profile("PALADIN", nil), 60)
  eq(r.total, base.total, "a nil-rank cache key changes nothing")
end)

test("switch worth: a price learned at a trainer refreshes the shown value", function()
  ns.db = { profile = {}, char = { costCache = {} } }
  ns.Context = { Profile = function() return { class = "HUNTER", plausibleSpecs = { "BM" }, milestone = { current = 40, state = "active" }, rules = { skipRevision = 1 } } end }
  local function desc(w) local d = w.desc; if type(d) == "function" then d = d() end; return d end
  local tuning = ns.Options.Tuning().args
  local before = desc(tuning.kind_skipRank)
  ns.db.char.costCache[ns.Ledger.CostKey(H.fid(ns, "HUNTER", "Mend Pet"), 6)] = 9999999
  truthy(desc(tuning.kind_skipRank) ~= before, "the value follows the newly seen price")
end)

test("savings: a price saved under an English name by an earlier version is ignored", function()
  local base = ns.Savings.Compute(profile("HUNTER", { "BM" }), 60)
  local r = ns.Savings.Compute(profile("HUNTER", { "BM" }), 60, { ["Distracting Shot1"] = 999999, ["Distracting Shot#1"] = 999999 })
  eq(r.total, base.total)
end)

test("savings: the projected savings follow the skip revision in use", function()
  local one = ns.Savings.Compute(profile("WARRIOR", { "ARMS" }, { skipRevision = 1 }), 60)
  local two = ns.Savings.Compute(profile("WARRIOR", { "ARMS" }, { skipRevision = 2 }), 60)
  local default = ns.Savings.Compute(profile("WARRIOR", { "ARMS" }), 60)
  truthy(one.skip > 0 and two.skip > 0)
  truthy(one.skip ~= two.skip, "revision 1 and 2 skip different ranks")
  eq(default.skip, two.skip, "no pick means the newest")
  -- Worth keeps the revision when it switches the kind off.
  eq(ns.Savings.Worth(profile("WARRIOR", { "ARMS" }, { skipRevision = 1 }), 60, nil, "offKinds", "skipRank") <= one.skip, true)
end)
