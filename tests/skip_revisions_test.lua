package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- Skip revisions: the frozen revision 1, the shape of revision 2, and how the engine uses a revision.

local ns = {}
H.loadSpellTables(ns)
H.load("DontDoThat/Rules/Schema.lua", ns)
H.load("DontDoThat/Rules/Engine.lua", ns)
local CLASSES = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue",
  SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior" }
for _, file in pairs(CLASSES) do H.load("DontDoThat/Rules/Data/" .. file .. ".lua", ns) end

-- The skip list as it was before revisions existed (every class's skipRanks, by English name).
local BEFORE_REVISIONS = {
  DRUID = {
    ["Rejuvenation"] = { 11 },
  },
  HUNTER = {
    ["Disengage"] = { 2, 3 },
    ["Freezing Trap"] = { 2, 3 },
    ["Great Stamina"] = { 5, 7, 9 },
    ["Mend Pet"] = { 6 },
    ["Natural Armor"] = { 6, 8, 10 },
    ["Raptor Strike"] = { 5, 6, 8 },
    ["Wing Clip"] = { 2, 3 },
  },
  MAGE = {
    ["Conjure Food"] = { 7 },
    ["Frostbolt"] = { 11 },
    ["Pyroblast"] = { 2 },
  },
  PALADIN = {
    ["Hammer of Justice"] = { 2, 3, 4 },
  },
  PRIEST = {
    ["Inner Fire"] = { 6 },
    ["Power Word: Shield"] = { 10 },
    ["Psychic Scream"] = { 2, 3, 4 },
    ["Renew"] = { 10 },
  },
  ROGUE = {
    ["Backstab"] = { 9 },
    ["Eviscerate"] = { 9 },
    ["Gouge"] = { 2, 3, 4, 5 },
    ["Kick"] = { 2, 3, 4 },
  },
  SHAMAN = {
    ["Frost Shock"] = { 2, 3, 4 },
    ["Healing Wave"] = { 10 },
    ["Rockbiter Weapon"] = { 5, 6, 7 },
    ["Strength of Earth Totem"] = { 5 },
  },
  WARRIOR = {
    ["Cleave"] = { 2, 3, 4, 5 },
    ["Heroic Strike"] = { 9 },
    ["Intercept"] = { 2, 3 },
    ["Mocking Blow"] = { 2, 3, 4, 5 },
    ["Overpower"] = { 2, 3, 4 },
    ["Pummel"] = { 2 },
    ["Rend"] = { 5, 6, 7 },
    ["Shield Bash"] = { 2, 3 },
    ["Slam"] = { 2, 3, 4, 5 },
    ["Thunder Clap"] = { 2, 3, 4, 5, 6 },
  },
}

local function entriesFor(class, rev, name, rank)
  local data = ns.Rules.GetClass(class)
  return ns.Rules.SkipEntries(data, rev, H.fid(ns, class, name), rank)
end

local function verdict(class, spec, name, rank, rules, milestone)
  local profile = { class = class, level = 25, plausibleSpecs = spec and { spec } or {}, rules = rules or {},
    milestone = milestone or { current = 40, state = "active" } }
  return ns.Rules.Evaluate(profile, { kind = "spell", name = name, familyId = H.fid(ns, class, name), rank = rank })
end

test("revision 1 is the skip list from before revisions existed, exactly", function()
  for class in pairs(CLASSES) do
    local data = ns.Rules.GetClass(class)
    local expected = {}
    for name, ranks in pairs(BEFORE_REVISIONS[class] or {}) do expected[H.fid(ns, class, name)] = ranks end
    eq(H.skipRanks(data, 1), expected, class)
  end
end)

test("revision 1 flags exactly those ranks for every spec, with a reason that is true", function()
  for class, byName in pairs(BEFORE_REVISIONS) do
    local specs = {}
    for key in pairs(ns.Rules.GetClass(class).specs) do specs[#specs + 1] = key end
    for name, ranks in pairs(byName) do
      for _, rank in ipairs(ranks) do
        for _, spec in ipairs(specs) do
          local v = verdict(class, spec, name, rank, { skipRevision = 1 })
          eq(v.source, "skipRank", class .. " " .. name .. " r" .. rank .. " " .. spec)
          eq(v.tier, "defer")
          truthy(v.reason ~= "Only a small upgrade over the rank before it.", "the old generic reason is not used")
        end
      end
    end
  end
end)

test("revision 2 builds on revision 1 and is the newest", function()
  eq(ns.Rules.SkipRevisionNumbers(), { 1, 2 })
  eq(ns.Rules.NewestRevision(), 2)
  for class in pairs(CLASSES) do eq(ns.Rules.GetClass(class).skipRevisionNumbers, { 1, 2 }, class) end
end)

test("revision choice: the newest unless the player picked one that exists", function()
  eq(ns.Rules.ResolveRevision(nil), 2)
  eq(ns.Rules.ResolveRevision(1), 1)
  eq(ns.Rules.ResolveRevision(2), 2)
  eq(ns.Rules.ResolveRevision(9), 2, "unknown revision falls back to the newest")
  eq(ns.Rules.ResolveRevision("two"), 2)
end)

test("the same rank is judged by the revision in use", function()
  -- Frost Shock rank 2: skipped by revision 1, bought on Wowhead's word in revision 2? (the guide says only rank 1.)
  eq(verdict("SHAMAN", "ELEM", "Frost Shock", 2, { skipRevision = 1 }).source, "skipRank")
  -- Mage: Frost Nova rank 2 is not in revision 1, and the guide says to buy only the first rank in revision 2.
  eq(verdict("MAGE", "FROST", "Frost Nova", 2, { skipRevision = 1 }).source ~= "skipRank", true)
  local v2 = verdict("MAGE", "FROST", "Frost Nova", 2)
  eq(v2.source, "skipRank")
  eq(v2.tier, "defer")
  eq(v2.reason, "The leveling guide says to buy only the first rank of this spell.")
  eq(verdict("MAGE", "FROST", "Frost Nova", 2, { skipRevision = 2 }).source, "skipRank")
end)

test("rank 1 is never skipped in any revision", function()
  for class in pairs(CLASSES) do
    local data = ns.Rules.GetClass(class)
    for rev, flat in pairs(data.skipRevisions) do
      for family, ranks in pairs(flat) do
        for rank, entries in pairs(ranks) do
          if #entries > 0 then truthy(rank >= 2, class .. " rev " .. rev .. " family " .. family .. " skips rank " .. rank) end
        end
      end
    end
  end
end)

test("revision 2: every skipped rank is a real rank of a real family, with a known source and reason", function()
  for class in pairs(CLASSES) do
    local data = ns.Rules.GetClass(class)
    local have = {}
    for _, row in ipairs(ns.SpellData.Rows(class)) do
      local family = ns.SpellData.FamilyOfId(class, row.id)
      if row.rank then have[family] = have[family] or {}; have[family][row.rank] = true end
    end
    for family, ranks in pairs(data.skipRevisions[2]) do
      for rank, entries in pairs(ranks) do
        for _, entry in ipairs(entries) do
          truthy(have[family] and have[family][rank], class .. " family " .. family .. " has no rank " .. rank)
          truthy(entry.source == "guide" or entry.source == "computed" or entry.source == "legacy")
          truthy(ns.Rules.SkipReason(entry.reason), "a sentence for the reason")
        end
      end
    end
  end
end)

test("every reason kind renders a plain sentence, with its numbers filled in", function()
  eq(ns.Rules.SkipReason({ kind = "guideFirstRankOnly" }), "The leveling guide says to buy only the first rank of this spell.")
  eq(ns.Rules.SkipReason({ kind = "guideSkipEntirely" }), "The leveling guide says this spell is not worth buying while leveling.")
  eq(ns.Rules.SkipReason({ kind = "guideUpToRank", n = 4 }), "The leveling guide says to buy this spell only up to rank 4.")
  eq(ns.Rules.SkipReason({ kind = "guideNotTrained" }), "The leveling guide does not buy this rank while leveling.")
  eq(ns.Rules.SkipReason({ kind = "noGain" }), "Adds nothing over the rank before it.")
  eq(ns.Rules.SkipReason({ kind = "smallStep", pct = 12 }), "Only 12% stronger than the rank before it, for a spell you only use now and then.")
  eq(ns.Rules.SkipReason({ kind = "notWorthPrice", pct = 8 }), "Only 8% stronger than the rank before it, which does not repay its price.")
  eq(ns.Rules.SkipReason({ kind = "waitForMount" }), "This rank can wait until you have your level 60 mount.")
  eq(ns.Rules.SkipReason({ kind = "legacy" }), "An earlier version of this list judged this rank a small upgrade.")
  for kind in pairs(ns.Rules.SKIP_REASON_KINDS) do
    local reason = { kind = kind, n = 4, pct = 9 }
    truthy(not ns.Rules.SkipReason(reason):find("%%[ds]"), kind .. " has no unfilled placeholder")
  end
  eq(ns.Rules.SkipSource("guide"), "From the Wowhead leveling guide.")
  eq(ns.Rules.SkipSource("computed"), "Computed from the game data.")
  eq(ns.Rules.SkipSource("legacy"), "From the earlier skip list.")
end)

test("the reason a player sees is the one the revision records for that rank", function()
  -- Warrior Heroic Strike rank 9 is a revision 1 skip the Wowhead guides back ("up to rank 4").
  local v = verdict("WARRIOR", "ARMS", "Heroic Strike", 9, { skipRevision = 1 })
  eq(v.reason, "The leveling guide says to buy this spell only up to rank 4.")
  eq(verdict("WARRIOR", "ARMS", "Overpower", 3, { skipRevision = 1 }).reason, "The leveling guide says to buy only the first rank of this spell.")
  -- A revision 1 skip no guide matches says only what revision 1 recorded.
  eq(verdict("HUNTER", "BM", "Wing Clip", 2, { skipRevision = 1 }).reason, "An earlier version of this list judged this rank a small upgrade.")
end)

test("skips are per spec: every plausible spec must skip the rank", function()
  local checked = 0
  for class in pairs(CLASSES) do
    local data = ns.Rules.GetClass(class)
    local all = {}
    for key in pairs(data.specs) do all[#all + 1] = key end
    table.sort(all)
    for family, ranks in pairs(data.skipRevisions[2]) do
      for rank, entries in pairs(ranks) do
        local covered = {}
        for _, e in ipairs(entries) do for _, key in ipairs(e.specs or all) do covered[key] = true end end
        local outside
        for _, key in ipairs(all) do if not covered[key] then outside = key end end
        if #entries > 0 and outside then
          local inside
          for key in pairs(covered) do inside = key end
          local function flagged(specs)
            local v = ns.Rules.Evaluate({ class = class, level = 25, plausibleSpecs = specs, rules = {}, milestone = { current = 40, state = "active" } },
              { kind = "spell", name = "x", familyId = family, rank = rank })
            return v.source == "skipRank"
          end
          truthy(flagged({ inside }), class .. " " .. family .. " r" .. rank .. " for a covered spec")
          falsy(flagged({ outside }), class .. " " .. family .. " r" .. rank .. " for a spec that buys it")
          falsy(flagged({ inside, outside }), class .. " " .. family .. " r" .. rank .. " when one plausible spec buys it")
          checked = checked + 1
        end
      end
    end
  end
  truthy(checked > 10, "found partial-spec skips to check: " .. checked)
end)

test("an undecided spec means every spec is plausible, so a rank only some specs skip is not flagged", function()
  local data = ns.Rules.GetClass("WARRIOR")
  local seen = false
  for family, ranks in pairs(data.skipRevisions[2]) do
    for rank, entries in pairs(ranks) do
      for _, e in ipairs(entries) do
        if e.specs and #e.specs < 3 then
          local v = ns.Rules.Evaluate({ class = "WARRIOR", level = 25, plausibleSpecs = {}, rules = {}, milestone = { current = 40, state = "active" } },
            { kind = "spell", name = "x", familyId = family, rank = rank })
          falsy(v.source == "skipRank" and #entries == 1, "r" .. rank)
          seen = true
        end
      end
    end
  end
end)

test("level 60 ranks: a first rank is bought, a utility later rank waits, and the mount ends the wait", function()
  local waits, firsts = 0, 0
  for class in pairs(CLASSES) do
    local data = ns.Rules.GetClass(class)
    for family, ranks in pairs(data.skipRevisions[2]) do
      for rank, entries in pairs(ranks) do
        local level60
        for _, row in ipairs(ns.SpellData.Rows(class)) do
          if ns.SpellData.FamilyOfId(class, row.id) == family and row.rank == rank then level60 = row.level == 60 end
        end
        if level60 and #entries > 0 then
          for _, e in ipairs(entries) do
            truthy(e.reason.kind == "waitForMount" or e.source == "guide" or e.source == "legacy", class .. " " .. family .. " r" .. rank .. " " .. e.reason.kind)
            if e.reason.kind == "waitForMount" then
              waits = waits + 1
              local profile = { class = class, level = 60, plausibleSpecs = {}, rules = {}, milestone = { current = 60, state = "active" } }
              local v = ns.Rules.Evaluate(profile, { kind = "spell", name = "x", familyId = family, rank = rank })
              if v.source == "skipRank" then
                eq(v.reason, "This rank can wait until you have your level 60 mount.")
                profile.milestone = { current = nil, state = "finished" }
                eq(ns.Rules.Evaluate(profile, { kind = "spell", name = "x", familyId = family, rank = rank }).tier, "keep", "no skip once the mount is bought")
              end
            end
          end
        end
      end
    end
    -- the first rank of a spell that unlocks at 60 is never listed
    local first = {}
    for _, row in ipairs(ns.SpellData.Rows(class)) do
      if row.rank then
        local family = ns.SpellData.FamilyOfId(class, row.id)
        if not first[family] or row.rank < first[family].rank then first[family] = row end
      end
    end
    for family, row in pairs(first) do
      if row.level >= 60 then
        firsts = firsts + 1
        for rev = 1, 2 do eq(#ns.Rules.SkipEntries(data, rev, family, row.rank), 0, class .. " family " .. family) end
      end
    end
  end
  truthy(waits > 0, "some level 60 ranks wait for the mount")
end)

test("a skip ends when the milestone is over, and the stop-after-40 choice ends it at the first mount", function()
  local v = ns.Rules.Evaluate({ class = "WARRIOR", level = 25, plausibleSpecs = { "ARMS" }, rules = { skipRevision = 1 },
    milestone = { current = nil, state = "finished" } }, { kind = "spell", name = "x", familyId = H.fid(ns, "WARRIOR", "Rend"), rank = 5 })
  eq(v.tier, "keep")
  H.load("DontDoThat/Model/Milestones.lua", ns)
  eq(ns.Milestones.State(true, false, nil, 40).state, "finished")
  eq(ns.Milestones.State(true, false, nil, 60).state, "active")
end)

test("switches keep working under every revision", function()
  for _, rev in ipairs({ 1, 2 }) do
    local family = H.fid(ns, "WARRIOR", "Rend")
    local off = { skipRevision = rev, offAbilities = { [family] = true } }
    eq(verdict("WARRIOR", "ARMS", "Rend", 5, off).source, "disabled", "ability off, revision " .. rev)
    local kind = { skipRevision = rev, offKinds = { skipRank = true } }
    truthy(verdict("WARRIOR", "ARMS", "Rend", 5, kind).source ~= "skipRank", "kind off, revision " .. rev)
  end
  eq(verdict("WARRIOR", "ARMS", "Rend", 5, { skipRevision = 1 }).source, "skipRank")
  eq(verdict("WARRIOR", "ARMS", "Rend", 5, {}).source, "skipRank")
end)

test("a revision's own skips do not leak into another spell's ranks", function()
  eq(#entriesFor("WARRIOR", 2, "Rend", 4), 0, "rank 4 is within the guide's limit")
  eq(#entriesFor("WARRIOR", 2, "Rend", 5), 1)
  eq(verdict("WARRIOR", "ARMS", "Rend", 4, {}).source ~= "skipRank", true)
end)
