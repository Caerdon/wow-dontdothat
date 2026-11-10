local addonName, ns = ...

-- Records what the client shows while debug logging is on, so a short play session
-- can be exported afterwards. Hooks only observe (post-hooks); nothing is blocked.
-- Frame and event names are Classic-family candidates, UNVERIFIED on WoW Forever.
local Capture = {}
ns.Capture = Capture

local MAX_TRAINERS = 10
local MAX_PURCHASES = 50

Capture.Frames = {
  "ClassTrainerFrame", "ClassTrainerTrainButton", "TalentFrame", "PlayerTalentFrame",
  "PlayerSpellsFrame", "StaticPopup1", "PlayerTalentFrameTalent1", "TalentFrameTalent1",
  "PlayerTalentFrameLearnButton", "PlayerTalentFrameResetButton",
}

-- Frames whose child fields (parentKey children such as a filter dropdown) are listed in the report.
Capture.InspectKeys = { ClassTrainerFrame = true, PlayerTalentFrame = true }
Capture.KeyPatterns = { "ilter", "ropdown", "enu", "croll", "Button" }

-- Events that fire for unrelated reasons; only their handlers decide whether anything is worth noting.
Capture.QuietEvents = { ADDON_LOADED = true }

Capture.HookedFunctions = { "BuyTrainerService", "LearnTalent", "LearnPreviewTalents", "StaticPopup_Show",
  "ClassTrainerFrame_Update" }

local MAX_POPUPS = 60

local hooked = {}

function Capture.Reset()
  hooked = {}
end

local function now()
  return time and time() or 0
end

local function active()
  return ns.Log and ns.Log.IsEnabled() or false
end

local function note(fmt, ...)
  if ns.Log then ns.Log.Add(fmt, ...) end
end

local function store(saved)
  saved.captures = saved.captures or {}
  local c = saved.captures
  c.events = c.events or {}
  c.trainers = c.trainers or {}
  c.purchases = c.purchases or {}
  c.popups = c.popups or {}
  c.petResetQuotes = c.petResetQuotes or {}
  c.eventFailures = c.eventFailures or {}
  return c
end

local function npcName(env)
  local ok, name = pcall(function() return env.UnitName("npc") end)
  return ok and type(name) == "string" and name or "unknown"
end

---------------------------------------------------------------------------
-- Frames

function Capture.FrameReport(env)
  env = env or _G
  local lines = {}
  for _, name in ipairs(Capture.Frames) do
    local frame = env[name]
    if type(frame) ~= "table" then
      lines[#lines + 1] = ("  %s: missing"):format(name)
    else
      local okT, objType = pcall(function() return frame:GetObjectType() end)
      local okP, isProtected, explicit = pcall(function() return frame:IsProtected() end)
      lines[#lines + 1] = ("  %s: %s, %s"):format(name, okT and tostring(objType) or "type?",
        okP and ("protected=%s explicit=%s"):format(tostring(isProtected), tostring(explicit)) or "IsProtected errored")
      if Capture.InspectKeys[name] then
        local keys = {}
        pcall(function()
          for key, value in pairs(frame) do
            if type(key) == "string" and (type(value) == "table" or type(value) == "function") then
              for _, pattern in ipairs(Capture.KeyPatterns) do
                if key:find(pattern, 1, true) then keys[#keys + 1] = key .. ":" .. type(value); break end
              end
            end
          end
        end)
        table.sort(keys)
        lines[#lines + 1] = ("    fields matching filter/dropdown/menu/scroll/button: %s"):format(
          #keys > 0 and table.concat(keys, " ", 1, math.min(#keys, 40)) or "none")
      end
    end
  end
  return lines
end

---------------------------------------------------------------------------
-- Snapshots

-- The trainer list can be empty at TRAINER_SHOW and filled by later TRAINER_UPDATE events,
-- and GetNumTrainerServices counts only services passing the window's type filters.
local function filterState(env)
  local out = {}
  for _, kind in ipairs({ "available", "unavailable", "used" }) do
    local ok, v = pcall(function() return env.GetTrainerServiceTypeFilter(kind) end)
    out[kind] = ok and tostring(v) or "n/a"
  end
  return out
end

function Capture.Trainer(env, saved)
  local snap = ns.Probe.TrainerSnapshot(env)
  if not snap.ok then
    note("capture: trainer snapshot unavailable (%s)", tostring(snap.reason))
    return
  end
  pcall(ns.Probe.RecordRankSkips, snap, saved)
  local c = store(saved)
  local npc = npcName(env)
  local previous = c.trainers[npc]
  c.trainers[npc] = { t = now(), services = snap.services, headers = snap.headers, filters = filterState(env) }
  if previous and #previous.services == #snap.services then return end
  local names = {}
  for name in pairs(c.trainers) do names[#names + 1] = name end
  while #names > MAX_TRAINERS do
    table.sort(names, function(a, b) return c.trainers[a].t < c.trainers[b].t end)
    c.trainers[table.remove(names, 1)] = nil
  end
  note("capture: trainer snapshot, %d services", #snap.services)
end

local function try(env, fname, ...)
  local f = env[fname]
  if type(f) ~= "function" then return nil end
  local res = { pcall(f, ...) }
  if not res[1] then return nil end
  return unpack(res, 2)
end

local MAX_BEAST_ROWS = 120

-- Beast Training (pet abilities) is a Craft-API window on Classic: GetCraftInfo(i) ->
-- name, subText, type, numAvailable, isExpanded, trainingPointCost, requiredLevel.
-- All UNVERIFIED on WoW Forever. The window may also be another craft (e.g. Enchanting),
-- which is why the skill line name is stored with the rows.
function Capture.Beast(env, saved)
  local count = try(env, "GetNumCrafts")
  if type(count) ~= "number" then
    note("capture: craft window unavailable")
    return
  end
  local total, spent = try(env, "GetPetTrainingPoints")
  local rows = {}
  for i = 1, math.min(count, MAX_BEAST_ROWS) do
    local name, sub, kind, _, _, points, level = try(env, "GetCraftInfo", i)
    if name then rows[#rows + 1] = { index = i, name = name, sub = sub, kind = kind, points = points, level = level } end
  end
  local c = store(saved)
  local previous = c.beast
  c.beast = { t = now(), skillLine = try(env, "GetCraftDisplaySkillLine"), trainingPoints = { total = total, spent = spent },
    rows = rows }
  if not previous or #previous.rows ~= #rows then note("capture: craft window snapshot, %d rows", #rows) end
end

function Capture.Talents(env, saved)
  local tp = ns.Probe.TalentPoints(env)
  local unspent = try(env, "GetUnspentTalentPoints")
  if unspent == nil then unspent = try(env, "GetNumUnspentTalents") end
  store(saved).talents = { t = now(), ok = tp.ok, reason = tp.reason, trees = tp.trees, unspent = unspent }
  note("capture: talent snapshot (%s)", tp.ok and "ok" or tostring(tp.reason))
end

---------------------------------------------------------------------------
-- Hooks (observe only)

local function recordPurchase(env, saved, index)
  local c = store(saved)
  local okI, name, subText = pcall(function()
    local shape = ns.Adapter and ns.Adapter.TrainerServiceInfo -- Forever's row order differs, see Adapter
    if shape then return shape(env.GetTrainerServiceInfo(index)) end
    return env.GetTrainerServiceInfo(index)
  end)
  local okC, cost = pcall(function() return env.GetTrainerServiceCost(index) end)
  c.purchases[#c.purchases + 1] = {
    t = now(), index = index, name = okI and name or nil, subText = okI and subText or nil,
    cost = okC and cost or nil,
  }
  while #c.purchases > MAX_PURCHASES do table.remove(c.purchases, 1) end
end

-- Records every confirmation dialog shown while debug is on, to discover the dialog names and
-- cost arguments of respec, pet untrain and similar prompts (UNVERIFIED which names exist).
-- Row buttons named ClassTrainerSkill1..N were observed on Classic Era 1.15.9 (11 rows). This records
-- what each row shows after the window refreshes, which the Recommended filter will need to rewrite.
local function textOf(obj)
  if type(obj) ~= "table" then return nil end
  local ok, text = pcall(function() return obj:GetText() end)
  return ok and text or nil
end

function Capture.TrainerRows(env, saved)
  local rows = {}
  for i = 1, 20 do
    local button = env["ClassTrainerSkill" .. i]
    if type(button) ~= "table" then break end
    local okShown, shown = pcall(function() return button:IsShown() end)
    local okId, id = pcall(function() return button:GetID() end)
    rows[#rows + 1] = { n = i, shown = okShown and shown or nil, id = okId and id or nil,
      text = textOf(env["ClassTrainerSkill" .. i .. "Text"]), sub = textOf(env["ClassTrainerSkill" .. i .. "SubText"]) }
  end
  local offset = try(env, "FauxScrollFrame_GetOffset", env.ClassTrainerListScrollFrame)
  store(saved).trainerRows = { t = now(), offset = offset, rows = rows }
end

local function recordPopup(saved, which, text1, text2)
  local c = store(saved)
  c.popups[#c.popups + 1] = { t = now(), which = tostring(which), text1 = text1, text2 = text2 }
  while #c.popups > MAX_POPUPS do table.remove(c.popups, 1) end
end

local function hookFunction(env, saved, fname)
  if hooked[fname] or type(env[fname]) ~= "function" or type(env.hooksecurefunc) ~= "function" then return end
  local ok = pcall(env.hooksecurefunc, fname, function(...)
    if not active() then return end
    if fname == "StaticPopup_Show" then
      pcall(recordPopup, saved, ...)
      return
    end
    if fname == "ClassTrainerFrame_Update" then
      pcall(Capture.TrainerRows, env, saved)
      pcall(Capture.ModernTrainer, env, saved)
      return
    end
    local index = ...
    pcall(ns.Probe.RecordInterception, "trainer/talent", fname .. " post-hook fired", saved)
    note("hook: %s(%s)", fname, tostring(index))
    if fname == "BuyTrainerService" then pcall(recordPurchase, env, saved, index) end
  end)
  hooked[fname] = ok or nil
  note("hooks: %s %s", fname, ok and "installed" or "FAILED to install")
end

local function hookTrainButton(env, saved)
  local btn = env.ClassTrainerTrainButton
  if hooked.trainButton or type(btn) ~= "table" or type(btn.HookScript) ~= "function" then return end
  local ok = pcall(btn.HookScript, btn, "PreClick", function()
    if not active() then return end
    pcall(ns.Probe.RecordInterception, "trainer", "Train button PreClick hook fired", saved)
    note("hook: Train button PreClick")
  end)
  hooked.trainButton = ok or nil
  note("hooks: Train button PreClick %s", ok and "installed" or "FAILED to install")
end

-- The talent UI is load-on-demand, so its frames do not exist until the player first opens it.
function Capture.TalentUI(env, saved)
  Capture.Talents(env, saved)
  for _, name in ipairs({ "PlayerTalentFrame", "TalentFrame" }) do
    local frame = env[name]
    if not hooked[name] and type(frame) == "table" and type(frame.HookScript) == "function" then
      local ok = pcall(frame.HookScript, frame, "OnShow", function()
        if not active() then return end
        note("event: %s shown", name)
        pcall(Capture.Talents, env, saved)
      end)
      hooked[name] = ok or nil
      note("hooks: %s OnShow %s", name, ok and "installed" or "FAILED to install")
    end
  end
  Capture.InstallHooks(env, saved)
end

-- The trainer filter is a modern dropdown (ClassTrainerFrame.FilterDropdown). Adding an entry through
-- Menu.ModifyMenu needs the menu's tag, which only exists while the menu is open, so record the
-- dropdown's own fields and the tags reported shortly after it is clicked. All UNVERIFIED API names.
local function openMenuTags(env)
  local menu = env.Menu
  if type(menu) ~= "table" or type(menu.GetOpenMenuTags) ~= "function" then return nil end
  local ok, tags = pcall(menu.GetOpenMenuTags)
  if not ok then return "error: " .. tostring(tags) end
  if type(tags) == "table" then
    local out = {}
    for k, v in pairs(tags) do out[#out + 1] = tostring(type(k) == "number" and v or k) end
    table.sort(out)
    return table.concat(out, ",")
  end
  return tostring(tags)
end

function Capture.Dropdown(env, saved)
  local frame = env.ClassTrainerFrame
  local dropdown = type(frame) == "table" and frame.FilterDropdown or nil
  if hooked.filterDropdown or type(dropdown) ~= "table" then return end
  local fields = {}
  pcall(function()
    for key, value in pairs(dropdown) do
      if type(key) == "string" then fields[#fields + 1] = key .. ":" .. type(value) end
    end
  end)
  table.sort(fields)
  local c = store(saved)
  c.filterDropdown = { fields = fields, tags = {} }
  if type(dropdown.HookScript) == "function" then
    local ok = pcall(dropdown.HookScript, dropdown, "OnClick", function()
      if not active() then return end
      local function record()
        local tags = openMenuTags(env)
        if tags then c.filterDropdown.tags[#c.filterDropdown.tags + 1] = tags end
        note("capture: open menu tags after clicking the filter: %s", tostring(tags))
      end
      local timer = env.C_Timer
      if type(timer) == "table" and type(timer.After) == "function" then pcall(timer.After, 0.05, record) else pcall(record) end
    end)
    hooked.filterDropdown = ok or nil
    note("hooks: filter dropdown OnClick %s", ok and "installed" or "FAILED to install")
  else
    hooked.filterDropdown = true
    note("hooks: filter dropdown has no HookScript (%d fields recorded)", #fields)
  end
end

-- Forever's trainer window lists its rows in a ScrollBox (ClassTrainerFrame.ScrollBox) instead of the
-- ClassTrainerSkillN buttons Classic Era has. Record what that list holds and what its row frames look like,
-- so row hiding and marks can be written against facts. All UNVERIFIED API names; every call is guarded.
local function scalarFields(t, limit)
  local out = {}
  pcall(function()
    for key, value in pairs(t) do
      local kind = type(value)
      if type(key) == "string" then
        if kind == "string" or kind == "number" or kind == "boolean" then
          out[#out + 1] = key .. "=" .. tostring(value)
        else
          out[#out + 1] = key .. ":" .. kind
        end
      end
    end
  end)
  table.sort(out)
  while #out > (limit or 40) do out[#out] = nil end
  return table.concat(out, " ")
end

function Capture.ModernTrainer(env, saved)
  local frame = env.ClassTrainerFrame
  local box = type(frame) == "table" and frame.ScrollBox or nil
  if type(box) ~= "table" then return end
  local m = { frameKeys = {}, boxKeys = {}, data = {}, frames = {} }
  pcall(function()
    for key, value in pairs(frame) do
      if type(key) == "string" and (type(value) == "function" or type(value) == "table") then
        m.frameKeys[#m.frameKeys + 1] = key .. ":" .. type(value)
      end
    end
  end)
  table.sort(m.frameKeys)
  pcall(function()
    for key, value in pairs(box) do
      if type(key) == "string" and type(value) ~= "table" or key == "ScrollTarget" then m.boxKeys[#m.boxKeys + 1] = key .. ":" .. type(value) end
    end
  end)
  table.sort(m.boxKeys)
  -- Methods that live on the frame's mixin (not in pairs(frame)) and may drive the list.
  pcall(function()
    local meta = getmetatable(frame)
    local index = type(meta) == "table" and meta.__index
    m.mixin = {}
    if type(index) == "table" then
      for key, value in pairs(index) do
        if type(key) == "string" and type(value) == "function" then m.mixin[#m.mixin + 1] = key end
      end
    end
    table.sort(m.mixin)
  end)
  -- Plain maps the frame keeps (display row <-> service index, collapsed categories).
  m.maps = {}
  for _, name in ipairs({ "displayIndexToSkillIndex", "skillIndexToDisplayIndex", "collapsedCategories" }) do
    pcall(function()
      local map, parts = frame[name], {}
      if type(map) == "table" then
        for k, v in pairs(map) do if #parts < 24 then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end end
        table.sort(parts)
      end
      m.maps[#m.maps + 1] = name .. ": " .. table.concat(parts, " ")
    end)
  end
  pcall(function()
    if type(box.GetDataProviderSize) == "function" then m.size = box:GetDataProviderSize() end
    if type(box.ForEachElementData) ~= "function" then return end
    box:ForEachElementData(function(element)
      if #m.data >= 14 then return end
      -- A tree node holds its payload behind GetData(); record that, not the node's own methods.
      local payload = element
      if type(element) == "table" and type(element.GetData) == "function" then
        local ok, d = pcall(element.GetData, element)
        if ok then payload = d end
      end
      m.data[#m.data + 1] = ("%s %s"):format(type(payload), type(payload) == "table" and scalarFields(payload, 20) or tostring(payload))
    end)
  end)
  pcall(function()
    if type(box.ForEachFrame) ~= "function" then return end
    box:ForEachFrame(function(row)
      if #m.frames >= 6 or type(row) ~= "table" then return end
      local data
      if type(row.GetElementData) == "function" then
        local ok, d = pcall(row.GetElementData, row)
        if ok and type(d) == "table" then
          if type(d.GetData) == "function" then
            local okData, payload = pcall(d.GetData, d)
            if okData and type(payload) == "table" then d = payload end
          end
          data = scalarFields(d, 20)
        end
      end
      m.frames[#m.frames + 1] = ("%s | data: %s | fields: %s"):format(
        type(row.GetObjectType) == "function" and tostring(row:GetObjectType()) or "?", tostring(data), scalarFields(row, 30))
    end)
  end)
  store(saved).modernTrainer = m
end

-- Lists the entries of the trainer's filter menu (and of any submenu) as they are built, so the export shows
-- where an added entry can go. Registered once; it records only while debug is on.
local function describeMenu(root, depth, out)
  if depth > 3 then return end
  for _, element in root:EnumerateElementDescriptions() do
    if type(element) == "table" then
      local text = type(element.GetText) == "function" and select(2, pcall(element.GetText, element)) or element.text
      out[#out + 1] = ("%s%s [%s]"):format(("  "):rep(depth), tostring(text), tostring(element.type or element.template or "?"))
      if type(element.HasElements) == "function" and element:HasElements() then describeMenu(element, depth + 1, out) end
    end
  end
end

function Capture.MenuEntries(env, saved)
  if hooked.menuEntries then return end
  local menu = env.Menu
  if type(menu) ~= "table" or type(menu.ModifyMenu) ~= "function" then return end
  hooked.menuEntries = pcall(menu.ModifyMenu, "MENU_TRAINER_FILTER", function(_, root)
    if not active() then return end
    local out = {}
    pcall(describeMenu, root, 0, out)
    store(saved).menuEntries = out
    note("capture: trainer filter menu has %d entries", #out)
  end)
end

-- Runs fn shortly after the current event, once the client has finished filling the window.
function Capture.Later(env, fn)
  local timer = env.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then pcall(timer.After, 0.3, fn) else pcall(fn) end
end

function Capture.InstallHooks(env, saved)
  pcall(Capture.MenuEntries, env, saved)
  pcall(Capture.ModernTrainer, env, saved)
  pcall(Capture.Dropdown, env, saved)
  for _, fname in ipairs(Capture.HookedFunctions) do hookFunction(env, saved, fname) end
  hookTrainButton(env, saved)
end

---------------------------------------------------------------------------
-- Events

local handlers = {
  TRAINER_SHOW = function(env, saved)
    Capture.InstallHooks(env, saved)
    Capture.Trainer(env, saved)
    Capture.Later(env, function() pcall(Capture.ModernTrainer, env, saved) end)
  end,
  TRAINER_UPDATE = function(env, saved)
    -- The trainer UI is load-on-demand, so its button and refresh function may not exist at
    -- TRAINER_SHOW on the first open. Hooks are idempotent, so retry on every update.
    Capture.InstallHooks(env, saved)
    Capture.Trainer(env, saved)
    Capture.Later(env, function() pcall(Capture.ModernTrainer, env, saved) end)
  end,
  TRAINER_CLOSED = function() end,
  CONFIRM_TALENT_WIPE = function(env, saved, cost, respecs)
    pcall(ns.Probe.RecordRespecQuote, respecs, cost, saved)
    note("capture: respec quote cost=%s respecs=%s", tostring(cost), tostring(respecs))
  end,
  CHARACTER_POINTS_CHANGED = function(env, saved)
    Capture.InstallHooks(env, saved)
    Capture.Talents(env, saved)
  end,
  PLAYER_TALENT_UPDATE = function(env, saved)
    Capture.Talents(env, saved)
  end,
  -- Event name is a Classic-family guess (UNVERIFIED); registration is failure-tolerant.
  CONFIRM_PET_UNLEARN = function(env, saved, cost)
    local q = store(saved).petResetQuotes
    q[#q + 1] = { t = now(), cost = cost }
    while #q > 50 do table.remove(q, 1) end
    note("capture: pet reset quote cost=%s", tostring(cost))
  end,
  ADDON_LOADED = function(env, saved, name)
    if name == "Blizzard_TalentUI" then
      note("event: talent UI loaded")
      Capture.TalentUI(env, saved)
    end
  end,
  CRAFT_SHOW = function(env, saved) Capture.Beast(env, saved) end,
  CRAFT_UPDATE = function(env, saved) Capture.Beast(env, saved) end,
}

function Capture.OnEvent(env, saved, event, ...)
  if not active() then return end
  local c = store(saved)
  if not Capture.QuietEvents[event] then
    c.events[event] = (c.events[event] or 0) + 1
    note("event: %s", event)
  end
  local handler = handlers[event]
  if handler then
    local ok, err = pcall(handler, env, saved, ...)
    if not ok then note("capture: %s handler failed: %s", event, tostring(err)) end
  end
end

-- addon must embed AceEvent-3.0. Handlers return immediately while debug logging is off.
function Capture.Enable(addon, env, saved)
  env = env or _G
  local failures = store(saved).eventFailures
  for event in pairs(handlers) do
    -- An event the client does not know can raise on registration; skip it and remember which.
    local ok = pcall(addon.RegisterEvent, addon, event, function(_, ...) Capture.OnEvent(env, saved, event, ...) end)
    if not ok then failures[#failures + 1] = event end
  end
  pcall(Capture.InstallHooks, env, saved)
end

---------------------------------------------------------------------------
-- Report

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function Capture.Lines(saved)
  local c = store(saved or {})
  local lines = {}
  local events = sortedKeys(c.events)
  if #events == 0 then
    lines[#lines + 1] = "  nothing captured (turn on /ddt debug on, then open a trainer or the talent window)"
  end
  for _, e in ipairs(events) do lines[#lines + 1] = ("  event %s x%d"):format(e, c.events[e]) end
  for _, name in ipairs(sortedKeys(c.trainers)) do
    local tr = c.trainers[name]
    lines[#lines + 1] = ("  trainer %q (t=%s, %d services)"):format(name, tostring(tr.t), #tr.services)
    if tr.filters then
      lines[#lines + 1] = ("    type filters: available=%s unavailable=%s used=%s"):format(
        tr.filters.available, tr.filters.unavailable, tr.filters.used)
    end
    for _, h in ipairs(tr.headers or {}) do
      lines[#lines + 1] = ("    header #%d %s"):format(h.index, tostring(h.name))
    end
    for _, l in ipairs(ns.Probe.ServiceLines(tr.services)) do lines[#lines + 1] = "  " .. l end
  end
  if c.talents then
    lines[#lines + 1] = ("  talents (t=%s, %s, unspent=%s)"):format(tostring(c.talents.t),
      c.talents.ok and "ok" or tostring(c.talents.reason), tostring(c.talents.unspent))
    for _, t in ipairs(c.talents.trees or {}) do
      lines[#lines + 1] = t.error and ("    tree %d error: %s"):format(t.index, t.error)
        or ("    tree %d %s: %s points"):format(t.index, tostring(t.name), tostring(t.points))
    end
  end
  if c.filterDropdown then
    local d = c.filterDropdown
    lines[#lines + 1] = "  trainer filter dropdown fields: " .. (#d.fields > 0 and table.concat(d.fields, " ") or "none")
    if #d.tags == 0 then
      lines[#lines + 1] = "  open menu tags after clicking the filter: none recorded (click the filter with debug on)"
    end
    for _, tags in ipairs(d.tags) do lines[#lines + 1] = "  open menu tags after clicking the filter: " .. tags end
  end
  if c.menuEntries then
    lines[#lines + 1] = "  trainer filter menu entries (as built, our own entry included):"
    for _, line in ipairs(c.menuEntries) do lines[#lines + 1] = "    " .. line end
  end
  if c.modernTrainer then
    local m = c.modernTrainer
    lines[#lines + 1] = ("  trainer ScrollBox: data provider size=%s"):format(tostring(m.size))
    lines[#lines + 1] = "    ClassTrainerFrame members: " .. (#m.frameKeys > 0 and table.concat(m.frameKeys, " ") or "none")
    lines[#lines + 1] = "    ScrollBox members: " .. (#m.boxKeys > 0 and table.concat(m.boxKeys, " ") or "none")
    lines[#lines + 1] = "    ClassTrainerFrame mixin methods: " .. (#(m.mixin or {}) > 0 and table.concat(m.mixin, " ") or "none")
    for _, line in ipairs(m.maps or {}) do lines[#lines + 1] = "    " .. line end
    for _, d in ipairs(m.data) do lines[#lines + 1] = "    data " .. d end
    for _, f in ipairs(m.frames) do lines[#lines + 1] = "    row frame " .. f end
  end
  if c.trainerRows then
    local tr = c.trainerRows
    lines[#lines + 1] = ("  trainer window rows after the last refresh (scroll offset=%s):"):format(tostring(tr.offset))
    for _, r in ipairs(tr.rows) do
      lines[#lines + 1] = ("    ClassTrainerSkill%d shown=%s id=%s text=%s sub=%s"):format(
        r.n, tostring(r.shown), tostring(r.id), tostring(r.text), tostring(r.sub))
    end
  end
  if #c.eventFailures > 0 then
    table.sort(c.eventFailures)
    lines[#lines + 1] = "  events this client rejected: " .. table.concat(c.eventFailures, ", ")
  end
  for _, q in ipairs(c.petResetQuotes) do
    lines[#lines + 1] = ("  pet reset quote: cost=%s t=%s"):format(tostring(q.cost), tostring(q.t))
  end
  for _, p in ipairs(c.popups) do
    lines[#lines + 1] = ("  popup %s text1=%s text2=%s t=%s"):format(p.which, tostring(p.text1), tostring(p.text2), tostring(p.t))
  end
  if c.beast then
    local b = c.beast
    lines[#lines + 1] = ("  craft window %q (t=%s, %d rows, training points total=%s spent=%s)"):format(
      tostring(b.skillLine), tostring(b.t), #b.rows, tostring(b.trainingPoints.total), tostring(b.trainingPoints.spent))
    for _, r in ipairs(b.rows) do
      lines[#lines + 1] = ("    #%d %s %s type=%s points=%s level=%s"):format(
        r.index, tostring(r.name), tostring(r.sub or ""), tostring(r.kind), tostring(r.points), tostring(r.level))
    end
  end
  for _, p in ipairs(c.purchases) do
    lines[#lines + 1] = ("  purchase #%s %s %s cost=%s t=%s"):format(tostring(p.index), tostring(p.name),
      tostring(p.subText), tostring(p.cost), tostring(p.t))
  end
  return lines
end
