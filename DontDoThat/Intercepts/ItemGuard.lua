local addonName, ns = ...
local L = ns.L

-- The shared flow for vendor and auction purchases: classify the item, decide if it is flagged, then alert,
-- ask, and either run `proceed` (the real purchase) or drop it. Anything unexpected lets the purchase through,
-- so the player is never stopped from buying by a fault in here. If the client reports a forbidden action,
-- the question switches off for the session and purchases go ahead with the warning sound and banner only.
local Guard = {}
ns.ItemGuard = Guard

local disabledReason
local trace -- defined below

function Guard.Reset() disabledReason = nil end
function Guard.DisabledReason() return disabledReason end

function Guard.Disable(reason)
  if disabledReason then return end
  disabledReason = reason
  pcall(trace, { surface = "-", outcome = "prompts switched off: " .. tostring(reason) })
  if ns.Log then ns.Log.Add("items: prompts switched off for the session (%s)", tostring(reason)) end
  if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
      L["Don't Do That: this game version won't let it confirm item purchases, so it will only warn you."])
  end
end

function Guard.Watch(eventTarget)
  for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(eventTarget.RegisterEvent, eventTarget, event, function(_, who, func)
      if who == addonName and (func == "BuyMerchantItem" or func == "PlaceAuctionBid") then
        Guard.Disable("blocked: " .. tostring(func))
      end
    end)
  end
end

local function profile() return (ns.db and ns.db.profile) or {} end

local function ledgerState() return ns.db and ns.db.char and ns.db.char.ledger end

local TRACE_MAX = 40

-- A saved record of every guarded purchase and what was decided, so a later /ddt export shows what happened.
-- Only kept when the "Record item purchases" setting is on. Newest last.
trace = function(entry)
  entry.t = type(_G.time) == "function" and _G.time() or nil
  local store = ns.db and ns.db.global
  if store and profile().traceItems then
    store.itemTrace = store.itemTrace or {}
    table.insert(store.itemTrace, entry)
    while #store.itemTrace > TRACE_MAX do table.remove(store.itemTrace, 1) end
  end
  if ns.Log then
    ns.Log.Add("items: %s %s total=%s category=%s -> %s", tostring(entry.surface), tostring(entry.name),
      tostring(entry.total), tostring(entry.category), tostring(entry.outcome))
  end
  return entry
end
Guard.Trace = trace

-- Items some classes are warned about by family: a Warlock's demon grimoires, for example. The class's rule data
-- lists the item families to keep; every other grimoire is flagged at a vendor. An item is recognised by the item
-- ID in its link ("|Hitem:1224:..."), which Data/RuleItems.lua maps to a family, so the item's name never matters.
local function itemId(link)
  return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

local function classGrimoires()
  local player = ns.Adapter and ns.Adapter.ReadPlayer and ns.Adapter.ReadPlayer(_G)
  local data = player and player.class and ns.Rules and ns.Rules.GetClass(player.class)
  return data and data.grimoires
end

-- The grimoire family named by the link, when this class flags grimoires and this one is not kept.
local function flaggedGrimoire(link)
  local rule = classGrimoires()
  local id = rule and itemId(link)
  local player = rule and ns.Adapter.ReadPlayer(_G)
  local family = id and player and ns.RuleItems and ns.RuleItems[player.class] and ns.RuleItems[player.class][id]
  if not family then return nil end
  for _, kept in ipairs(rule.keep or {}) do
    if kept == family then return nil end
  end
  return family, rule.reason
end

-- The Forever client moved GetItemInfoInstant into C_Item; both return the same values.
local function instantInfo(env)
  if type(env.GetItemInfoInstant) == "function" then return env.GetItemInfoInstant end
  local c = env.C_Item
  if type(c) == "table" and type(c.GetItemInfoInstant) == "function" then return c.GetItemInfoInstant end
end

-- Everything known about one purchase: its item numbers, category, mode, and whether it is flagged (and if
-- not, why not).
function Guard.Inspect(surface, link, total)
  local p = profile()
  local info = { surface = surface, total = total, minPrice = p.minPrice }
  if p.enabled == false then info.why = "addon off"; return info end
  if p.watch and p.watch.shopping == false then info.why = "Shopping is off"; return info end
  if surface == "vendor" then
    local family, reason = flaggedGrimoire(link)
    if family then
      info.category, info.reason, info.mode = "grimoires", reason, L["class rule"]
      if total >= (p.minPrice or 0) then info.flagged = true else info.why = "below minimum price" end
      return info
    end
  end
  local instant = instantInfo(_G)
  if not instant or not link then info.why = "no item info"; return info end
  local _, _, _, equipLoc, _, classID, subClassID = instant(link)
  if not classID then info.why = "item not cached"; return info end
  info.classID, info.subClassID, info.equipLoc = classID, subClassID, equipLoc
  info.category = ns.ItemCategory.Classify({ classID = classID, subClassID = subClassID, equipLoc = equipLoc })
  info.mode = p.itemModes and p.itemModes[info.category] or "off"
  if ns.ItemWarning.Flagged(p.itemModes, info.category, surface, total, p.minPrice) then
    info.flagged = true
  elseif total < (p.minPrice or 0) then
    info.why = "below minimum price"
  else
    info.why = "mode " .. info.mode .. " does not cover " .. surface
  end
  return info
end

-- The category when this purchase should be warned about, else nil.
function Guard.Flag(surface, link, total)
  local info = Guard.Inspect(surface, link, total)
  return info.flagged and info.category or nil
end

local function alertSettings()
  local p = profile()
  local a = p.alert or {}
  return { alertsEnabled = p.alerts ~= false, alertBanner = a.banner ~= false,
    alertSound = a.sound, alertCooldown = a.cooldown }
end

local function record(info, name, outcome)
  return trace({ surface = info.surface, name = name, total = info.total, classID = info.classID,
    subClassID = info.subClassID, equipLoc = info.equipLoc, category = info.category, mode = info.mode,
    minPrice = info.minPrice, why = info.why, outcome = outcome })
end

-- surface: "vendor" | "ah". name: item name. link: item link. total: copper. proceed(): the real purchase.
function Guard.Run(surface, name, link, total, proceed)
  local okInfo, info = pcall(Guard.Inspect, surface, link, total)
  if not okInfo then
    trace({ surface = surface, name = name, total = total, outcome = "passed through: decision failed: " .. tostring(info) })
    return proceed()
  end
  if not info.flagged then
    record(info, name, "passed through: " .. tostring(info.why))
    return proceed()
  end

  local category = info.category
  local verdict = { tier = "defer", name = name or L["This item"], cost = total,
    reason = info.reason or ns.ItemWarning.Reason(category) }
  local key = surface .. ":" .. tostring(name)
  local settings = alertSettings()
  local asking = not disabledReason and profile().blockingConfirmations ~= false
  local entry = record(info, name, "flagged")

  if not asking then
    local fired = false
    pcall(function() fired = ns.Alert.Trigger(verdict, key, settings) end)
    entry.outcome = "alert only (" .. (disabledReason and ("prompts off: " .. tostring(disabledReason)) or "Ask before buying is off")
      .. "), alert " .. (fired and "played" or "not played") .. ", bought"
    return proceed()
  end

  -- The question says everything the banner would, so it gets the sound alone.
  local soundOnly = {}
  for k, v in pairs(settings) do soundOnly[k] = v end
  soundOnly.alertBanner = false
  pcall(ns.Alert.Trigger, verdict, key, soundOnly)

  local shown = false
  pcall(function()
    shown = ns.ConfirmPopup.Ask(verdict,
      function()
        entry.outcome = "question shown, accepted, bought"
        local state = ledgerState()
        if state then ns.Ledger.RecordItemPerformed(state, total) end
        proceed()
      end,
      function()
        entry.outcome = "question shown, declined, not bought"
        local state = ledgerState()
        if state then ns.Ledger.RecordItemAvoided(state, total) end
      end)
  end)
  if shown then
    entry.outcome = "question shown, waiting for an answer"
    return
  end
  entry.outcome = "question could not be shown, bought with banner"
  if settings.alertBanner and settings.alertsEnabled and ns.AlertBanner then
    pcall(ns.AlertBanner.Show, verdict, verdict.name)
  end
  return proceed()
end

-- What /ddt export shows for item warnings.
function Guard.Report(env)
  env = env or _G
  local p = profile()
  local rate = ns.EarnBack and type(env.UnitLevel) == "function" and ns.EarnBack.Rate(env.UnitLevel("player"))
  local buildInfo = type(env.GetBuildInfo) == "function" and { env.GetBuildInfo() } or {}
  local report = {
    client = ("%s (build %s, interface %s)"):format(tostring(buildInfo[1]), tostring(buildInfo[2]), tostring(buildInfo[4])),
    promptsSwitchedOffBy = disabledReason or "no",
    GetItemInfoInstant = instantInfo(env) and "available" or "MISSING",
    vendor = ns.Merchant and ns.Merchant.Status(env) or "module missing",
    auction = ns.Auction and ns.Auction.Status(env) or "module missing",
    guardedDialogs = ns.Resets and ns.Resets.Status() or "module missing",
    minPrice = ns.UIHelpers.FormatMoney(p.minPrice or 0),
    modes = p.itemModes,
    earnBackRateCopperPerHour = rate or "unknown",
    recentPurchases = (ns.db and ns.db.global and ns.db.global.itemTrace) or {},
  }
  return report
end

-- A tooltip line for a flagged item, used where a prompt is not possible and as a heads-up beforehand.
function Guard.Tooltip(tooltip, surface, name, link, total)
  if profile().warnings == false then return end
  local ok, info = pcall(Guard.Inspect, surface, link, total)
  if not ok or not info.flagged then return end
  ns.TooltipAugment.Augment(tooltip, { tier = "defer", name = name, cost = total,
    reason = info.reason or ns.ItemWarning.Reason(info.category) })
end
