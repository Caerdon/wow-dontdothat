local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.
-- Written by tools/scaffold_class_rules.py from tools/class_plans/mage.py.
-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_classes_test.lua fails on any that does not.

-- What every spec of this class keeps buying.
local SHARED_CORE = {
  "Arcane Intellect", "Conjure Food", "Conjure Water", "Polymorph", "Blink", "Frost Armor",
  "Ice Armor", "Mage Armor", "Frost Nova", "Counterspell",
}
-- Handy now and then for any spec. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = {
  "Remove Lesser Curse", "Slow Fall", "Arcane Explosion", "Fire Blast", "Conjure Mana Agate",
  "Conjure Mana Jade", "Conjure Mana Citrine", "Conjure Mana Ruby", "Teleport: Dalaran",
  "Teleport: Darnassus", "Teleport: Ironforge", "Teleport: Orgrimmar", "Teleport: Stormwind",
  "Teleport: Thunder Bluff", "Teleport: Undercity",
}

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "MAGE",

  specs = {
    ARCANE = {
      name = L["Arcane"], tree = 1, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Arcane Missiles", "Arcane Explosion", "Blizzard", "Mana Shield", "Fireball" }), situational = with(SHARED_SITUATIONAL, { "Arcane Wrath", "Arcane Blast" }) },
    },
    FIRE = {
      name = L["Fire"], tree = 2, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Fireball", "Fire Blast", "Flamestrike", "Combustion" }), situational = SHARED_SITUATIONAL },
    },
    FROST = {
      name = L["Frost"], tree = 3, -- TalentTab order verified from the game tables
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Frostbolt", "Cone of Cold", "Blizzard", "Ice Barrier", "Frostfire Bolt", "Ice Block" }), situational = with(SHARED_SITUATIONAL, { "Ice Lance" }) },
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
    ["Amplify Magic"] = L["Only matters in specific group fights."],
    ["Arcane Brilliance"] = L["Costs a reagent each cast. Not needed while leveling."],
    ["Blast Wave"] = L["Mostly useful in PvP and groups."],
    ["Dampen Magic"] = L["Only matters in specific group fights."],
    ["Fire Ward"] = L["A short shield no leveling build relies on."],
    ["Frost Ward"] = L["A short shield no leveling build relies on."],
    ["Polymorph: Cow"] = L["The ordinary Polymorph does the same job."],
    ["Portal: Darnassus"] = L["Takes a group somewhere and needs a Rune of Portals."],
    ["Portal: Ironforge"] = L["Takes a group somewhere and needs a Rune of Portals."],
    ["Portal: Orgrimmar"] = L["Takes a group somewhere and needs a Rune of Portals."],
    ["Portal: Stormwind"] = L["Takes a group somewhere and needs a Rune of Portals."],
    ["Portal: Thunder Bluff"] = L["Takes a group somewhere and needs a Rune of Portals."],
    ["Portal: Undercity"] = L["Takes a group somewhere and needs a Rune of Portals."],
    ["Pyroblast"] = L["A slow opener you can do without."],
    ["Scorch"] = L["A filler spell you can do without."],
  },

  tags = {
    ["Dampen Magic"] = { "LowValue" },
    ["Amplify Magic"] = { "LowValue" },
    ["Fire Ward"] = { "LowValue" },
    ["Frost Ward"] = { "LowValue" },
    ["Polymorph: Cow"] = { "LowValue" },
    ["Scorch"] = { "LowValue" },
    ["Pyroblast"] = { "LowValue" },
    ["Blast Wave"] = { "LowValue" },
    ["Portal: Darnassus"] = { "RaidGroup" },
    ["Portal: Ironforge"] = { "RaidGroup" },
    ["Portal: Orgrimmar"] = { "RaidGroup" },
    ["Portal: Stormwind"] = { "RaidGroup" },
    ["Portal: Thunder Bluff"] = { "RaidGroup" },
    ["Portal: Undercity"] = { "RaidGroup" },
    ["Arcane Brilliance"] = { "Endgame" },
  },

  -- Ranks to skip, from expert leveling guides (Wowhead "Spells to Buy").
  skipRanks = {
    ["Conjure Food"] = { 7 },
    ["Frostbolt"] = { 11 },
    ["Pyroblast"] = { 2 },
  },

  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.
  talentSpells = {
    "Arcane Resilience", "Arcane Subtlety", "Blast Wave", "Burning Soul", "Cold Snap", "Combustion",
    "Critical Mass", "Precision", "Fire Power", "Flame Throwing", "Frost Channeling",
    "Frost Warding", "Frostbite", "Ice Barrier", "Ice Block", "Ice Shards", "Impact",
    "Improved Blizzard", "Improved Cone of Cold", "Improved Fire Blast", "Accelerant",
    "Improved Flamestrike", "Improved Frost Nova", "Improved Frostbolt", "Improved Scorch",
    "Magic Absorption", "Master of Elements", "Permafrost", "Piercing Ice", "Pyroblast", "Shatter",
    "Winter's Chill",
  },

  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.
  reviewed = {
    "Arcane Barrage", "Arcane Resilience", "Arcane Subtlety", "Arcane Surge", "Balefire Bolt",
    "Burning Soul", "Chilled", "Cold Snap", "Comprehend Scroll", "Critical Mass", "Detect Magic",
    "Precision", "Expanded Intellect", "Fire Power", "Fire Vulnerability", "Flame Throwing",
    "Frost Channeling", "Frost Warding", "Frostbite", "Frozen Orb", "Ice Shards",
    "Icy Veins", "Impact", "Improved Blizzard", "Improved Cone of Cold", "Improved Fire Blast",
    "Accelerant", "Improved Flamestrike", "Improved Frost Nova", "Improved Frostbolt",
    "Improved Scorch", "Living Bomb", "Living Flame", "Magic Absorption", "Mass Regeneration",
    "Master of Elements", "Permafrost", "Piercing Ice", "Regeneration", "Rewind Time", "Shatter",
    "Spellfrost Bolt", "Study", "Winter's Chill",
  },
})
