local addonName, ns = ...

-- In-game API probe. Every WoW access goes through an injected environment table
-- (default _G) and is pcall-wrapped, so the report completes even when calls
-- error or return restricted ("secret") values. All API names below are
-- CANDIDATES: their existence on WoW Forever is exactly what this probe reports.
local Probe = {}
ns.Probe = Probe

local MAX_QUOTES = 50

local boundStore

local function newStore()
  return { respecQuotes = {}, interceptions = {}, rankSkips = {} }
end

function Probe.Init(saved)
  boundStore = saved or newStore()
  boundStore.respecQuotes = boundStore.respecQuotes or {}
  boundStore.interceptions = boundStore.interceptions or {}
  boundStore.rankSkips = boundStore.rankSkips or {}
  return boundStore
end

local function store(s)
  if s then
    s.respecQuotes = s.respecQuotes or {}
    s.interceptions = s.interceptions or {}
    s.rankSkips = s.rankSkips or {}
    return s
  end
  if not boundStore then Probe.Init() end
  return boundStore
end

local function now()
  return time and time() or 0
end

---------------------------------------------------------------------------
-- Safe helpers

-- issecretvalue is a Midnight-era global; unverified on Forever, so optional.
local function isSecret(env, v)
  local f = env.issecretvalue
  if type(f) ~= "function" then return false end
  local ok, res = pcall(f, v)
  return ok and res == true
end

local function describe(env, v)
  if isSecret(env, v) then return "<secret>" end
  local ok, s = pcall(tostring, v)
  if not ok then return "<unprintable>" end
  if type(v) == "string" then return ("%q"):format(s) end
  return s
end

-- Calls fn(...) and returns { ok=bool, err=string|nil, secret=bool, n=count, values={...} }.
-- Keeps the count of results, so a nil in the middle (a header row with no rank text) does not cut the rest off.
local function pack(...) return { n = select("#", ...), ... } end

local function safeCall(env, fn, ...)
  local packed = pack(pcall(fn, ...))
  if not packed[1] then
    return { ok = false, err = tostring(packed[2]), values = {}, n = 0 }
  end
  local res = { ok = true, values = {}, n = packed.n - 1 }
  for i = 2, packed.n do
    res.values[i - 1] = packed[i]
    if isSecret(env, packed[i]) then res.secret = true end
  end
  return res
end

local function resolve(env, path)
  local cur = env
  for part in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    local ok, nxt = pcall(function() return cur[part] end)
    if not ok then return nil end
    cur = nxt
  end
  return cur
end

local function summarize(env, res)
  if not res.ok then return "ERROR " .. res.err end
  local parts = {}
  for i = 1, math.min(res.n, 6) do parts[#parts + 1] = describe(env, res.values[i]) end
  local text = (#parts == 0) and "ok (no values)" or ("ok -> " .. table.concat(parts, ", "))
  if res.secret then text = text .. " [SECRET]" end
  return text
end

---------------------------------------------------------------------------
-- Candidate API existence

Probe.Candidates = {
  { group = "Legacy trainer", names = { "GetNumTrainerServices", "GetTrainerServiceInfo",
      "GetTrainerServiceCost", "GetTrainerServiceLevelReq", "BuyTrainerService", "SelectTrainerService" } },
  { group = "Modern trainer", names = { "C_Trainer.*" } },
  { group = "Talents", names = { "LearnTalent", "GetTalentInfo", "GetNumTalentTabs", "GetTalentTabInfo",
      "C_Traits.*", "C_ClassTalents.*", "C_SpecializationInfo.*" } },
  { group = "Respec", names = { "ConfirmTalentWipe", "GetTalentWipeCost", "ResetTalents",
      "C_ClassTalents.*" } },
  { group = "Spellbook", names = { "C_SpellBook.*" } },
  { group = "Menus (filter dropdowns)", names = { "Menu.*", "MenuUtil.*", "UIDropDownMenu_AddButton",
      "UIDropDownMenu_Initialize", "SetTrainerServiceTypeFilter" } },
  { group = "Auction house", names = { "C_AuctionHouse.*", "PlaceAuctionBid", "GetAuctionItemInfo",
      "GetAuctionItemLink", "GetSelectedAuctionItem", "AuctionFrame", "AuctionHouseFrame" } },
  { group = "Items", names = { "GetItemInfoInstant", "C_Item.*" } },
  { group = "Tooltips", names = { "GameTooltip", "TooltipDataProcessor", "TooltipDataProcessor.AddTooltipPostCall",
      "GameTooltip.SetMerchantItem", "GameTooltip.SetTrainerService", "GameTooltip.GetSpell", "GameTooltip.SetInboxItem" } },
  { group = "Vendor", names = { "BuyMerchantItem", "GetMerchantItemInfo", "GetMerchantItemLink", "GetMerchantNumItems",
      "GetMerchantItemCostInfo", "C_MerchantFrame.*", "MerchantFrame" } },
  { group = "Bank", names = { "PurchaseSlot", "GetBankSlotCost", "GetNumBankSlots", "C_Bank.*", "BankFrame" } },
  { group = "Stable", names = { "BuyStableSlot", "GetNextStableSlotCost", "GetNumStableSlots", "C_StableInfo.*" } },
  { group = "Mail", names = { "TakeInboxItem", "AutoLootMailItem", "GetInboxItem", "GetInboxItemLink",
      "GetInboxNumItems", "C_Mail.*" } },
  { group = "Pet reset", names = { "ConfirmPetUnlearn", "GetPetUnlearnCost", "ResetPetTalents" } },
  { group = "Skills and professions", names = { "GetNumSkillLines", "GetSkillLineInfo", "C_SkillInfo.*",
      "GetProfessions", "GetProfessionInfo", "C_TradeSkillUI.*", "IsSpellKnown", "GetMoney" } },
  { group = "Popups", names = { "StaticPopup_Show", "StaticPopupDialogs", "hooksecurefunc", "C_Timer.After" } },
  { group = "Sounds", names = { "PlaySound", "PlaySoundFile" } },
  { group = "Addons", names = { "C_AddOns.*", "GetAddOnMetadata", "LibStub", "issecretvalue" } },
}

local function listMembers(env, path)
  local base = path:gsub("%.%*$", "")
  local t = resolve(env, base)
  if type(t) ~= "table" then return nil end
  local names = {}
  local ok = pcall(function()
    for k, v in pairs(t) do
      if type(k) == "string" and type(v) == "function" then names[#names + 1] = k end
    end
  end)
  if not ok then return nil end
  table.sort(names)
  return names
end

function Probe.Existence(env)
  env = env or _G
  local lines = {}
  for _, g in ipairs(Probe.Candidates) do
    lines[#lines + 1] = "[" .. g.group .. "]"
    for _, name in ipairs(g.names) do
      if name:find("%.%*$") then
        local members = listMembers(env, name)
        if members then
          lines[#lines + 1] = ("  %s: present, %d functions: %s"):format(name, #members, table.concat(members, " "))
        else
          lines[#lines + 1] = "  " .. name .. ": missing"
        end
      else
        local v = resolve(env, name)
        lines[#lines + 1] = ("  %s: %s"):format(name, v == nil and "missing" or type(v))
      end
    end
  end
  return lines
end

---------------------------------------------------------------------------
-- Read-only call probes: { name, fn(env) } -> fn returns the values to record.
-- Add entries to this table to probe more.

local function callIfPresent(env, path, ...)
  local f = resolve(env, path)
  if type(f) ~= "function" then error("not available", 0) end
  return f(...)
end

Probe.Probes = {
  { name = "GetBuildInfo", fn = function(env) return callIfPresent(env, "GetBuildInfo") end },
  { name = "UnitClass(player)", fn = function(env) return callIfPresent(env, "UnitClass", "player") end },
  { name = "UnitLevel(player)", fn = function(env) return callIfPresent(env, "UnitLevel", "player") end },
  { name = "GetNumTrainerServices()", fn = function(env) return callIfPresent(env, "GetNumTrainerServices") end },
  { name = "GetTrainerServiceInfo(1)", fn = function(env) return callIfPresent(env, "GetTrainerServiceInfo", 1) end },
  { name = "GetNumTalentTabs()", fn = function(env) return callIfPresent(env, "GetNumTalentTabs") end },
  { name = "GetTalentTabInfo(1)", fn = function(env) return callIfPresent(env, "GetTalentTabInfo", 1) end },
  { name = "GetTalentInfo(1,1)", fn = function(env) return callIfPresent(env, "GetTalentInfo", 1, 1) end },
  { name = "GetTalentWipeCost()", fn = function(env) return callIfPresent(env, "GetTalentWipeCost") end },
  { name = "GetTalentClearInfo()", fn = function(env) return callIfPresent(env, "GetTalentClearInfo") end },
  { name = "GetNumUnspentTalents()", fn = function(env) return callIfPresent(env, "GetNumUnspentTalents") end },
  { name = "GetNextTalentLevel()", fn = function(env) return callIfPresent(env, "GetNextTalentLevel") end },
  { name = "C_ClassTalents.GetActiveConfigID()", fn = function(env) return callIfPresent(env, "C_ClassTalents.GetActiveConfigID") end },
  { name = "C_SpecializationInfo.GetSpecialization()", fn = function(env) return callIfPresent(env, "C_SpecializationInfo.GetSpecialization") end },
  { name = "GetMoney()", fn = function(env) return callIfPresent(env, "GetMoney") end },
  { name = "GetNumBankSlots()", fn = function(env) return callIfPresent(env, "GetNumBankSlots") end },
  { name = "GetBankSlotCost(1)", fn = function(env) return callIfPresent(env, "GetBankSlotCost", 1) end },
  { name = "GetNumStableSlots()", fn = function(env) return callIfPresent(env, "GetNumStableSlots") end },
  { name = "GetNextStableSlotCost()", fn = function(env) return callIfPresent(env, "GetNextStableSlotCost") end },
  { name = "GetInboxNumItems()", fn = function(env) return callIfPresent(env, "GetInboxNumItems") end },
  { name = "GetInboxItemLink(1,1)", fn = function(env) return callIfPresent(env, "GetInboxItemLink", 1, 1) end },
  { name = "GetMerchantNumItems()", fn = function(env) return callIfPresent(env, "GetMerchantNumItems") end },
  { name = "GetMerchantItemInfo(1)", fn = function(env) return callIfPresent(env, "GetMerchantItemInfo", 1) end },
  { name = "GetMerchantItemLink(1)", fn = function(env) return callIfPresent(env, "GetMerchantItemLink", 1) end },
  { name = "C_MerchantFrame.GetItemInfo(1)", fn = function(env) return callIfPresent(env, "C_MerchantFrame.GetItemInfo", 1) end },
  { name = "GetNumSkillLines()", fn = function(env) return callIfPresent(env, "GetNumSkillLines") end },
  { name = "C_SkillInfo.GetNumSkillLines()", fn = function(env) return callIfPresent(env, "C_SkillInfo.GetNumSkillLines") end },
  { name = "C_SkillInfo.GetSkillLineInfo(1)", fn = function(env)
      local info = callIfPresent(env, "C_SkillInfo.GetSkillLineInfo", 1)
      if type(info) ~= "table" then return info end
      local keys = {}
      for k, v in pairs(info) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
      table.sort(keys)
      return table.concat(keys, " ")
    end },
  { name = "GetProfessions()", fn = function(env) return callIfPresent(env, "GetProfessions") end },
  { name = "C_SpellBook.IsSpellKnown(33388 apprentice riding)", fn = function(env)
      return callIfPresent(env, "C_SpellBook.IsSpellKnown", 33388) end },
  { name = "C_AddOns.GetAddOnMetadata(Interface)", fn = function(env)
      return callIfPresent(env, "C_AddOns.GetAddOnMetadata", addonName, "Interface") end },
}

function Probe.CallResults(env)
  env = env or _G
  local lines = {}
  for _, p in ipairs(Probe.Probes) do
    local res = safeCall(env, p.fn, env)
    lines[#lines + 1] = ("  %s: %s"):format(p.name, summarize(env, res))
  end
  return lines
end

function Probe.BuildInfo(env)
  env = env or _G
  local res = safeCall(env, function() return callIfPresent(env, "GetBuildInfo") end)
  if not res.ok then return { "  GetBuildInfo: " .. summarize(env, res) } end
  -- Classic-family return order: version, build, date, interface (unverified for Forever).
  local v = res.values
  return {
    "  version: " .. describe(env, v[1]),
    "  build: " .. describe(env, v[2]),
    "  date: " .. describe(env, v[3]),
    "  interface: " .. describe(env, v[4]),
  }
end

---------------------------------------------------------------------------
-- Trainer snapshot

local function firstValue(env, path, ...)
  local f = resolve(env, path)
  if type(f) ~= "function" then return nil, "missing" end
  local res = safeCall(env, f, ...)
  if not res.ok then return nil, res.err end
  if res.secret then return nil, "secret" end
  return res.values[1], nil, res.values
end

local function parseRank(sub)
  if type(sub) ~= "string" then return nil end
  local n = sub:match("(%d+)")
  return n and tonumber(n) or nil
end

-- GetTrainerServiceInfo(i) -> name, subText ("Rank 3"), serviceType ("available"|"unavailable"|"used"|"header") on
-- Classic Era; Forever returns name, serviceType, texture, reqLevel, subText, category, and Adapter.TrainerServiceInfo
-- puts either into the Classic order. GetTrainerServiceCost(i) -> copper; GetTrainerServiceLevelReq(i) -> level.
-- Returns { ok=bool, reason=string|nil, services={...} }.
function Probe.TrainerSnapshot(env)
  env = env or _G
  local count, why = firstValue(env, "GetNumTrainerServices")
  if type(count) ~= "number" then
    return { ok = false, reason = "GetNumTrainerServices: " .. tostring(why or "no numeric result"), services = {} }
  end
  local services, headers = {}, {}
  for i = 1, count do
    local name, werr, vals = firstValue(env, "GetTrainerServiceInfo", i)
    local sub, status
    if name ~= nil then
      if ns.Adapter and ns.Adapter.TrainerServiceInfo then
        _, sub, status = ns.Adapter.TrainerServiceInfo(unpack(vals, 1, 6))
      else
        sub, status = vals[2], vals[3]
      end
    end
    if name == nil then
      services[#services + 1] = { index = i, error = werr or "no name" }
    elseif status == "header" then
      headers[#headers + 1] = { index = i, name = name }
    else
      local cost = firstValue(env, "GetTrainerServiceCost", i)
      local level = firstValue(env, "GetTrainerServiceLevelReq", i)
      services[#services + 1] = {
        index = i, name = name, rank = parseRank(sub), subText = sub,
        level = level, cost = cost, status = status,
        available = status == "available", learned = status == "used",
      }
    end
  end
  return { ok = true, services = services, headers = headers }
end

-- Names of spells where a higher rank is available while a lower rank is unlearned.
-- Returns an array of { name=, rank=, lowerUnlearned= }.
function Probe.RankSkips(services)
  local byName, out = {}, {}
  for _, s in ipairs(services or {}) do
    if s.name and s.rank then
      byName[s.name] = byName[s.name] or {}
      table.insert(byName[s.name], s)
    end
  end
  local names = {}
  for name in pairs(byName) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    for _, hi in ipairs(byName[name]) do
      if hi.available then
        for _, lo in ipairs(byName[name]) do
          if lo.rank < hi.rank and not lo.learned then
            out[#out + 1] = { name = name, rank = hi.rank, lowerUnlearned = lo.rank }
            break
          end
        end
      end
    end
  end
  return out
end

-- Remembers rank-skip observations in the store (deduplicated by name+rank).
function Probe.RecordRankSkips(snapshot, saved)
  local s = store(saved)
  for _, skip in ipairs(Probe.RankSkips(snapshot.services)) do
    local key = skip.name .. "#" .. skip.rank
    if not s.rankSkips[key] then
      s.rankSkips[key] = { name = skip.name, rank = skip.rank, lowerUnlearned = skip.lowerUnlearned, t = now() }
    end
  end
end

---------------------------------------------------------------------------
-- Talent points per tree

-- GetNumTalentTabs(), GetTalentTabInfo(i): two return shapes are handled, see below.
function Probe.TalentPoints(env)
  env = env or _G
  local count, why = firstValue(env, "GetNumTalentTabs")
  if type(count) ~= "number" then
    return { ok = false, reason = "GetNumTalentTabs: " .. tostring(why or "no numeric result"), trees = {} }
  end
  local trees = {}
  for i = 1, count do
    local first, werr, vals = firstValue(env, "GetTalentTabInfo", i)
    if first == nil then
      trees[#trees + 1] = { index = i, error = werr or "no result" }
    else
      -- Observed on Classic Era 1.15.9: id, name, description, icon, pointsSpent, background.
      -- Older Classic builds returned name, icon, pointsSpent.
      local name, points = vals[1], vals[3]
      if type(vals[1]) == "number" and type(vals[2]) == "string" then
        name, points = vals[2], vals[5]
      end
      trees[#trees + 1] = { index = i, name = name, points = type(points) == "number" and points or nil }
    end
  end
  return { ok = true, trees = trees }
end

-- Forever has no GetNumTalentTabs; its talents are retail-style C_Traits trees. Walks the active config and lists
-- every node with points (node, rank, entry, spell ID), so the real shapes and spell IDs can be read from a report.
-- Every call is pcall-guarded; the output is capped.
local TRAIT_LINE_CAP = 80

function Probe.TraitTalents(env)
  env = env or _G
  local CT, T = env.C_ClassTalents, env.C_Traits
  if type(CT) ~= "table" or type(T) ~= "table" then return { "  unavailable: no C_ClassTalents / C_Traits" } end
  local function try(label, f, ...)
    if type(f) ~= "function" then return nil, label .. ": missing" end
    local ok, a = pcall(f, ...)
    if not ok then return nil, label .. ": error " .. tostring(a) end
    return a
  end
  local configID, why = try("GetActiveConfigID", CT.GetActiveConfigID)
  if not configID then return { "  unavailable: " .. tostring(why or "GetActiveConfigID returned nil") } end
  local cfg, cwhy = try("GetConfigInfo", T.GetConfigInfo, configID)
  if type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then
    return { ("  configID %s; %s"):format(tostring(configID), tostring(cwhy or "GetConfigInfo has no treeIDs")) }
  end
  local lines = { ("  configID %s, %d tree(s)"):format(tostring(configID), #cfg.treeIDs) }
  local function add(s) if #lines <= TRAIT_LINE_CAP then lines[#lines + 1] = s end end
  for _, treeID in ipairs(cfg.treeIDs) do
    local nodes, nwhy = try("GetTreeNodes", T.GetTreeNodes, treeID)
    if type(nodes) ~= "table" then
      add(("  tree %s: %s"):format(tostring(treeID), tostring(nwhy)))
    else
      local spent = 0
      add(("  tree %s: %d nodes"):format(tostring(treeID), #nodes))
      for _, nodeID in ipairs(nodes) do
        local node = try("GetNodeInfo", T.GetNodeInfo, configID, nodeID)
        local rank = type(node) == "table" and node.currentRank
        if type(rank) == "number" and rank > 0 then
          spent = spent + rank
          local entryID = node.activeEntry and node.activeEntry.entryID
          local entry = entryID and try("GetEntryInfo", T.GetEntryInfo, configID, entryID)
          local def = type(entry) == "table" and entry.definitionID and try("GetDefinitionInfo", T.GetDefinitionInfo, entry.definitionID)
          add(("    node %s rank %s/%s entry %s spell %s"):format(tostring(nodeID), tostring(rank),
            tostring(node.maxRanks), tostring(entryID), tostring(type(def) == "table" and def.spellID)))
        end
      end
      add(("  tree %s: %d points spent"):format(tostring(treeID), spent))
    end
  end
  return lines
end

-- Dialog names the guards look for, and any other popup in the client that sounds related. A guard whose name is
-- missing here never fires.
local WANTED_POPUPS = { "CONFIRM_BUY_BANK_SLOT", "CONFIRM_BUY_STABLE_SLOT", "COD_CONFIRMATION",
  "COD_CONFIRMATION_AUTO_LOOT", "CONFIRM_TALENT_WIPE", "CONFIRM_PET_UNLEARN" }
local POPUP_WORDS = { "BANK", "STABLE", "COD", "WIPE", "UNLEARN", "TALENT", "RESET", "PET", "RESPEC", "MAIL" }

function Probe.Popups(env)
  env = env or _G
  local dialogs = env.StaticPopupDialogs
  if type(dialogs) ~= "table" then return { "  unavailable: no StaticPopupDialogs" } end
  local lines, extra = {}, {}
  for _, name in ipairs(WANTED_POPUPS) do
    lines[#lines + 1] = ("  %s: %s"):format(name, dialogs[name] ~= nil and "present" or "MISSING")
  end
  local wanted = {}
  for _, name in ipairs(WANTED_POPUPS) do wanted[name] = true end
  pcall(function()
    for key in pairs(dialogs) do
      if type(key) == "string" and not wanted[key] then
        for _, word in ipairs(POPUP_WORDS) do
          if key:find(word, 1, true) then extra[#extra + 1] = key; break end
        end
      end
    end
  end)
  table.sort(extra)
  lines[#lines + 1] = "  other related popups: " .. (#extra > 0 and table.concat(extra, " ") or "none")
  return lines
end

---------------------------------------------------------------------------
-- Observations

function Probe.RecordRespecQuote(count, copper, saved)
  local q = store(saved).respecQuotes
  q[#q + 1] = { count = count, copper = copper, t = now() }
  while #q > MAX_QUOTES do table.remove(q, 1) end
end

function Probe.RecordInterception(surface, outcome, saved)
  local s = store(saved).interceptions
  surface, outcome = tostring(surface), tostring(outcome)
  s[surface] = s[surface] or {}
  local o = s[surface][outcome]
  if not o then
    o = { n = 0 }
    s[surface][outcome] = o
  end
  o.n = o.n + 1
  o.last = now()
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function Probe.ObservationLines(saved)
  local s = store(saved)
  local lines = {}
  if #s.respecQuotes == 0 then
    lines[#lines + 1] = "  respec quotes: none observed"
  else
    for _, q in ipairs(s.respecQuotes) do
      lines[#lines + 1] = ("  respec quote: count=%s copper=%s t=%s"):format(tostring(q.count), tostring(q.copper), tostring(q.t))
    end
  end
  local surfaces = sortedKeys(s.interceptions)
  if #surfaces == 0 then lines[#lines + 1] = "  interceptions: none observed" end
  for _, surface in ipairs(surfaces) do
    for _, outcome in ipairs(sortedKeys(s.interceptions[surface])) do
      lines[#lines + 1] = ("  interception %s -> %s: x%d"):format(surface, outcome, s.interceptions[surface][outcome].n)
    end
  end
  local skips = sortedKeys(s.rankSkips)
  if #skips == 0 then lines[#lines + 1] = "  rank skipping: not observed" end
  for _, key in ipairs(skips) do
    local r = s.rankSkips[key]
    lines[#lines + 1] = ("  rank skipping possible: %s rank %d purchasable with rank %d unlearned"):format(r.name, r.rank, r.lowerUnlearned)
  end
  return lines
end

---------------------------------------------------------------------------
-- Report

local function money(c)
  return type(c) == "number" and tostring(c) .. "c" or "?"
end

-- Lists global functions/tables whose names contain any pattern, to discover APIs we did not guess.
function Probe.GlobalsMatching(env, patterns, limit)
  env = env or _G
  limit = limit or 60
  local lines = {}
  for _, pattern in ipairs(patterns) do
    local names = {}
    pcall(function()
      for k, v in pairs(env) do
        if type(k) == "string" and (type(v) == "function" or type(v) == "table")
            and k:lower():find(pattern:lower(), 1, true) then
          names[#names + 1] = k
        end
      end
    end)
    table.sort(names)
    local shown = {}
    for i = 1, math.min(#names, limit) do shown[i] = names[i] end
    lines[#lines + 1] = ("  *%s*: %d match(es)%s"):format(pattern, #names,
      #shown > 0 and (": " .. table.concat(shown, " ")) or "")
  end
  return lines
end

-- Skill lines as the client reports them (professions, weapon skills, languages), to confirm the shape
-- the profession rules rely on.
function Probe.SkillLines(env)
  env = env or _G
  local count = firstValue(env, "GetNumSkillLines")
  if type(count) ~= "number" then return { "  GetNumSkillLines unavailable" } end
  local lines = { ("  %d skill lines"):format(count) }
  for i = 1, math.min(count, 60) do
    local name, why, vals = firstValue(env, "GetSkillLineInfo", i)
    if name == nil then
      lines[#lines + 1] = ("  #%d %s"):format(i, tostring(why or "no result"))
    else
      lines[#lines + 1] = ("  #%d %s header=%s rank=%s max=%s"):format(i, tostring(name), tostring(vals[2]),
        tostring(vals[4]), tostring(vals[7]))
    end
  end
  return lines
end

-- Checks the bundled spell tables against the real client: does the spellbook answer for these IDs, and
-- does the game return an icon for them? A mismatch here is the first thing to look at if icons or the
-- tally look wrong.
local SAMPLE_SPELLS = { "Arcane Shot", "Serpent Sting", "Distracting Shot", "Great Stamina", "Aspect of the Beast" }

-- Answers two open questions about identifying spells without English text: does the trainer give a spell ID
-- (directly, or through an item link), and can a talent be tied to a spell ID. Reports what the client returns
-- for the first trainer row and the first talent so the shape is on record. Row shape on Forever is UNVERIFIED.
function Probe.SpellIdentity(env)
  env = env or _G
  local lines = {}
  local function shape(path, ...)
    local first, err, vals = firstValue(env, path, ...)
    if first == nil and err then return nil, err end
    local parts = {}
    for i = 1, math.max(#vals, 1) do parts[#parts + 1] = describe(env, vals[i]) end
    return vals, table.concat(parts, ", ")
  end
  local count = firstValue(env, "GetNumTrainerServices")
  if type(count) == "number" and count > 0 then
    local vals, text = shape("GetTrainerServiceInfo", 1)
    lines[#lines + 1] = "  GetTrainerServiceInfo(1) -> " .. tostring(text)
    local numeric
    for i, v in ipairs(vals or {}) do if type(v) == "number" and v > 100 then numeric = i end end
    lines[#lines + 1] = numeric and ("  value %d looks like an ID"):format(numeric) or "  no ID-like value in the row"
    for _, path in ipairs({ "GetTrainerServiceItemLink", "GetTrainerServiceSpellID", "C_TrainerUI.GetTrainerServiceInfo" }) do
      local _, t = shape(path, 1)
      lines[#lines + 1] = ("  %s(1) -> %s"):format(path, tostring(t))
    end
  else
    lines[#lines + 1] = "  open a trainer and run the report again for the trainer row shape"
  end
  local _, talent = shape("GetTalentInfo", 1, 1)
  lines[#lines + 1] = "  GetTalentInfo(1, 1) -> " .. tostring(talent)
  for _, path in ipairs({ "GetTalentLink", "C_SpellBook.GetSpellInfo" }) do
    local _, t = shape(path, 1, 1)
    lines[#lines + 1] = ("  %s(1, 1) -> %s"):format(path, tostring(t))
  end
  return lines
end

-- Can the addon see a spell ID for a trainer row? Tries every way known to give one on an open trainer window and
-- prints what each returns, so the answer comes from the real client. Read-only. Run through /ddt trainerids with
-- the trainer open; the rows from the first few services are checked, and the line "RESULT" names what worked.
local TRAINER_ID_CALLS = {
  "GetTrainerServiceItemLink", "GetTrainerServiceSpellID", "GetTrainerServiceSkillLine", "GetTrainerServiceSpell",
  "GetTrainerServiceSkillReq", "C_TrainerUI.GetTrainerServiceInfo", "C_Trainer.GetTrainerServiceInfo",
  "C_Trainer.GetServiceInfo",
}

local function listValues(env, vals, n)
  local parts = {}
  for i = 1, math.max(n or 0, #vals, 1) do parts[#parts + 1] = describe(env, vals[i]) end
  return table.concat(parts, ", ")
end

local function spellName(env, id)
  local f = resolve(env, "GetSpellInfo")
  if type(f) ~= "function" then return nil end
  local ok, name = pcall(f, id)
  return ok and type(name) == "string" and name or nil
end

-- Numbers in a list of values that name the row's spell, according to GetSpellInfo.
local function matchingId(env, vals, rowName)
  for i, v in ipairs(vals) do
    if type(v) == "number" and v > 100 and spellName(env, v) == rowName then return v, i end
  end
end

-- The other places the addon relies on a spell or talent ID, checked against the real client: talent hyperlinks,
-- the riding spells, the profession apprentice spells, and which trainer window is open.
function Probe.IdentityChecks(env)
  env = env or _G
  local lines = { "== identity checks ==" }
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
  local class = ns.Adapter and ns.Adapter.ReadPlayer(env).class

  -- Talents: does GetTalentLink exist, carry a talent ID the generated table knows, and resolve to a spell family?
  local tabs = firstValue(env, "GetNumTalentTabs")
  if type(tabs) ~= "number" then
    add("talents: GetNumTalentTabs gave %s", tostring(tabs))
  elseif type(resolve(env, "GetTalentLink")) ~= "function" then
    add("talents: GetTalentLink is MISSING, so talents are read by name")
  else
    local total, ranked, linked, known, resolved = 0, 0, 0, 0, 0
    local examples = {}
    for tab = 1, tabs do
      local n = firstValue(env, "GetNumTalents", tab)
      for i = 1, type(n) == "number" and n or 0 do
        total = total + 1
        local rank = safeCall(env, resolve(env, "GetTalentInfo") or function() end, tab, i).values[5]
        if type(rank) == "number" and rank > 0 then ranked = ranked + 1 end
        local link = firstValue(env, "GetTalentLink", tab, i)
        local id = type(link) == "string" and tonumber(link:match("Htalent:(%d+)")) or nil
        if id then
          linked = linked + 1
          local spells = ns.TalentSpells and ns.TalentSpells[id]
          if spells then known = known + 1 end
          local family = spells and class and ns.SpellData and ns.SpellData.FamilyOfId(class, spells[1])
          if family then resolved = resolved + 1 end
          if #examples < 3 then
            examples[#examples + 1] = ("  tab %d talent %d: link %s -> talent %d -> spells %s -> family %s"):format(
              tab, i, tostring(link):gsub("|", "||"), id, spells and table.concat(spells, "/") or "unknown",
              family and tostring(ns.SpellData.FamilyName(class, family)) or "none")
          end
        end
      end
    end
    add("talents: %d total, %d with points; %d links carried a talent ID, %d known to the table, %d resolve to a spell family",
      total, ranked, linked, known, resolved)
    for _, l in ipairs(examples) do lines[#lines + 1] = l end
  end

  -- Riding: the IDs the addon watches, what the client calls them, and what it says about the spellbook.
  local known = ns.Adapter and ns.Adapter.IsSpellKnown
  for _, id in ipairs({ 33388, 33389, 33391, 33392, 824, 825, 826, 828, 10861, 18995, 10906, 10907, 13819, 1279399, 5784, 23214, 23161 }) do
    add("riding spell %d: client name %s, known %s", id, tostring(spellName(env, id)),
      tostring(known and known(env, id)))
  end
  -- Era's riding skill lines: the rank is how level 60 riding shows.
  local skills = {}
  local nLines = firstValue(env, "GetNumSkillLines")
  for i = 1, type(nLines) == "number" and nLines or 0 do
    local r = safeCall(env, resolve(env, "GetSkillLineInfo") or function() end, i)
    local sname, header, rank, maxRank = r.values[1], r.values[2], r.values[4], r.values[7]
    if type(sname) == "string" and not header then
      for id, english in pairs(ns.Adapter and ns.Adapter.EraRidingSkills or {}) do
        if sname == english or sname == spellName(env, id) then
          skills[#skills + 1] = ("riding skill line %q (racial spell %d): rank %s / max %s"):format(sname, id, tostring(rank), tostring(maxRank))
        end
      end
    end
  end
  table.sort(skills)
  if #skills == 0 then skills[1] = "no racial riding skill line found in the skill list" end
  for _, l in ipairs(skills) do lines[#lines + 1] = l end
  add("ReadRiding says: %s", ns.Adapter and (function() local r = ns.Adapter.ReadRiding(env); return ("apprentice %s, journeyman %s"):format(tostring(r.apprentice), tostring(r.journeyman)) end)() or "adapter missing")
  for _, name in ipairs({ "Apprentice Riding", "Journeyman Riding" }) do
    local r = safeCall(env, resolve(env, "GetSpellInfo") or function() end, name)
    add("GetSpellInfo(%q) -> %s", name, r.ok and listValues(env, r.values, r.n) or "ERROR")
  end

  -- Professions: the apprentice spell the addon expects for each.
  if ns.Rules and ns.Rules.ProfessionNames then
    local ids = {}
    for id in pairs(ns.Rules.ProfessionNames()) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      add("profession %d (%s): client name %s, known %s", id, ns.Rules.ProfessionNames()[id], tostring(spellName(env, id)),
        tostring(known and known(env, id)))
    end
  end

  -- Which trainer window is open (the pet trainer may use the craft window).
  for _, frame in ipairs({ "ClassTrainerFrame", "CraftFrame", "TradeSkillFrame" }) do
    local f = env[frame]
    local shown = type(f) == "table" and type(f.IsShown) == "function" and select(2, pcall(f.IsShown, f))
    add("%s: %s", frame, type(f) == "table" and ("exists, " .. (shown and "SHOWN" or "hidden")) or "missing")
  end
  local crafts = firstValue(env, "GetNumCrafts")
  if type(crafts) == "number" and crafts > 0 then
    local tip = env.DontDoThatProbeTip
    for i = 1, math.min(crafts, 3) do
      local r = safeCall(env, resolve(env, "GetCraftInfo"), i)
      local line = ("craft %d: GetCraftInfo -> %s"):format(i, listValues(env, r.values, r.n))
      if tip and type(tip.SetCraftSpell) == "function" and pcall(tip.SetOwner, tip, env.UIParent, "ANCHOR_NONE")
        and pcall(tip.SetCraftSpell, tip, i) then
        local g = safeCall(env, tip.GetSpell, tip)
        line = line .. ("; tooltip:GetSpell -> %s"):format(listValues(env, g.values, g.n))
        pcall(tip.Hide, tip)
      end
      lines[#lines + 1] = line
    end
  end
  return lines
end

function Probe.TrainerIds(env, opts)
  env = env or _G
  opts = opts or {}
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
  local count = firstValue(env, "GetNumTrainerServices")
  if type(count) ~= "number" or count == 0 then
    return "open a trainer window first, then run this again (GetNumTrainerServices gave " .. tostring(count) .. ")"
      .. "\n\n" .. table.concat(Probe.IdentityChecks(env), "\n")
  end

  local tip
  if type(env.CreateFrame) == "function" then
    if type(env.DontDoThatProbeTip) == "table" then
      tip = env.DontDoThatProbeTip
    else
      local ok, frame = pcall(env.CreateFrame, "GameTooltip", "DontDoThatProbeTip", env.UIParent, "GameTooltipTemplate")
      if ok and frame then tip = frame end
    end
  end
  add("trainer services: %d; private tooltip: %s; C_TooltipInfo: %s", count, tip and "created" or "NOT available",
    type(resolve(env, "C_TooltipInfo.GetTrainerService")) == "function" and "has GetTrainerService" or "no GetTrainerService")

  local worked, rows = {}, 0
  for i = 1, count do
    local name, _, vals = firstValue(env, "GetTrainerServiceInfo", i)
    if name ~= nil and vals[3] ~= "header" and rows < (opts.rows or 8) then
      rows = rows + 1
      local res = safeCall(env, resolve(env, "GetTrainerServiceInfo"), i)
      add("")
      add("row %d: %s", i, listValues(env, res.values, res.n))
      local id, at = matchingId(env, res.values, name)
      if id then add("  GetTrainerServiceInfo value %d = %d MATCHES the row", at, id); worked["GetTrainerServiceInfo"] = true end

      for _, path in ipairs(TRAINER_ID_CALLS) do
        local f = resolve(env, path)
        if type(f) == "function" then
          local r = safeCall(env, f, i)
          add("  %s(%d) -> %s", path, i, r.ok and listValues(env, r.values, r.n) or ("ERROR " .. tostring(r.err)))
          local link = r.ok and r.values[1]
          local fromLink = type(link) == "string" and tonumber(link:match("[Hh]%a+:(%d+)"))
          local hit = matchingId(env, r.values, name) or (fromLink and spellName(env, fromLink) == name and fromLink)
          if hit then add("    %s gives %d and it MATCHES the row", path, hit); worked[path] = true end
        end
      end

      if tip then
        pcall(tip.SetOwner, tip, env.UIParent, "ANCHOR_NONE")
        local okSet, errSet = pcall(tip.SetTrainerService, tip, i)
        if not okSet then
          add("  tooltip:SetTrainerService(%d) -> ERROR %s", i, tostring(errSet))
        else
          for _, method in ipairs({ "GetSpell", "GetItem" }) do
            if type(tip[method]) == "function" then
              local r = safeCall(env, tip[method], tip)
              add("  tooltip:%s() -> %s", method, r.ok and listValues(env, r.values, r.n) or ("ERROR " .. tostring(r.err)))
              local hit = matchingId(env, r.values, name)
              if hit then add("    tooltip:%s gives %d and it MATCHES the row", method, hit); worked["tooltip:" .. method] = true end
            else
              add("  tooltip:%s is missing", method)
            end
          end
          local title = env.DontDoThatProbeTipTextLeft1
          if type(title) == "table" and type(title.GetText) == "function" then
            local okT, text = pcall(title.GetText, title)
            add("  tooltip first line -> %s", okT and tostring(text) or "ERROR")
          end
        end
        pcall(tip.Hide, tip)
      end

      local info = resolve(env, "C_TooltipInfo.GetTrainerService")
      if type(info) == "function" then
        local r = safeCall(env, info, i)
        local data = r.ok and r.values[1]
        if type(data) == "table" then
          local keys = {}
          for k, v in pairs(data) do if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end end
          table.sort(keys)
          add("  C_TooltipInfo.GetTrainerService(%d) -> %s", i, table.concat(keys, " "))
          for _, key in ipairs({ "id", "spellID", "spellId" }) do
            if type(data[key]) == "number" and spellName(env, data[key]) == name then
              add("    C_TooltipInfo field %s = %d MATCHES the row", key, data[key]); worked["C_TooltipInfo." .. key] = true
            end
          end
        else
          add("  C_TooltipInfo.GetTrainerService(%d) -> %s", i, r.ok and tostring(data) or ("ERROR " .. tostring(r.err)))
        end
      end
    end
  end

  -- The row buttons are real frames: any field on one that holds the spell ID would also do.
  local button = env.ClassTrainerSkill1
  if type(button) == "table" then
    local keys = {}
    local okPairs = pcall(function()
      for k, v in pairs(button) do
        if type(v) == "number" or type(v) == "string" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
      end
    end)
    table.sort(keys)
    add("")
    add("ClassTrainerSkill1 plain fields: %s", okPairs and (#keys > 0 and table.concat(keys, " ") or "none") or "unreadable")
  end

  add("")
  for _, l in ipairs(Probe.IdentityChecks(env)) do lines[#lines + 1] = l end

  add("")
  local names = {}
  for k in pairs(worked) do names[#names + 1] = k end
  table.sort(names)
  if #names > 0 then
    add("RESULT: a spell ID that matches the row is available through: %s", table.concat(names, ", "))
  else
    add("RESULT: no method gave an ID that matches the row's spell")
  end
  return table.concat(lines, "\n")
end

-- What the game's own tooltip holds for whatever the mouse is over: hover a trainer row during the countdown.
function Probe.HoveredSpell(env)
  env = env or _G
  local tip = env.GameTooltip
  if type(tip) ~= "table" then return "GameTooltip is not available" end
  local out = {}
  for _, method in ipairs({ "GetSpell", "GetItem", "GetUnit" }) do
    if type(tip[method]) == "function" then
      local r = safeCall(env, tip[method], tip)
      out[#out + 1] = ("GameTooltip:%s() -> %s"):format(method, r.ok and listValues(env, r.values, r.n) or ("ERROR " .. tostring(r.err)))
    end
  end
  local owner = safeCall(env, tip.GetOwner or function() end, tip)
  local o = owner.ok and owner.values[1]
  out[#out + 1] = "tooltip owner: " .. (type(o) == "table" and type(o.GetName) == "function" and tostring(o:GetName()) or "none")
  return table.concat(out, "\n")
end

function Probe.SpellDataCheck(env)
  env = env or _G
  if not (ns.SpellData and ns.SpellTables and ns.Adapter) then return { "  spell data not loaded" } end
  local class = ns.Adapter.ReadPlayer(env).class
  local rows = ns.SpellData.Rows(class or "")
  local lines = { ("  bundled spell tables: build %s, %d spells for %s"):format(
    tostring(ns.SpellTables.build), #rows, tostring(class)) }
  local known, unknown, answered = 0, 0, false
  for _, row in ipairs(rows) do
    local any
    for _, id in ipairs(ns.SpellData.Ids(row)) do
      local k = ns.Adapter.IsSpellKnown(env, id)
      if k ~= nil then answered = true end
      if k then any = true end
    end
    if any then known = known + 1 else unknown = unknown + 1 end
  end
  lines[#lines + 1] = answered and ("  spellbook says %d known, %d not known"):format(known, unknown)
    or "  the client did not answer IsSpellKnown for any bundled ID"
  for _, name in ipairs(SAMPLE_SPELLS) do
    local row = ns.SpellData.Rank(class or "", name, 2) or ns.SpellData.Rank(class or "", name, 1)
      or ns.SpellData.Rank(class or "", name, nil)
    if row then
      local ids = ns.SpellData.Ids(row)
      local flags = {}
      for _, id in ipairs(ids) do flags[#flags + 1] = ("%d=%s"):format(id, tostring(ns.Adapter.IsSpellKnown(env, id))) end
      lines[#lines + 1] = ("  %s%s level %s: known [%s], icon %s"):format(name, row.rank and (" rank " .. row.rank) or "",
        tostring(row.level), table.concat(flags, " "), tostring((ns.SpellData.IconFor(row.id, env))))
    else
      lines[#lines + 1] = ("  %s: not in the bundled tables"):format(name)
    end
  end
  return lines
end

function Probe.ServiceLines(services)
  local lines = {}
  for _, s in ipairs(services) do
    if s.error then
      lines[#lines + 1] = ("  #%d error: %s"):format(s.index, s.error)
    else
      lines[#lines + 1] = ("  #%d %s rank=%s level=%s cost=%s status=%s"):format(
        s.index, tostring(s.name), tostring(s.rank), tostring(s.level), money(s.cost), tostring(s.status))
    end
  end
  return lines
end

function Probe.Run(env, saved)
  env = env or _G
  local out = {}
  local function section(title, lines)
    out[#out + 1] = title
    for _, l in ipairs(lines) do out[#out + 1] = l end
  end
  -- Each section is isolated so a bug in one cannot abort the report.
  local function guarded(title, fn)
    local ok, lines = pcall(fn)
    section(title, ok and lines or { "  FAILED: " .. tostring(lines) })
  end

  guarded("Build", function() return Probe.BuildInfo(env) end)
  guarded("API existence", function() return Probe.Existence(env) end)
  guarded("Call results", function() return Probe.CallResults(env) end)
  guarded("Globals matching", function()
    return Probe.GlobalsMatching(env, { "ClassTrainerSkill", "ClassTrainerFrame_", "TrainerService", "TrainerSkill",
      "PreviewTalent", "Wipe", "Unlearn", "Untrain", "TrainerFrameFilter", "FilterDropDown", "PlayerTalentFrame" }, 100)
  end)
  guarded("Trainer snapshot", function()
    local snap = Probe.TrainerSnapshot(env)
    if not snap.ok then return { "  unavailable: " .. snap.reason } end
    pcall(Probe.RecordRankSkips, snap, saved)
    local lines = { ("  %d services"):format(#snap.services) }
    for _, l in ipairs(Probe.ServiceLines(snap.services)) do lines[#lines + 1] = l end
    return lines
  end)
  guarded("Talent points", function()
    local tp = Probe.TalentPoints(env)
    if not tp.ok then return { "  unavailable: " .. tp.reason } end
    local lines = {}
    for _, t in ipairs(tp.trees) do
      lines[#lines + 1] = t.error and ("  tree %d error: %s"):format(t.index, t.error)
        or ("  tree %d %s: %s points"):format(t.index, tostring(t.name), tostring(t.points))
    end
    return lines
  end)
  guarded("Talent traits", function() return Probe.TraitTalents(env) end)
  guarded("Popups", function() return Probe.Popups(env) end)
  guarded("Skill lines", function() return Probe.SkillLines(env) end)
  guarded("Spell identity", function() return Probe.SpellIdentity(env) end)
  guarded("Spell data check", function() return Probe.SpellDataCheck(env) end)
  guarded("Observations", function() return Probe.ObservationLines(saved) end)
  if ns.Capture then
    guarded("Frames", function() return ns.Capture.FrameReport(env) end)
    guarded("Captured while debug was on", function() return ns.Capture.Lines(saved) end)
  end
  return table.concat(out, "\n")
end
