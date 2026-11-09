package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = {}
H.loadSpellTables(ns)
H.load("DontDoThat/Rules/Schema.lua", ns)
H.load("DontDoThat/Rules/Engine.lua", ns)
H.load("DontDoThat/Model/Milestones.lua", ns)
H.load("DontDoThat/Model/Settings.lua", ns)
H.load("DontDoThat/Model/PlayerProfile.lua", ns)
H.load("DontDoThat/Data/Sounds.lua", ns)
H.load("DontDoThat/UI/Helpers.lua", ns)
H.load("DontDoThat/UI/Alert.lua", ns)

ns.Rules.Load({
  class = "TEST",
  specs = {
    A = { name = "Alpha", rotation = { core = { "ACore" }, situational = {} } },
    B = { name = "Beta", rotation = { core = { "BCore" }, situational = {} } },
  },
  tagTiers = { PvP = "deferLow", Raid = "defer" },
  tags = { Pvper = { "PvP" }, Both = { "PvP", "Raid" } },
  skipRevisions = H.skipRevisions({ Skipper = { 2 } }),
  ranks = { Plain = { { rank = 1, unlockLevel = 4 }, { rank = 2, unlockLevel = 10 } } },
}, H.sameKeys)

local function profile(rules, specs)
  return { class = "TEST", level = 25, plausibleSpecs = specs or { "A" }, rules = rules,
    milestone = { current = 40, state = "active" } }
end
local function spell(name, extra)
  local a = { kind = "spell", name = name, familyId = name }
  for k, v in pairs(extra or {}) do a[k] = v end
  return a
end
local E = ns.Rules.Evaluate

test("rules: untouched settings change nothing", function()
  eq(E(profile(nil), spell("Pvper")).tier, "deferLow")
  eq(E(profile({}), spell("Pvper")).tier, "deferLow")
  eq(E(profile(ns.Settings.RulesFor("TEST", {})), spell("Pvper")).tier, "deferLow")
end)

test("rules: switched-off ability is kept, before any other rule", function()
  local v = E(profile({ offAbilities = { Pvper = true, Skipper = true } }), spell("Skipper", { rank = 2 }))
  eq(v.tier, "keep"); eq(v.source, "disabled")
  eq(E(profile({ offAbilities = { Pvper = true } }), spell("Pvper")).tier, "keep")
end)

test("rules: switched-off tag is ignored, others still decide", function()
  eq(E(profile({ offTags = { PvP = true } }), spell("Pvper")).tier, "keep")
  local v = E(profile({ offTags = { PvP = true } }), spell("Both"))
  eq(v.tier, "defer")
  local w = E(profile({ offTags = { Raid = true } }), spell("Both"))
  eq(w.tier, "deferLow")
end)

test("rules: rule kinds switch off individually", function()
  eq(E(profile(nil), spell("Skipper", { rank = 2 })).source, "skipRank")
  eq(E(profile({ offKinds = { skipRank = true } }), spell("Skipper", { rank = 2 })).tier, "keep")
  local offSpec = spell("BCore")
  eq(E(profile(nil), offSpec).source, "rotation")
  eq(E(profile({ offKinds = { offSpec = true } }), offSpec).tier, "keep")
end)

test("settings: numbers must be whole and zero or more", function()
  eq(ns.Settings.Number(6), 6); eq(ns.Settings.Number(0), 0)
  eq(ns.Settings.Number(-1), nil); eq(ns.Settings.Number("4"), nil); eq(ns.Settings.Number(2.5), nil)
end)

test("settings: RulesFor reads one class's switches", function()
  local r = ns.Settings.RulesFor("TEST", { ruleOff = {
    abilities = { TEST = { Pvper = true }, OTHER = { X = true } }, tags = { TEST = { PvP = true } },
    kinds = { skipRank = true } } })
  eq(r.offAbilities, { Pvper = true }); eq(r.offTags, { PvP = true }); eq(r.offKinds, { skipRank = true })
end)

test("settings: prompt tiers default to defer only; keep never counts", function()
  eq(ns.Settings.PromptTiers({}), { defer = true, deferLow = false, info = false })
  truthy(ns.Settings.PromptsFor("defer", {}))
  falsy(ns.Settings.PromptsFor("deferLow", {}))
  local p = { tuning = { promptTiers = { defer = true, deferLow = true } } }
  truthy(ns.Settings.PromptsFor("deferLow", p)); falsy(ns.Settings.PromptsFor("info", p))
  falsy(ns.Settings.PromptsFor("keep", { tuning = { promptTiers = { keep = true } } }))
  falsy(ns.Settings.PromptsFor("defer", { tuning = { promptTiers = {} } }), "no tiers ticked")
end)

test("settings: spec override only when the class has the spec", function()
  local data = ns.Rules.GetClass("TEST")
  eq(ns.Settings.SpecOverride("TEST", data, { specOverride = { TEST = "B" } }), "B")
  eq(ns.Settings.SpecOverride("TEST", data, { specOverride = { TEST = "Z" } }), nil)
  eq(ns.Settings.SpecOverride("TEST", data, {}), nil)
end)

test("settings: stop after defaults to the level 60 mount", function()
  eq(ns.Settings.StopAfter({}), 60); eq(ns.Settings.StopAfter({ tuning = { stopAfter = 40 } }), 40)
  eq(ns.Settings.StopAfter({ tuning = { stopAfter = 7 } }), 60)
end)

test("milestones: stopping after the 40 mount finishes once it is bought", function()
  eq(ns.Milestones.State(false, false, nil, 40), { current = 40, state = "active" })
  eq(ns.Milestones.State(true, false, nil, 40), { current = nil, state = "finished" })
  eq(ns.Milestones.State(false, false, { [40] = true }, 40), { current = nil, state = "finished" })
  eq(ns.Milestones.State(true, false, nil, 60), { current = 60, state = "active" })
  eq(ns.Milestones.State(true, false, nil), { current = 60, state = "active" })
end)

test("profile: carries the rules and stop after", function()
  local p = ns.PlayerProfile.Build({ class = "TEST", level = 30, treePoints = {}, plausibleSpecs = { "A" },
    rules = { offTags = { PvP = true } }, ridingLearned40 = true, stopAfter = 40 })
  eq(p.rules.offTags, { PvP = true })
  eq(p.milestone.state, "finished")
end)

test("alert: extra chosen tiers sound; unchosen do not; default is defer only", function()
  local deferLow = { tier = "deferLow", cost = 100 }
  falsy(ns.Alert.Trigger(deferLow, "k1", { alertSound = "raidwarning" }, 1))
  falsy(ns.Alert.Trigger(deferLow, "k2", { alertTiers = { defer = true } }, 1))
  truthy(ns.Alert.Trigger(deferLow, "k3", { alertTiers = { deferLow = true }, alertBanner = false }, 1))
  falsy(ns.Alert.Trigger({ tier = "defer" }, "k4", { alertTiers = { defer = false, deferLow = false } }, 1), "no tiers")
end)

test("alert: cooldown falls back to the default of 3 seconds", function()
  local d = { tier = "defer", cost = 100 }
  truthy(ns.Alert.Trigger(d, "cd", { alertBanner = false }, 100))
  falsy(ns.Alert.Trigger(d, "cd", { alertBanner = false }, 102))
  truthy(ns.Alert.Trigger(d, "cd", { alertBanner = false }, 103))
end)

test("alert: channel is used when valid, else Master", function()
  local used
  _G.PlaySound = function(id, channel) used = channel; return true end
  _G.SOUNDKIT = { RAID_WARNING = 8959 }
  ns.Alert.PlaySound("raidwarning", { alertChannel = "Dialog" }); eq(used, "Dialog")
  ns.Alert.PlaySound("raidwarning", { alertChannel = "Bogus" }); eq(used, "Master")
  ns.Alert.PlaySound("raidwarning"); eq(used, "Master")
  _G.PlaySound, _G.SOUNDKIT = nil, nil
end)

test("rules: default settings leave every Hunter verdict unchanged", function()
  H.load("DontDoThat/Rules/Data/Hunter.lua", ns)
  local data = ns.Rules.GetClass("HUNTER")
  local names = {}
  for name in pairs(data.tags or {}) do names[name] = true end
  for name in pairs(data.overrides or {}) do names[name] = true end
  for name in pairs(data.skipRevisions[1].entries or {}) do names[name] = true end
  for name in pairs(data.ranks or {}) do names[name] = true end
  for _, spec in pairs(data.specs) do
    for _, n in ipairs(spec.rotation.core or {}) do names[n] = true end
    for _, n in ipairs(spec.rotation.situational or {}) do names[n] = true end
  end
  local defaults = ns.Settings.RulesFor("HUNTER", {})
  local checked = 0
  for name in pairs(names) do
    for _, specs in ipairs({ { "BM" }, { "MM" }, { "SV" }, {} }) do
      for rank = 1, 3 do
        local function p(rules) return { class = "HUNTER", level = 40, plausibleSpecs = specs, rules = rules,
          milestone = { current = 40, state = "active" } } end
        local a = spell(name, { rank = rank })
        eq(E(p(defaults), a), E(p(nil), a), name)
        checked = checked + 1
      end
    end
  end
  truthy(checked > 100, "swept enough cases")
end)

test("settings: debug recording is switched off whenever the addon loads", function()
  local p = { debug = true, traceItems = true, enabled = true }
  ns.Settings.ClearDebug(p)
  eq(p.debug, false); eq(p.traceItems, false); eq(p.enabled, true)
end)

test("settings: reset all clears every setting except what the player has already done", function()
  local p = { enabled = false, watch = { shopping = false }, tuning = { stopAfter = 40 }, professionAsked = { [2575] = true },
    milestoneOverride = { [60] = true }, debug = true }
  ns.Settings.ResetAll(p)
  eq(p, { professionAsked = { [2575] = true }, milestoneOverride = { [60] = true } })
  ns.Settings.ResetAll(nil)
end)
