package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- A fake game: StaticPopup_Show / hooksecurefunc / frames, enough to drive the guarded dialogs.
local function setup(profile)
  local ns = { }
  for _, f in ipairs({ "UI/Helpers.lua", "Data/GoldRates.lua", "Model/EarnBack.lua", "Model/Ledger.lua",
    "Intercepts/Resets.lua" }) do
    H.load("DontDoThat/" .. f, ns)
  end
  ns.db = { profile = profile or { enabled = true, warnings = true, blockingConfirmations = true },
    char = { ledger = ns.Ledger.NewState() } }
  local calls, shown = {}, {}
  local env
  env = {
    BankFrame = { nextSlotCost = 25000 },
    GetNextStableSlotCost = function() return 50000 end,
    OpenMailFrame = { cod = 700, lastTakeAttachment = 2 },
    InboxFrame = { openMailID = 5 },
    PurchaseSlot = function() calls[#calls + 1] = "PurchaseSlot" end,
    BuyStableSlot = function() calls[#calls + 1] = "BuyStableSlot" end,
    TakeInboxItem = function(a, b) calls[#calls + 1] = "TakeInboxItem:" .. a .. ":" .. b end,
    AutoLootMailItem = function(i) calls[#calls + 1] = "AutoLootMailItem:" .. i end,
    StaticPopup_Show = function() end,
    StaticPopup_Hide = function(which) calls[#calls + 1] = "hide:" .. which end,
    -- Runs `fn` after the named global, like the game's hooksecurefunc.
    hooksecurefunc = function(name, fn)
      local orig = env[name]
      env[name] = function(...) local r = orig(...); fn(...); return r end
    end,
  }
  ns.ConfirmPopup = { Show = function(text, yes, no) shown.text, shown.yes, shown.no = text, yes, no; return true end }
  ns.Resets.Enable({ RegisterEvent = function() end }, env)
  local function popup(which, data) env.StaticPopup_Show(which, nil, nil, data) end
  return ns, env, shown, calls, popup
end

test("bank slot: question shows the price and earn-back, decline counts as avoided", function()
  local ns, env, shown, calls, popup = setup()
  _G.UnitLevel = function() return 24 end
  popup("CONFIRM_BUY_BANK_SLOT")
  truthy(shown.text:find("2g 50s", 1, true), shown.text)
  truthy(shown.text:find("At level 24", 1, true))
  truthy(shown.text:find("Buy anyway?", 1, true))
  shown.no()
  eq(ns.db.char.ledger.itemsAvoided, 1); eq(ns.db.char.ledger.itemsAvoidedCopper, 25000)
  falsy(#calls > 0 and calls[1] == "PurchaseSlot")
  _G.UnitLevel = nil
end)

test("stable slot: accept buys it and counts as spent", function()
  local ns, env, shown, calls, popup = setup()
  popup("CONFIRM_BUY_STABLE_SLOT")
  shown.yes()
  eq(calls[#calls], "BuyStableSlot")
  eq(ns.db.char.ledger.spentAgainst, 50000)
  eq(ns.db.char.ledger.itemsAvoided, 0)
end)

test("COD: warn only, the game's dialog is annotated and its price is noted", function()
  local ns, env, shown, calls, popup = setup()
  local text = "Pay 7s for this mail?"
  env.StaticPopup1 = { which = "COD_CONFIRMATION",
    text = { GetText = function() return text end, SetText = function(_, v) text = v end } }
  popup("COD_CONFIRMATION")
  eq(shown.text, nil, "no question of ours")
  truthy(text:find("Paying a COD costs gold", 1, true), text)
  eq(ns.Resets.Status().cod.lastSeen.price, 700)
  eq(#calls, 0)
end)

test("taking ordinary mail records nothing", function()
  local ns, env, shown, calls, popup = setup()
  env.TakeInboxItem(5, 1)
  eq(ns.db.char.ledger.spentAgainst, 0)
end)

test("a kind that is switched off is left alone", function()
  local ns, env, shown, calls, popup = setup({ enabled = true, warnings = true, blockingConfirmations = true,
    guard = { cod = false } })
  popup("COD_CONFIRMATION")
  eq(shown.text, nil)
  popup("CONFIRM_BUY_BANK_SLOT")
  truthy(shown.text)
end)

test("the minimum price does not apply to these", function()
  local ns, env, shown, calls, popup = setup({ enabled = true, warnings = true, blockingConfirmations = true, minPrice = 999999 })
  env.GetNextStableSlotCost = function() return 5 end
  popup("CONFIRM_BUY_STABLE_SLOT")
  truthy(shown.text)
end)

test("export status lists each kind and what it last saw", function()
  local ns, env, shown, calls, popup = setup()
  popup("CONFIRM_BUY_BANK_SLOT")
  local st = ns.Resets.Status()
  eq(st.bank.on, true); eq(st.bank.lastSeen.price, 25000); eq(st.stable.lastSeen, "not seen this session")
end)

local function dialogText(which, body)
  local text = body
  return { which = which, text = { GetText = function() return text end, SetText = function(_, v) text = v end } },
    function() return text end
end

test("stable slot: accept falls back to C_StableInfo when the globals are gone", function()
  local ns, env, shown, calls, popup = setup()
  env.BuyStableSlot, env.GetNextStableSlotCost = nil, nil
  env.C_StableInfo = { GetNextStableSlotCost = function() return 50000 end,
    BuyStableSlot = function() calls[#calls + 1] = "C_StableInfo.BuyStableSlot" end }
  popup("CONFIRM_BUY_STABLE_SLOT")
  truthy(shown.text:find("5g", 1, true), shown.text)
  shown.yes()
  eq(calls[#calls], "C_StableInfo.BuyStableSlot")
end)

test("Forever bank tab: our question is not used, the game's dialog is annotated and nothing is bought by us", function()
  local ns, env, shown, calls, popup = setup()
  env.PurchaseSlot, env.BankFrame = nil, nil
  env.C_Bank = { FetchNextPurchasableBankTabData = function() return { tabCost = 100000 } end,
    PurchaseBankTab = function(t) calls[#calls + 1] = "PurchaseBankTab:" .. t end }
  local text = "Purchase a bank tab?"
  env.StaticPopup1 = { which = "CONFIRM_BUY_BANK_TAB",
    text = { GetText = function() return text end, SetText = function(_, v) text = v end } }
  popup("CONFIRM_BUY_BANK_TAB", { bankType = 0 })
  eq(shown.text, nil, "no question of ours")
  truthy(text:find("Bank slots cost gold", 1, true), text)
  eq(#calls, 0)
end)

test("talent reset: warn only, with the pet trainer's dialog told apart by its text", function()
  local ns, env, shown, calls, popup = setup()
  local frame, current = dialogText("CONFIRM_TALENT_WIPE", "Are you sure you want to reset your talents?")
  env.StaticPopup1 = frame
  popup("CONFIRM_TALENT_WIPE")
  eq(shown.text, nil)
  truthy(current():find("Resetting costs gold", 1, true), current())
  local pframe, pcurrent = dialogText("CONFIRM_TALENT_WIPE", "Do you want to unlearn all of your pet's skills?")
  env.StaticPopup1 = pframe
  popup("CONFIRM_TALENT_WIPE")
  eq(shown.text, nil)
  truthy(pcurrent():find("Taking skills off your pet costs gold", 1, true), pcurrent())
  eq(#calls, 0)
end)
