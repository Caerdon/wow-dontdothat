package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- The trainer window shows the reason a rank is skipped: the badge tooltip and the "Buy anyway?" question both read
-- the verdict's reason, so they carry the same words, with no source label.

local ns = {}
H.loadSpellTables(ns)
for _, f in ipairs({ "Rules/Schema.lua", "Rules/Engine.lua", "Rules/Data/Warrior.lua", "Rules/Data/Hunter.lua", "Model/Milestones.lua", "Model/Settings.lua",
  "Model/SkipRevision.lua", "Model/SpecInference.lua", "Model/PlayerProfile.lua", "Intercepts/Adapter.lua", "Intercepts/Context.lua",
  "Intercepts/Trainer.lua", "UI/Helpers.lua", "UI/ConfirmPopup.lua" }) do
  H.load("DontDoThat/" .. f, ns)
end

local ROWS = {
  { "Arms", nil, "header" },
  { "Rend", "Rank 5", "available", 22000, 40 },
  { "Rend", "Rank 4", "available", 12000, 30 },
  { "Thunder Clap", "Rank 3", "available", 4000, 28 },
  { "Overpower", "Rank 2", "available", 800, 16 },
}

local function env(class)
  local e = {}
  e.UnitClass = function() return class, class:upper(), 1 end
  e.UnitLevel = function() return 41 end
  e.UnitName = function() return "Trainer" end
  e.GetNumTrainerServices = function() return #ROWS end
  e.GetTrainerServiceInfo = function(i) local r = ROWS[i]; return r[1], r[2], r[3], 1 end
  e.GetTrainerServiceCost = function(i) return ROWS[i][4] end
  e.GetTrainerServiceLevelReq = function(i) return ROWS[i][5] end
  e.GetNumTalentTabs = function() return 3 end
  e.GetTalentTabInfo = function(i) return 160 + i, ({ "Arms", "Fury", "Protection" })[i], "", 132164, i == 1 and 20 or 0, "Background" end
  return e
end

local function compute(profile)
  ns.db = { profile = profile or {} }
  return ns.TrainerOverlay.Compute(env("Warrior"))
end

test("training window: a skipped rank's tooltip says why, in the words of the guide that decided it", function()
  local c = compute()
  eq(c.verdicts[2].source, "skipRank"); eq(c.verdicts[2].tier, "defer")
  eq(c.verdicts[2].reason, "The leveling guide says to buy this spell only up to rank 4.")
  eq(c.verdicts[3].source ~= "skipRank", true, "rank 4 is within the guide's limit")
  eq(c.verdicts[4].reason, "The leveling guide says to buy only the first rank of this spell.")
  eq(c.verdicts[5].reason, "The leveling guide says to buy only the first rank of this spell.")
end)

test("training window: the reason names no source and no internal term", function()
  local c = compute()
  for _, i in ipairs({ 2, 4, 5 }) do
    local reason = c.verdicts[i].reason
    falsy(reason:find("Wowhead", 1, true), reason)
    falsy(reason:find("computed", 1, true), reason)
    falsy(reason:find("revision", 1, true), reason)
    falsy(reason:find("tier", 1, true), reason)
  end
end)

test("training window: on revision 1 each rank states what revision 1 records for it", function()
  local c = compute({ tuning = { skipRevision = 1 } })
  eq(c.verdicts[2].reason, "The leveling guide says to buy this spell only up to rank 4.")
  eq(c.verdicts[5].reason, "The leveling guide says to buy only the first rank of this spell.")
end)

test("training window: the Buy anyway question gives the same reason as the tooltip", function()
  local c = compute()
  local asked
  ns.ConfirmPopup.Show = function(text) asked = text; return true end
  ns.ConfirmPopup.Ask(c.verdicts[2], function() end, function() end)
  truthy(asked and asked:find(c.verdicts[2].reason, 1, true), "the question includes the tooltip's reason")
  truthy(asked:find("Buy anyway?", 1, true))
end)

test("training window: a rank the player switched off warnings for is not marked", function()
  local family = H.fid(ns, "WARRIOR", "Rend")
  local c = compute({ ruleOff = { abilities = { WARRIOR = { [family] = true } } } })
  eq(c.verdicts[2].tier, "keep")
  eq(c.verdicts[2].source, "disabled")
end)
