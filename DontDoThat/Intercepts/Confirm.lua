local addonName, ns = ...
local L = ns.L

-- Asks before a flagged purchase at a trainer. For a spell the rules fully defer, the player gets a loud alert
-- and a "Buy anyway?" prompt, and the purchase goes ahead only on confirm. Everything else passes straight
-- through. On Classic Era the Train button's click is wrapped and the original handler runs on confirm; on
-- Forever the addon's own button sits over Train and makes the purchase itself (see the Forever section).
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
local overlay, overlayEnv -- the addon's button over the Train button (Forever), once created

function Confirm.Reset()
  installed = false
  restore = nil
  disabledReason = nil
  overlay, overlayEnv = nil, nil
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

-- The selected service's index, the one the trainer API and the verdicts count by. Forever's window numbers its
-- selection by place in the list and keeps the map back to the service index (ClassTrainer_GetSkillIndexForDisplayIndex
-- in its source); Classic Era's selection is the service index itself.
local function selectedIndex(env)
  local frame = env.ClassTrainerFrame
  if type(frame) == "table" and type(frame.selectedService) == "number" then
    local map = frame.displayIndexToSkillIndex
    local index = type(map) == "table" and map[frame.selectedService]
    return type(index) == "number" and index or frame.selectedService
  end
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

-- WoW Forever's trainer window (a ScrollBox list). Nothing of the game's is written there, because any write
-- marks it as the addon's: replacing the Train button's click handler, or the global BuyTrainerService, taints
-- the purchase, and so does putting the original back afterwards. Blizzard's own handler then runs tainted and
-- the game refuses BuyTrainerService for a service paid in training points (beast training), with
-- "AddOn 'DontDoThat' tried to call the protected function 'UNKNOWN()'". Gold purchases are not protected, so
-- a class trainer never shows it.
--
-- So the question is asked from a button of the addon's own, laid over Blizzard's Train button: the click lands
-- on ours, and on confirm (or at once, for a spell nothing flags) the addon makes the gold purchase itself, the
-- way Blizzard's handler does (ClassTrainerTrainButton_OnClick in its source), reading the selection and never
-- writing it. The overlay is shown only while Blizzard's button is enabled, and never over beast training, whose
-- purchases cost training points and cannot be made from addon code at all. Blizzard's button is also hooked
-- (PreClick), so a flagged spell still gets its warning when a click reaches it: with the overlay away, or from
-- the keyboard.
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

-- Makes the purchase as Blizzard's Train handler would: its own dialog first for a new profession, else the service.
local function buy(env, skillIndex)
  local frame = env.ClassTrainerFrame
  local okT, tradeskill = pcall(env.IsTradeskillTrainer)
  if okT and tradeskill and type(frame) == "table" and frame.showDialog and type(env.StaticPopup_Show) == "function" then
    return env.StaticPopup_Show("CONFIRM_PROFESSION")
  end
  if type(env.BuyTrainerService) == "function" then return env.BuyTrainerService(skillIndex) end
end

-- A click on the overlay: the question for a flagged service, the purchase for any other.
function Confirm.OverlayClick(env)
  env = env or _G
  local ok, verdict, index = pcall(Confirm.Decide, env)
  if not ok then
    if ns.Log then ns.Log.Add("confirm: decision failed: %s", tostring(verdict)) end
    verdict = nil
  end
  index = index or selectedIndex(env)
  if not index then return end -- nothing selected: Blizzard's button would do nothing either
  local function proceed(skillIndex) return buy(env, skillIndex) end
  if not verdict then return proceed(index) end
  return run(env, verdict, proceed, index)
end

-- Whether the overlay should be taking the clicks right now: only while it can ask, and while Blizzard's button
-- would take them too.
local function overlayWanted(env)
  if not addonEnabled() or not promptsEnabled() then return false end
  if ns.Adapter and ns.Adapter.IsBeastTraining(env) then return false end
  local button = env.ClassTrainerTrainButton
  if type(button) ~= "table" then return false end
  if type(button.IsEnabled) ~= "function" then return true end
  local ok, enabled = pcall(button.IsEnabled, button)
  return ok and enabled and true or false
end

-- Shows or hides the overlay to match Blizzard's button. Runs as each trainer opens, after each redraw of the
-- window, and after Blizzard enables or disables the button.
function Confirm.Sync(env)
  env = env or overlayEnv or _G
  if not overlay then return end
  pcall(overlay.SetShown, overlay, overlayWanted(env))
end

local function createOverlay(env, button)
  if overlay then return true end
  if type(env.CreateFrame) ~= "function" then return false end
  local ok, frame = pcall(env.CreateFrame, "Button", nil, button)
  if not ok or type(frame) ~= "table" then return false end
  local okSetup = pcall(function()
    frame:SetAllPoints(button)
    frame:SetScript("OnClick", function() Confirm.OverlayClick(env) end)
    -- Blizzard's button never sees the mouse now, so it is shown highlighted and pressed by hand.
    frame:SetScript("OnEnter", function() pcall(button.LockHighlight, button) end)
    frame:SetScript("OnLeave", function()
      pcall(button.UnlockHighlight, button)
      pcall(button.SetButtonState, button, "NORMAL")
    end)
    frame:SetScript("OnMouseDown", function() pcall(button.SetButtonState, button, "PUSHED") end)
    frame:SetScript("OnMouseUp", function() pcall(button.SetButtonState, button, "NORMAL") end)
  end)
  if not okSetup then pcall(frame.Hide, frame); return false end
  overlay, overlayEnv = frame, env
  -- Follow Blizzard's button as it is enabled and disabled. Its scripts are only hooked, never replaced.
  if type(button.HookScript) == "function" then
    pcall(button.HookScript, button, "OnEnable", function() Confirm.Sync(env) end)
    pcall(button.HookScript, button, "OnDisable", function() Confirm.Sync(env) end)
  end
  if type(env.hooksecurefunc) == "function" and type(env.ClassTrainerFrame_SetTrainButtonEnabled) == "function" then
    pcall(env.hooksecurefunc, "ClassTrainerFrame_SetTrainButtonEnabled", function() Confirm.Sync(env) end)
  end
  return true
end

-- Wraps the Train button once. Safe to call repeatedly (the button only exists after the trainer
-- window first loads).
-- Beast training must stay untouched (Classic Era): the wrapped click taints the game's own purchase and it refuses
-- the ones that cost training points. So the wrapper is taken off for that window and put back for any other trainer.
function Confirm.Release()
  if restore then restore(); restore = nil; installed = false end
end

function Confirm.Install(env)
  env = env or _G
  if ns.Adapter and ns.Adapter.IsBeastTraining(env) then
    Confirm.Release()
    Confirm.Sync(env)
    return false
  end
  if installed then
    Confirm.Sync(env)
    return true
  end
  local button = env.ClassTrainerTrainButton
  if type(button) ~= "table" or type(button.GetScript) ~= "function" or type(button.SetScript) ~= "function" then return false end
  if modernWindow(env) and type(button.HookScript) == "function" then
    installed = pcall(button.HookScript, button, "PreClick", function(self) Confirm.WarnOnly(env, self) end)
    local overlaid = installed and createOverlay(env, button)
    Confirm.Sync(env)
    if ns.Log then
      ns.Log.Add("confirm: Forever window: Train button %s, question %s", installed and "hooked" or "NOT hooked",
        overlaid and "asked from the addon's own button" or "not asked (no overlay)")
    end
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
  Confirm.Sync()
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
