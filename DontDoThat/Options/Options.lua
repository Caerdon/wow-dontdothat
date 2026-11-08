local addonName, ns = ...
local L = ns.L

-- Group titles the page sorts by, so a translation changes the text and not the order.
local ALL_SPECS, OTHER, PET = L["All specs"], L["Other"], L["Pet"]

-- The settings pages. Each page is built by a pure function that returns an AceConfig group, so the
-- content can be tested without the game. Wording is for players: no internal terms.
local Options = {}
ns.Options = Options

local APP = "DontDoThat"
local TITLE = "Don't Do That"

local function profile() return ns.db and ns.db.profile end

local function isOn(key)
  local p = profile()
  return p == nil or p[key] ~= false
end

-- A changed setting should show in an open trainer window straight away, not at its next refresh.
local function applyNow()
  if ns.TrainerFilter then
    pcall(ns.TrainerFilter.RebuildMenu, _G)
    pcall(ns.TrainerFilter.Refresh, _G)
  end
  if ns.TrainerOverlay and ns.TrainerOverlay.SafeRefresh then pcall(ns.TrainerOverlay.SafeRefresh, _G) end
end

-- One look for every page: a gold title and a one-line introduction, then sections (a ruled heading and
-- its items). Body text and notes share one size; notes are the one muted gray. Order numbers come from
-- the builder, so pages never space things with blank rows or hand-picked decimals.
local ACCENT = "|cffffd100"
local MUTED = "|cff9d9d9d"

local Page = {}
Page.__index = Page

-- The game's AddOns panel already prints a page's name as its heading, so a title that repeats the name is left
-- out there (set while the panel's pages are built). The /ddt tree window shows no heading of its own and keeps it.
local panelBuild = false

local function newPage(name, order, title, intro)
  local page = setmetatable({ args = {}, n = 0, name = name, order = order }, Page)
  if not (panelBuild and title == name) then page:add("title", { type = "description", fontSize = "large", width = "full", name = ACCENT .. title .. "|r" }) end
  if intro then page:text("intro", intro) end
  page.lead = page.n -- items before the first section: the title and introduction
  return page
end

function Page:add(key, widget)
  self.n = self.n + 1
  widget.order = self.n
  self.args[key] = widget
  return widget
end
-- A ruled heading, with a blank line above it once something precedes it.
function Page:section(key, name)
  if self.n > self.lead and self.lastGap ~= self.n then self:gap() end
  return self:add(key, { type = "header", name = name })
end
function Page:text(key, body) return self:add(key, { type = "description", fontSize = "medium", width = "full", name = body }) end
function Page:note(key, body) return self:text(key, MUTED .. body .. "|r") end
-- A blank line between items that would otherwise run together, and above each section heading.
function Page:gap()
  local gap = self:add("gap" .. self.n, { type = "description", fontSize = "medium", width = "full", name = " " })
  self.lastGap = self.n
  return gap
end

function Page:toggle(key, name, desc, get, set)
  -- inline: the explanation is shown under the checkbox, not only on hover.
  return self:add(key, { type = "toggle", width = "full", name = name, desc = desc, descStyle = "inline", get = get, set = set })
end

function Page:group(extra)
  local group = { type = "group", name = self.name, order = self.order, args = self.args }
  for k, v in pairs(extra or {}) do group[k] = v end
  return group
end

-- A toggle bound to a plain profile key; on unless saved as false.
local function profileToggle(page, key, name, desc, field)
  return page:toggle(key, name, desc,
    function() return isOn(field) end,
    function(_, value)
      local p = profile()
      if p then p[field] = value end
      applyNow()
    end)
end

local function money(copper)
  return ns.UIHelpers and ns.UIHelpers.FormatMoney(copper) or tostring(copper)
end

local PRICE_NOTE = L["Prices: from your trainers, else Wowhead's lists, else an estimate."]

-- Whole gold, in gold: "226g", or the exact amount below 1g. For totals where silver and copper are noise.
local function bigMoney(copper)
  if type(copper) ~= "number" then return " " end
  if copper < 10000 then return "|cffffd100" .. (money(copper) or "0c") .. "|r" end
  return ("|cffffd100%sg|r"):format((tostring(math.floor(copper / 10000)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")))
end

-- One bulleted figure: a coloured label, then its amount.
local function figure(label, hex, amountText)
  return ("\226\128\162 |cff%s%s|r   %s"):format(hex, label, amountText)
end

-- What a switch is worth in gold: the savings with it on minus with it off, up to the stop-after mount, for
-- the player's character, or for another class built from its settings. nil when it can't be worked out.
local worthMemo, worthCount = {}, 0

-- A redraw asks the same question many times; answers are reused for a quarter of a second. Without a clock, never reused.
local recentAnswers = {}
local function recent(key, compute)
  local now = type(_G.GetTime) == "function" and _G.GetTime() or nil
  local held = recentAnswers[key]
  if now and held and now - held.at < 0.25 then return held.value end
  local value = compute()
  recentAnswers[key] = { at = now or -1, value = value }
  return value
end

local function savingsProfile(classKey)
  local ok, p = pcall(function() return recent("profile", function() return ns.Context and ns.Context.Profile(_G) end) end)
  if ok and p and (classKey == nil or p.class == classKey) then return p end
  if not classKey or not ns.Settings or not ns.Rules then return nil end
  local data = ns.Rules.GetClass(classKey)
  if not data then return nil end
  local pick = ns.Settings.SpecOverride(classKey, data)
  return { class = classKey, plausibleSpecs = pick and { pick } or nil, rules = ns.Settings.RulesFor(classKey) }
end

-- Everything that can change a worth: the rules, the specs, the talents and the prices seen so far.
local function ruleSignature(p, stop)
  local parts = { p.class, stop, table.concat(p.plausibleSpecs or {}, ",") }
  local talents, seenPrices = {}, 0
  for id, active in pairs(p.activeTalents or {}) do if active then talents[#talents + 1] = tostring(id) end end
  table.sort(talents)
  parts[#parts + 1] = table.concat(talents, ",")
  for _ in pairs(ns.db and ns.db.char and ns.db.char.costCache or {}) do seenPrices = seenPrices + 1 end
  parts[#parts + 1] = seenPrices
  for _, bucket in ipairs({ "offAbilities", "offTags", "offKinds" }) do
    local names = {}
    for name in pairs(p.rules and p.rules[bucket] or {}) do names[#names + 1] = tostring(name) end
    table.sort(names)
    parts[#parts + 1] = table.concat(names, ",")
  end
  return table.concat(parts, "|")
end

local function worthLine(copper)
  if copper == nil then return nil end
  if copper <= 0 then return MUTED .. L["Worth nothing for your spec right now."] .. "|r" end
  return MUTED .. L["Worth about %s by your level %d mount."]:format("|r" .. bigMoney(copper) .. MUTED, ns.Settings and ns.Settings.StopAfter() or 60) .. "|r"
end

-- classKey nil means the player's own class. bucket is offKinds, offTags or offAbilities.
local function switchWorth(classKey, bucket, name)
  if not ns.Savings then return nil end
  local p = savingsProfile(classKey)
  if not p then return nil end
  local stop = ns.Settings and ns.Settings.StopAfter() or 60
  local cache = ns.db and ns.db.char and ns.db.char.costCache
  local sig = ruleSignature(p, stop)
  local key = sig .. "#" .. bucket .. "#" .. tostring(name)
  if worthMemo[key] == nil then
    if worthCount > 500 then worthMemo, worthCount = {}, 0 end
    worthCount = worthCount + 1
    local value
    if bucket == "offAbilities" then
      worthMemo["abilities#" .. sig] = worthMemo["abilities#" .. sig] or ns.Savings.ByAbility(p, stop, cache)
      value = worthMemo["abilities#" .. sig][name] or 0
    else
      value = ns.Savings.Worth(p, stop, cache, bucket, name)
    end
    worthMemo[key] = value
  end
  return worthMemo[key]
end

-- A switch's explanation with its gold value beneath it.
local function withWorth(text, classKey, bucket, name)
  return function()
    local line = worthLine(switchWorth(classKey, bucket, name))
    if not line then return text end
    return text and (text .. "\n" .. line) or line
  end
end

local function titleCase(word)
  return (tostring(word):lower():gsub("^%l", string.upper))
end

-- Where the player's switches are kept. Created on first write, so a missing database is just "all on".
local function ruleOff(bucket, create)
  local p = profile()
  if not p then return {} end
  if create then
    p.ruleOff = p.ruleOff or {}
    p.ruleOff[bucket] = p.ruleOff[bucket] or {}
  end
  return p.ruleOff and p.ruleOff[bucket] or {}
end

local function isOff(bucket, class, name)
  local per = ruleOff(bucket)[class]
  return per ~= nil and per[name] == true
end

local function setOff(bucket, class, name, off)
  local all = ruleOff(bucket, true)
  all[class] = all[class] or {}
  all[class][name] = off or nil
end

local function kindOff(kind) return ruleOff("kinds")[kind] == true end
local function setKindOff(kind, off) ruleOff("kinds", true)[kind] = off or nil end

local RULE_KINDS = {
  { key = "skipRank", name = L["Skip ranks that are a small upgrade"], desc = L["Marks a rank that is barely better than the one before it."] },
  { key = "offSpec", name = L["Mark spells for the specs you don't play"], desc = L["Marks spells that suit another talent build, based on where your points are."] },
}

---------------------------------------------------------------------------
-- Home and Tuning

-- The tuning values live under profile.tuning; created on first write.
local function tuning(create)
  local p = profile()
  if not p then return {} end
  if create and not p.tuning then p.tuning = {} end
  return p.tuning or {}
end

local TIER_CHOICES = {
  { key = "defer", name = L["Save your gold"], desc = L["Things you won't need until later. This is what the addon always warned about."] },
  { key = "deferLow", name = L["Not worth buying yet"], desc = L["Low-value spells. Marked, but they don't get in your way unless you tick this."] },
  { key = "info", name = L["Optional"], desc = L["Handy now and then, but you can get by without them."] },
}

local function promptTiers()
  if ns.Settings then return ns.Settings.PromptTiers() end
  return { defer = true, deferLow = false, info = false }
end

local MUTED_TEXT = "|cff9d9d9d"
local NAME_TEXT = "|cffffd100"

-- A level's name in gold, then what it does in gray, on one line.
local function levelLabel(name, detail)
  return NAME_TEXT .. name .. "|r  " .. MUTED_TEXT .. detail .. "|r"
end

local NUDGE_LEVELS = {
  mark = levelLabel(L["Mark it, but let me buy"], L["Shows an (i) and never asks."]),
  ask = levelLabel(L["Ask me first"], L["Also asks \"Buy anyway?\" before you buy."]),
  everything = levelLabel(L["Ask me about everything"], L["Also asks about low-value and optional things."]),
}

-- "Marks are on. It asks about Save your gold and Optional." for the saved values behind a Custom choice.
function Options.CustomDetail()
  local parts = { isOn("warnings") and L["Marks are on."] or L["Marks are off."] }
  if not isOn("blockingConfirmations") then
    parts[#parts + 1] = L["It never asks."]
  else
    local asked = {}
    local tiers = promptTiers()
    for _, info in ipairs(TIER_CHOICES) do
      if tiers[info.key] then asked[#asked + 1] = info.name end
    end
    if #asked == 0 then parts[#parts + 1] = L["It asks about nothing."]
    else parts[#parts + 1] = L["It asks about %s."]:format((table.concat(asked, ", "):gsub(", ([^,]*)$", " " .. L["and"] .. " %1"))) end
  end
  return table.concat(parts, " ")
end

local function isCustom() return ns.Settings and ns.Settings.Nudge() == "custom" end

function Options.Home()
  local off = function() return not isOn("enabled") end
  local page = newPage(L["Home"], 1, L["Don't Do That"],
    L["Keeps you from spending gold on things you don't need yet, so you can afford your level 40 and level 60 mounts."])

  profileToggle(page, "enabled", L["Turn on Don't Do That"], L["Turn this off to pause all warnings."], "enabled")

  page:section("nudgeHeader", L["When you're about to buy something that can wait"])
  page:add("nudge", {
    type = "select", style = "radio", width = "full", name = "",
    values = function()
      local values = { mark = NUDGE_LEVELS.mark, ask = NUDGE_LEVELS.ask, everything = NUDGE_LEVELS.everything }
      if isCustom() then values.custom = levelLabel(L["Custom"], Options.CustomDetail()) end
      return values
    end,
    sorting = function()
      if isCustom() then return { "mark", "ask", "everything", "custom" } end
      return { "mark", "ask", "everything" }
    end,
    get = function() return ns.Settings and ns.Settings.Nudge() or "ask" end,
    set = function(_, value)
      if ns.Settings then ns.Settings.SetNudge(value) end
      applyNow()
    end,
  })
  page:add("customNote", { type = "description", fontSize = "medium", width = "full",
    hidden = function() return not isCustom() end,
    name = MUTED .. L["Pick a level above to set these again, or fine-tune them under Advanced > Tuning.|r"] })

  page:section("stopHeader", L["When to stop warning me"])
  page:add("stopAfter", {
    type = "select", width = "double", name = "",
    values = { [60] = L["After my level 60 mount"], [40] = L["After my level 40 mount"] }, sorting = { 60, 40 },
    get = function() return ns.Settings and ns.Settings.StopAfter() or 60 end,
    set = function(_, value) tuning(true).stopAfter = value; applyNow() end,
  })

  page:section("resetHeader", L["Start over"])
  page:add("resetAll", {
    type = "execute", name = L["Reset all settings"],
    desc = L["Puts every setting back to its default. Your tally and progress are kept."],
    confirm = true, confirmText = L["Put every setting back to its default? Your tally and progress are kept."],
    func = function()
      if ns.Settings then ns.Settings.ResetAll() end
      applyNow()
      local ok, registry = pcall(LibStub, "AceConfigRegistry-3.0")
      if ok and registry then pcall(registry.NotifyChange, registry, APP) end
    end,
  })

  page.args.nudge.disabled = off
  page.args.stopAfter.disabled = off
  return page:group()
end

function Options.Tuning()
  local off = function() return not isOn("enabled") end
  local page = newPage(L["Tuning"], 2, L["Tuning"], L["Fine-tune what counts as worth waiting on and what asks you first."])

  page:section("marksHeader", L["Marks and questions"])
  profileToggle(page, "warnings", L["Mark things to wait on"], L["Shows a colored (i) next to anything you can wait on. Hover it for the reason and the cost."], "warnings")
  profileToggle(page, "blocking", L["Ask before buying"], L["Asks \"Buy anyway?\" before you buy something you should wait on. You can always say yes."], "blockingConfirmations")

  page:section("countsHeader", L["What counts"])
  for _, kind in ipairs(RULE_KINDS) do
    page:toggle("kind_" .. kind.key, kind.name, withWorth(kind.desc, nil, "offKinds", kind.key),
      function() return not kindOff(kind.key) end,
      function(_, value) setKindOff(kind.key, not value); applyNow() end)
  end

  page:section("tiersHeader", L["Ask and warn about"])
  for _, info in ipairs(TIER_CHOICES) do
    page:toggle("tier_" .. info.key, info.name, info.desc,
      function() return promptTiers()[info.key] == true end,
      function(_, value)
        local t = tuning(true)
        t.promptTiers = t.promptTiers or {}
        t.promptTiers[info.key] = value
      end)
  end
  page:note("tiersNote", L["Leave all three empty to be asked about nothing. The (i) marks and tooltips still show."])

  for _, key in ipairs({ "warnings", "blocking", "kind_skipRank", "kind_offSpec",
      "tier_defer", "tier_deferLow", "tier_info" }) do
    page.args[key].disabled = off
  end
  return page:group()
end

---------------------------------------------------------------------------
-- Alerts

-- The picker's entries in display order: common sounds first, then sound packs.
local function soundEntries()
  if ns.SoundList then return ns.SoundList.Entries(_G) end
  local out = {}
  for _, entry in ipairs((ns.Sounds and ns.Sounds.list) or {}) do out[#out + 1] = { key = entry.key, label = entry.label } end
  return out
end

function Options.SoundChoices()
  local values = {}
  for _, entry in ipairs(soundEntries()) do values[entry.key] = entry.label end
  return values
end

function Options.SoundOrder()
  local keys = {}
  for _, entry in ipairs(soundEntries()) do keys[#keys + 1] = entry.key end
  return keys
end

local function alertSettings()
  if ns.TrainerConfirm and ns.TrainerConfirm.AlertSettings then return ns.TrainerConfirm.AlertSettings() end
  return {}
end

local CHANNEL_CHOICES = { Master = "Master", SFX = L["Sound effects"], Music = "Music", Ambience = "Ambience", Dialog = "Dialog" }
local CHANNEL_ORDER = { "Master", "SFX", "Music", "Ambience", "Dialog" }

function Options.Alerts()
  local function alert() local p = profile(); return p and p.alert or {} end
  local function soundKey()
    local key = alert().sound
    if key == nil or key == "default" then return ns.Sounds and ns.Sounds.default end
    return key
  end
  local function setAlert(field, value)
    local p = profile()
    if p then p.alert = p.alert or {}; p.alert[field] = value end
  end
  local page = newPage(L["Sound & messages"], 1, L["Sound & messages"], L["Choose how you're warned when you try to buy something you should wait on."])

  profileToggle(page, "alerts", L["Play a warning sound"], L["Plays a sound when you try to buy something you should wait on."], "alerts")

  page:section("soundHeader", L["Warning sound"])
  page:add("sound", {
    type = "select", width = "double", name = L["Sound"],
    values = Options.SoundChoices, sorting = Options.SoundOrder,
    get = soundKey, set = function(_, value) setAlert("sound", value) end,
  })
  page:add("channel", {
    type = "select", width = "double", name = L["Volume channel"],
    desc = L["Which of the game's volume sliders controls this sound."],
    values = CHANNEL_CHOICES, sorting = CHANNEL_ORDER,
    get = function() local c = alert().channel; return CHANNEL_CHOICES[c] and c or "Master" end,
    set = function(_, value) setAlert("channel", value) end,
  })
  page:add("test", {
    type = "execute", name = L["Play sound"],
    func = function() if ns.Alert then pcall(ns.Alert.PlaySound, soundKey(), alertSettings()) end end,
  })
  page:note("soundNote", L["The Master channel plays even when sound effects are muted."])

  page:section("bannerHeader", L["On-screen message"])
  page:toggle("banner", L["Show a message on screen"], L["Shown when there's no question to answer, so you still see why."],
    function() return alert().banner ~= false end,
    function(_, value) setAlert("banner", value) end)

  page:section("cooldownHeader", L["How often"])
  page:add("cooldown", {
    type = "range", width = "full", name = L["Seconds between warnings for the same thing"],
    min = 1, max = 30, step = 1,
    get = function() return alert().cooldown or 3 end,
    set = function(_, value) setAlert("cooldown", value) end,
  })
  page:note("cooldownNote", L["After one warning, the same thing stays quiet for this long."])

  local function quiet() return not isOn("enabled") or not isOn("alerts") end
  page.args.alerts.disabled = function() return not isOn("enabled") end
  for _, key in ipairs({ "sound", "channel", "test", "banner", "cooldown" }) do page.args[key].disabled = quiet end
  return page:group()
end

---------------------------------------------------------------------------
-- Rules: a tree of class > category > one spell per line, each with its icon and a switch.

local ICON_SIZE = 28
local SEVERITY = { deferLow = 1, defer = 2 }

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function byName(items)
  table.sort(items, function(x, y) return x.name < y.name end)
  return items
end

-- Groups a class's abilities by what the player is told. Pure; used by the page and by tests.
-- Every entry is { name = , detail = } where detail is the plain-language reason, if any.
-- Specs of a class in tree order: { { key =, name = }, ... }.
local function orderedSpecs(data)
  local list = {}
  for key, spec in pairs(data.specs or {}) do list[#list + 1] = { key = key, name = spec.name or key, tree = spec.tree or 0 } end
  table.sort(list, function(a, b) if a.tree ~= b.tree then return a.tree < b.tree end return a.key < b.key end)
  return list
end

local TAG_LABELS = {
  PvP = L["Spells for fighting players"],
  RaidGroup = L["Spells for groups and raids"],
  LowValue = L["Spells that rarely help"],
  Endgame = L["Spells for level 60"],
}

-- Group titles run: All specs, the specs or tag headings, Other, then Pet.
local function titleRank(title)
  if title == ALL_SPECS then return 0 elseif title == OTHER then return 2 elseif title == PET then return 3 end
  return 1
end

-- Splits entries into titled groups: { { title =, entries = }, ... } in title order, entries by name.
local function buildGroups(entries, titleOf)
  local groups, order = {}, {}
  for _, entry in ipairs(entries) do
    local title = titleOf(entry)
    if not groups[title] then groups[title] = {}; order[#order + 1] = title end
    table.insert(groups[title], entry)
  end
  table.sort(order, function(a, b)
    if titleRank(a) ~= titleRank(b) then return titleRank(a) < titleRank(b) end
    return a < b
  end)
  local out = {}
  for _, title in ipairs(order) do out[#out + 1] = { title = title, entries = byName(groups[title]) } end
  return out
end

local function setOf(list)
  local out = {}
  for _, name in ipairs(list or {}) do out[name] = true end
  return out
end

-- A line on the rules page: the family ID (what switches and worths are keyed by) and the name the client shows for it.
local function entryFor(data, id, detail)
  return { id = id, name = ns.SpellData.DisplayName(data.class, id) or tostring(id), detail = detail }
end

function Options.ClassSummary(data)
  local keep, wait, low, skipped = {}, {}, {}, {}
  local best, tagOf = {}, {}
  local specs = orderedSpecs(data)
  -- Rotation lists come first in the engine, so a spell in one is never shown by its tag.
  local coreBy, sitBy = {}, {}
  for key, spec in pairs(data.specs or {}) do
    for _, id in ipairs(spec.rotation.core or {}) do coreBy[id] = coreBy[id] or {}; coreBy[id][key] = true end
    for _, id in ipairs(spec.rotation.situational or {}) do sitBy[id] = sitBy[id] or {}; sitBy[id][key] = true end
  end
  for id, tags in pairs(data.tags or {}) do
    for _, tag in ipairs(tags) do
      local tier = data.tagTiers and data.tagTiers[tag]
      if tier and SEVERITY[tier] and SEVERITY[tier] > (best[id] and SEVERITY[best[id]] or 0) then
        best[id], tagOf[id] = tier, tag
      end
    end
  end
  local keepBy = {}
  for id in pairs(coreBy) do keepBy[id] = coreBy[id] end
  local allSpecs = {}
  for _, spec in ipairs(specs) do allSpecs[spec.key] = true end
  for id, tier in pairs(data.overrides or {}) do
    if tier == "keep" then
      keepBy[id] = allSpecs
      best[id] = nil
    elseif SEVERITY[tier] then
      best[id], tagOf[id] = tier, nil
    end
  end
  for id in pairs(keepBy) do keep[#keep + 1] = entryFor(data, id); best[id] = nil end
  local optionalBy, optional = {}, {}
  for id, used in pairs(sitBy) do
    if not keepBy[id] then optionalBy[id] = used; optional[#optional + 1] = entryFor(data, id); best[id] = nil end
  end
  for id, tier in pairs(best) do
    if not (coreBy[id] or sitBy[id]) then
      local entry = entryFor(data, id, ns.Rules.WhyWait(data, id, tagOf[id]))
      if tier == "defer" then wait[#wait + 1] = entry else low[#low + 1] = entry end
    end
  end
  for id, ranks in pairs(data.skipRanks or {}) do
    local list = {}
    for _, rank in ipairs(ranks) do list[#list + 1] = tostring(rank) end
    skipped[#skipped + 1] = entryFor(data, id,
      (L["Skip rank%s %s. Only a small upgrade over the rank before it."]):format(#list > 1 and "s" or "", table.concat(list, ", ")))
  end
  -- General skills (Auto Shot, Dual Wield) are left off the page; pet spells sit under Pet, not under a spec.
  local general, pet = setOf(data.general), setOf(data.pet)
  local function without(list)
    local out = {}
    for _, entry in ipairs(list) do if not general[entry.id] then out[#out + 1] = entry end end
    return out
  end
  local function specTitle(used)
    local titles, count = {}, 0
    for _, spec in ipairs(specs) do
      if used[spec.key] then titles[#titles + 1] = spec.name; count = count + 1 end
    end
    if count == 0 then return OTHER end
    return (count == #specs) and ALL_SPECS or table.concat(titles, ", ")
  end
  local function bySpec(usedBy)
    return function(entry)
      if pet[entry.id] then return PET end
      return usedBy[entry.id] and specTitle(usedBy[entry.id]) or OTHER
    end
  end
  local function byTag(entry)
    if pet[entry.id] then return PET end
    return TAG_LABELS[tagOf[entry.id]] or OTHER
  end
  local usedBy = {}
  for id, used in pairs(coreBy) do usedBy[id] = used end
  for id, used in pairs(sitBy) do usedBy[id] = usedBy[id] or used end
  keep, optional, wait, low, skipped = without(keep), without(optional), without(wait), without(low), without(skipped)
  return { keep = byName(keep), optional = byName(optional), wait = byName(wait), low = byName(low), skipped = byName(skipped),
    keepGroups = buildGroups(keep, bySpec(keepBy)), optionalGroups = buildGroups(optional, bySpec(optionalBy)),
    waitGroups = buildGroups(wait, byTag), lowGroups = buildGroups(low, byTag),
    skippedGroups = buildGroups(skipped, bySpec(usedBy)) }
end

-- A read-only line: name, then the reason beneath it, with an icon.
local function item(entry, icon)
  local label = entry.name
  if entry.detail then label = label .. "\n" .. MUTED .. entry.detail .. "|r" end
  return {
    type = "description", width = "full", fontSize = "medium", name = label,
    -- Looked up when drawn, so icons learned at a trainer show up without reloading.
    image = function()
      return icon or (ns.Icons and ns.Icons.Lookup(entry.id)) or nil, ICON_SIZE, ICON_SIZE
    end,
  }
end

-- The same line with a switch: ticked means the addon watches for this ability.
local function abilityToggle(entry, classKey)
  return {
    type = "toggle", width = "full", name = entry.name, desc = withWorth(entry.detail, classKey, "offAbilities", entry.id),
    descStyle = "inline",
    image = function()
      return (ns.Icons and ns.Icons.Lookup(entry.id)) or nil, ICON_SIZE, ICON_SIZE
    end,
    get = function() return not isOff("abilities", classKey, entry.id) end,
    set = function(_, value) setOff("abilities", classKey, entry.id, not value); applyNow() end,
  }
end

-- `classKey` makes each line a switch; without it the lines are only listed.
local function category(order, title, hex, entries, empty, classKey)
  local page = { args = {}, n = 0 }
  if #entries == 0 then page.args.none = { type = "description", fontSize = "medium", width = "full", order = 0, name = MUTED .. (empty or L["Nothing here."]) .. "|r" } end
  for i, entry in ipairs(entries) do
    page.args["item" .. i] = classKey and abilityToggle(entry, classKey) or item(entry)
    page.args["item" .. i].order = i * 2 - 1
    if not classKey then -- read-only lines get a blank line between them; switches already have room
      page.args["gap" .. i] = { type = "description", fontSize = "small", width = "full", name = " ", order = i * 2 }
    end
  end
  return { type = "group", order = order, name = ("|cff%s%s|r (%d)"):format(hex, title, #entries), args = page.args }
end

-- Like `category`, but the lines sit in one inline box per group (All specs, then each spec).
local function groupedCategory(order, title, hex, groups, empty, classKey)
  local total, args = 0, {}
  for _, g in ipairs(groups) do total = total + #g.entries end
  if total == 0 then args.none = { type = "description", fontSize = "medium", width = "full", order = 0, name = MUTED .. (empty or L["Nothing here."]) .. "|r" } end
  for i, g in ipairs(groups) do
    local box = category(i, g.title, "ffffff", g.entries, nil, classKey)
    box.inline = true
    box.name = ("%s (%d)"):format(g.title, #g.entries)
    args["group" .. i] = box
  end
  return { type = "group", order = order, name = ("|cff%s%s|r (%d)"):format(hex, title, total), args = args }
end

local function classChoices(key, data)
  local page = newPage(L["Your choices"], 0, L["Your choices"],
    L["Tell the addon how you play. Untick anything to stop it being marked."])
  local specNames, order = { auto = L["Automatic"] }, { "auto" }
  local specKeys = sortedKeys(data.specs)
  table.sort(specKeys, function(a, b)
    local ta, tb = data.specs[a].tree or 0, data.specs[b].tree or 0
    if ta ~= tb then return ta < tb end
    return a < b
  end)
  for _, spec in ipairs(specKeys) do
    specNames[spec] = data.specs[spec].name or spec
    order[#order + 1] = spec
  end
  page:section("specHeader", L["My spec"])
  page:add("spec", {
    type = "select", width = "double", name = L["Which spec do you play?"],
    desc = L["Automatic works it out from your talents."],
    values = specNames, sorting = order,
    get = function()
      local p = profile()
      local pick = p and p.specOverride and p.specOverride[key]
      return specNames[pick] and pick or "auto"
    end,
    set = function(_, value)
      local p = profile()
      if not p then return end
      p.specOverride = p.specOverride or {}
      p.specOverride[key] = value ~= "auto" and value or nil
      applyNow()
    end,
  })
  local tags = sortedKeys(data.tagTiers)
  if #tags > 0 then
    page:section("tagHeader", L["Kinds of spell to mark"])
    for _, tag in ipairs(tags) do
      page:toggle("tag_" .. tag, TAG_LABELS[tag] or tag, withWorth(data.tagReasons and data.tagReasons[tag], key, "offTags", tag),
        function() return not isOff("tags", key, tag) end,
        function(_, value) setOff("tags", key, tag, not value); applyNow() end)
    end
  end
  return page:group()
end

-- The class page's own text: what each spec could keep, and how its spells are sorted.
-- Worked out with every rule on, whatever the player has switched off, up to the level 60 mount.
local OVERVIEW_COUNTS = {
  { "keep", L["Worth buying"], "33e633" }, { "optional", L["Optional"], "66e0cc" }, { "wait", L["Save your gold"], "ff3333" },
  { "low", L["Not worth buying yet"], "ffd100" }, { "skipped", L["Ranks to skip"], "66b3ff" },
}

function Options.ClassOverview(key, s)
  local at40, at60
  local function results()
    at40 = at40 or ns.Savings.Max(key, 40)
    at60 = at60 or ns.Savings.Max(key, 60)
    return at40, at60
  end
  local page = newPage(L["Overview"], 0, L["Overview"], L["What this class could keep, and how its spells are sorted."])
  page:section("specHeader", L["Savings by spec: level 40 / level 60"])
  for i, spec in ipairs(orderedSpecs(ns.Rules.GetClass(key))) do
    page:add("spec" .. i, { type = "description", fontSize = "medium", width = "full",
      name = function()
        local a, b = results()
        local x, y = a.specs[i], b.specs[i]
        if not (x and y) then return " " end
        return figure(spec.name, "ffffff", bigMoney(x.total) .. MUTED .. " / |r" .. bigMoney(y.total))
      end })
    page:gap()
  end
  page:section("countsHeader", L["How the spells are sorted"])
  for _, c in ipairs(OVERVIEW_COUNTS) do
    page:add("count_" .. c[1], { type = "description", fontSize = "medium", width = "full",
      name = figure(c[2], c[3], "|cffffffff" .. #s[c[1]] .. "|r") })
    page:gap()
  end
  page:note("priceNote", PRICE_NOTE)
  return page.args
end

function Options.Rules()
  local classes, classCount = {}, 0
  for _, key in ipairs((ns.Rules and ns.Rules.ListClasses and ns.Rules.ListClasses()) or {}) do
    local data = ns.Rules.GetClass(key)
    if data then
      local s = Options.ClassSummary(data)
      classCount = classCount + 1
      classes[key] = {
        type = "group", order = classCount + 2, name = titleCase(key), childGroups = "tree",
        args = {
          choices = classChoices(key, data),
          keep = groupedCategory(101, L["Worth buying"], "33e633", s.keepGroups),
          optional = groupedCategory(102, L["Optional"], "66e0cc", s.optionalGroups),
          wait = groupedCategory(103, L["Save your gold"], "ff3333", s.waitGroups, nil, key),
          low = groupedCategory(104, L["Not worth buying yet"], "ffd100", s.lowGroups, nil, key),
          skipped = groupedCategory(105, L["Ranks to skip"], "66b3ff", s.skippedGroups, nil, key),
        },
      }
      for argKey, widget in pairs(Options.ClassOverview(key, s)) do classes[key].args[argKey] = widget end
    end
  end

  local intro = newPage(L["Classes"], 0, L["Classes"], L["Open a class to see what the addon marks and why. Tick or untick anything to decide what you're told about."])
  for key, widget in pairs(intro.args) do classes[key] = widget end
  return { type = "group", name = ("Classes (%d)"):format(classCount), order = 3, childGroups = "tree", args = classes }
end

---------------------------------------------------------------------------
-- Milestones

local MOUNT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"

local function playerClass()
  local ok, player = pcall(function() return ns.Adapter and ns.Adapter.ReadPlayer(_G) end)
  return ok and player and player.class or nil
end

-- The targets for the player's class, or the defaults when it can't be told.
local function milestoneTargets(class)
  if ns.Milestones and ns.Milestones.For then return ns.Milestones.For(class) end
  return (ns.Milestones and ns.Milestones.Defaults) or {}
end

function Options.MilestoneItems(class)
  local d = milestoneTargets(class or playerClass())
  local items = {}
  if d[40] then
    local detail = (L["%s for riding and your first mount."]):format(money((d[40].riding or 0) + (d[40].mount or 0)))
    if d[40].note then detail = detail .. " " .. d[40].note end
    items[#items + 1] = { name = L["Level 40 mount"], detail = detail }
  end
  if d[60] then
    items[#items + 1] = { name = L["Level 60 mount"],
      detail = (L["%s for riding, plus %s for each epic mount."]):format(money(d[60].riding), money(d[60].mount)) }
  end
  return items
end

function Options.MilestoneStatus()
  local ok, p = pcall(function() return ns.Context and ns.Context.Profile(_G) end)
  if not ok or not p then return L["Log in on a supported character to see your progress."] end
  local m = p.milestone or {}
  if m.state == "finished" then
    if ns.Settings and ns.Settings.StopAfter() == 40 then
      return L["You've bought your level 40 mount, the one you chose to stop at, so the addon has stopped warning you."]
    end
    return L["You've bought your level 60 mount, so the addon has stopped warning you."]
  end
  if m.current == 60 then return L["You're saving for your level 60 mount."] end
  return L["You're saving for your level 40 mount."]
end

-- "You have 12g of the 100g you need (12%)." for the mount being saved for; nil when it can't be worked out.
function Options.MilestoneProgress(env)
  env = env or _G
  local okProfile, p = pcall(function() return ns.Context and ns.Context.Profile(env) end)
  local m = okProfile and p and p.milestone
  local d = milestoneTargets(p and p.class)
  if not (m and m.current and d[m.current] and type(env.GetMoney) == "function") then return nil end
  local okMoney, have = pcall(env.GetMoney)
  if not okMoney or type(have) ~= "number" then return nil end
  local goal = (d[m.current].riding or 0) + (d[m.current].mount or 0)
  if goal <= 0 then return nil end
  if have >= goal then
    return "|cff33e633" .. L["You have %s. That's enough for your level %d mount."]:format(money(have), m.current) .. "|r"
  end
  return (L["You have |cffffd100%s|r of the |cffffd100%s|r you need (%d%%)."]):format(
    money(have), money(goal), math.floor(have / goal * 100))
end

function Options.Milestones()
  local page = newPage(L["Milestones"], 5, L["Milestones"])
  page:add("status", { type = "description", fontSize = "medium", width = "full",
    name = function() return ACCENT .. Options.MilestoneStatus() .. "|r" end })
  page:add("progress", { type = "description", fontSize = "medium", width = "full",
    name = function() return Options.MilestoneProgress(_G) or " " end })

  page:section("mountsHeading", L["The mounts"])
  for i, entry in ipairs(Options.MilestoneItems()) do
    page:add("mount" .. i, item(entry, MOUNT_ICON))
    page:gap()
  end
  page:note("note", L["Prices are what the addon expects and may change."])

  -- The addon reads your riding skill to know when a mount is bought. If it gets that wrong, set it here.
  local function overridden(level)
    local p = profile()
    return p ~= nil and p.milestoneOverride ~= nil and p.milestoneOverride[level] == true
  end
  local function override(level, value)
    local p = profile()
    if not p then return end
    p.milestoneOverride = p.milestoneOverride or {}
    p.milestoneOverride[level] = value or nil
    applyNow()
  end
  page:section("fixHeading", L["Not right?"])
  page:text("fix", L["If the addon doesn't notice that you bought a mount, tell it here."])
  page:toggle("have40", L["I've already bought my level 40 mount"], nil,
    function() return overridden(40) end, function(_, value) override(40, value) end)
  page:toggle("have60", L["I've already bought my level 60 mount"], nil,
    function() return overridden(60) end, function(_, value) override(60, value) end)
  return page:group()
end

---------------------------------------------------------------------------
-- Tally

function Options.TallyLines()
  if ns.Tally and ns.Tally.Summary then
    local ok, lines = pcall(ns.Tally.Summary)
    if ok and lines then return lines end
  end
  return { L["The tally isn't available right now."] }
end

-- The tally's numbers, or nil when they can't be worked out yet.
local function tallyEntries()
  if not (ns.Tally and ns.Tally.Entries) then return nil, L["The tally isn't available right now."] end
  local ok, entries, message = pcall(ns.Tally.Entries)
  if not ok then return nil, L["The tally isn't available right now."] end
  return entries, message
end

local function amount(label, hex, key)
  return { type = "description", fontSize = "medium", width = "full",
    name = function()
      local entries, message = tallyEntries()
      if not entries then return key == "verified" and (MUTED .. (message or "") .. "|r") or " " end
      return figure(label, hex, money(entries[key]))
    end }
end

function Options.Tally()
  local page = newPage(L["Tally"], 6, L["Tally"], L["How much gold you've kept by waiting."])
  page:section("keptHeader", L["Kept"])
  page:add("verified", amount(L["Kept for sure"], "33e633", "verified"))
  page:note("verifiedNote", L["You skipped these and already learned a better version."])
  page:gap()
  page:add("projected", amount(L["Kept so far"], "ffd100", "projected"))
  page:note("projectedNote", L["Things you could buy right now but haven't."])
  page:gap()

  page:section("spentHeader", L["Spent anyway"])
  page:add("spent", amount(L["Spent on things the addon marked"], "ff3333", "spentAgainst"))
  page:add("avoided", { type = "description", fontSize = "medium", width = "full",
    name = function()
      local entries = tallyEntries()
      if not entries then return " " end
      return "|cff33e633" .. L["Purchases you turned down:"] .. "|r    " .. L["%d, worth %s"]:format(entries.avoidedCount, money(entries.avoided))
    end })
  page:add("resets", { type = "description", fontSize = "medium", width = "full",
    name = function()
      local entries = tallyEntries()
      if not entries or #entries.resets == 0 then return " " end
      return table.concat(entries.resets, "\n")
    end })
  page:note("footer", L["Prices are the ones trainers showed you, or an estimate for spells you haven't seen priced. Turning a rule off only changes what is counted from then on."])

  page:section("resetHeader", L["Start over"])
  page:text("resetNote", L["Forget what the addon has seen at trainers and set everything back to zero."])
  page:add("reset", {
    type = "execute", name = L["Start the count over"],
    confirm = true, confirmText = L["Reset the tally to zero?"],
    func = function()
      local db = ns.db and ns.db.char
      if db then
        db.catalog, db.ledger, db.costCache = {}, {}, {}
        if ns.Tally then ns.Tally.Init(ns.db); ns.Tally.Reset() end
      end
    end,
  })
  return page:group()
end

---------------------------------------------------------------------------
-- What to watch

local MODE_CHOICES = { off = L["Off"], vendor = L["Vendor"], ah = L["Auction house"], both = L["Both"] }
local MODE_ORDER = { "off", "vendor", "ah", "both" }
local COIN = {
  g = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t Gold",
  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t Silver",
  c = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t Copper",
}
local COIN_UNIT = { g = 10000, s = 100, c = 1 }

local function minPrice()
  local p = profile()
  return p and p.minPrice or 0
end

-- The part of the minimum price shown in one box. Gold has no upper limit; silver and copper show 0-99.
function Options.PriceBox(copper, coin)
  copper = math.floor(copper or 0)
  if coin == "g" then return math.floor(copper / 10000) end
  if coin == "s" then return math.floor(copper / 100) % 100 end
  return copper % 100
end

-- The new minimum price after typing `text` into one box. Anything that is not a whole number of zero
-- or more leaves the price as it was. Silver and copper above 99 carry upward.
function Options.SetPriceBox(copper, coin, text)
  local digits = tostring(text or ""):match("^%s*(%d+)%s*$")
  if not digits then return copper end
  return copper - Options.PriceBox(copper, coin) * COIN_UNIT[coin] + tonumber(digits) * COIN_UNIT[coin]
end

local function priceBox(coin)
  return {
    type = "input", width = 0.6, name = COIN[coin],
    get = function() return tostring(Options.PriceBox(minPrice(), coin)) end,
    validate = function(_, value)
      if tostring(value or ""):match("^%s*%d+%s*$") then return true end
      return L["Enter a whole number, 0 or more."]
    end,
    set = function(_, value)
      local p = profile()
      if p then p.minPrice = Options.SetPriceBox(p.minPrice or 0, coin, value) end
      local ok, registry = pcall(LibStub, "AceConfigRegistry-3.0")
      if ok and registry then pcall(registry.NotifyChange, registry, APP) end
    end,
  }
end

local function watchToggle(page, area, name, desc)
  return page:toggle("watch_" .. area, name, desc,
    function() return ns.Settings == nil or ns.Settings.Watching(area) end,
    function(_, value)
      if ns.Settings then ns.Settings.SetWatching(area, value) end
      applyNow()
    end)
end

function Options.Watch()
  local page = newPage(L["What to watch"], 2, L["What to watch"], L["Choose which kinds of spending Don't Do That keeps an eye on."])
  local categoriesOpen = false

  page:section("spellsHeader", L["Spells"])
  watchToggle(page, "spells", L["Warn about spells I can wait on"], L["Class and pet trainer spells you won't need yet."])
  profileToggle(page, "filter", L["Add a Recommended filter to trainers"], L["Adds a Recommended choice to the trainer's Filter menu that hides what you can wait on."], "recommendedFilter")

  page:section("professionsHeader", L["Professions"])
  watchToggle(page, "professions", L["Warn about professions I can wait on"], L["The first time you learn a new profession."])
  page:note("professionsNote", L["Asks once, the first time you learn a profession other than Fishing, Herbalism, Mining or Skinning. Leveling a profession costs gold at every step."])

  page:section("shoppingHeader", L["Shopping"])
  watchToggle(page, "shopping", L["Warn about things I buy"], L["Gear, bags, potions and other items at vendors and the auction house."])
  page:note("minNote", L["Purchases that cost less than this, in total, are never warned about."])
  page:add("minGold", priceBox("g"))
  page:add("minSilver", priceBox("s"))
  page:add("minCopper", priceBox("c"))
  page:add("showCategories", {
    type = "toggle", width = "full", name = L["Choose categories"],
    desc = L["Pick vendor, auction house, both or neither for each kind of item."],
    get = function() return categoriesOpen end,
    set = function(_, value) categoriesOpen = value end,
  })
  local categories = {}
  for i, info in ipairs(ns.ItemCategory.List) do
    categories[info.key] = {
      type = "select", width = "double", name = info.label, order = i,
      values = MODE_CHOICES, sorting = MODE_ORDER,
      get = function()
        local p = profile()
        return p and p.itemModes and p.itemModes[info.key] or "off"
      end,
      set = function(_, value)
        local p = profile()
        if p then p.itemModes = p.itemModes or {}; p.itemModes[info.key] = value end
      end,
    }
  end
  page:add("categories", { type = "group", inline = true, name = L["Warn me when I buy"], args = categories,
    hidden = function() return not categoriesOpen end })

  page:section("otherHeader", L["Other"])
  local function guardToggle(key, name, desc)
    page:toggle("guard_" .. key, name, desc,
      function()
        local p = profile()
        return p == nil or p.guard == nil or p.guard[key] ~= false
      end,
      function(_, value)
        local p = profile()
        if p then p.guard = p.guard or {}; p.guard[key] = value end
      end)
  end
  guardToggle("bank", L["Buying a bank slot"], L["Each slot costs more than the last."])
  guardToggle("stable", L["Buying a stable slot"], L["For Hunters; each slot costs more than the last."])
  guardToggle("cod", L["Paying for COD mail"], L["Asks before you pay to take a mailed item."])

  return page:group({ disabled = function() return not isOn("enabled") end })
end

-- Milestones and the tally, one after the other.
-- What following the addon's advice keeps, for this character's spec and settings. nil and a message when
-- it can't be worked out.
function Options.SavingsEntries(env)
  env = env or _G
  local ok, p = pcall(function() return ns.Context and ns.Context.Profile(env) end)
  if not ok or not p or not ns.Savings then return nil, L["Log in on a supported character to see your projected savings."] end
  local stop = ns.Settings and ns.Settings.StopAfter() or 60
  local cache = ns.db and ns.db.char and ns.db.char.costCache
  return recent("savings", function()
    local result = ns.Savings.Compute(p, stop, cache)
    result.stop = stop
    return result
  end)
end

function Options.Savings()
  local page = newPage(L["Projected savings"], 7, L["Projected savings"])
  local function row(label, hex, key, size)
    return { type = "description", fontSize = size or "medium", width = "full",
      name = function()
        local entries = Options.SavingsEntries()
        if not entries then return " " end
        return figure(label, hex, bigMoney(entries[key]))
      end }
  end
  page:add("intro", { type = "description", fontSize = "medium", width = "full",
    name = function()
      local entries, message = Options.SavingsEntries()
      if not entries then return MUTED .. message .. "|r" end
      return MUTED .. (L["What you'd keep by following the advice up to your level %d mount, for your spec and your settings.|r"]):format(entries.stop)
    end })
  page:section("totalHeader", L["You'd keep"])
  page:add("total", { type = "description", fontSize = "large", width = "full",
    name = function()
      local entries = Options.SavingsEntries()
      return entries and bigMoney(entries.total) or " "
    end })
  page:section("fromHeader", L["Where it comes from"])
  page:add("wait", row(L["Save your gold"], "ff3333", "wait"))
  page:note("waitNote", L["Spells you won't need until later."])
  page:gap()
  page:add("low", row(L["Not worth buying yet"], "ffd100", "low"))
  page:note("lowNote", L["Low-value spells that rarely help while leveling."])
  page:gap()
  page:add("skip", row(L["Ranks to skip"], "66b3ff", "skip"))
  page:note("skipNote", L["Ranks that are only a small upgrade over the one before."])
  page:gap()
  page:note("note", PRICE_NOTE .. " " .. L["Turning a rule off lowers this number."])
  return page:group()
end

function Options.Progress()
  local page = newPage(L["Progress"], 3, L["Progress"], L["How close you are to your mounts, and how much gold you've kept by waiting."])
  local milestones, savings, tally = Options.Milestones(), Options.Savings(), Options.Tally()
  -- The boxes already show their name, so the groups' own gold titles would repeat it.
  milestones.args.title, savings.args.title, tally.args.title = nil, nil, nil
  milestones.inline, milestones.order = true, 10
  savings.inline, savings.order = true, 15
  tally.inline, tally.order = true, 20
  page.args.milestones, page.args.savings, page.args.tally = milestones, savings, tally
  return page:group()
end

-- The deeper controls, each one step away. A tree, so Rules keeps its own tree inside it.
function Options.Advanced()
  local page = newPage(L["Advanced"], 4, L["Advanced"], L["Fine controls. You never need these to use the addon."])
  local sound, tuningGroup, classes, debug = Options.Alerts(), Options.Tuning(), Options.Rules(), Options.Debug()
  sound.order, tuningGroup.order, classes.order, debug.order = 10, 20, 30, 40
  sound.name = L["Sound & messages"]
  page.args.sound, page.args.tuning, page.args.classes, page.args.debug = sound, tuningGroup, classes, debug
  return page:group({ childGroups = "tree" })
end

---------------------------------------------------------------------------
-- Debug

function Options.Debug()
  local page = newPage(L["Debug"], 7, L["Debug"],
    L["For reporting a problem. Turn the recording on, do the thing that went wrong, then show the report and copy it."])
  page:section("recordingHeader", L["Recording"])
  page:toggle("logging", L["Record what the addon sees"],
    L["Keeps a log of trainer windows, purchases and dialogs. Turn it on before the thing you want to report."],
    function() local p = profile(); return p ~= nil and p.debug == true end,
    function(_, value)
      local p = profile(); if p then p.debug = value end
      if ns.Log then ns.Log.SetEnabled(value) end
    end)
  page:toggle("traceItems", L["Record item purchases"],
    L["Keeps the last 40 vendor and auction decisions, even across logins, and includes them in the report. Off by default."],
    function() local p = profile(); return p ~= nil and p.traceItems == true end,
    function(_, value) local p = profile(); if p then p.traceItems = value end end)

  page:section("reportHeader", L["Report"])
  page:note("reportNote", L["Opens a window with everything the addon knows. Press Ctrl+A, then Ctrl+C to copy it, and paste it where you're reporting the problem."])
  page:add("export", {
    type = "execute", name = L["Show the report"],
    func = function() if ns.Export then ns.Export.Show() end end,
  })

  page:section("clearHeader", L["Clear"])
  page:note("clearNote", L["Empties the recording and the item purchase record. Your settings and tally are kept."])
  page:add("clear", {
    type = "execute", name = L["Clear the recording"],
    func = function()
      if ns.Log then ns.Log.ClearAll() end
      if ns.db and ns.db.global then ns.db.global.itemTrace = {} end
    end,
  })
  return page:group()
end

---------------------------------------------------------------------------
-- About

-- Sections of { heading, lines }. A line starting with "!" is a small gray note; one starting with "*" is a bullet.
function Options.AboutSections()
  return {
    { heading = L["What the marks mean"], lines = {
      "*|cffff3333(i)  " .. L["Save your gold"] .. "|r",
      "!" .. L["You won't need this until level 60. You'll hear a warning and be asked before you buy it."],
      "*|cffffd100(i)  " .. L["Not worth buying yet"] .. "|r",
      "!" .. L["A low-value spell. It's marked, but it never gets in your way."],
      "*|cff66b3ff(i)  " .. L["Optional"] .. "|r",
      "!" .. L["Handy now and then, but you can get by without it."],
    } },
    { heading = L["How to use it"], lines = {
      "*" .. L["Hover an (i) to see why, and what it costs. Click it to keep the message open."],
      "*" .. L["Use Recommended in the trainer's Filter menu to hide what you can wait on."],
      "*" .. L["Type /ddt any time to open these settings."],
    } },
    { heading = L["Good to know"], lines = {
      L["The addon only ever asks. You can always buy anything, and you can turn any part of it off."],
    } },
  }
end

-- The same content as plain lines.
function Options.AboutLines()
  local lines = { L["Version %s"]:format(tostring(ns.version or "unknown")), "" }
  for _, section in ipairs(Options.AboutSections()) do
    lines[#lines + 1] = section.heading
    for _, line in ipairs(section.lines) do
      lines[#lines + 1] = line:sub(1, 1) == "*" and ("\226\128\162 " .. line:sub(2)) or (line:gsub("^!", ""))
    end
    lines[#lines + 1] = ""
  end
  return lines
end

function Options.About()
  local page = newPage(L["About"], 5, L["Don't Do That"])
  page:note("version", L["Version %s"]:format(tostring(ns.version or "unknown")))
  for i, section in ipairs(Options.AboutSections()) do
    page:section("heading" .. i, section.heading)
    for j, line in ipairs(section.lines) do
      local first = line:sub(1, 1)
      local body = line
      if first == "!" then body = MUTED .. line:sub(2) .. "|r"
      elseif first == "*" then body = ACCENT .. "\226\128\162|r  " .. line:sub(2) end
      page:text("line" .. i .. "_" .. j, body)
    end
  end
  return page:group()
end

---------------------------------------------------------------------------
-- Pages and registration

function Options.Pages()
  return {
    { key = "home", group = Options.Home() },
    { key = "watch", group = Options.Watch() },
    { key = "progress", group = Options.Progress() },
    { key = "advanced", group = Options.Advanced() },
    { key = "about", group = Options.About() },
  }
end

-- One window with every page in a tree (used by /ddt).
function Options.Root()
  local args = {}
  for _, page in ipairs(Options.Pages()) do args[page.key] = page.group end
  return { type = "group", name = TITLE, childGroups = "tree", args = args }
end

function Options.Register(addon)
  local libs = _G.LibStub
  if not libs then return false end
  local okC, config = pcall(libs, "AceConfig-3.0")
  local okD, dialog = pcall(libs, "AceConfigDialog-3.0")
  if not (okC and okD and config and dialog) then return false end

  pcall(config.RegisterOptionsTable, config, APP, Options.Root())

  -- The game's own AddOns list: a parent entry with one sub-page per group.
  panelBuild = true
  local parentPage = newPage(TITLE, 0, TITLE, L["Pick a page from the list on the left, or type /ddt."])
  local parent = parentPage:group()
  pcall(config.RegisterOptionsTable, config, APP .. "_parent", parent)
  pcall(dialog.AddToBlizOptions, dialog, APP .. "_parent", TITLE)
  for _, page in ipairs(Options.Pages()) do
    local name = APP .. "_" .. page.key
    pcall(config.RegisterOptionsTable, config, name, page.group)
    pcall(dialog.AddToBlizOptions, dialog, name, page.group.name, TITLE)
  end
  panelBuild = false

  if addon then
    function addon:OpenOptions() Options.Open() end
  end
  return true
end

function Options.Open()
  local libs = _G.LibStub
  if not libs then return false end
  local ok, dialog = pcall(libs, "AceConfigDialog-3.0")
  if not ok or not dialog then return false end
  pcall(dialog.Open, dialog, APP)
  return true
end
