package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local function setup(opts)
  opts = opts or {}
  local ns = { Log = { Add = function() end } }
  local rec = { alerts = {}, alertSettings = {}, banners = {}, asks = {}, bought = {} }
  ns.TrainerOverlay = { Compute = function()
    if opts.computeError then error("boom") end
    return { verdicts = opts.verdicts or {} }
  end }
  ns.Alert = { Trigger = function(verdict, key, settings)
    rec.alerts[#rec.alerts + 1] = key
    rec.alertSettings[#rec.alertSettings + 1] = settings
  end }
  ns.AlertBanner = { Show = function(verdict) rec.banners[#rec.banners + 1] = verdict.name end }
  ns.ConfirmPopup = { Ask = function(verdict, onConfirm, onCancel)
    if opts.noPrompt then return false end
    rec.asks[#rec.asks + 1] = { verdict = verdict, confirm = onConfirm, cancel = onCancel }
    return true
  end }
  H.load("DontDoThat/Intercepts/Confirm.lua", ns)
  ns.TrainerConfirm.Reset()
  ns.db = opts.profile and { profile = opts.profile } or nil

  local button = { script = nil }
  button.GetScript = function(self, name) return name == "OnClick" and self.script or nil end
  button.SetScript = function(self, name, fn) if name == "OnClick" then self.script = fn end end
  button.script = function(self, ...) rec.bought[#rec.bought + 1] = { ... } end
  local env = { ClassTrainerTrainButton = button, ClassTrainerFrame = { selectedService = opts.selected or 5 } }
  if opts.useApi then env.ClassTrainerFrame = {}; env.GetTrainerSelectionIndex = function() return opts.selected or 5 end end
  return ns, env, button, rec
end

local DEFER = { tier = "defer", name = "Distracting Shot", cost = 600, reason = "Only needed in groups." }

test("install wraps the Train button once", function()
  local ns, env, button = setup()
  local original = button.script
  truthy(ns.TrainerConfirm.Install(env))
  truthy(button.script ~= original)
  local wrapped = button.script
  truthy(ns.TrainerConfirm.Install(env))
  truthy(button.script == wrapped, "not wrapped twice")
end)

test("install does nothing until the button exists", function()
  local ns, env = setup()
  env.ClassTrainerTrainButton = nil
  falsy(ns.TrainerConfirm.Install(env))
  local ns2, env2, button2 = setup()
  button2.script = nil
  falsy(ns2.TrainerConfirm.Install(env2))
end)

test("a flagged purchase alerts and asks; the original runs only on confirm", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  ns.TrainerConfirm.Install(env)
  button.script(button, "LeftButton")
  eq(#rec.bought, 0, "held until answered")
  eq(#rec.asks, 1)
  eq(rec.alerts, { "trainer:Distracting Shot" })
  eq(rec.alertSettings[1].alertBanner, false, "the dialog replaces the banner, so sound only")
  eq(#rec.banners, 0)
  rec.asks[1].confirm()
  eq(rec.bought, { { "LeftButton" } }, "original runs with the same arguments")
end)

test("declining never runs the original", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  rec.asks[1].cancel()
  eq(#rec.bought, 0)
end)

test("kept, optional and low-value rows go straight through without a prompt", function()
  for _, tier in ipairs({ "keep", "info", "deferLow" }) do
    local ns, env, button, rec = setup({ verdicts = { [5] = { tier = tier, name = "X" } } })
    ns.TrainerConfirm.Install(env)
    button.script(button)
    eq(#rec.bought, 1, tier)
    eq(#rec.asks, 0, tier)
  end
end)

test("a service with no verdict goes straight through", function()
  local ns, env, button, rec = setup({ verdicts = {} })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.bought, 1)
end)

test("turning the addon off lets everything through silently", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER }, profile = { enabled = false } })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.bought, 1); eq(#rec.asks, 0); eq(#rec.alerts, 0)
end)

test("with confirmations off the purchase goes ahead but still alerts, banner included", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER }, profile = { blockingConfirmations = false } })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.bought, 1); eq(#rec.asks, 0)
  eq(#rec.alerts, 1)
  eq(rec.alertSettings[1].alertBanner, true)
end)

test("the banner setting and the alerts setting are passed on", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER },
    profile = { blockingConfirmations = false, alerts = false, alert = { banner = false, cooldown = 9 } } })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(rec.alertSettings[1].alertsEnabled, false)
  eq(rec.alertSettings[1].alertBanner, false)
  eq(rec.alertSettings[1].alertCooldown, 9)
end)

test("when no prompt can be shown the purchase is not blocked", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER }, noPrompt = true })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.bought, 1)
  eq(rec.banners, { "Distracting Shot" }, "the banner stands in for the missing dialog")
end)

test("an error while deciding never blocks the purchase", function()
  local ns, env, button, rec = setup({ computeError = true })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.bought, 1)
  eq(#rec.asks, 0)
end)

test("the selection can come from the client API when the frame field is absent", function()
  local ns, env, button, rec = setup({ verdicts = { [7] = DEFER }, useApi = true, selected = 7 })
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.asks, 1)
end)

test("no known selection lets the click through", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  env.ClassTrainerFrame = {}
  ns.TrainerConfirm.Install(env)
  button.script(button)
  eq(#rec.bought, 1)
end)

test("if the client blocks our addon, prompting switches off and purchases flow", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  ns.TrainerConfirm.Install(env)
  local handlers = {}
  ns.TrainerConfirm.Watch({ RegisterEvent = function(_, event, fn) handlers[event] = fn end })
  truthy(handlers.ADDON_ACTION_FORBIDDEN)
  handlers.ADDON_ACTION_FORBIDDEN("event", "SomeOtherAddon", "Foo")
  falsy(ns.TrainerConfirm.DisabledReason(), "other addons are ignored")
  handlers.ADDON_ACTION_FORBIDDEN("event", "DontDoThat", "BuyTrainerService")
  truthy(ns.TrainerConfirm.DisabledReason())
  button.script(button)
  eq(#rec.bought, 1)
  eq(#rec.asks, 0)
end)

test("a block from another guard (UNKNOWN() with no trainer purchase running) leaves trainer prompts on", function()
  local ns = setup({ verdicts = { [5] = DEFER } })
  local handlers = {}
  ns.TrainerConfirm.Watch({ RegisterEvent = function(_, event, fn) handlers[event] = fn end })
  handlers.ADDON_ACTION_FORBIDDEN("event", "DontDoThat", "UNKNOWN()")
  falsy(ns.TrainerConfirm.DisabledReason())
end)

test("on the Forever window the button is only hooked, never replaced", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  env.ClassTrainerFrame.ScrollBox = {}
  local original, pre = button.script, nil
  button.HookScript = function(_, name, fn) if name == "PreClick" then pre = fn end end
  truthy(ns.TrainerConfirm.Install(env))
  truthy(button.script == original, "click handler untouched")
  pre(button)
  eq(rec.alerts, { "trainer:Distracting Shot" })
  eq(#rec.asks, 0, "no question, so nothing can taint the purchase")
end)

test("when the client refuses us the button gets its own handler back", function()
  local ns, env, button = setup()
  local original = button.script
  ns.TrainerConfirm.Install(env)
  truthy(button.script ~= original)
  ns.TrainerConfirm.Disable("blocked: x")
  truthy(button.script == original)
end)

-- Forever: a window with a ScrollBox, a Train button that can be enabled, hooked and lit, a frame factory for the
-- overlay, and the game's own purchase. The selection is a display index; the map gives the service index.
local function foreverSetup(opts)
  opts = opts or {}
  local ns, env, button, rec = setup(opts)
  env.ClassTrainerFrame.ScrollBox = {}
  env.ClassTrainerFrame.displayIndexToSkillIndex = opts.map
  env.BuyTrainerService = function(i) rec.bought[#rec.bought + 1] = i end
  rec.hooks, rec.states, rec.popups = {}, {}, {}
  button.enabled = true
  button.IsEnabled = function(self) return self.enabled end
  button.HookScript = function(_, name, fn) rec.hooks[name] = fn end
  button.LockHighlight = function() rec.states[#rec.states + 1] = "lit" end
  button.UnlockHighlight = function() rec.states[#rec.states + 1] = "unlit" end
  button.SetButtonState = function(_, state) rec.states[#rec.states + 1] = state end
  env.StaticPopup_Show = function(which) rec.popups[#rec.popups + 1] = which end
  env.CreateFrame = function(kind, name, parent)
    local f = { kind = kind, parent = parent, scripts = {}, shown = true }
    f.SetAllPoints = function(self, to) self.anchoredTo = to end
    f.SetScript = function(self, handler, fn) self.scripts[handler] = fn end
    f.SetShown = function(self, shown) self.shown = shown end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    rec.overlay = f
    return f
  end
  local beast = false
  ns.Adapter = { IsBeastTraining = function() return beast end }
  rec.setBeast = function(v) beast = v end
  return ns, env, button, rec
end

test("on the Forever window the game's BuyTrainerService is never written, not even to put it back", function()
  local ns, env, button, rec = foreverSetup({ verdicts = { [5] = DEFER } })
  local buy, original = env.BuyTrainerService, button.script
  truthy(ns.TrainerConfirm.Install(env))
  truthy(env.BuyTrainerService == buy, "the game's function is untouched")
  truthy(button.script == original, "click handler untouched")
  -- A click that reaches Blizzard's button (overlay away, keyboard) only warns.
  rec.hooks.PreClick(button)
  eq(rec.alerts, { "trainer:Distracting Shot" })
  eq(#rec.asks, 0, "no question from the hook, so nothing can taint the purchase")
  eq(#rec.bought, 0, "the click itself is the game's")
  -- Beast training, then another trainer: still nothing of the game's is written, and the hook is not doubled.
  rec.setBeast(true)
  falsy(ns.TrainerConfirm.Install(env))
  truthy(env.BuyTrainerService == buy)
  truthy(button.script == original)
  rec.setBeast(false)
  local hooks = 0
  button.HookScript = function() hooks = hooks + 1 end
  truthy(ns.TrainerConfirm.Install(env))
  eq(hooks, 0, "hooked once")
  truthy(env.BuyTrainerService == buy)
end)

test("Forever: the question comes from the addon's own button over Train, and the addon buys on confirm", function()
  local ns, env, button, rec = foreverSetup({ verdicts = { [5] = DEFER } })
  truthy(ns.TrainerConfirm.Install(env))
  local overlay = rec.overlay
  truthy(overlay and overlay.parent == button and overlay.anchoredTo == button, "laid over the Train button")
  eq(overlay.kind, "Button")
  truthy(overlay.shown, "shown while Train is enabled")
  overlay.scripts.OnClick(overlay)
  eq(#rec.bought, 0, "held until answered")
  eq(#rec.asks, 1)
  eq(rec.alerts, { "trainer:Distracting Shot" })
  rec.asks[1].confirm()
  eq(rec.bought, { 5 }, "the addon makes the purchase itself, for the selected service")
  overlay.scripts.OnClick(overlay)
  rec.asks[2].cancel()
  eq(rec.bought, { 5 }, "declining buys nothing")
  -- A spell nothing flags is bought at once, with no question.
  env.ClassTrainerFrame.selectedService = 3
  overlay.scripts.OnClick(overlay)
  eq(rec.bought, { 5, 3 })
  eq(#rec.asks, 2)
  -- Nothing selected: nothing happens, as with Blizzard's button.
  env.ClassTrainerFrame.selectedService = nil
  overlay.scripts.OnClick(overlay)
  eq(rec.bought, { 5, 3 })
end)

test("Forever: the selection is a display index, mapped to the service index for the verdict and the purchase", function()
  local ns, env, button, rec = foreverSetup({ verdicts = { [7] = DEFER }, selected = 2, map = { [2] = 7 } })
  ns.TrainerConfirm.Install(env)
  rec.overlay.scripts.OnClick(rec.overlay)
  eq(#rec.asks, 1, "the verdict is looked up by service index 7, not display index 2")
  rec.asks[1].confirm()
  eq(rec.bought, { 7 })
  -- The hook on Blizzard's button reads it the same way.
  rec.hooks.PreClick(button)
  eq(rec.alerts, { "trainer:Distracting Shot", "trainer:Distracting Shot" })
  -- Without a map the selection is the service index itself (Classic Era).
  env.ClassTrainerFrame.displayIndexToSkillIndex = nil
  env.ClassTrainerFrame.selectedService = 7
  rec.overlay.scripts.OnClick(rec.overlay)
  eq(#rec.asks, 2)
end)

test("Forever: the overlay follows Blizzard's button and stays away from beast training", function()
  local ns, env, button, rec = foreverSetup({ verdicts = { [5] = DEFER } })
  ns.TrainerConfirm.Install(env)
  local overlay = rec.overlay
  truthy(rec.hooks.OnEnable and rec.hooks.OnDisable, "follows the button's own enable and disable")
  button.enabled = false
  rec.hooks.OnDisable(button)
  falsy(overlay.shown, "hidden while Train is disabled, so its disabled look and tooltip are Blizzard's")
  button.enabled = true
  rec.hooks.OnEnable(button)
  truthy(overlay.shown)
  -- Beast training: away. The next trainer: back, and the overlay is not made twice.
  rec.setBeast(true)
  falsy(ns.TrainerConfirm.Install(env))
  falsy(overlay.shown)
  rec.setBeast(false)
  truthy(ns.TrainerConfirm.Install(env))
  truthy(overlay.shown)
  truthy(rec.overlay == overlay, "one overlay")
  -- A redraw of the window syncs it too.
  button.enabled = false
  ns.TrainerConfirm.Sync(env)
  falsy(overlay.shown)
  -- With "Ask before buying" off there is nothing to ask, so Blizzard's button takes the clicks (and the hook warns).
  button.enabled = true
  ns.db = { profile = { blockingConfirmations = false } }
  ns.TrainerConfirm.Sync(env)
  falsy(overlay.shown)
  ns.db = nil
  ns.TrainerConfirm.Sync(env)
  truthy(overlay.shown)
end)

test("Forever: the overlay lights and presses Blizzard's button for it, and buys through its profession dialog", function()
  local ns, env, button, rec = foreverSetup({ verdicts = {} })
  ns.TrainerConfirm.Install(env)
  local o = rec.overlay
  o.scripts.OnEnter(o); o.scripts.OnMouseDown(o); o.scripts.OnMouseUp(o); o.scripts.OnLeave(o)
  eq(rec.states, { "lit", "PUSHED", "NORMAL", "unlit", "NORMAL" })
  -- A new profession: Blizzard asks its own question first, through its dialog, as its handler does.
  env.IsTradeskillTrainer = function() return true end
  env.ClassTrainerFrame.showDialog = true
  o.scripts.OnClick(o)
  eq(rec.popups, { "CONFIRM_PROFESSION" })
  eq(#rec.bought, 0)
  env.ClassTrainerFrame.showDialog = nil
  o.scripts.OnClick(o)
  eq(rec.bought, { 5 })
end)

test("Forever: a blocked purchase takes the overlay away, so Blizzard's button is back", function()
  local ns, env, button, rec = foreverSetup({ verdicts = { [5] = DEFER } })
  ns.TrainerConfirm.Install(env)
  _G.DEFAULT_CHAT_FRAME = nil
  ns.TrainerConfirm.Disable("blocked: BuyTrainerService()")
  falsy(rec.overlay.shown)
end)

test("Forever: without a frame factory the hook alone is installed", function()
  local ns, env, button, rec = foreverSetup({ verdicts = { [5] = DEFER } })
  env.CreateFrame = nil
  truthy(ns.TrainerConfirm.Install(env))
  eq(rec.overlay, nil)
  truthy(rec.hooks.PreClick)
end)
