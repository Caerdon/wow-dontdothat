local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.
-- Written by tools/scaffold_class_rules.py from tools/class_plans/priest.py.
-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_classes_test.lua fails on any that does not.

-- What every spec of this class keeps buying.
local SHARED_CORE = {
  "Power Word: Fortitude", "Power Word: Shield", "Shadow Word: Pain", "Mind Blast", "Renew",
  "Lesser Heal", "Heal", "Flash Heal", "Inner Fire", "Resurrection",
}
-- Handy now and then for any spec. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = {
  "Dispel Magic", "Cure Disease", "Abolish Disease", "Psychic Scream", "Greater Heal", 
  "Prayer of Healing", "Holy Nova", "Power Infusion", "Penance", "Mind Flay", "Vampiric Embrace",
  "Devouring Plague", "Starshards", "Desperate Prayer", "Touch of Weakness", "Hex of Weakness",
  "Chastise", "Levitate",
}

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "PRIEST",

  specs = {
    DISC = {
      name = L["Discipline"], tree = 1, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Smite" }), situational = SHARED_SITUATIONAL },
    },
    HOLY = {
      name = L["Holy"], tree = 2, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Smite", "Greater Heal" }), situational = with(SHARED_SITUATIONAL, { "Circle of Healing" }) },
    },
    SHADOW = {
      name = L["Shadow"], tree = 3, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Mind Flay", "Vampiric Embrace", "Shadowform", "Devouring Plague", "Silence" }), situational = with(SHARED_SITUATIONAL, { "Mind Spike", "Void Plague", "Shadowfiend", "Dispersion", "Mind Sear", "Vampiric Touch", "Shadow Word: Death" }) },
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
    ["Divine Spirit"] = L["A group buff."],
    ["Elune's Grace"] = L["A small defensive bonus most players never notice."],
    ["Fade"] = L["Lowers your threat. Only needed in groups."],
    ["Fear Ward"] = L["Mostly a PvP and raid tool."],
    ["Feedback"] = L["Only counters enemy mana burn, mostly in PvP."],
    ["Holy Fire"] = L["Costs more than Smite for a small gain while leveling."],
    ["Lightwell"] = L["A group spell."],
    ["Mana Burn"] = L["Mostly useful against other casters."],
    ["Mind Control"] = L["Mostly useful against other players."],
    ["Mind Soothe"] = L["Only calms a few enemies."],
    ["Mind Vision"] = L["A scouting tool you can live without."],
    ["Pain Suppression"] = L["A group-healing cooldown."],
    ["Power Word: Barrier"] = L["A group-healing cooldown."],
    ["Prayer of Fortitude"] = L["Costs a reagent each cast. Not needed while leveling."],
    ["Prayer of Mending"] = L["A group heal."],
    ["Prayer of Shadow Protection"] = L["Costs a reagent each cast. Not needed while leveling."],
    ["Prayer of Spirit"] = L["Costs a reagent each cast. Not needed while leveling."],
    ["Shackle Undead"] = L["Only useful against undead."],
    ["Shadow Protection"] = L["Only matters against specific raid fights."],
    ["Shadowguard"] = L["Only helps against shadow casters."],
  },

  tags = {
    ["Mana Burn"] = { "LowValue" },
    ["Mind Soothe"] = { "LowValue" },
    ["Mind Vision"] = { "LowValue" },
    ["Elune's Grace"] = { "LowValue" },
    ["Feedback"] = { "LowValue" },
    ["Shadowguard"] = { "LowValue" },
    ["Fear Ward"] = { "LowValue" },
    ["Holy Fire"] = { "LowValue" },
    ["Shackle Undead"] = { "LowValue" },
    ["Fade"] = { "LowValue" },
    ["Mind Control"] = { "PvP" },
    ["Pain Suppression"] = { "RaidGroup" },
    ["Power Word: Barrier"] = { "RaidGroup" },
    ["Shadow Protection"] = { "RaidGroup" },
    ["Divine Spirit"] = { "RaidGroup" },
    ["Prayer of Mending"] = { "RaidGroup" },
    ["Lightwell"] = { "RaidGroup" },
    ["Prayer of Fortitude"] = { "Endgame" },
    ["Prayer of Spirit"] = { "Endgame" },
    ["Prayer of Shadow Protection"] = { "Endgame" },
  },

  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.
  talentSpells = {
    "Blackout", "Blessed Recovery", "Darkness", "Divine Spirit", "Holy Nova", "Holy Reach",
    "Improved Fade", "Improved Mind Blast", "Improved Psychic Scream", "Improved Shadow Word: Pain",
    "Improved Vampiric Embrace", "Lightwell", "Martyrdom", "Mind Flay", "Power Infusion",
    "Shadow Affinity", "Shadow Focus", "Shadow Reach", "Shadow Weaving", "Shadowform", "Silence",
    "Spell Warding", "Spirit Tap", "Vampiric Embrace",
  },

  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.
  reviewed = {
    "Blackout", "Blessed Recovery", "Confounding Flash", "Contingency Plan", "Dark Sacrifice",
    "Darkness", "Divine Grace", "Eye of the Void", "Focused Casting", "Holy Reach", "Homunculi",
    "Improved Fade", "Improved Mind Blast", "Improved Psychic Scream", "Improved Shadow Word: Pain",
    "Improved Vampiric Embrace", "Increased Fortitude", "Lightwell Renew", "Martyrdom",
    "Shadow Affinity", "Shadow Focus", "Shadow Reach", "Shadow Weaving", "Spell Warding", "Spirit Tap",
  },
})
