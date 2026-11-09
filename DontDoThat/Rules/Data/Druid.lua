local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.
-- Written by tools/scaffold_class_rules.py from tools/class_plans/druid.py.
-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_classes_test.lua fails on any that does not.

-- What every spec of this class keeps buying.
local SHARED_CORE = {
  "Mark of the Wild", "Healing Touch", "Rejuvenation", "Regrowth", "Barkskin", "Cat Form", "Bear Form",
  "Dire Bear Form", "Travel Form", "Revive", "Rebirth",
}
-- Handy now and then for any spec. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = {
  "Thorns", "Aquatic Form", "Demoralizing Roar", "Cure Poison", "Abolish Poison", "Remove Curse",
  "Hurricane", "Teleport: Moonglade", "Nature's Grasp",
}

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "DRUID",

  specs = {
    BAL = {
      name = L["Balance"], tree = 1, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Wrath", "Moonfire", "Starfire", "Insect Swarm", "Entangling Roots", "Faerie Fire", "Moonkin Form" }), situational = with(SHARED_SITUATIONAL, { "Starsurge", "Starfall", "Sunfire" }) },
    },
    FERAL = {
      name = L["Feral"], tree = 2, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Faerie Fire (Feral)", "Claw", "Rake", "Rip", "Shred", "Ferocious Bite", "Maul", "Swipe", "Lacerate", "Pounce", "Ravage", "Prowl", "Dash", "Growl", "Enrage", "Bash", "Feral Charge", "Primal Bite", "Thrash (Cat)", "Skull Bash", "Frenzied Regeneration" }), situational = with(SHARED_SITUATIONAL, { "Mangle", "Tiger's Fury", "Savage Roar", "Berserk", "Survival Instincts" }) },
    },
    RESTO = {
      name = L["Restoration"], tree = 3, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, {}), situational = with(SHARED_SITUATIONAL, { "Lifebloom", "Nourish" }) },
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
    ["Challenging Roar"] = L["A group taunt."],
    ["Cower"] = L["Lowers threat. Only needed in groups."],
    ["Gift of the Wild"] = L["Costs a reagent each cast. Not needed while leveling."],
    ["Hibernate"] = L["Only works on beasts and dragonkin."],
    ["Soothe Animal"] = L["Only calms a few animals."],
    ["Track Humanoids"] = L["A tracking toy you can live without."],
    ["Tranquility"] = L["A group heal."],
    ["Wild Growth"] = L["A group heal."],
  },

  tags = {
    ["Soothe Animal"] = { "LowValue" },
    ["Hibernate"] = { "LowValue" },
    ["Track Humanoids"] = { "LowValue" },
    ["Cower"] = { "LowValue" },
    ["Tranquility"] = { "RaidGroup" },
    ["Challenging Roar"] = { "RaidGroup" },
    ["Wild Growth"] = { "RaidGroup" },
    ["Gift of the Wild"] = { "Endgame" },
  },

  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.
  talentSpells = {
    "Faerie Fire (Feral)", "Feral Charge", "Gift of Nature", "Insect Swarm", "Leader of the Pack",
    "Moonkin Form", "Nature's Grasp", "Tranquil Spirit",
  },

  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.
  reviewed = {
    "Abolish Poison Effect", "Aquatic Form (Passive)", "Barkskin Effect (DND)", "Bear Form (Passive)",
    "Bear Form (Passive2)", "Cat Form (Passive)", "Deeper Wilds", "Dire Bear Form (Passive)", "Efflorescence",
    "Enhanced Restoration", "Feline Grace", "Feral Combat", "Gift of Nature", "Leader of the Pack",
    "Living Seed", "Moonkin Aura", "Moonkin Form (Passive)", "Poised", "Pounce Bleed",
    "S03 - Tuning and Overrides Passive - Druid", "Shifting Power", "Tranquil Spirit",
  },
})
