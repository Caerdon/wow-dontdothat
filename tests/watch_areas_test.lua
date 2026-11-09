package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- Nudge level and the watch-area switches (Model/Settings.lua), and what the switches do.
local ns = {}
for _, f in ipairs({ "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua", "Rules/Data/Hunter.lua", "Model/SpecInference.lua",
  "Model/Milestones.lua", "Model/Settings.lua", "Model/PlayerProfile.lua", "Intercepts/Adapter.lua",
  "Intercepts/Context.lua", "Intercepts/Trainer.lua" }) do
  H.load("DontDoThat/" .. f, ns)
end

test("nudge: a fresh profile is Ask me first", function()
  eq(ns.Settings.Nudge({}), "ask")
  eq(ns.Settings.Nudge(nil), "ask")
end)

test("nudge: each level sets the saved values and reads back", function()
  for _, level in ipairs({ "mark", "ask", "everything" }) do
    local p = { warnings = false, blockingConfirmations = false, tuning = { promptTiers = { info = true } } }
    ns.Settings.SetNudge(level, p)
    eq(ns.Settings.Nudge(p), level, level)
  end
  local p = {}
  ns.Settings.SetNudge("everything", p)
  eq(p.tuning.promptTiers, { defer = true, deferLow = true, info = true })
  eq(p.warnings, true); eq(p.blockingConfirmations, true)
end)

test("nudge: values matching no level read as custom, and choosing custom changes nothing", function()
  local p = { tuning = { promptTiers = { defer = true, deferLow = true, info = false } } }
  eq(ns.Settings.Nudge(p), "custom")
  ns.Settings.SetNudge("custom", p)
  eq(ns.Settings.Nudge(p), "custom")
  eq(ns.Settings.Nudge({ warnings = false }), "custom", "marks off")
  eq(ns.Settings.Nudge({ tuning = { promptTiers = {} } }), "custom", "no tier asks")
end)

test("nudge: sound settings do not change the level", function()
  eq(ns.Settings.Nudge({ alerts = false, alert = { banner = false } }), "ask")
end)

test("areas: on by default, off only when saved as false, and the inner settings are kept", function()
  for _, area in ipairs(ns.Settings.Areas) do truthy(ns.Settings.Watching(area, {}), area) end
  local p = { itemModes = { armor = "both" } }
  ns.Settings.SetWatching("shopping", false, p)
  falsy(ns.Settings.Watching("shopping", p)); truthy(ns.Settings.Watching("spells", p))
  eq(p.itemModes.armor, "both")
  ns.Settings.SetWatching("shopping", true, p)
  truthy(ns.Settings.Watching("shopping", p))
end)

-- Trainer rows: a class spell and a profession first-tier row.
local ROWS = {
  { "Distracting Shot", "Rank 1", "available", 600, 12 },
  { "Leatherworking", "Apprentice", "available", 100, 5 },
}
local function env()
  local e = {}
  e.UnitClass = function() return "Hunter", "HUNTER", 3 end
  e.UnitLevel = function() return 10 end
  e.UnitName = function() return "Hunter Trainer" end
  e.GetNumTrainerServices = function() return #ROWS end
  e.GetTrainerServiceInfo = function(i) local r = ROWS[i]; return r[1], r[2], r[3], 1 end
  e.GetTrainerServiceCost = function(i) return ROWS[i][4] end
  e.GetTrainerServiceLevelReq = function(i) return ROWS[i][5] end
  e.GetNumTalentTabs = function() return 3 end
  e.GetTalentTabInfo = function(i) return 360 + i, ({ "Beast Mastery", "Marksmanship", "Survival" })[i], "", 1, 0, "bg" end
  return e
end
ns.Rules.SetProfessionLearn({ gathering = {}, apprentice = { Leatherworking = 2108 }, reason = "%s is not needed yet." })

test("spells off: spell rows get no verdict, profession rows still do", function()
  ns.db = { profile = {} }
  local c = ns.TrainerOverlay.Compute(env())
  eq(c.verdicts[1].tier, "defer"); eq(c.verdicts[2].tier, "defer")
  ns.Settings.SetWatching("spells", false)
  c = ns.TrainerOverlay.Compute(env())
  eq(c.verdicts[1], nil); eq(c.verdicts[2].tier, "defer")
  ns.Settings.SetWatching("spells", true)
  eq(ns.TrainerOverlay.Compute(env()).verdicts[1].tier, "defer")
end)

test("professions off: profession rows get no verdict, spell rows still do", function()
  ns.db = { profile = {} }
  ns.Settings.SetWatching("professions", false)
  local c = ns.TrainerOverlay.Compute(env())
  eq(c.verdicts[1].tier, "defer"); eq(c.verdicts[2], nil)
end)
