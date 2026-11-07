local addonName, ns = ...
local L = ns.L

-- Asks before a flagged purchase at a trainer. The Train button's click is wrapped: for a spell the
-- rules fully defer, the player gets a loud alert and a "Buy anyway?" prompt, and the original click
-- handler runs only on confirm. Everything else passes straight through to the original handler.
--
-- Blizzard's handler buys ClassTrainerFrame.selectedService (observed in its source). If this client
-- turns out to forbid that call from our confirm callback, the ADDON_ACTION_FORBIDDEN watcher switches
-- prompting off for the session, so the player is never left unable to buy.
local Confirm = {}
ns.TrainerConfirm = Confirm

local installed = false
local disabledReason
local confirming -- true while our callback runs the trainer's own purchase
local restore

function Confirm.Reset()
  installed = false
  restore = nil
  disabledReason = nil
end

function Confirm.DisabledReason() return disabledReason end

local function profile()
  return (ns.db and ns.db.profile) or {}
end

local function addonEnabled()
  return profile().enabled ~= false
end

local function promptsEnabled()
  return not disabledReason and profile().blockingConfirmations ~= false
end

-- The alert module's settings, mapped from the saved profile.
local function alertSettings()
  local p = profile()
  local a = p.alert or {}
  return { alertsEnabled = p.alerts ~= false, alertBanner = a.banner ~= false,
    alertSound = a.sound, alertCooldown = a.cooldown, alertChannel = a.channel }
end

Confirm.AlertSettings = alertSettings

-- Whether a rule verdict's tier is one the player asked to be prompted and warned about.
local function chosenTier(tier)
  if ns.Settings then return ns.Settings.PromptsFor(tier) end
  return tier == "defer"
end

local function selectedIndex(env)
  local frame = env.ClassTrainerFrame
  if type(frame) == "table" and type(frame.selectedService) == "number" then return frame.selectedService end
  if type(env.GetTrainerSelectionIndex) == "function" then
    local ok, index = pcall(env.GetTrainerSelectionIndex)
    if ok and type(index) == "number" then return index end
  end
end

-- Returns the verdict to alert or prompt about, or nil to let the click through.
function Confirm.Decide(env, index)
  if not addonEnabled() then return nil end
  index = index or selectedIndex(env)
  if not index then return nil end
  local computed = ns.TrainerOverlay.Compute(env)
  local verdict = computed and computed.verdicts[index]
  if verdict and chosenTier(verdict.tier) then return verdict, index end
  return nil
end

-- Asks about a flagged purchase. proceed(...) makes the purchase and is called with the same arguments on confirm.
local function run(env, verdict, proceed, ...)
  local key = "trainer:" .. tostring(verdict.name)
  local settings = alertSettings()
  if ns.Settings then settings.alertTiers = ns.Settings.PromptTiers() end

  if not promptsEnabled() then
    -- Alert only: sound and banner, and the purchase goes ahead.
    pcall(ns.Alert.Trigger, verdict, key, settings)
    return proceed(...)
  end

  -- The dialog says everything the banner would, so a prompt gets the sound alone.
  local args = { ... }
  local soundOnly = {}
  for k, v in pairs(settings) do soundOnly[k] = v end
  soundOnly.alertBanner = false
  pcall(ns.Alert.Trigger, verdict, key, soundOnly)
  local shown = false
  -- A profession is asked about once: either answer counts.
  local function markAsked()
    if verdict.source == "professionLearn" and ns.Settings then
      ns.Settings.MarkProfessionAsked(verdict.profession)
    end
  end
  pcall(function()
    shown = ns.ConfirmPopup.Ask(verdict,
      function()
        markAsked()
        if ns.Log then ns.Log.Add("confirm: bought %s anyway", tostring(verdict.name)) end
        confirming = true
        local okc, err = pcall(proceed, unpack(args))
        confirming = false
        if not okc then error(err, 0) end
      end,
      function()
        markAsked()
        if ns.Log then ns.Log.Add("confirm: declined %s", tostring(verdict.name)) end
      end)
  end)
  if not shown then
    -- Cannot prompt on this client: never block silently, and show the banner instead.
    if settings.alertBanner and settings.alertsEnabled and ns.AlertBanner then
      pcall(ns.AlertBanner.Show, verdict, verdict.name)
    end
    if ns.Log then ns.Log.Add("confirm: no prompt available for %s, letting it through", tostring(verdict.name)) end
    return proceed(...)
  end
end

-- original(self, ...) is the Train button's own handler.
function Confirm.Handle(env, original, button, ...)
  local ok, verdict = pcall(Confirm.Decide, env)
  if not ok or not verdict then
    if not ok and ns.Log then ns.Log.Add("confirm: decision failed: %s", tostring(verdict)) end
    return original(button, ...)
  end
  return run(env, verdict, function(...) return original(button, ...) end, ...)
end

-- WoW Forever's trainer window (a ScrollBox list). Replacing the Train button's click handler there taints the
-- purchase, and the game refuses BuyTrainerService (seen with the hunter's pet trainer), so no question is asked.
local function modernWindow(env)
  local frame = env.ClassTrainerFrame
  return type(frame) == "table" and type(frame.ScrollBox) == "table"
end

-- Warns (sound and banner) from a PreClick hook, which cannot taint or stop the purchase.
function Confirm.WarnOnly(env, button)
  local ok, verdict = pcall(Confirm.Decide, env)
  if not ok or not verdict then return end
  local settings = alertSettings()
  if ns.Settings then settings.alertTiers = ns.Settings.PromptTiers() end
  pcall(ns.Alert.Trigger, verdict, "trainer:" .. tostring(verdict.name), settings)
end

-- Wraps the Train button once. Safe to call repeatedly (the button only exists after the trainer
-- window first loads).
function Confirm.Install(env)
  env = env or _G
  if installed then return true end
  local button = env.ClassTrainerTrainButton
  if type(button) ~= "table" or type(button.GetScript) ~= "function" or type(button.SetScript) ~= "function" then return false end
  if modernWindow(env) then
    -- Forever: leave the button alone and wrap the game's own BuyTrainerService, as the vendor and auction purchases
    -- are wrapped. Falls back to the warning below when there is nothing to wrap.
    local buy = env.BuyTrainerService
    if type(buy) == "function" then
      local wrapper
      wrapper = function(index, ...)
        local ok, verdict = pcall(Confirm.Decide, env, index)
        if not ok or not verdict then return buy(index, ...) end
        return run(env, verdict, function(...) return buy(index, ...) end, ...)
      end
      env.BuyTrainerService = wrapper
      restore = function() if env.BuyTrainerService == wrapper then env.BuyTrainerService = buy end end
      installed = true
      if ns.Log then ns.Log.Add("confirm: BuyTrainerService wrapped (Forever window)") end
      return true
    end
  end
  if modernWindow(env) and type(button.HookScript) == "function" then
    installed = pcall(button.HookScript, button, "PreClick", function(self) Confirm.WarnOnly(env, self) end)
    if ns.Log then ns.Log.Add("confirm: Train button warns only (Forever window): %s", installed and "hooked" or "FAILED") end
    return installed
  end
  local okGet, original = pcall(button.GetScript, button, "OnClick")
  if not okGet or type(original) ~= "function" then return false end
  local okSet = pcall(button.SetScript, button, "OnClick", function(self, ...)
    return Confirm.Handle(env, original, self, ...)
  end)
  installed = okSet
  if okSet then restore = function() pcall(button.SetScript, button, "OnClick", original) end end
  if ns.Log then ns.Log.Add("confirm: Train button click %s", okSet and "wrapped" or "FAILED to wrap") end
  return okSet
end

-- If the client blocks our confirm callback from completing the purchase, stop prompting.
function Confirm.Disable(reason)
  disabledReason = reason
  -- Our click handler taints every later purchase too, so give the button its own back.
  if restore then restore(); restore = nil end
  if ns.Log then ns.Log.Add("confirm: prompts disabled (%s)", tostring(reason)) end
  if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
      L["Don't Do That: this game version won't let it confirm purchases, so it will only mark them."])
  end
end

function Confirm.Watch(eventTarget)
  for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(eventTarget.RegisterEvent, eventTarget, event, function(_, who, func)
      -- Blocks from other guards (bank, stable...) are theirs to handle; only a trainer purchase switches this off.
      if who == addonName and (confirming or tostring(func):find("Trainer", 1, true)) then
        Confirm.Disable("blocked: " .. tostring(func))
      end
    end)
  end
end

-- What `/ddt test` does: behaves exactly as a purchase of a deferred spell would with the current settings,
-- but buys nothing. say(text) reports what happened.
function Confirm.Test(say)
  local verdict = { tier = "defer", name = L["Distracting Shot"], cost = 600,
    reason = L["Pulls enemies off your tank. You only need it in groups and raids."] }
  local key = "test:" .. tostring(time and time() or 0)
  local settings = alertSettings()
  if not addonEnabled() then
    say(L["test: Don't Do That is turned off, so a purchase would go through with no warning."])
    return
  end
  if not promptsEnabled() then
    -- No question: the warning, then the purchase goes ahead.
    local fired = ns.Alert.Trigger(verdict, key, settings)
    say(fired and L["test: \"Ask before buying\" is off, so you'd get the warning and the purchase would go ahead."]
      or L["test: \"Ask before buying\" and the warning sound are both off, so nothing would happen."])
    return
  end
  local soundOnly = {}
  for k, v in pairs(settings) do soundOnly[k] = v end
  soundOnly.alertBanner = false
  pcall(ns.Alert.Trigger, verdict, key, soundOnly)
  local shown = ns.ConfirmPopup.Ask(verdict,
    function() say(L["test: you chose to buy it anyway (nothing was bought)"]) end,
    function() say(L["test: you declined"]) end)
  if not shown then say(L["test: this game version could not show the question"]) end
end
