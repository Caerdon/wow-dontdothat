package.path = "./tests/?.lua;" .. package.path
local H = require("harness")
local C = require("locale_check")

local used = C.usedKeys("DontDoThat")

test("the enUS file gives English-as-key: a sentence with no translation shows as written", function()
  local ns = {}
  H.load("DontDoThat/Locales/enUS.lua", ns)
  eq(ns.L["Buy anyway?"], "Buy anyway?")
  eq(ns.L["Anything at all, even a sentence nobody wrote"], "Anything at all, even a sentence nobody wrote")
end)

test("the source asks for the sentences the tests below rely on", function()
  truthy(used["Buy anyway?"]); truthy(used["Costs about %s"]); truthy(used["%s costs %s."])
  truthy(next(used), "keys were found")
end)

test("a good translation file passes, and a locale file only loads for its own locale", function()
  local t = C.translations("tests/fixtures/locale_good.lua", "xxXX")
  eq(t["Buy anyway?"], "Xx?")
  eq(C.check(t, used), {})
  eq(C.translations("tests/fixtures/locale_good.lua", "deDE"), {}, "another locale loads nothing")
end)

test("a translation key the source never uses, and a placeholder mismatch, both fail and name the key", function()
  local problems = C.check(C.translations("tests/fixtures/locale_bad.lua", "xxXX"), used)
  eq(#problems, 3)
  local text = table.concat(problems, "\n")
  truthy(text:find('placeholder count differs: "Costs about %s"', 1, true), text)
  truthy(text:find('placeholder count differs: "%s costs %s."', 1, true), text)
  truthy(text:find('unused key: "A sentence the addon never asks for"', 1, true), text)
end)

test("every shipped translation file passes", function()
  local p = io.popen('ls DontDoThat/Locales/*.lua')
  for path in p:lines() do
    local name = path:match("([%w]+)%.lua$")
    if name ~= "enUS" and name ~= "Example" then
      eq(C.check(C.translations(path, name), used), {}, path)
    end
  end
  p:close()
end)

test("the example file loads for no real locale and translates nothing", function()
  eq(C.translations("DontDoThat/Locales/Example.lua", "enUS"), {})
  eq(C.translations("DontDoThat/Locales/Example.lua", "deDE"), {})
end)

test("the example locale file lists every skip reason, source line, and sentence of the revision notice and replies", function()
  local f = io.open("DontDoThat/Locales/Example.lua"); local example = f:read("*a"); f:close()
  local keys = C.keysInFile("DontDoThat/Model/SkipRevision.lua")
  for _, k in ipairs({
    "The leveling guide says to buy only the first rank of this spell.", "The leveling guide says this spell is not worth buying while leveling.",
    "The leveling guide says to buy this spell only up to rank %d.", "The leveling guide does not buy this rank while leveling.",
    "Adds nothing over the rank before it.", "Only %d%% stronger than the rank before it, for a spell you only use now and then.",
    "Only %d%% stronger than the rank before it, which does not repay its price.", "This rank can wait until you have your level 60 mount.",
    "An earlier version of this list judged this rank a small upgrade.", "From the Wowhead leveling guide.", "Computed from the game data.",
    "From the earlier skip list." }) do keys[k] = true end
  local count = 0
  for key in pairs(keys) do
    truthy(used[key], "the source asks for: " .. key)
    truthy(example:find('-- L["' .. key .. '"]', 1, true), "Example.lua lists: " .. key)
    count = count + 1
  end
  truthy(count >= 24, "checked " .. count)
end)
