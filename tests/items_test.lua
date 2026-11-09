package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local function fresh()
  local ns = { defaults = nil }
  for _, f in ipairs({ "UI/Helpers.lua", "Data/Sounds.lua", "Data/GoldRates.lua", "Model/EarnBack.lua",
    "Model/ItemCategory.lua", "Model/ItemWarning.lua", "Model/Ledger.lua", "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua",
    "Rules/Data/Hunter.lua", "Model/Milestones.lua",
    "Options/Options.lua" }) do
    H.load("DontDoThat/" .. f, ns)
  end
  -- The defaults table lives in Core/Addon.lua, which needs Ace; pull the same values from its source.
  ns.defaults = { profile = { itemModes = { armor = "both", mounts = "off", food = "ah" }, minPrice = 100 } }
  return ns
end

test("earn-back picks the band for the level and describes the time", function()
  local ns = fresh()
  eq(ns.EarnBack.Rate(1), 4000)
  eq(ns.EarnBack.Rate(24), 20000)
  eq(ns.EarnBack.Rate(70), 120000)
  eq(ns.EarnBack.Describe(1, 24), "under a minute")
  eq(ns.EarnBack.Describe(66000, 24), "about 3 hours 20 minutes") -- 6.6g at 2g/h
  eq(ns.EarnBack.Describe(13333, 24), "about 40 minutes")
  eq(ns.EarnBack.Describe(0, 24), nil)
  eq(ns.EarnBack.Line(nil, 24), nil)
  truthy(ns.EarnBack.Line(33200, 24):find("At level 24", 1, true))
end)

test("item categories follow the game's class numbers", function()
  local C = fresh().ItemCategory
  eq(C.Classify({ classID = 4, subClassID = 2, equipLoc = "INVTYPE_CHEST" }), "armor")
  eq(C.Classify({ classID = 4, subClassID = 0, equipLoc = "INVTYPE_TABARD" }), "vanity")
  eq(C.Classify({ classID = 2, subClassID = 7 }), "weapons")
  eq(C.Classify({ classID = 1, subClassID = 0 }), "bags")
  eq(C.Classify({ classID = 0, subClassID = 5 }), "food")
  eq(C.Classify({ classID = 0, subClassID = 1 }), "potions")
  eq(C.Classify({ classID = 15, subClassID = 5 }), "mounts")
  eq(C.Classify({ classID = 15, subClassID = 2 }), "vanity")
  eq(C.Classify({ classID = 11, subClassID = 2 }), "ammo")
  eq(C.Classify({ classID = 12 }), "misc")
  eq(C.Classify(nil), "misc")
  eq(#C.List, 13)
end)

test("a purchase is flagged by mode, surface and minimum price", function()
  local W = fresh().ItemWarning
  local modes = { armor = "both", food = "ah", mounts = "off", bags = "vendor" }
  truthy(W.Flagged(modes, "armor", "vendor", 100, 100)) -- at the minimum
  truthy(W.Flagged(modes, "armor", "ah", 500, 100))
  falsy(W.Flagged(modes, "armor", "vendor", 99, 100))
  falsy(W.Flagged(modes, "food", "vendor", 5000, 100))
  truthy(W.Flagged(modes, "food", "ah", 5000, 100))
  falsy(W.Flagged(modes, "mounts", "ah", 99999, 0))
  falsy(W.Flagged(modes, "bags", "ah", 5000, 0))
  falsy(W.Flagged(modes, "unknown", "ah", 5000, 0))
  truthy(W.Flagged(modes, "armor", "vendor", 1, 0)) -- minimum of zero warns on everything
end)

test("ledger counts avoided item purchases apart from savings", function()
  local L = fresh().Ledger
  local state = L.NewState()
  L.RecordItemAvoided(state, 20000)
  L.RecordItemAvoided(state, 500)
  eq(state.itemsAvoided, 2)
  eq(state.itemsAvoidedCopper, 20500)
  eq(state.spentAgainst, 0)
  L.RecordItemPerformed(state, 700)
  eq(state.spentAgainst, 700)
  eq(state.itemsAvoided, 2)
  local old = { respecSavings = 0, petResetSavings = 0 }
  L.RecordItemAvoided(old, 100) -- an old save without the new fields
  eq(old.itemsAvoided, 1)
end)

test("the minimum price boxes split, carry and reject bad input", function()
  local O = fresh().Options
  eq(O.PriceBox(100, "g"), 0); eq(O.PriceBox(100, "s"), 1); eq(O.PriceBox(100, "c"), 0)
  eq(O.PriceBox(12345, "g"), 1); eq(O.PriceBox(12345, "s"), 23); eq(O.PriceBox(12345, "c"), 45)
  eq(O.SetPriceBox(100, "s", "10"), 1000)
  eq(O.SetPriceBox(0, "c", "150"), 150) -- shows as 1s 50c
  eq(O.PriceBox(150, "s"), 1); eq(O.PriceBox(150, "c"), 50)
  eq(O.SetPriceBox(100, "g", "abc"), 100)
  eq(O.SetPriceBox(100, "g", "-3"), 100)
  eq(O.SetPriceBox(100, "g", "1.5"), 100)
  eq(O.SetPriceBox(100, "g", ""), 100)
end)

test("what to watch: categories are collapsed, list every category and write modes", function()
  local ns = fresh()
  ns.db = { profile = { itemModes = { armor = "both" }, minPrice = 5000 } }
  local page = ns.Options.Watch()
  local cats = page.args.categories
  truthy(cats.hidden(), "collapsed until opened")
  page.args.showCategories.set(nil, true)
  falsy(cats.hidden())
  for _, info in ipairs(ns.ItemCategory.List) do truthy(cats.args[info.key], info.key .. " has a dropdown") end
  eq(cats.args.armor.get(), "both")
  eq(cats.args.bags.get(), "off") -- unset reads as off
  cats.args.bags.set(nil, "ah")
  eq(ns.db.profile.itemModes.bags, "ah")
  eq(page.args.minSilver.get(), "50")
  truthy(page.args.minGold.name:find("UI-GoldIcon", 1, true))
  falsy(page.args.minSilver.validate(nil, "x") == true)
  falsy(page.args.reset, "no reset control on this page")
end)

-- Guard flow and the export report.
local function guarded(over)
  local ns = fresh()
  over = over or {}
  local shown = {}
  for _, f in ipairs({ "Intercepts/ItemGuard.lua", "Debug/Export.lua" }) do H.load("DontDoThat/" .. f, ns) end
  ns.db = { profile = { enabled = true, blockingConfirmations = true, alerts = true, minPrice = 100,
      traceItems = over.trace ~= false,
      itemModes = over.modes or { armor = "both", food = "ah" } },
    char = { ledger = ns.Ledger.NewState() }, global = {} }
  ns.Alert = { Trigger = function() return true end }
  ns.ConfirmPopup = { Ask = function(_, yes, no) shown.yes, shown.no = yes, no; return true end }
  _G.GetItemInfoInstant = function() return 1, "Armor", "Plate", "INVTYPE_CHEST", 0, 4, 4 end
  return ns, shown
end

test("a flagged purchase is traced, asked about, and recorded when declined", function()
  local ns, shown = guarded()
  local bought = false
  ns.ItemGuard.Run("vendor", "Plate Chest", "link", 5000, function() bought = true end)
  falsy(bought)
  local t = ns.db.global.itemTrace
  eq(#t, 1); eq(t[1].category, "armor"); eq(t[1].classID, 4); eq(t[1].outcome, "question shown, waiting for an answer")
  shown.no()
  eq(t[1].outcome, "question shown, declined, not bought")
  eq(ns.db.char.ledger.itemsAvoided, 1); eq(ns.db.char.ledger.itemsAvoidedCopper, 5000)
  ns.ItemGuard.Run("vendor", "Plate Chest", "link", 5000, function() bought = true end)
  shown.yes()
  truthy(bought); eq(ns.db.char.ledger.spentAgainst, 5000)
  _G.GetItemInfoInstant = nil
end)

test("an unflagged purchase goes through and the trace says why", function()
  local ns = guarded()
  local bought = 0
  ns.ItemGuard.Run("vendor", "Cheap", "link", 5, function() bought = bought + 1 end)
  _G.GetItemInfoInstant = function() return 1, "Consumable", "Food", "", 0, 0, 5 end
  ns.ItemGuard.Run("vendor", "Bread", "link", 5000, function() bought = bought + 1 end)
  eq(bought, 2)
  local t = ns.db.global.itemTrace
  eq(t[1].outcome, "passed through: below minimum price")
  eq(t[2].outcome, "passed through: mode ah does not cover vendor")
  _G.GetItemInfoInstant = nil
end)

test("the trace keeps only the newest entries and the export has an Items section", function()
  local ns = guarded()
  for i = 1, 45 do ns.ItemGuard.Run("vendor", "Item" .. i, "link", 5, function() end) end
  eq(#ns.db.global.itemTrace, 40)
  eq(ns.db.global.itemTrace[40].name, "Item45")
  ns.Merchant = { Status = function() return { wrapped = true } end }
  ns.Auction = { Status = function() return { wrapped = false } end }
  local text = ns.Export.Build({ settings = ns.db.profile, items = function() return ns.ItemGuard.Report({}) end })
  truthy(text:find("== Items ==", 1, true))
  truthy(text:find("recentPurchases", 1, true))
  truthy(text:find("GetItemInfoInstant = MISSING", 1, true) or text:find("GetItemInfoInstant = available", 1, true))
  _G.GetItemInfoInstant = nil
end)

test("switching prompts off is recorded in the trace", function()
  local ns = guarded()
  ns.ItemGuard.Disable("blocked: BuyMerchantItem")
  eq(ns.db.global.itemTrace[1].outcome, "prompts switched off: blocked: BuyMerchantItem")
  _G.GetItemInfoInstant = nil
end)

test("nothing is saved to the trace when item recording is off", function()
  local ns = guarded({ trace = false })
  ns.ItemGuard.Run("vendor", "Plate Chest", "link", 5000, function() end)
  eq(#(ns.db.global.itemTrace or {}), 0)
  _G.GetItemInfoInstant = nil
end)

test("what to watch: Other has the slot and COD switches", function()
  local ns = fresh()
  ns.db = { profile = { guard = { cod = false } } }
  local page = ns.Options.Watch()
  eq(page.args.guard_cod.get(), false)
  eq(page.args.guard_bank.get(), true)
  page.args.guard_bank.set(nil, false)
  eq(ns.db.profile.guard.bank, false)
  falsy(page.args.reset, "no reset control on this page")
end)

test("shopping off: nothing is flagged, and turning it back on restores the warning", function()
  local ns = guarded()
  ns.db.profile.watch = { shopping = false }
  local bought = false
  ns.ItemGuard.Run("vendor", "Plate Chest", "link", 5000, function() bought = true end)
  truthy(bought, "goes straight through")
  eq(ns.ItemGuard.Flag("vendor", "link", 5000), nil)
  ns.db.profile.watch = { shopping = true }
  eq(ns.ItemGuard.Flag("vendor", "link", 5000), "armor")
  _G.GetItemInfoInstant = nil
end)
