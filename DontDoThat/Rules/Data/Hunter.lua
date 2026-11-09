local addonName, ns = ...
local L = ns.L

-- Source status: BM rotation is sourced. MM and SV rotations are thinly sourced
-- (plausible Classic-style lists) and carry needsReview = true.
-- All gold costs are UNKNOWN and left nil; they are filled from the trainer-cost cache at runtime.

local function ranks(levels, manaCosts)
  local rows = {}
  for i, level in ipairs(levels) do
    rows[i] = { rank = i, unlockLevel = level, manaCost = manaCosts and manaCosts[i], cost = nil }
  end
  return rows
end

-- What every Hunter spec uses while leveling: the ranged attacks, the Hawk aspect, kiting and survival tools, and the
-- pet's basics. Aspect of the Pack is for groups and causes trouble in dungeons and raids when misused, so it is optional.
local SHARED_CORE = { "Hunter's Mark", "Serpent Sting", "Arcane Shot", "Auto Shot", "Multi-Shot", "Aspect of the Hawk",
  "Aspect of the Cheetah", "Feign Death", "Concussive Shot", "Growl", "Great Stamina", "Natural Armor" }
local SHARED_SITUATIONAL = { "Aspect of the Pack", "Frost Trap", "Aimed Shot", "Raptor Strike" }

local function with(base, extra)
  local out = {}
  for _, name in ipairs(base) do out[#out + 1] = name end
  for _, name in ipairs(extra) do out[#out + 1] = name end
  return out
end

ns.Rules.Load({
  class = "HUNTER",

  specs = {
    BM = {
      name = L["Beast Mastery"], tree = 1, -- talent tab order observed on Classic Era 1.15.9
      rotation = {
        core = with(SHARED_CORE, { "Summon Hawk", "Mend Pet", "Intimidation", "Bestial Wrath" }),
        situational = SHARED_SITUATIONAL,
      },
    },
    MM = {
      name = L["Marksmanship"], tree = 2,
      rotation = {
        needsReview = true, -- UNVERIFIED: plausible Classic-style list
        core = with(SHARED_CORE, { "Aimed Shot", "Rapid Fire" }),
        situational = SHARED_SITUATIONAL,
      },
    },
    SV = {
      name = L["Survival"], tree = 3,
      rotation = {
        needsReview = true, -- UNVERIFIED: plausible Classic-style list
        core = with(SHARED_CORE, { "Raptor Strike", "Mongoose Bite", "Wing Clip" }),
        situational = with(SHARED_SITUATIONAL, { "Explosive Trap" }),
      },
    },
  },

  -- Endgame: not needed until level 60 (full defer: prompt, alert, hidden by the Recommended filter).
  tagTiers = { PvP = "deferLow", RaidGroup = "defer", LowValue = "deferLow", Endgame = "defer" },

  -- Plain-language reasons shown to the player. `why` is per ability; `tagReasons` is the fallback per tag.
  tagReasons = {
    PvP = L["Only useful against other players."],
    RaidGroup = L["Only needed in groups and raids."],
    LowValue = L["Rarely helps while leveling."],
    Endgame = L["You won't need this until level 60."],
  },
  why = {
    ["Distracting Shot"] = L["Pulls enemies off your tank. You only need it in groups and raids."],
    ["Tranquilizing Shot"] = L["Only needed for a few raid fights."],
    ["Volley"] = L["Group damage for raids. Not needed while leveling."],
    ["Aspect of the Wild"] = L["A resistance bonus for groups and raids."],
    ["Beast Lore"] = L["Only shows information about a pet."],
    ["Eagle Eye"] = L["A scouting tool you can live without."],
    ["Eyes of the Beast"] = L["A scouting tool you can live without."],
    ["Arcane Resistance"] = L["Only matters against specific raid fights."],
    ["Fire Resistance"] = L["Only matters against specific raid fights."],
    ["Frost Resistance"] = L["Only matters against specific raid fights."],
    ["Nature Resistance"] = L["Only matters against specific raid fights."],
    ["Shadow Resistance"] = L["Only matters against specific raid fights."],
  },

  tags = {
    ["Viper Sting"] = { "PvP" }, ["Scorpid Sting"] = { "PvP" }, ["Scatter Shot"] = { "PvP" },
    ["Flare"] = { "PvP" }, ["Enchanted Flare"] = { "PvP" }, ["Track Hidden"] = { "PvP" },
    ["Counterattack"] = { "PvP" },

    ["Distracting Shot"] = { "RaidGroup" }, ["Tranquilizing Shot"] = { "RaidGroup" },
    ["Volley"] = { "RaidGroup" }, ["Aspect of the Wild"] = { "RaidGroup" },

    ["Wyvern Sting"] = { "Endgame" }, ["Aspect of the Beast"] = { "Endgame" },

    -- Low-value utility; pet resistance names are UNVERIFIED as beast-training entries.
    ["Beast Lore"] = { "LowValue" }, ["Eagle Eye"] = { "LowValue" }, ["Eyes of the Beast"] = { "LowValue" },
    ["Scare Beast"] = { "LowValue" },
    -- All tracking is low value.
    ["Track Beasts"] = { "LowValue" }, ["Track Humanoids"] = { "LowValue" }, ["Track Undead"] = { "LowValue" },
    ["Track Demons"] = { "LowValue" }, ["Track Giants"] = { "LowValue" },
    ["Track Dragonkin"] = { "LowValue" }, ["Track Elementals"] = { "LowValue" },
    ["Arcane Resistance"] = { "LowValue" }, ["Fire Resistance"] = { "LowValue" },
    ["Frost Resistance"] = { "LowValue" }, ["Nature Resistance"] = { "LowValue" },
    ["Shadow Resistance"] = { "LowValue" },
  },

  -- Skills that come with being a Hunter and are never trained; left off the Classes page.
  general = { "Auto Shot" },
  -- What a Pet Trainer teaches your pet (beast training), listed under Pet rather than under a spec.
  pet = { "Growl", "Great Stamina", "Natural Armor", "Arcane Resistance", "Fire Resistance", "Frost Resistance",
    "Nature Resistance", "Shadow Resistance" },

  overrides = {
    ["Serpent Sting"] = "keep", ["Hunter's Mark"] = "keep", ["Freezing Trap"] = "keep",
    ["Immolation Trap"] = "keep", ["Explosive Trap"] = "keep",
    ["Deterrence"] = "keep", ["Disengage"] = "keep",
    ["Trueshot Aura"] = "keep", -- big Hunter DPS boost
    ["Dual Wield"] = "keep",    -- big stat gain
    ["Mail"] = "keep",          -- armor proficiency at 40
    ["Wing Clip"] = "keep",     -- vital for solo play
  },

  -- Serpent Sting levels and mana costs are from fan-site databases (Endgame Tools), cross-checked only partially; gold costs unknown.
  ranks = {
    ["Serpent Sting"] = ranks({ 4, 10, 18, 26, 34, 42, 50, 58, 60 }, { 15, 30, 50, 80, 115, 150, 190, 230, 250 }),
  },

  -- Spells that only exist once the player has taken the talent of the same name. Until then they do
  -- not count as part of any rotation.
  talentSpells = { "Aimed Shot", "Scatter Shot", "Wyvern Sting", "Intimidation", "Bestial Wrath", "Counterattack" },

  -- Trainer levels for single-rank abilities, from the wowforevertalent.com ability list (fan site).
  abilityLevels = {
    ["Aimed Shot"] = 20, ["Multi-Shot"] = 18, ["Rapid Fire"] = 26, ["Scorpid Sting"] = 22,
    ["Scatter Shot"] = 30, ["Flare"] = 32, ["Beast Lore"] = 24, ["Eagle Eye"] = 14,
    ["Feign Death"] = 30, ["Intimidation"] = 30, ["Aspect of the Pack"] = 40, ["Bestial Wrath"] = 40,
    ["Track Giants"] = 40, ["Track Dragonkin"] = 50, ["Tranquilizing Shot"] = 60,
  },
})
