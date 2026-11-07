local addonName, ns = ...
local L = ns.L

-- One-click gold sinks that the game guards with an "Are you sure?" dialog: talent resets, pet-skill resets,
-- bank slots, stable slots and COD mail. When the game opens its dialog for one, this plays the warning sound
-- and shows its own Accept / Cancel question (the same kind as "Buy anyway?"), then puts the game's dialog
-- away. Accepting calls the same function the game's own Accept calls; cancelling does what the game's Cancel
-- does. Skipped and done purchases are counted.
--
-- Dialog and function names are from Blizzard's own source for this client:
--   CONFIRM_TALENT_WIPE -> ConfirmTalentWipe()    CONFIRM_PET_UNLEARN -> ConfirmPetUnlearn()
--   CONFIRM_BUY_BANK_SLOT -> PurchaseSlot()       CONFIRM_BUY_STABLE_SLOT -> BuyStableSlot()
--   COD_CONFIRMATION -> TakeInboxItem(mail, attachment)    COD_CONFIRMATION_AUTO_LOOT -> AutoLootMailItem(index)
-- If the client ever refuses our call (ADDON_ACTION_FORBIDDEN), our question switches off for the session and
-- the game's own dialog is left alone with a note added, so these are never impossible.
--
-- A kind supplies: popups (dialog names), label, title, advice, ask (the closing question), rises (the price goes
-- up each time), and how it ends: avoided(state, cost), performed(state, cost). Its price comes from the
-- game's event (`event`) or from price(env, data) read as the dialog opens. Accepting runs accept(env, data,
-- which), or the global named confirmFn. `done` lists the globals the game's Accept calls, to count a purchase.
local Resets = {}
ns.Resets = Resets

local MARK = L["Don't Do That:"]

local KINDS = {
  talent = {
    popups = { "CONFIRM_TALENT_WIPE" }, confirmFn = "ConfirmTalentWipe", event = "CONFIRM_TALENT_WIPE", label = L["Talent reset"],
    title = L["Reset your talents?"], ask = L["Reset anyway?"], rises = true,
    advice = L["Resetting costs gold, and more each time you do it. Only do it if you really need to."],
    avoided = function(state) ns.Ledger.RecordRespecAvoided(state) end,
    performed = function(state, cost) ns.Ledger.RecordRespecPerformed(state, nil, cost) end,
    -- What the game's own Cancel does for this dialog.
    afterCancel = function(env)
      if type(env.PlayerTalentFrame) == "table" and type(env.HideUIPanel) == "function" then
        pcall(env.HideUIPanel, env.PlayerTalentFrame)
      end
    end,
  },
  pet = {
    popups = { "CONFIRM_PET_UNLEARN" }, confirmFn = "ConfirmPetUnlearn", event = "CONFIRM_PET_UNLEARN", label = L["Pet skill reset"],
    -- Forever has no pet-unlearn dialog or call: the pet trainer opens CONFIRM_TALENT_WIPE with pet text, and its Accept
    -- runs ConfirmTalentWipe (seen in the export). onPopupShown tells the two apart by the dialog text.
    done = { "ConfirmPetUnlearn", "ConfirmTalentWipe" },
    accept = function(env, _, which)
      if type(env.ConfirmPetUnlearn) == "function" then env.ConfirmPetUnlearn()
      elseif which == "CONFIRM_TALENT_WIPE" and type(env.ConfirmTalentWipe) == "function" then env.ConfirmTalentWipe() end
    end,
    title = L["Take every skill off your pet?"], ask = L["Reset anyway?"], rises = true,
    advice = L["Taking skills off your pet costs gold, and more each time. Only do it if you really need to."],
    avoided = function(state) ns.Ledger.RecordPetResetAvoided(state) end,
    performed = function(state, cost) ns.Ledger.RecordPetResetPerformed(state, nil, cost) end,
  },
  bank = {
    guard = "bank", popups = { "CONFIRM_BUY_BANK_SLOT" }, done = { "PurchaseSlot" }, label = L["Bank slot"],
    title = L["Buy another bank slot?"], ask = L["Buy anyway?"], rises = true,
    advice = L["Bank slots cost gold, and more each time. Only buy one if you really need the space."],
    price = function(env) return type(env.BankFrame) == "table" and env.BankFrame.nextSlotCost or nil end,
    accept = function(env) if type(env.PurchaseSlot) == "function" then env.PurchaseSlot() end end,
    avoided = function(state, cost) ns.Ledger.RecordItemAvoided(state, cost) end,
    performed = function(state, cost) ns.Ledger.RecordItemPerformed(state, cost) end,
  },
  stable = {
    guard = "stable", popups = { "CONFIRM_BUY_STABLE_SLOT" }, done = { "BuyStableSlot", "C_StableInfo.BuyStableSlot" }, label = L["Stable slot"],
    title = L["Buy another stable slot?"], ask = L["Buy anyway?"], rises = true,
    advice = L["Stable slots cost gold, and more each time. Only buy one if you really need to keep another pet."],
    price = function(env)
      local f = env.GetNextStableSlotCost or (type(env.C_StableInfo) == "table" and env.C_StableInfo.GetNextStableSlotCost)
      if type(f) ~= "function" then return nil end
      local ok, cost = pcall(f)
      return ok and cost or nil
    end,
    -- Forever moved the stable calls into C_StableInfo; the globals are gone there.
    accept = function(env)
      local f = env.BuyStableSlot or (type(env.C_StableInfo) == "table" and env.C_StableInfo.BuyStableSlot)
      if type(f) == "function" then f() end
    end,
    avoided = function(state, cost) ns.Ledger.RecordItemAvoided(state, cost) end,
    performed = function(state, cost) ns.Ledger.RecordItemPerformed(state, cost) end,
  },
  cod = {
    guard = "cod", popups = { "COD_CONFIRMATION", "COD_CONFIRMATION_AUTO_LOOT" },
    done = { "TakeInboxItem", "AutoLootMailItem" }, label = L["COD mail"],
    title = L["Pay for this mail?"], ask = L["Pay anyway?"], rises = false,
    advice = L["Paying a COD costs gold. Only pay it if you really want what's in the mail."],
    price = function(env) return type(env.OpenMailFrame) == "table" and env.OpenMailFrame.cod or nil end,
    -- Read when Accept is pressed, as the game does; skip quietly if the mail window is gone.
    accept = function(env, data, which)
      if which == "COD_CONFIRMATION_AUTO_LOOT" then
        if type(env.AutoLootMailItem) == "function" and data ~= nil then env.AutoLootMailItem(data) end
        return
      end
      if type(env.TakeInboxItem) == "function" and type(env.InboxFrame) == "table" and type(env.OpenMailFrame) == "table" then
        env.TakeInboxItem(env.InboxFrame.openMailID, env.OpenMailFrame.lastTakeAttachment)
      end
    end,
    avoided = function(state, cost) ns.Ledger.RecordItemAvoided(state, cost) end,
    performed = function(state, cost) ns.Ledger.RecordItemPerformed(state, cost) end,
  },
}

local KIND_OF = {}
for key, kind in pairs(KINDS) do
  for _, which in ipairs(kind.popups) do KIND_OF[which] = key end
end

local pending, shownFrame, lastQuote, seen = {}, {}, {}, {}
local disabledReason

function Resets.Reset() pending, shownFrame, lastQuote, seen, disabledReason = {}, {}, {}, {}, nil end
function Resets.DisabledReason() return disabledReason end

local function ledgerState()
  return ns.db and ns.db.char and ns.db.char.ledger
end

local function profile()
  return (ns.db and ns.db.profile) or {}
end

local function active(kind)
  if profile().enabled == false or profile().warnings == false then return false end
  if kind and kind.guard and (profile().guard or {})[kind.guard] == false then return false end
  return true
end

-- For /ddt export: which kinds are on, and what each showed when its dialog last opened this session.
function Resets.Status()
  local out = { switchedOffBy = disabledReason or "no" }
  for key, kind in pairs(KINDS) do
    out[key] = { on = active(kind), lastSeen = seen[key] or L["not seen this session"] }
  end
  return out
end

-- Our own question is used unless the player turned off "Ask before buying" or the client refused us once.
local function ownDialog()
  return not disabledReason and profile().blockingConfirmations ~= false
end

local function question(kind, cost)
  local price
  if type(cost) == "number" and cost > 0 then
    price = (L["This costs %s%s."]):format(ns.UIHelpers.FormatMoney(cost), kind.rises and L[", and the price goes up each time"] or "")
  else
    price = kind.rises and L["This costs gold, and more each time."] or L["This costs gold."]
  end
  local earn = ns.EarnBack and ns.EarnBack.Line(cost)
  return (L["%s\n\n%s You'll want that gold for your mount.%s\n\n%s"]):format(kind.title, price,
    earn and ("\n\n" .. earn) or "", kind.ask)
end

local function textObject(frame)
  if type(frame.text) == "table" then return frame.text end
  if type(frame.GetName) == "function" then
    local name = frame:GetName()
    if name and type(_G[name .. "Text"]) == "table" then return _G[name .. "Text"] end
  end
end

local function findFrame(env, which)
  if type(env.StaticPopup_Visible) == "function" then
    local ok, _, frame = pcall(env.StaticPopup_Visible, which)
    if ok and type(frame) == "table" then return frame end
  end
  for i = 1, 4 do
    local frame = env["StaticPopup" .. i]
    if type(frame) == "table" and frame.which == which then return frame end
  end
end

-- Fallback when our question cannot be used: leave the game's dialog and add our note to it.
local function annotate(env, frame, kind, which)
  local text = textObject(frame)
  if not text then return end
  local current = text:GetText()
  if not current or current:find(MARK, 1, true) then return end
  text:SetText(current .. "\n\n|cffff3333" .. MARK .. "|r " .. kind.advice)
  if type(env.StaticPopup_Resize) == "function" then pcall(env.StaticPopup_Resize, frame, which) end
end

local function countSkippedWhenClosed(kind, key, frame)
  if frame.dontdothatResets or type(frame.HookScript) ~= "function" then return end
  frame.dontdothatResets = true
  pcall(frame.HookScript, frame, "OnHide", function(self)
    if pending[key] and shownFrame[key] == self then
      pending[key] = nil
      local state = ledgerState()
      if state then kind.avoided(state, lastQuote[key]) end
      if ns.Log then ns.Log.Add("reset: %s skipped", kind.label) end
    end
  end)
end

local function warn(key, kind)
  if not (ns.Alert and ns.TrainerConfirm) then return end
  local settings = ns.TrainerConfirm.AlertSettings()
  settings.alertBanner = false -- there is always a dialog on screen with this
  pcall(ns.Alert.Trigger, { tier = "defer", name = kind.label, cost = lastQuote[key], reason = kind.advice },
    "reset:" .. key, settings)
end

local function present(env, key, kind, which, data)
  if pending[key] then return end
  pending[key] = true
  -- The price is either already known from the game's event, or read from the game now.
  if kind.price then
    local ok, cost = pcall(kind.price, env, data)
    lastQuote[key] = ok and type(cost) == "number" and cost or nil
  end
  if key == "pet" and not lastQuote.pet then lastQuote.pet = lastQuote.talent end -- Forever sends the talent-wipe event
  seen[key] = { dialog = which, price = lastQuote[key] or "unknown" }
  warn(key, kind)

  if ownDialog() then
    local shown = ns.ConfirmPopup.Show(question(kind, lastQuote[key]),
      function()
        if ns.Log then ns.Log.Add("reset: %s accepted", kind.label) end
        local ok, err
        if kind.accept then
          ok, err = pcall(kind.accept, env, data, which)
        else
          local fn = env[kind.confirmFn]
          if type(fn) ~= "function" then return end
          ok, err = pcall(fn)
        end
        if not ok and ns.Log then ns.Log.Add("reset: %s call failed: %s", kind.label, tostring(err)) end
      end,
      function()
        if not pending[key] then return end
        pending[key] = nil
        local state = ledgerState()
        if state then kind.avoided(state, lastQuote[key]) end
        if ns.Log then ns.Log.Add("reset: %s skipped", kind.label) end
        if kind.afterCancel then pcall(kind.afterCancel, env) end
      end)
    if shown then
      -- Ours is up, so put the game's away. Hiding it does not run its Cancel.
      if type(env.StaticPopup_Hide) == "function" then pcall(env.StaticPopup_Hide, which) end
      return
    end
  end

  -- Our question could not be used: keep the game's dialog, note the warning on it, and count how it ends.
  local frame = findFrame(env, which)
  if frame then
    shownFrame[key] = frame
    pcall(annotate, env, frame, kind, which)
    pcall(countSkippedWhenClosed, kind, key, frame)
  else
    pending[key] = nil
  end
end

-- Is this CONFIRM_TALENT_WIPE really the pet trainer's? Its text talks about the pet (the client's word for it, or English).
local function isPetWipe(env, which)
  local frame = findFrame(env, which)
  local text = frame and textObject(frame)
  local current = text and type(text.GetText) == "function" and text:GetText()
  if type(current) ~= "string" then return false end
  current = current:lower()
  return current:find("pet", 1, true) ~= nil or (type(env.PET) == "string" and current:find(env.PET:lower(), 1, true) ~= nil)
end

local function onPopupShown(env, which, data)
  local key = KIND_OF[which]
  if key == "talent" and isPetWipe(env, which) then key = "pet" end
  local kind = key and KINDS[key]
  if not kind or not active(kind) then return end
  if ns.Log then ns.Log.Add("reset: the game's %s dialog opened", kind.label) end
  -- The price arrives by event (or is read from the game) around the same moment; give it a frame so our text
  -- can include it.
  if type(env.C_Timer) == "table" and type(env.C_Timer.After) == "function" then
    pcall(env.C_Timer.After, 0, function() pcall(present, env, key, kind, which, data) end)
  else
    present(env, key, kind, which, data)
  end
end

-- The game's own function ran (from its Accept or from ours): count the purchase as done.
local function onConfirmed(key)
  if not pending[key] then return end
  pending[key] = nil
  local state = ledgerState()
  if state then KINDS[key].performed(state, lastQuote[key]) end
  if ns.Log then ns.Log.Add("reset: %s done", KINDS[key].label) end
end

local function refuse(env, func)
  disabledReason = "blocked: " .. tostring(func)
  if ns.Log then ns.Log.Add("reset: our question switched off (%s)", disabledReason) end
  if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
      "|cffff3333" .. L["Don't Do That:"] .. "|r " .. L["this game version won't let it confirm these for you. Try again; it will add a warning to the game's own question instead."])
  end
end

function Resets.Enable(eventTarget, env)
  env = env or _G
  if type(env.hooksecurefunc) ~= "function" then return false end

  if type(env.StaticPopup_Show) == "function" then
    pcall(env.hooksecurefunc, "StaticPopup_Show", function(which, _, _, data)
      local ok, err = pcall(onPopupShown, env, which, data)
      if not ok and ns.Log then ns.Log.Add("reset: dialog check failed: %s", tostring(err)) end
    end)
  end
  local watched = {}
  for key, kind in pairs(KINDS) do
    local fns = kind.done or { kind.confirmFn }
    for _, name in ipairs(fns) do
      watched[name] = true
      local owner, fname = name:match("^(.-)%.(.+)$") -- "C_StableInfo.BuyStableSlot"
      if owner then
        if type(env[owner]) == "table" and type(env[owner][fname]) == "function" then
          pcall(env.hooksecurefunc, env[owner], fname, function() pcall(onConfirmed, key) end)
        end
      elseif type(env[name]) == "function" then
        pcall(env.hooksecurefunc, name, function() pcall(onConfirmed, key) end)
      end
    end
    -- The quoted price arrives with the event; remember it for the dialog and the count.
    if kind.event then
      pcall(eventTarget.RegisterEvent, eventTarget, kind.event, function(_, cost)
        if type(cost) == "number" then lastQuote[key] = cost end
      end)
    end
  end
  for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(eventTarget.RegisterEvent, eventTarget, event, function(_, who, func)
      if who == addonName and watched[func] then refuse(env, func) end
    end)
  end
  return true
end
