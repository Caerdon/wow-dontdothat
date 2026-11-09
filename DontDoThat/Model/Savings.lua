local addonName, ns = ...

-- Projected savings: the trainer gold a player keeps by following the addon's advice all the way up to a level.
-- Counts every purchasable rank up to that level that the rules would warn about (Save your gold, Not worth
-- buying yet, and ranks to skip). Worth buying and Optional spells cost nothing here.
local Savings = {}
ns.Savings = Savings

-- copper per group, plus how many spells and whether any price is not one seen at a trainer.
local function empty() return { total = 0, wait = 0, low = 0, skip = 0, count = 0, unconfirmed = false, byFamily = {} } end

-- profile: class, plausibleSpecs, rules, activeTalents (as the context builds it). stopLevel: the mount level
-- to save for. costCache: prices seen at this character's trainers, by Ledger.CostKey.
function Savings.Compute(profile, stopLevel, costCache)
  local out = empty()
  local data = ns.Rules and ns.Rules.GetClass(profile.class)
  if not data then return out end
  local planned = {}
  for k, v in pairs(profile) do planned[k] = v end
  planned.milestone = { current = stopLevel, state = "active" }
  local talent = {}
  for _, id in ipairs(data.talentSpells or {}) do talent[id] = true end
  for _, row in ipairs(ns.SpellData.Rows(profile.class)) do
    local level = row.level or 0
    -- A talent's first rank comes with the talent; later ranks are bought.
    local familyId = ns.SpellData.FamilyOfId(profile.class, row.id)
    local free = talent[familyId] and (row.rank or 1) <= 1
    if (row.kind == "class" or row.kind == "pet") and level > 1 and level <= stopLevel and not free then
      local verdict = ns.Rules.Evaluate(planned, { kind = "spell", name = row.name, familyId = familyId,
        rank = row.rank, unlockLevel = level })
      if verdict.tier == "defer" or verdict.tier == "deferLow" then
        local cost, estimate = ns.SpellData.Cost(profile.class, row)
        -- A rank-less row would share one key with every other rank-less spell of its name, so it has no seen price.
        local seen = row.rank and costCache and costCache[ns.Ledger.CostKey(familyId, row.rank)]
        if seen then cost, estimate = seen, false end
        if cost then
          local group = verdict.source == "skipRank" and "skip" or (verdict.tier == "defer" and "wait" or "low")
          out[group] = out[group] + cost
          out.total = out.total + cost
          out.count = out.count + 1
          out.byFamily[familyId] = (out.byFamily[familyId] or 0) + cost
          if estimate then out.unconfirmed = true end
        else
          out.unconfirmed = true -- no price anywhere, so the total is short by this rank
        end
      end
    end
  end
  return out
end

local function copyRules(rules)
  local out = { offAbilities = {}, offTags = {}, offKinds = {} }
  for _, bucket in ipairs({ "offAbilities", "offTags", "offKinds" }) do
    for name, off in pairs(rules and rules[bucket] or {}) do out[bucket][name] = off end
  end
  out.skipRevision = rules and rules.skipRevision -- which skip list the savings are worked out on
  return out
end

local function withRules(profile, edit)
  local planned = {}
  for k, v in pairs(profile) do planned[k] = v end
  planned.rules = copyRules(profile.rules)
  edit(planned.rules)
  return planned
end

-- What one switch is worth: the savings with it on minus the savings with it off, every other setting as it is.
-- bucket is "offKinds", "offTags" or "offAbilities"; name is the switch (a family ID for offAbilities).
function Savings.Worth(profile, stopLevel, costCache, bucket, name)
  local on = Savings.Compute(withRules(profile, function(r) r[bucket][name] = nil end), stopLevel, costCache).total
  local off = Savings.Compute(withRules(profile, function(r) r[bucket][name] = true end), stopLevel, costCache).total
  return math.max(0, on - off)
end

-- What each spell would keep with every ability switch on: { [family ID] = copper }.
function Savings.ByAbility(profile, stopLevel, costCache)
  return Savings.Compute(withRules(profile, function(r) r.offAbilities = {} end), stopLevel, costCache).byFamily
end

-- What each spec of a class could keep with every rule on, whatever the player's settings.
-- Returns { specs = { { name =, total = }, ... in tree order }, unconfirmed = }.
function Savings.Max(classKey, stopLevel)
  local data = ns.Rules and ns.Rules.GetClass(classKey)
  local out = { specs = {}, unconfirmed = false }
  if not data then return out end
  local list = {}
  for key, spec in pairs(data.specs) do list[#list + 1] = { key = key, name = spec.name or key, tree = spec.tree or 0 } end
  table.sort(list, function(a, b) if a.tree ~= b.tree then return a.tree < b.tree end return a.key < b.key end)
  for _, spec in ipairs(list) do
    local r = Savings.Compute({ class = classKey, plausibleSpecs = { spec.key } }, stopLevel)
    out.specs[#out.specs + 1] = { name = spec.name, total = r.total }
    out.unconfirmed = out.unconfirmed or r.unconfirmed
  end
  return out
end
