local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.
-- Written by tools/scaffold_class_rules.py from tools/class_plans/rogue.py.
-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_classes_test.lua fails on any that does not.

-- What every spec of this class keeps buying.
local SHARED_CORE = {
  "Sinister Strike", "Eviscerate", "Slice and Dice", "Stealth", "Garrote", "Cheap Shot", "Gouge",
  "Sap", "Evasion", "Sprint", "Kick", "Vanish", "Kidney Shot", "Instant Poison", "Instant Poison II",
  "Instant Poison III", "Instant Poison IV", "Instant Poison V", "Instant Poison VI", "Deadly Poison",
  "Deadly Poison II", "Deadly Poison III", "Deadly Poison IV", "Deadly Poison V",
}
-- Handy now and then for any spec. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = {
  "Rupture", "Pick Pocket", "Blind", "Blinding Powder", "Safe Fall", "Crippling Poison",
  "Crippling Poison II",
}

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "ROGUE",

  specs = {
    ASSN = {
      name = L["Assassination"], tree = 1, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Backstab", "Mutilate", "Rupture" }), situational = SHARED_SITUATIONAL },
    },
    COMBAT = {
      name = L["Combat"], tree = 2, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, {}), situational = with(SHARED_SITUATIONAL, { "Backstab" }) },
    },
    SUBT = {
      name = L["Subtlety"], tree = 3, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Backstab", "Ambush", "Hemorrhage" }), situational = SHARED_SITUATIONAL },
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
    ["Detect Traps"] = L["Rarely helps while leveling."],
    ["Disarm Trap"] = L["Rarely helps while leveling."],
    ["Distract"] = L["Rarely helps while leveling."],
    ["Expose Armor"] = L["A group debuff you can do without."],
    ["Feint"] = L["Lowers your threat. Only needed in groups."],
    ["Mind-numbing Poison"] = L["A utility poison you can do without."],
    ["Mind-numbing Poison II"] = L["A utility poison you can do without."],
    ["Mind-numbing Poison III"] = L["A utility poison you can do without."],
    ["Occult Poison I"] = L["A utility poison you can do without."],
    ["Occult Poison II"] = L["A utility poison you can do without."],
    ["Wound Poison"] = L["A utility poison you can do without."],
    ["Wound Poison II"] = L["A utility poison you can do without."],
    ["Wound Poison III"] = L["A utility poison you can do without."],
    ["Wound Poison IV"] = L["A utility poison you can do without."],
  },

  tags = {
    ["Expose Armor"] = { "LowValue" },
    ["Feint"] = { "LowValue" },
    ["Detect Traps"] = { "LowValue" },
    ["Disarm Trap"] = { "LowValue" },
    ["Mind-numbing Poison"] = { "LowValue" },
    ["Mind-numbing Poison II"] = { "LowValue" },
    ["Mind-numbing Poison III"] = { "LowValue" },
    ["Wound Poison"] = { "LowValue" },
    ["Wound Poison II"] = { "LowValue" },
    ["Wound Poison III"] = { "LowValue" },
    ["Wound Poison IV"] = { "LowValue" },
    ["Occult Poison I"] = { "LowValue" },
    ["Occult Poison II"] = { "LowValue" },
    ["Atrophic Poison"] = { "LowValue" },
    ["Numbing Poison"] = { "LowValue" },
    ["Sebacious Poison"] = { "LowValue" },
    ["Distract"] = { "LowValue" },
  },

  overrides = {
    ["Dual Wield"] = "keep",
  },

  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.
  talentSpells = {
    "Ghostly Strike", "Hemorrhage",
  },

  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.
  reviewed = {
    "Between the Eyes", "Blade Dance", "Death Mark", "Envenom", "Ghostly Strike", "Main Gauche", "Poised", "Poisoned Knife",
    "Poisons", "Quick Draw", "Redirect", "Rogue Passive (DND)", "Saber Slash", "Shadowstrike", "Shank", "Shiv",
    "Shuriken Toss", "Venom",
  },
})
