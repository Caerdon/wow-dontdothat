local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.
-- Written by tools/scaffold_class_rules.py from tools/class_plans/shaman.py.
-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_classes_test.lua fails on any that does not.

-- What every spec of this class keeps buying.
local SHARED_CORE = {
  "Lightning Bolt", "Earth Shock", "Flame Shock", "Healing Wave", "Lightning Shield", "Ghost Wolf",
  "Rockbiter Weapon", "Searing Totem", "Stoneclaw Totem", "Earthbind Totem", "Ancestral Spirit",
  "Reincarnation", "Astral Recall",
}
-- Handy now and then for any spec. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = {
  "Cure Poison", "Cure Disease", "Totemic Recall", "Call of the Elements", "Call of the Ancestors",
  "Call of the Spirits", "Totemic Call", "Decoy Totem", "Healing Rain", "Frostbrand Weapon",
  "Flametongue Weapon", "Frost Shock",
}

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "SHAMAN",

  specs = {
    ELEM = {
      name = L["Elemental"], tree = 1, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Chain Lightning", "Fire Nova", "Fire Nova Totem", "Magma Totem", "Flametongue Weapon", "Frost Shock" }), situational = with(SHARED_SITUATIONAL, { "Mana Spring Totem", "Healing Stream Totem", "Water Shield" }) },
    },
    ENH = {
      name = L["Enhancement"], tree = 2, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Stormstrike", "Strength of Earth Totem", "Grace of Air Totem", "Chain Lightning", "Fire Nova", "Fire Nova Totem", "Magma Totem", "Frost Shock" }), situational = with(SHARED_SITUATIONAL, { "Mana Spring Totem", "Healing Stream Totem", "Lava Lash", "Shamanistic Rage", "Water Shield" }) },
    },
    RESTO = {
      name = L["Restoration"], tree = 3, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Lesser Healing Wave", "Chain Heal", "Riptide", "Healing Stream Totem", "Mana Spring Totem", "Mana Tide Totem" }), situational = with(SHARED_SITUATIONAL, { "Chain Lightning", "Strength of Earth Totem", "Grace of Air Totem", "Water Shield", "Earth Shield" }) },
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
    ["Disease Cleansing Totem"] = L["Rarely helps while leveling."],
    ["Far Sight"] = L["A scouting tool you can live without."],
    ["Fire Resistance Totem"] = L["Only matters against specific raid fights."],
    ["Flametongue Totem"] = L["A totem you can do without."],
    ["Frost Resistance Totem"] = L["Only matters against specific raid fights."],
    ["Grounding Totem"] = L["Mostly useful against other players."],
    ["Nature Resistance Totem"] = L["Only matters against specific raid fights."],
    ["Poison Cleansing Totem"] = L["Rarely helps while leveling."],
    ["Purge"] = L["Mostly useful against other players."],
    ["Sentry Totem"] = L["A scouting tool you can live without."],
    ["Stoneskin Totem"] = L["A defensive totem you can do without."],
    ["Tremor Totem"] = L["Only matters in groups and raids."],
    ["Water Breathing"] = L["Rarely helps while leveling."],
    ["Water Walking"] = L["Rarely helps while leveling."],
    ["Windfury Totem"] = L["A group buff."],
    ["Windwall Totem"] = L["A defensive totem you can do without."],
  },

  tags = {
    ["Stoneskin Totem"] = { "LowValue" },
    ["Windwall Totem"] = { "LowValue" },
    ["Flametongue Totem"] = { "LowValue" },
    ["Frost Resistance Totem"] = { "LowValue" },
    ["Fire Resistance Totem"] = { "LowValue" },
    ["Nature Resistance Totem"] = { "LowValue" },
    ["Disease Cleansing Totem"] = { "LowValue" },
    ["Poison Cleansing Totem"] = { "LowValue" },
    ["Sentry Totem"] = { "LowValue" },
    ["Water Breathing"] = { "LowValue" },
    ["Water Walking"] = { "LowValue" },
    ["Far Sight"] = { "LowValue" },
    ["Purge"] = { "PvP" },
    ["Grounding Totem"] = { "PvP" },
    ["Tremor Totem"] = { "RaidGroup" },
    ["Windfury Totem"] = { "RaidGroup" },
  },

  overrides = {
    ["Mail"] = "keep",
    ["Dual Wield"] = "keep",
  },

  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.
  talentSpells = {
    "Ancestral Healing", "Elemental Devastation", "Elemental Reach", "Elemental Warding",
    "Elemental Weapons", "Eye of the Storm", "Healing Grace", "Healing Way", "Improved Weapon Totems",
    "Mana Tide Totem", "Natural Grace", "Storm Reach", "Stormstrike", "Weapon Mastery",
  },

  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.
  reviewed = {
    "Ancestral Fortitude", "Ancestral Guidance", "Ancestral Healing", "Elemental Devastation",
    "Elemental Reach", "Elemental Warding", "Elemental Weapons", "Eye of the Storm", "Focused Casting",
    "Healing Grace", "Healing Way", "Improved Weapon Totems", "Molten Blast", "Natural Grace",
    "Rage of the Farseer", "Spirit of the Alpha", "Storm Reach", "Weapon Mastery",
  },
})
