local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.
-- Written by tools/scaffold_class_rules.py from tools/class_plans/warrior.py.
-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_classes_test.lua fails on any that does not.

-- What every spec of this class keeps buying.
local SHARED_CORE = {
  "Heroic Strike", "Battle Shout", "Rend", "Charge", "Overpower", "Execute", "Bloodrage",
  "Sunder Armor", "Hamstring", "Pummel", "Shield Bash",
}
-- Handy now and then for any spec. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = {
  "Intercept", "Demoralizing Shout", "Mocking Blow", "Retaliation", "Berserker Rage", "Shield Wall",
  "Recklessness", "Victory Rush", "Cleave", "Whirlwind", "Berserker Stance", "Defensive Stance",
}

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "WARRIOR",

  specs = {
    ARMS = {
      name = L["Arms"], tree = 1, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Mortal Strike", "Sweeping Strikes" }), situational = SHARED_SITUATIONAL },
    },
    FURY = {
      name = L["Fury"], tree = 2, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Bloodthirst", "Whirlwind", "Berserker Stance", "Cleave" }), situational = SHARED_SITUATIONAL },
    },
    PROT = {
      name = L["Protection"], tree = 3, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Revenge", "Taunt", "Shield Block", "Defensive Stance", "Shield Slam", "Demoralizing Shout" }), situational = SHARED_SITUATIONAL },
    },
  },

  tagTiers = { PvP = "deferLow", RaidGroup = "defer", LowValue = "deferLow", Endgame = "defer" },

  tagReasons = {
    PvP = L["Mostly useful against other players."],
    RaidGroup = L["Only needed in groups and raids."],
    LowValue = L["Rarely helps while leveling."],
    Endgame = L["You won't need this until level 60."],
  },
  why = {
    ["Challenging Shout"] = L["A group taunt for tanking."],
    ["Disarm"] = L["Mostly useful against other players."],
    ["Intimidating Shout"] = L["Mostly useful against other players."],
    ["Slam"] = L["Slows your swings down. Heroic Strike does the job."],
    ["Thunder Clap"] = L["Costs a lot of rage for little damage while soloing."],
  },

  tags = {
    ["Disarm"] = { "PvP" },
    ["Intimidating Shout"] = { "PvP" },
    ["Challenging Shout"] = { "RaidGroup" },
    ["Thunder Clap"] = { "LowValue" },
    ["Slam"] = { "LowValue" },
  },

  overrides = {
    ["Plate Mail"] = "keep",
    ["Dual Wield"] = "keep",
  },

  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.
  talentSpells = {
    "Bloodthirst", "Dual Wield Specialization", "Mortal Strike", "Shield Slam", "Sweeping Strikes",
    "Tactical Mastery",
  },

  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.
  reviewed = {
    "Battle Stance", "Battle Stance Passive", "Berserker Stance Passive", "Commanding Shout",
    "Defensive Stance Passive", "Devastate", "Dual Wield Specialization", "Enraged Regeneration",
    "Intervene", "Meathook", "Quick Strike", "Raging Blow", "Rallying Cry", "Shockwave",
    "Spearing Strike", "Tactical Mastery", "Valor of Azeroth",
  },
})
