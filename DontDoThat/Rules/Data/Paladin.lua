local addonName, ns = ...
local L = ns.L

-- Source status: every rotation is a judgement call from a short class brief, not a verified guide, so each
-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables
-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are
-- UNVERIFIED until a Paladin trainer is captured with /ddt export. Gold costs are left nil.
-- Every Paladin spell family must appear below (a rotation, a tag, an override or `reviewed`);
-- tests/rules_paladin_test.lua fails on any that does not.

-- What every Paladin keeps buying, whatever the talents. Hammer of Justice is the stun and interrupt every
-- leveling build uses; Consecration is a Holy talent that Protection and Retribution leveling builds rely on
-- (it counts only while the talent is active). Rebuke is the interrupt.
-- Paladin and Warlock get a free level 40 mount, but the aim is still to save gold, so the core list is the one
-- Icy Veins calls "Recommended Skills to Upgrade" (with Wowhead's spec guides), and the rest wait.
local SHARED_CORE = { "Seal of Righteousness", "Judgement", "Holy Light", "Flash of Light", "Blessing of Might",
  "Blessing of Wisdom", "Redemption", "Purify", "Cleanse", "Divine Protection", "Divine Shield",
  "Hammer of Justice", "Consecration", "Rebuke", "Seal of the Crusader", "Lay on Hands", "Blessing of Protection",
  "Blessing of Freedom", "Divine Intervention", "Retribution Aura", "Hammer of Wrath", "Seal of Command" }
-- Handy now and then for any Paladin. The talent ones count only while the talent is active.
local SHARED_SITUATIONAL = { "Devotion Aura", "Seal of Light", "Seal of Wisdom", "Sanctity Aura", "Repentance",
  "Light's Vigil", "Holy Strike", "Seal of Fury", "Hammer of the Righteous" }

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "PALADIN",

  specs = {
    HOLY = {
      name = L["Holy"], tree = 1, -- TalentTab order verified from the game tables (Holy, Protection, Retribution)
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Holy Shock" }), situational = SHARED_SITUATIONAL },
    },
    PROT = {
      name = L["Protection"], tree = 2,
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Righteous Fury", "Holy Shield" }), situational = SHARED_SITUATIONAL },
    },
    RET = {
      name = L["Retribution"], tree = 3,
      rotation = { needsReview = true, core = with(SHARED_CORE, { "Sanctity Aura" }), situational = SHARED_SITUATIONAL },
    },
  },

  -- Ranks to skip, from expert guides: Icy Veins' Classic Paladin guide lists "Hammer of Justice - Just Rank 1".
  -- Wowhead's Paladin guidance gives no per-rank advice, so nothing else is skipped.
  skipRanks = { ["Hammer of Justice"] = { 2, 3, 4 } },

  tagTiers = { PvP = "deferLow", RaidGroup = "defer", LowValue = "deferLow", Endgame = "defer" },

  tagReasons = {
    PvP = L["Mostly useful against other players."],
    RaidGroup = L["Only needed in groups and raids."],
    LowValue = L["Rarely helps while leveling."],
    Endgame = L["You won't need this until level 60."],
  },
  why = {
    ["Lay on Hands"] = L["Spends your whole mana bar to heal someone else. A group spell."],
    ["Blessing of Protection"] = L["Shields a friend, mostly in PvP and groups."],
    ["Blessing of Freedom"] = L["Frees a friend from roots and slows, mostly in PvP."],
    ["Blessing of Sacrifice"] = L["Takes damage meant for a party member. Only useful in groups."],
    ["Blessing of Light"] = L["Boosts healing on one party member. Only useful in groups."],
    ["Blessing of Salvation"] = L["Lowers a party member's threat. Not needed solo."],
    ["Concentration Aura"] = L["Keeps group casters from being interrupted. Not needed solo."],
    ["Divine Intervention"] = L["Sacrifices you to save a group member."],
    ["Seal of Justice"] = L["Mostly useful in PvP."],
    ["Repentance"] = L["Crowd control for PvP and groups."],
    ["Turn Undead"] = L["Rarely helps while leveling."],
    ["Exorcism"] = L["Only works on undead and demons."],
    ["Holy Wrath"] = L["Only hits undead and demons."],
    ["Divine Favor"] = L["A talent you can do without while leveling."],
    ["Blessing of Kings"] = L["A group buff you can do without while leveling."],
    ["Blessing of Sanctuary"] = L["A group buff you can do without while leveling."],
    ["Sense Undead"] = L["Only shows where undead are."],
    ["Fire Resistance Aura"] = L["Only matters against specific raid fights."],
    ["Frost Resistance Aura"] = L["Only matters against specific raid fights."],
    ["Shadow Resistance Aura"] = L["Only matters against specific raid fights."],
    ["Greater Blessing of Might"] = L["Costs Symbol of Kings reagents each cast. Not worth it while leveling."],
    ["Greater Blessing of Wisdom"] = L["Costs Symbol of Kings reagents each cast. Not worth it while leveling."],
    ["Greater Blessing of Light"] = L["Costs Symbol of Kings reagents each cast. Not worth it while leveling."],
    ["Greater Blessing of Kings"] = L["Costs Symbol of Kings reagents each cast. Not worth it while leveling."],
    ["Greater Blessing of Sanctuary"] = L["Costs Symbol of Kings reagents each cast. Not worth it while leveling."],
    ["Greater Blessing of Salvation"] = L["Costs Symbol of Kings reagents each cast. Not worth it while leveling."],
  },

  tags = {
    ["Seal of Justice"] = { "PvP" },

    ["Blessing of Sacrifice"] = { "RaidGroup" },
    ["Blessing of Light"] = { "RaidGroup" }, ["Blessing of Salvation"] = { "RaidGroup" },
   
    ["Concentration Aura"] = { "RaidGroup" },
    ["Righteous Fury"] = { "RaidGroup" }, -- core for Protection, so only others see this
    ["Fire Resistance Aura"] = { "RaidGroup" }, ["Frost Resistance Aura"] = { "RaidGroup" },
    ["Shadow Resistance Aura"] = { "RaidGroup" },

    ["Turn Undead"] = { "LowValue" }, ["Sense Undead"] = { "LowValue" },
    ["Exorcism"] = { "LowValue" }, ["Holy Wrath"] = { "LowValue" }, ["Divine Favor"] = { "LowValue" },
    ["Blessing of Kings"] = { "LowValue" }, ["Blessing of Sanctuary"] = { "LowValue" },

    ["Greater Blessing of Might"] = { "Endgame" }, ["Greater Blessing of Wisdom"] = { "Endgame" },
    ["Greater Blessing of Light"] = { "Endgame" }, ["Greater Blessing of Kings"] = { "Endgame" },
    ["Greater Blessing of Sanctuary"] = { "Endgame" }, ["Greater Blessing of Salvation"] = { "Endgame" },
  },

  overrides = {
    ["Summon Warhorse"] = "keep", ["Summon Charger"] = "keep", -- the mounts
    ["Plate Mail"] = "keep", -- kept until its price has been seen at a trainer
  },

  -- Active spells that come from a talent of the same name. They count as part of a rotation only while
  -- the talent is active. Verified from the game's talent tables.
  talentSpells = { "Consecration", "Divine Favor", "Holy Shock", "Blessing of Kings", "Blessing of Sanctuary",
    "Holy Shield", "Seal of Command", "Sanctity Aura", "Repentance" },

  -- Considered and deliberately left at keep: effects of other spells, talent passives, abilities taught by
  -- runes rather than sold by the trainer, riding, and Forever spells whose use is not yet known.
  reviewed = {
    "Judgement of Righteousness", "Judgement of Light", "Judgement of Wisdom", "Judgement of Justice",
    "Judgement of the Crusader", "Judgement of Fury", "Judgement of Martyrdom",
    "Enhanced Blessings", "Holy Power", "Unyielding Faith", "Lasting Judgement", "Improved Judgement",
    "Pursuit of Justice", "Eye for an Eye", "Vindication", "Precision", "Improved Concentration Aura",
    "Improved Seal of Fury", "Swift Judgement", "Righteous Judgement", "Unsealed Wrath", "Exorcist", "Anticipation",
    "Avenging Wrath", "Divine Light", "Divine Sacrifice", "Divine Storm", "Horn of Lordaeron",
    "Inspiration Exemplar", "Sacred Shield", "Seal of Martyrdom",
    "Avenger's Shield", "Beacon of Light", "Crusader Strike", "Divine Steed", "Hand of Reckoning", "Righteous Vengeance",
    "Journeyman Riding",
  },

  -- The trainer's price is not in the game tables and the Paladin level 40 mount is a class perk: the
  -- Warhorse needs no separate riding purchase. UNVERIFIED: sources put the spell at about 1 to 10 gold.
  milestones = {
    [40] = { riding = 10 * 10000, mount = 0,
      note = L["The Light covers your first ride. The Charger sends the bill later."] },
  },
})
