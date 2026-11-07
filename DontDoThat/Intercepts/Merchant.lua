local addonName, ns = ...

-- Vendor purchases. BuyMerchantItem is wrapped once: a flagged item gets the warning and a "Buy anyway?"
-- question, and the real call runs only on confirm. Everything else passes straight through.
local Merchant = {}
ns.Merchant = Merchant

local installed = false
local wrapper

function Merchant.Reset() installed = false; wrapper = nil end

-- For /ddt export: did the wrap happen, and is the game still calling our version?
function Merchant.Status(env)
  env = env or _G
  return {
    wrapped = installed,
    gameStillCallsOurs = installed and env.BuyMerchantItem == wrapper or false,
    tooltipHook = Merchant.tooltipHooked or false,
    BuyMerchantItem = type(env.BuyMerchantItem),
  }
end

-- price in GetMerchantItemInfo is for one bundle of `bundle` units; qty is units asked for.
function Merchant.Total(price, bundle, qty)
  bundle = (type(bundle) == "number" and bundle > 0) and bundle or 1
  qty = (type(qty) == "number" and qty > 0) and qty or 1
  return math.floor(price * qty / bundle + 0.5)
end

-- name, price, bundle, extendedCost for a vendor row. The legacy GetMerchantItemInfo lost its fallback in 12.0.0;
-- C_MerchantFrame.GetItemInfo(index) returns a table instead (stackCount, hasExtendedCost). Docs only, not yet seen on Forever.
local function rowInfo(env, index)
  if type(env.GetMerchantItemInfo) == "function" then
    local name, _, price, bundle, _, _, extendedCost = env.GetMerchantItemInfo(index)
    return name, price, bundle, extendedCost
  end
  local api = env.C_MerchantFrame
  if type(api) == "table" and type(api.GetItemInfo) == "function" then
    local info = api.GetItemInfo(index)
    if type(info) == "table" then return info.name, info.price, info.stackCount, info.hasExtendedCost end
  end
end

local function itemAt(env, index)
  if type(env.GetMerchantItemLink) ~= "function" then return nil end
  local name, price, bundle, extendedCost = rowInfo(env, index)
  if not name or type(price) ~= "number" or extendedCost then return nil end
  return name, env.GetMerchantItemLink(index), price, bundle
end

function Merchant.Install(env)
  env = env or _G
  if installed then return true end
  local original = env.BuyMerchantItem
  if type(original) ~= "function" then
    if ns.Log then ns.Log.Add("items: BuyMerchantItem is %s, cannot wrap", type(original)) end
    return false
  end
  wrapper = function(index, qty, ...)
    local ok, name, link, price, bundle = pcall(itemAt, env, index)
    if not ok or not name then
      pcall(ns.ItemGuard.Trace, { surface = "vendor", total = nil, outcome = ok
        and "passed through: no item name or it costs tokens/honor" or ("passed through: read failed: " .. tostring(name)) })
      return original(index, qty, ...)
    end
    local args = { ... }
    return ns.ItemGuard.Run("vendor", name, link, Merchant.Total(price, bundle, qty),
      function() return original(index, qty, unpack(args)) end)
  end
  env.BuyMerchantItem = wrapper
  installed = true
  if ns.Log then ns.Log.Add("items: BuyMerchantItem wrapped") end
  return true
end

-- Adds the warning line to vendor item tooltips.
local function hookTooltip(env)
  local tip = env.GameTooltip
  if type(env.hooksecurefunc) ~= "function" or type(tip) ~= "table" then return end
  Merchant.tooltipHooked = pcall(env.hooksecurefunc, tip, "SetMerchantItem", function(self, index)
    local ok, name, link, price, bundle = pcall(itemAt, env, index)
    if ok and name then ns.ItemGuard.Tooltip(self, "vendor", name, link, Merchant.Total(price, bundle, 1)) end
  end)
end

function Merchant.Enable(eventTarget, env)
  env = env or _G
  ns.ItemGuard.Watch(eventTarget)
  pcall(Merchant.Install, env)
  hookTooltip(env)
end
