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

test("on the Forever window BuyTrainerService is wrapped: flagged asks, others pass", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  env.ClassTrainerFrame.ScrollBox = {}
  local original = button.script
  env.BuyTrainerService = function(i) rec.bought[#rec.bought + 1] = i end
  truthy(ns.TrainerConfirm.Install(env))
  truthy(button.script == original, "click handler untouched")
  env.BuyTrainerService(3)
  eq(rec.bought, { 3 }, "an unflagged service goes straight through")
  env.BuyTrainerService(5)
  eq(#rec.asks, 1)
  eq(#rec.bought, 1, "held until answered")
  rec.asks[1].confirm()
  eq(rec.bought, { 3, 5 })
  env.BuyTrainerService(5)
  rec.asks[2].cancel()
  eq(#rec.bought, 2, "declined")
end)

test("a block while the confirmed purchase runs switches prompting off and restores BuyTrainerService", function()
  local ns, env, button, rec = setup({ verdicts = { [5] = DEFER } })
  env.ClassTrainerFrame.ScrollBox = {}
  local handlers = {}
  local buy = function() handlers.ADDON_ACTION_FORBIDDEN("event", "DontDoThat", "UNKNOWN()") end
  env.BuyTrainerService = buy
  ns.TrainerConfirm.Install(env)
  ns.TrainerConfirm.Watch({ RegisterEvent = function(_, event, fn) handlers[event] = fn end })
  env.BuyTrainerService(5)
  falsy(ns.TrainerConfirm.DisabledReason(), "nothing has run yet")
  rec.asks[1].confirm()
  truthy(ns.TrainerConfirm.DisabledReason())
  truthy(env.BuyTrainerService == buy, "game's own call restored")
end)
