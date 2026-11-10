local addonName, ns = ...

-- The only module that reads trainer, talent and player state from the client. Everything goes
-- through an injected environment table (default _G) and pcall, so a missing or restricted
-- function degrades to "no data" instead of an error. Shapes below were observed on
-- Classic Era 1.15.9 (see docs/contracts.md); WoW Forever is UNVERIFIED.
local Adapter = {}
ns.Adapter = Adapter

-- Keeps the count of results, so a nil in the middle (a header row with no subtext) does not cut the rest off.
local function pack(...) return { n = select("#", ...), ... } end

local function call(env, fname, ...)
  local f = env[fname]
  if type(f) ~= "function" then return nil end
  local res = pack(pcall(f, ...))
  if not res[1] then return nil end
  return unpack(res, 2, res.n)
end

local function parseRank(sub)
  if type(sub) ~= "string" then return nil end
  local n = sub:match("(%d+)")
  return n and tonumber(n) or nil
end

-- Localized spell name -> family ID for a class, from the client's own spell names (see Model/SpellData.lua), so
-- trainer rows and talents in any language resolve. Cached per client environment and class.
local nameMaps = setmetatable({}, { __mode = "k" })

function Adapter.FamilyId(env, class, name)
  env = env or _G
  if not (class and ns.SpellData) then return nil end
  nameMaps[env] = nameMaps[env] or {}
  local maps = nameMaps[env]
  maps[class] = maps[class] or ns.SpellData.NameMap(class, env)
  return maps[class][name] or nil
end

-- The spell ID the game gives for trainer service i. The client has no call for it, but its tooltip knows the
-- spell: tooltip:SetTrainerService(i), then tooltip:GetSpell() -> name, spellID (confirmed by /ddt trainerids on a
-- Warrior trainer). Cached by row name and rank text, which identify a trainer spell, so scrolling costs nothing.
local scanTips = setmetatable({}, { __mode = "k" })
local seenIds = setmetatable({}, { __mode = "k" })

local function trainerSpellId(env, index, name, sub)
  local key = tostring(name) .. "\0" .. tostring(sub)
  seenIds[env] = seenIds[env] or {}
  if seenIds[env][key] then return seenIds[env][key] end
  if type(env.CreateFrame) ~= "function" then return nil end
  local tip = scanTips[env]
  if tip == nil then
    local ok, frame = pcall(env.CreateFrame, "GameTooltip", "DontDoThatScanTip", env.UIParent, "GameTooltipTemplate")
    tip = ok and frame or false
    scanTips[env] = tip
  end
  if not tip then return nil end
  pcall(tip.SetOwner, tip, env.UIParent, "ANCHOR_NONE")
  local id
  if pcall(tip.SetTrainerService, tip, index) and type(tip.GetSpell) == "function" then
    local ok, _, spellId = pcall(tip.GetSpell, tip)
    if ok and type(spellId) == "number" then id = spellId end
  end
  pcall(tip.Hide, tip)
  if id then seenIds[env][key] = id end
  return id
end

-- Localized name -> profession ID, from the client's name for each profession's apprentice spell.
local professionMaps = setmetatable({}, { __mode = "k" })

-- The profession a trainer row teaches the first tier of: the row's own spell ID when it is a profession's apprentice
-- spell, else the row's name (the trainer may teach a spell whose effect grants the profession, which this cannot
-- tell). A later tier shares the name; the engine ignores it for a profession the player already has.
function Adapter.TrainerProfessionId(env, row)
  if row.spellId and ns.Rules.ProfessionNames()[row.spellId] then return row.spellId end
  return Adapter.ProfessionId(env, row.name)
end

-- The profession ID (the apprentice spell ID, see Rules/Data/ProfessionLearn.lua) for a trainer row or skill line
-- name in the client's language, or nil. The English name also matches, which covers a client that names nothing and
-- the skill lines whose name differs from the spell's (the skill is "Herbalism", the spell "Herb Gathering").
function Adapter.ProfessionId(env, name)
  env = env or _G
  if type(name) ~= "string" then return nil end
  if not professionMaps[env] then
    local map = {}
    for id, english in pairs(ns.Rules.ProfessionNames()) do
      local localized = ns.SpellData and ns.SpellData.ClientName(env, id)
      if localized then map[localized] = id end
      map[english] = map[english] or id
    end
    professionMaps[env] = map
  end
  return professionMaps[env][name]
end

-- A trainer row in Classic Era's order: name, subText ("Rank 3"), type ("available"|"unavailable"|"used"|"header"),
-- expanded, and the category when the client gives one. Classic Era's GetTrainerServiceInfo returns it that way.
-- Forever returns Blizzard's mainline order instead, name, type, texture, reqLevel, subText, category (its
-- Blizzard_TrainerUI.lua reads it so; seen on 1.60.1 as "Eagle Eye", "available", 132172, 14, "", ""), told apart
-- by the type word sitting second. Read any other way, every Forever row looks unranked and never learned.
local SERVICE_TYPES = { available = true, unavailable = true, used = true, header = true }
function Adapter.TrainerServiceInfo(a, b, c, d, e, f)
  if SERVICE_TYPES[b] and not SERVICE_TYPES[c] then return a, e, b, nil, f end
  return a, b, c, d
end

-- GetTrainerServiceInfo(i) -> a row, see TrainerServiceInfo above
-- GetTrainerServiceCost(i) -> copper; GetTrainerServiceLevelReq(i) -> level
-- Returns { ok, reason, rows, byIndex }. rows keep the client's order and original service indexes;
-- category headers are included with header = true.
function Adapter.ReadTrainer(env)
  env = env or _G
  local count = call(env, "GetNumTrainerServices")
  if type(count) ~= "number" then
    return { ok = false, reason = "GetNumTrainerServices unavailable", rows = {}, byIndex = {} }
  end
  local rows, byIndex = {}, {}
  local class = Adapter.ReadPlayer(env).class
  for i = 1, count do
    local name, sub, kind, expanded = Adapter.TrainerServiceInfo(call(env, "GetTrainerServiceInfo", i))
    if name ~= nil then
      local row = { index = i, name = name, kind = kind, sub = sub }
      if kind == "header" then
        row.header = true
        row.expanded = expanded and true or false
      else
        -- The spell ID the game gives is the identity; the client's spell name only stands in when it gives none.
        row.spellId = trainerSpellId(env, i, name, sub)
        row.familyId = (row.spellId and class and ns.SpellData.FamilyOfId(class, row.spellId))
          or Adapter.FamilyId(env, class, name)
        row.rank = parseRank(sub)
        row.cost = (call(env, "GetTrainerServiceCost", i))
        row.level = (call(env, "GetTrainerServiceLevelReq", i))
        row.icon = (call(env, "GetTrainerServiceIcon", i))
        row.available = kind == "available"
        row.learned = kind == "used"
      end
      rows[#rows + 1] = row
      byIndex[i] = row
    end
  end

  return { ok = true, rows = rows, byIndex = byIndex }
end

-- Returns { class = "HUNTER", level = 10 } with nil fields when unreadable.
function Adapter.ReadPlayer(env)
  env = env or _G
  local _, class = call(env, "UnitClass", "player")
  local level = call(env, "UnitLevel", "player")
  return { class = type(class) == "string" and class or nil, level = type(level) == "number" and level or nil }
end

-- GetTalentTabInfo(i): id-first shape (id, name, description, icon, pointsSpent, ...) observed on
-- Classic Era 1.15.9; the older (name, icon, pointsSpent) shape is also accepted.
-- Returns an array indexed by tab: { name = , points = }.
function Adapter.ReadTalentTabs(env)
  env = env or _G
  local tabs = {}
  local count = call(env, "GetNumTalentTabs")
  if type(count) ~= "number" then return tabs end
  for i = 1, count do
    local a, b, c, _, e = call(env, "GetTalentTabInfo", i)
    if a ~= nil then
      local name, points = a, c
      if type(a) == "number" and type(b) == "string" then name, points = b, e end
      tabs[i] = { name = name, points = type(points) == "number" and points or 0 }
    end
  end
  return tabs
end

-- The talent's database ID, read from its hyperlink ("|Htalent:2213:1|h[Name]|h"), or nil.
local function talentId(env, tab, index)
  local link = call(env, "GetTalentLink", tab, index)
  return type(link) == "string" and tonumber(link:match("Htalent:(%d+)")) or nil
end

-- Family IDs of the spells the player's talents grant, as a set: the talents with at least one point. A talent is
-- recognised by its ID from the talent hyperlink (Data/TalentData.lua gives its rank spells), and only when the
-- client gives no link, or the table does not know the talent, by the talent's name. A talent that is not a spell
-- the rules care about is left out. Returns nil when the client cannot say, so rules treat every talent as unknown
-- rather than missing.
-- Forever has no talent tabs: its talents are C_Traits nodes, each giving the spell of its chosen entry (confirmed by the
-- Talent traits section of the export: node rank, entry, spell 19552 = rank 1 of talent 1382). A node with a rank
-- counts, and its spell resolves to a family like any other spell.
local function traitTalents(env, class)
  local CT, T = env.C_ClassTalents, env.C_Traits
  if type(CT) ~= "table" or type(T) ~= "table" or not class then return nil end
  local ok, configID = pcall(CT.GetActiveConfigID)
  if not ok or not configID then return nil end
  local okc, cfg = pcall(T.GetConfigInfo, configID)
  if not okc or type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then return nil end
  local active = {}
  for _, treeID in ipairs(cfg.treeIDs) do
    local okn, nodes = pcall(T.GetTreeNodes, treeID)
    for _, nodeID in ipairs(okn and type(nodes) == "table" and nodes or {}) do
      local _, node = pcall(T.GetNodeInfo, configID, nodeID)
      local entryID = type(node) == "table" and (node.currentRank or 0) > 0 and node.activeEntry and node.activeEntry.entryID
      if entryID then
        local _, entry = pcall(T.GetEntryInfo, configID, entryID)
        local _, def = pcall(T.GetDefinitionInfo, type(entry) == "table" and entry.definitionID or 0)
        local family = type(def) == "table" and def.spellID and ns.SpellData.FamilyOfId(class, def.spellID)
        if family then active[family] = true end
      end
    end
  end
  return active
end

function Adapter.ReadActiveTalents(env)
  env = env or _G
  local tabCount = call(env, "GetNumTalentTabs")
  if type(tabCount) ~= "number" then return traitTalents(env, Adapter.ReadPlayer(env).class) end
  local active = {}
  local class = Adapter.ReadPlayer(env).class
  for tab = 1, tabCount do
    local count = call(env, "GetNumTalents", tab)
    for i = 1, type(count) == "number" and count or 0 do
      local name, _, _, _, rank = call(env, "GetTalentInfo", tab, i)
      if type(rank) == "number" and rank > 0 then
        local spells = ns.TalentSpells and ns.TalentSpells[talentId(env, tab, i)]
        local family
        if spells then
          for _, spellId in ipairs(spells) do
            family = family or (class and ns.SpellData.FamilyOfId(class, spellId))
          end
        elseif type(name) == "string" then
          family = Adapter.FamilyId(env, class, name)
        end
        if family then active[family] = true end
      end
    end
  end
  return active
end

-- The trainer window's type filters. The list only holds rows that pass them, so a row missing from it
-- can only be read as "learned" while both of these are on.
function Adapter.ReadTrainerFilters(env)
  env = env or _G
  local function on(kind)
    local value = call(env, "GetTrainerServiceTypeFilter", kind)
    return value == true or value == 1
  end
  return { available = on("available"), unavailable = on("unavailable"), used = on("used") }
end

-- Who the open trainer is: the NPC's GUID, which is the same in every language and different for two trainers
-- that share a name. The name stands in when the client gives no GUID.
function Adapter.ReadNpcId(env)
  env = env or _G
  local guid = call(env, "UnitGUID", "npc")
  if type(guid) == "string" and guid ~= "" then return guid end
  local name = call(env, "UnitName", "npc")
  return type(name) == "string" and name or nil
end

-- Beast training (the hunter's pet abilities, paid in training points) opens the trainer window with the pet as the
-- "npc" unit, or with no "npc" at all (the debug log names that case "unknown"). The addon stays out of it. A Pet
-- Trainer NPC is neither, so it gets the full treatment.
function Adapter.IsBeastTraining(env)
  env = env or _G
  -- Forever says so outright: its trainer window reads C_Trainer.GetTrainerType() and treats Enum.TrainerType.Pet
  -- as beast training, switching to the "pet" unit for the title. The "npc" unit does not name the pet there, so the
  -- unit checks below would call beast training a trainer and leave the purchase wrapped, which the client refuses.
  local trainerType = type(env.C_Trainer) == "table" and call(env.C_Trainer, "GetTrainerType")
  local petType = type(env.Enum) == "table" and type(env.Enum.TrainerType) == "table" and env.Enum.TrainerType.Pet
  if type(trainerType) == "number" and type(petType) == "number" then return trainerType == petType end
  if type(env.UnitName) ~= "function" then return false end -- cannot tell
  local guid, name = call(env, "UnitGUID", "npc"), call(env, "UnitName", "npc")
  if not (type(guid) == "string" and guid ~= "") and not (type(name) == "string" and name ~= "") then return true end
  if call(env, "UnitIsUnit", "npc", "pet") then return true end
  local petGuid = call(env, "UnitGUID", "pet")
  return type(guid) == "string" and guid == petGuid
end

-- Riding is bought as a spell, and the player has it when the spellbook knows any of the IDs. Forever has
-- Apprentice Riding (the level 40 goal) and Journeyman Riding (level 60). Classic Era has neither: riding is the
-- racial passive of the player's mount (Horse Riding, Wolf Riding, Ram Riding, Tiger Riding, Raptor Riding, Kodo
-- Riding, Undead Horsemanship, Mechanostrider Piloting), confirmed absent by /ddt trainerids on Era. Era's level 60
-- riding is a higher skill rank of the same skill. A Paladin or Warlock has class mounts instead: Summon Warhorse / Felsteed are the level 40 goal and Summon
-- Charger / Dreadsteed the level 60 one, on both clients. Level 60 riding for the races on Era is read from the skill
-- line's max rank below.
local RIDING = {
  apprentice = { 33388, 33389, 824, 825, 826, 828, 10861, 18995, 10906, 10907, 13819, 1279399, 5784 },
  journeyman = { 33391, 33392, 23214, 23161 },
}

local function knowsAny(env, ids)
  for _, id in ipairs(ids) do
    if Adapter.IsSpellKnown(env, id) == true then return true end
  end
  return false
end

-- Classic Era's racial riding skills: spell ID -> the English name of the spell and of its skill line, which are the
-- same word (Horse Riding spell 824 and skill line 148). The skill's max rank is 75 once riding is learned and 150
-- once epic riding is, which is the only sign of level 60 riding there.
local ERA_RIDING_SKILLS = {
  [824] = "Horse Riding", [825] = "Wolf Riding", [826] = "Ram Riding", [828] = "Tiger Riding",
  [10861] = "Raptor Riding", [18995] = "Kodo Riding", [10906] = "Undead Horsemanship", [10907] = "Mechanostrider Piloting",
}
Adapter.EraRidingSkills = ERA_RIDING_SKILLS

-- Has the player trained the 150 rank of a racial riding skill? The skill line is found through the client's name
-- for the racial spell, so this works in any language; GetSkillLineInfo gives no skill ID.
local function epicRidingSkill(env)
  local wanted = {}
  for id, english in pairs(ERA_RIDING_SKILLS) do
    wanted[(ns.SpellData and ns.SpellData.ClientName(env, id)) or english] = true
    wanted[english] = true
  end
  local count = call(env, "GetNumSkillLines")
  if type(count) ~= "number" then return false end
  for i = 1, count do
    local name, isHeader, _, _, _, _, maxRank = call(env, "GetSkillLineInfo", i)
    if type(name) == "string" and not isHeader and wanted[name] and type(maxRank) == "number" and maxRank >= 150 then
      return true
    end
  end
  return false
end

function Adapter.ReadRiding(env)
  env = env or _G
  return {
    apprentice = knowsAny(env, RIDING.apprentice),
    journeyman = knowsAny(env, RIDING.journeyman) or epicRidingSkill(env),
  }
end

-- GetSkillLineInfo(i) -> name, isHeader, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank
-- (the Classic shape, UNVERIFIED on Forever; the debug report lists the lines it sees).
-- Returns { [professionId] = { skill = , max = } } for each profession the player has.
function Adapter.ReadProfessions(env)
  env = env or _G
  local out = {}
  -- Forever: C_SkillInfo.GetNumSkillLines and GetSkillLineInfo(i) -> { name, isHeader, rank, maxRank, ... }
  -- (shape seen in the export); the legacy globals are gone there.
  local api = env.C_SkillInfo
  local modern = type(env.GetNumSkillLines) ~= "function" and type(api) == "table" and type(api.GetSkillLineInfo) == "function"
  local count = modern and select(2, pcall(api.GetNumSkillLines)) or call(env, "GetNumSkillLines")
  if type(count) ~= "number" then count = 0 end
  for i = 1, count do
    local name, isHeader, rank, maxRank, _
    if modern then
      local ok, info = pcall(api.GetSkillLineInfo, i)
      if ok and type(info) == "table" then name, isHeader, rank, maxRank = info.name, info.isHeader, info.rank, info.maxRank end
    else
      name, isHeader, _, rank, _, _, maxRank = call(env, "GetSkillLineInfo", i)
    end
    if type(name) == "string" and not isHeader and type(rank) == "number" then
      local id = Adapter.ProfessionId(env, name)
      if id then out[id] = { skill = rank, max = type(maxRank) == "number" and maxRank or nil } end
    end
  end
  -- A profession whose apprentice spell the spellbook knows counts as known whatever the skill line is called.
  for id in pairs(ns.Rules.ProfessionNames()) do
    if not out[id] and Adapter.IsSpellKnown(env, id) == true then out[id] = {} end
  end
  return out
end

-- Does the character know this spell? true or false, or nil when the client cannot say.
-- (C_SpellBook.IsSpellKnown and the older IsSpellKnown both exist on Classic Era 1.15.9.)
function Adapter.IsSpellKnown(env, id)
  env = env or _G
  if type(env.C_SpellBook) == "table" and type(env.C_SpellBook.IsSpellKnown) == "function" then
    local ok, known = pcall(env.C_SpellBook.IsSpellKnown, id)
    if ok then return known == true end
  end
  if type(env.IsSpellKnown) == "function" then
    local ok, known = pcall(env.IsSpellKnown, id)
    if ok then return known == true end
  end
  return nil
end
