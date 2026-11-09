local addonName, ns = ...

-- Reads the player's rule settings (Rules and General pages) in the shapes the engine and intercepts
-- need. Pure: every function takes the saved profile table, or finds it in ns.db, and tolerates it
-- being absent so a missing database means "all defaults".
local Settings = {}
ns.Settings = Settings

Settings.RuleKinds = { "skipRank", "offSpec" }

local function saved()
  return ns.db and ns.db.profile
end

-- A whole number of zero or more, else nil.
function Settings.Number(value)
  if type(value) == "number" and value >= 0 and value == math.floor(value) then return value end
  return nil
end

local function tuning(p)
  p = p or saved()
  return p and p.tuning or {}
end

-- { defer = true, deferLow = false, info = false }: the tiers that ask "Buy anyway?" and play the sound.
-- Only defer by default. keep never counts.
function Settings.PromptTiers(p)
  local chosen = tuning(p).promptTiers
  local out = {}
  for _, tier in ipairs({ "defer", "deferLow", "info" }) do
    if chosen == nil then out[tier] = tier == "defer" else out[tier] = chosen[tier] == true end
  end
  return out
end

function Settings.PromptsFor(tier, p)
  return Settings.PromptTiers(p)[tier] == true
end

local function flag(p, key) return p == nil or p[key] ~= false end

-- How firmly the addon nudges: "mark" (marks only, never asks), "ask" (asks about what to wait on),
-- "everything" (also asks about low-value and informational items), or "custom" when the saved marks,
-- "Ask before buying" and prompt tiers match none of those. Derived, never stored. Sound is not part of it.
function Settings.Nudge(p)
  p = p or saved()
  if not flag(p, "warnings") then return "custom" end
  if not flag(p, "blockingConfirmations") then return "mark" end
  local tiers = Settings.PromptTiers(p)
  if tiers.defer and tiers.deferLow and tiers.info then return "everything" end
  if tiers.defer and not tiers.deferLow and not tiers.info then return "ask" end
  return "custom"
end

-- Sets the three values behind a nudge level. "custom" (or anything else) changes nothing.
function Settings.SetNudge(name, p)
  p = p or saved()
  if not p then return end
  local tiers
  if name == "mark" then
    p.warnings, p.blockingConfirmations = true, false
    return
  elseif name == "ask" then tiers = { defer = true, deferLow = false, info = false }
  elseif name == "everything" then tiers = { defer = true, deferLow = true, info = true }
  else return end
  p.warnings, p.blockingConfirmations = true, true
  p.tuning = p.tuning or {}
  p.tuning.promptTiers = tiers
end

-- The areas of "What to watch" that have a switch of their own. Other has none: it is the slot and COD switches.
Settings.Areas = { "spells", "professions", "shopping" }

function Settings.Watching(area, p)
  p = p or saved()
  return not (p and p.watch and p.watch[area] == false)
end

function Settings.SetWatching(area, on, p)
  p = p or saved()
  if not p then return end
  p.watch = p.watch or {}
  p.watch[area] = on and true or false
end

-- 40 or 60: the mount after which warnings stop.
function Settings.StopAfter(p)
  return tuning(p).stopAfter == 40 and 40 or 60
end

-- The skip revision the player picked, or nil for "the newest" (the default). A non-number is ignored.
function Settings.SkipRevision(p)
  local v = tuning(p).skipRevision
  if type(v) == "number" and v == math.floor(v) then return v end
  return nil
end

-- Saves the pick; nil goes back to following the newest revision.
function Settings.SetSkipRevision(revision, p)
  p = p or saved()
  if not p then return end
  p.tuning = p.tuning or {}
  p.tuning.skipRevision = revision
end

-- True while the profile has not been told about the newest revision: a new install, or an update that added one.
function Settings.RevisionNoticeDue(newest, p)
  p = p or saved()
  local told = p and p.revisionNotice
  return type(told) ~= "number" or told < newest
end

function Settings.MarkRevisionNotice(newest, p)
  p = p or saved()
  if p then p.revisionNotice = newest end
end

-- The settings the engine reads, copied so later edits don't reach a built profile. Nil values mean
-- "use the rule data".
function Settings.RulesFor(class, p)
  p = p or saved()
  local off = p and p.ruleOff or {}
  local t = tuning(p)
  local function set(from)
    local out = {}
    for k, v in pairs(from or {}) do if v then out[k] = true end end
    return out
  end
  return {
    offAbilities = set(off.abilities and off.abilities[class]),
    offTags = set(off.tags and off.tags[class]),
    offKinds = set(off.kinds),
    skipRevision = t.skipRevision, -- nil: the newest revision (the engine checks the number is one it has)
  }
end

-- Remembers that the player was asked about learning a profession, so it is asked about only once.
function Settings.MarkProfessionAsked(profession, p)
  p = p or saved()
  if not p then return end
  p.professionAsked = p.professionAsked or {}
  p.professionAsked[profession] = true
end

-- Settings that record what the player has already done rather than how they like things.
local KEEP_ON_RESET = { professionAsked = true, milestoneOverride = true, revisionNotice = true }

-- Puts every setting back to its default. With AceDB, removing a saved key lets the default show through again.
function Settings.ResetAll(p)
  p = p or saved()
  if not p then return end
  for key in pairs(p) do
    if not KEEP_ON_RESET[key] then p[key] = nil end
  end
  if ns.Log and ns.Log.SetEnabled then ns.Log.SetEnabled(false) end
end

-- Debug recording is for one session: it is switched off whenever the addon loads.
function Settings.ClearDebug(p)
  p = p or saved()
  if p then p.debug, p.traceItems = false, false end
end

-- The spec the player picked for a class, only when the class data has it.
function Settings.SpecOverride(class, classData, p)
  p = p or saved()
  local pick = p and p.specOverride and p.specOverride[class]
  if pick and classData and classData.specs and classData.specs[pick] then return pick end
  return nil
end

return Settings
