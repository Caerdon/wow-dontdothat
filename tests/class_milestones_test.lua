package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local function fresh(class)
  local ns = { version = "0.1.0" }
  for _, f in ipairs({ "UI/Helpers.lua", "Data/Sounds.lua", "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua", "Rules/Data/Hunter.lua",
    "Rules/Data/Paladin.lua", "Rules/Data/Warlock.lua", "Model/Milestones.lua", "Model/Settings.lua", "Model/ItemCategory.lua", "Options/Options.lua" }) do
    H.load("DontDoThat/" .. f, ns)
  end
  ns.db = { profile = {} }
  ns.Context = { Profile = function() return { class = class, milestone = { current = 40, state = "active" } } end }
  return ns
end

local GOLD = 10000

test("targets: a class override replaces only the milestone it names", function()
  local ns = fresh("PALADIN")
  local paladin, hunter = ns.Milestones.For("PALADIN"), ns.Milestones.For("HUNTER")
  eq(paladin[40].riding + paladin[40].mount, 10 * GOLD)
  eq(paladin[60], ns.Milestones.Defaults[60], "level 60 keeps the default")
  eq(hunter[40], ns.Milestones.Defaults[40]); eq(hunter[60], ns.Milestones.Defaults[60])
  eq(ns.Milestones.For(nil)[40], ns.Milestones.Defaults[40])
  eq(ns.Milestones.For("MAGE")[40], ns.Milestones.Defaults[40], "a class with no data gets the defaults")
end)

test("the milestone list shows the Paladin target and joke, and nothing extra for a Hunter", function()
  local ns = fresh("PALADIN")
  local paladin = ns.Options.MilestoneItems("PALADIN")
  truthy(paladin[1].detail:find("10g", 1, true) or paladin[1].detail:find("10 ", 1, true), paladin[1].detail)
  truthy(paladin[1].detail:find("The Light covers your first ride", 1, true))
  local hunter = ns.Options.MilestoneItems("HUNTER")
  falsy(hunter[1].detail:find("Light", 1, true))
  falsy(hunter[1].detail:find("10g", 1, true))
  eq(paladin[2].detail, hunter[2].detail, "the level 60 line is the same")
end)

test("progress compares your gold with the Paladin target", function()
  local ns = fresh("PALADIN")
  local line = ns.Options.MilestoneProgress({ GetMoney = function() return 6 * GOLD end })
  truthy(line:find("60%%"), line)
  local enough = ns.Options.MilestoneProgress({ GetMoney = function() return 12 * GOLD end })
  truthy(enough:find("enough for your level 40 mount", 1, true), enough)
  local hunter = fresh("HUNTER")
  truthy(hunter.Options.MilestoneProgress({ GetMoney = function() return 6 * GOLD end }):find("6%%"))
end)

test("an edited class cost shows up in the list", function()
  local ns = fresh("PALADIN")
  ns.Rules.GetClass("PALADIN").milestones[40].riding = 3 * GOLD
  local detail = ns.Options.MilestoneItems("PALADIN")[1].detail
  truthy(detail:find("3g", 1, true) or detail:find("3 ", 1, true), detail)
end)

test("a Warlock's level 40 mount costs nothing and carries the Felsteed note; level 60 is the default", function()
  local ns = fresh("WARLOCK")
  local targets = ns.Milestones.For("WARLOCK")
  eq(targets[40].riding + targets[40].mount, 0)
  eq(targets[60], ns.Milestones.Defaults[60])
  local detail = ns.Options.MilestoneItems("WARLOCK")[1].detail
  truthy(detail:find("Your Felsteed is paid for in souls, not gold.", 1, true), detail)
  eq(ns.Options.MilestoneProgress({ GetMoney = function() return 5 * GOLD end }), nil, "no progress line for a free mount")
end)
