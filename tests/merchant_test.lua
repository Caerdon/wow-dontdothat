local H = require("harness")

local function setup(env)
  local ns, seen = {}, {}
  ns.ItemGuard = {
    Trace = function() end,
    Run = function(surface, name, link, total, proceed) seen.name, seen.total = name, total; return proceed() end,
  }
  H.load("DontDoThat/Intercepts/Merchant.lua", ns)
  env.BuyMerchantItem = function() seen.bought = true end
  ns.Merchant.Install(env)
  return env, seen
end

test("vendor buy reads the row from C_MerchantFrame when the legacy call is gone", function()
  local env, seen = setup({
    GetMerchantItemLink = function() return "|Hitem:1|h[Bag]|h" end,
    C_MerchantFrame = { GetItemInfo = function() return { name = "Bag", price = 500, stackCount = 1 } end },
  })
  env.BuyMerchantItem(1, 1)
  eq(seen.name, "Bag")
  eq(seen.total, 500)
  truthy(seen.bought)
end)

test("vendor buy still reads the legacy call", function()
  local env, seen = setup({
    GetMerchantItemLink = function() return "|Hitem:1|h[Bag]|h" end,
    GetMerchantItemInfo = function() return "Bag", nil, 500, 1 end,
  })
  env.BuyMerchantItem(1, 2)
  eq(seen.total, 1000)
end)
