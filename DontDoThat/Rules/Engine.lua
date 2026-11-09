local addonName, ns = ...
local L = ns.L

local Rules = ns.Rules or {}
ns.Rules = Rules

local classes = {}
local revisionNumbers -- the revisions the loaded classes have, kept until a class is loaded or reset

-- Validates rule data written with English spell names and stores it compiled to family IDs. A resolver can be
-- passed in (tests do); by default names resolve through the bundled spell tables for the data's class.
function Rules.Load(data, resolver)
  local id = Rules.Validate(data)
  resolver = resolver or {
    id = function(name) return ns.SpellData.FamilyId(id, name) end,
    prefix = function(prefix) return ns.SpellData.FamiliesWithPrefix(id, prefix) end,
  }
  local compiled = Rules.Compile(data, resolver)
  -- The skip revisions: written in the rule data (tests), else the generated Data/SkipRevisions.lua for the class.
  local raw = compiled.skipRevisions or (ns.SkipRevisions and ns.SkipRevisions[id])
  if raw then
    local specs = {}
    for key in pairs(compiled.specs) do specs[key] = true end
    local familyOk = (not data.skipRevisions) and ns.SpellData and function(family) return ns.SpellData.FamilyOfId(id, family) == family end or nil
    Rules.ValidateSkipRevisions(id, raw, specs, familyOk)
    compiled.skipRevisions, compiled.skipRevisionNumbers = Rules.FlattenSkipRevisions(raw)
  end
  classes[id] = compiled
  revisionNumbers = nil
  return compiled
end

-- Every skip revision any loaded class has, ascending, and the newest of them (the default).
function Rules.SkipRevisionNumbers()
  if revisionNumbers then return revisionNumbers end
  local seen, out = {}, {}
  for _, data in pairs(classes) do
    for _, rev in ipairs(data.skipRevisionNumbers or {}) do
      if not seen[rev] then seen[rev] = true; out[#out + 1] = rev end
    end
  end
  table.sort(out)
  revisionNumbers = out
  return out
end

function Rules.NewestRevision()
  local all = Rules.SkipRevisionNumbers()
  return all[#all]
end

-- The revision to use: the player's pick when it exists, otherwise the newest.
function Rules.ResolveRevision(wanted)
  for _, rev in ipairs(Rules.SkipRevisionNumbers()) do
    if rev == wanted then return rev end
  end
  return Rules.NewestRevision()
end

-- The skip entries of one family and rank in a revision: a list of { source, reason, specs }, empty when none.
function Rules.SkipEntries(data, revision, family, rank)
  local flat = data.skipRevisions and data.skipRevisions[revision]
  local ranks = flat and flat[family]
  return ranks and ranks[rank] or {}
end

-- The sentence that says why a rank is skipped, from the locale and the numbers the data records.
local REASON_TEXT = {
  guideFirstRankOnly = L["The leveling guide says to buy only the first rank of this spell."],
  guideSkipEntirely = L["The leveling guide says this spell is not worth buying while leveling."],
  guideUpToRank = L["The leveling guide says to buy this spell only up to rank %d."],
  guideNotTrained = L["The leveling guide does not buy this rank while leveling."],
  noGain = L["Adds nothing over the rank before it."],
  smallStep = L["Only %d%% stronger than the rank before it, for a spell you only use now and then."],
  notWorthPrice = L["Only %d%% stronger than the rank before it, which does not repay its price."],
  waitForMount = L["This rank can wait until you have your level 60 mount."],
  legacy = L["An earlier version of this list judged this rank a small upgrade."],
}
local REASON_NUMBER = { guideUpToRank = "n", smallStep = "pct", notWorthPrice = "pct" }

function Rules.SkipReason(reason)
  local text = REASON_TEXT[reason.kind]
  local field = REASON_NUMBER[reason.kind]
  return field and text:format(reason[field]) or text
end

-- Where a skip came from, for the Rules page.
local SOURCE_TEXT = {
  guide = L["From the Wowhead leveling guide."],
  computed = L["Computed from the game data."],
  legacy = L["From the earlier skip list."],
}
function Rules.SkipSource(source) return SOURCE_TEXT[source] end

-- The entry that skips a rank for a player, or nil. Every spec still plausible for the player must skip it; an
-- entry with no `specs` covers every spec of the class.
local function skipEntryFor(entries, keys)
  local covered, byKey = {}, {}
  for _, entry in ipairs(entries) do
    for _, key in ipairs(entry.specs or keys) do
      covered[key] = true
      byKey[key] = byKey[key] or entry
    end
  end
  for _, key in ipairs(keys) do
    if not covered[key] then return nil end
  end
  return byKey[keys[1]]
end
Rules.SkipEntryFor = skipEntryFor

function Rules.GetClass(key) return classes[key] end

-- Sorted keys of every loaded class, e.g. { "HUNTER" }.
function Rules.ListClasses()
  local keys = {}
  for key in pairs(classes) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local learn = { names = {}, gathering = {}, reason = L["%s costs gold at every level."] }

-- Rule data for the one-time "learning a profession" question (Rules/Data/ProfessionLearn.lua). A profession is
-- identified by the spell ID of its apprentice tier. The data names them in English (apprentice = { Cooking = 2550 },
-- gathering = { Fishing = true }); the engine works in the IDs.
function Rules.SetProfessionLearn(data)
  local names, gathering = {}, {}
  for name, id in pairs(data.apprentice or {}) do names[id] = name end
  for name in pairs(data.gathering or {}) do
    local id = data.apprentice and data.apprentice[name]
    if not id then error(("DontDoThat rule data (professions): gathering profession '%s' has no apprentice spell"):format(name), 0) end
    gathering[id] = true
  end
  learn = { names = names, gathering = gathering, reason = data.reason }
end

-- Profession ID -> its English name, for the adapter to match against and for text when the client gives none.
function Rules.ProfessionNames() return learn.names end

-- A profession ID the player should be asked about the first time they learn it. Gathering professions and
-- anything unknown return nil.
function Rules.MatchProfessionLearn(id)
  if learn.names[id] and not learn.gathering[id] then return id end
end

-- Test hook: forget all loaded data.
function Rules.Reset()
  classes = {}
  revisionNumbers = nil
end

local SEVERITY = { keep = 0, info = 1, deferLow = 2, defer = 3 }

local function contains(list, name)
  for _, v in ipairs(list or {}) do
    if v == name then return true end
  end
  return false
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function specName(data, key)
  return data.specs[key].name or key
end

local function plausible(profile, data)
  local keys, seen = {}, {}
  for _, key in ipairs(profile.plausibleSpecs or {}) do
    if data.specs[key] and not seen[key] then seen[key] = true; keys[#keys + 1] = key end
  end
  if #keys == 0 then keys = sortedKeys(data.specs) end -- ambiguous: every spec is plausible
  return keys, seen
end

-- A talent-only spell is part of a rotation only while its talent is active. An unknown talent list
-- (nil) never hides a spell.
local function inRotation(profile, data, list, name)
  if not contains(list, name) then return false end
  if profile.activeTalents and contains(data.talentSpells, name) and not profile.activeTalents[name] then return false end
  return true
end

local function rankRow(data, action)
  local rows = data.ranks and data.ranks[action.familyId]
  return rows and action.rank and rows[action.rank], rows
end

local function verdict(profile, tier, source, reason, cost, isEstimate)
  local m = profile.milestone or {}
  return {
    tier = tier, cost = cost, costIsEstimate = cost ~= nil and isEstimate or false,
    reason = reason, milestone = m.current, source = source,
  }
end

local function keep(profile)
  return verdict(profile, "keep", "default", L["No rule applies."])
end

-- Cost: the adapter-supplied price wins; otherwise a data estimate, marked as such.
local function costFor(action, estimate)
  if action.cost then return action.cost, false end
  return estimate, true
end

-- Player-facing wording. Keep it short and free of internal terms (tags, tiers, specs, rotations).
local WAIT_UNTIL_60 = L["You won't need this until level 60."]

-- A per-ability sentence wins, then a per-tag sentence from the rule data, then the default.
local function whyWait(data, name, tag)
  if data.why and data.why[name] then return data.why[name] end
  if tag and data.tagReasons and data.tagReasons[tag] then return data.tagReasons[tag] end
  return WAIT_UNTIL_60
end

-- The same sentence the player sees in a tooltip, for pages that list an ability without a purchase.
function Rules.WhyWait(data, name, tag) return whyWait(data, name, tag) end

local function evaluateSpell(profile, action, data)
  local name = action.familyId
  if name == nil then return keep(profile) end
  local rules = profile.rules or {}
  local offAbilities, offTags, offKinds = rules.offAbilities or {}, rules.offTags or {}, rules.offKinds or {}
  -- An ability the player switched off is never flagged, whatever else would apply.
  if offAbilities[name] then return verdict(profile, "keep", "disabled", L["You turned off warnings for this."]) end
  local row, rows = rankRow(data, action)
  local cost, isEstimate = costFor(action, row and row.cost)
  local function out(tier, source, reason) return verdict(profile, tier, source, reason, cost, isEstimate) end

  -- A skipped rank is judged on its own, even when the spell as a whole is kept. Which ranks are skipped is decided
  -- by the revision the player chose (the newest unless they picked an earlier one).
  local keys, isPlausible = plausible(profile, data)
  if action.rank and not offKinds.skipRank then
    local entries = Rules.SkipEntries(data, Rules.ResolveRevision(rules.skipRevision), name, action.rank)
    local entry = #entries > 0 and skipEntryFor(entries, keys)
    if entry then return out("defer", "skipRank", Rules.SkipReason(entry.reason)) end
  end

  local override = data.overrides and data.overrides[name]
  if override then
    if override == "keep" then return verdict(profile, "keep", "override", L["Worth having."]) end
    return out(override, "override", whyWait(data, name))
  end

  local infoSpec
  for _, key in ipairs(keys) do
    local rot = data.specs[key].rotation
    if inRotation(profile, data, rot.core, name) then
      return verdict(profile, "keep", "rotation", L["You'll use this a lot."])
    end
    if not infoSpec and inRotation(profile, data, rot.situational, name) then infoSpec = key end
  end
  if infoSpec then
    return out("info", "rotation", L["Handy now and then, but you can get by without it."])
  end

  local bestTier, bestTag
  local tags = {}
  for _, t in ipairs((data.tags and data.tags[name]) or {}) do tags[#tags + 1] = t end
  for _, t in ipairs(action.tags or {}) do tags[#tags + 1] = t end
  for _, tag in ipairs(tags) do
    local tier = not offTags[tag] and data.tagTiers and data.tagTiers[tag]
    if tier and SEVERITY[tier] > (bestTier and SEVERITY[bestTier] or 0) then bestTier, bestTag = tier, tag end
  end
  if bestTier then
    return out(bestTier, "tag", whyWait(data, name, bestTag))
  end

  for _, key in ipairs(offKinds.offSpec and {} or sortedKeys(data.specs)) do
    local rot = data.specs[key].rotation
    if not isPlausible[key] and (inRotation(profile, data, rot.core, name) or inRotation(profile, data, rot.situational, name)) then
      return out("deferLow", "rotation", (L["Mostly used by %s players, and your talents lean another way."]):format(specName(data, key)))
    end
  end

  return keep(profile)
end

-- Asked once per profession: already known, or already asked, means nothing to say.
local function evaluateProfessionLearn(profile, action)
  local name = action.profession
  if (profile.professions or {})[name] or (profile.professionAsked or {})[name] then return keep(profile) end
  local v = verdict(profile, "defer", "professionLearn", learn.reason:format(action.displayName or learn.names[name] or tostring(name)), nil, false)
  v.profession = name
  return v
end

function Rules.Evaluate(profile, action)
  local m = profile.milestone
  if not (m and m.state == "active") then return keep(profile) end
  if action.kind == "professionLearn" then return evaluateProfessionLearn(profile, action) end
  local data = classes[profile.class]
  if not data then return keep(profile) end
  return evaluateSpell(profile, action, data)
end
