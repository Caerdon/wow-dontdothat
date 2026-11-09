package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

-- The revision setting, /ddt revision, and the notice printed once when a profile first meets a revision.

local ns = {}
H.loadSpellTables(ns)
H.load("DontDoThat/Rules/Schema.lua", ns)
H.load("DontDoThat/Rules/Engine.lua", ns)
H.load("DontDoThat/Rules/Data/Warrior.lua", ns)
H.load("DontDoThat/Model/Milestones.lua", ns)
H.load("DontDoThat/Model/Settings.lua", ns)
H.load("DontDoThat/Model/SkipRevision.lua", ns)

local function has(lines, text)
  for _, l in ipairs(lines) do if l:find(text, 1, true) then return true end end
  return false
end

test("settings: the revision pick is read, written and cleared", function()
  local p = {}
  eq(ns.Settings.SkipRevision(p), nil)
  ns.Settings.SetSkipRevision(1, p)
  eq(ns.Settings.SkipRevision(p), 1)
  ns.Settings.SetSkipRevision(nil, p)
  eq(ns.Settings.SkipRevision(p), nil)
  p.tuning = { skipRevision = "two" }
  eq(ns.Settings.SkipRevision(p), nil, "a value that is not a number is ignored")
end)

test("settings: RulesFor carries the pick, and the engine uses it", function()
  eq(ns.Settings.RulesFor("WARRIOR", {}).skipRevision, nil)
  eq(ns.Settings.RulesFor("WARRIOR", { tuning = { skipRevision = 1 } }).skipRevision, 1)
  eq(ns.Rules.ResolveRevision(ns.Settings.RulesFor("WARRIOR", { tuning = { skipRevision = 1 } }).skipRevision), 1)
  eq(ns.Rules.ResolveRevision(ns.Settings.RulesFor("WARRIOR", {}).skipRevision), 2)
  eq(ns.Rules.ResolveRevision(ns.Settings.RulesFor("WARRIOR", { tuning = { skipRevision = 7 } }).skipRevision), 2)
end)

test("/ddt revision: shows what is in use and what exists", function()
  local lines = ns.SkipRevision.Command("", {})
  truthy(has(lines, "Skip list revision 2 is in use (the default)."))
  truthy(has(lines, "Revision 1: Original using Expert Advice"))
  truthy(has(lines, "Revision 2: Revised with Rules + Expert Advice"))
  truthy(has(lines, "/ddt revision"))
  local picked = ns.SkipRevision.Command("", { tuning = { skipRevision = 1 } })
  truthy(has(picked, "Skip list revision 1 is in use."))
  falsy(has(picked, "(the default)"))
end)

test("/ddt revision: a number that is a revision switches to it", function()
  local p = {}
  eq(ns.SkipRevision.Command("1", p), { "Now using skip list revision 1." })
  eq(ns.Settings.SkipRevision(p), 1)
  eq(ns.SkipRevision.InUse(p), 1)
  eq(ns.SkipRevision.Command(" 2 ", p), { "Now using skip list revision 2." })
  eq(ns.SkipRevision.InUse(p), 2)
end)

test("/ddt revision: a number that is not a revision changes nothing and lists the valid ones", function()
  local p = { tuning = { skipRevision = 1 } }
  for _, bad in ipairs({ "9", "0", "two", "1.5" }) do
    local lines = ns.SkipRevision.Command(bad, p)
    truthy(lines[1]:find("is not a skip list revision. The revisions are: 1, 2.", 1, true), bad)
    eq(ns.Settings.SkipRevision(p), 1, "unchanged after " .. bad)
  end
end)

test("/ddt revision: the slash command prints those lines", function()
  local said = {}
  local addon = { db = { profile = {} } }
  function addon:Print(msg) said[#said + 1] = msg end
  function addon:RegisterChatCommand() end
  ns.addon = addon
  H.load("DontDoThat/Core/Slash.lua", ns)
  addon:HandleSlash("revision")
  truthy(has(said, "Skip list revision 2 is in use"))
  said = {}
  addon:HandleSlash("revision 1")
  eq(said, { "Now using skip list revision 1." })
  eq(addon.db.profile.tuning.skipRevision, 1)
  said = {}
  addon:HandleSlash("revision 9")
  truthy(has(said, "is not a skip list revision"))
  eq(addon.db.profile.tuning.skipRevision, 1)
end)

test("load notice: a new install is told which revision, that it changed a lot, and how to change it", function()
  local p = {}
  local lines = ns.SkipRevision.Notice(p)
  truthy(lines, "a notice")
  truthy(has(lines, "Skip list revision 2 is in use."))
  truthy(has(lines, "Revision 2 changes the rules significantly"))
  truthy(has(lines, "many more ranks are skipped, decided for your spec"))
  truthy(has(lines, "/ddt revision 1"))
  truthy(has(lines, "Advanced > Tuning"))
  eq(p.revisionNotice, 2, "the profile is marked as told")
end)

test("load notice: it is printed once", function()
  local p = {}
  truthy(ns.SkipRevision.Notice(p))
  eq(ns.SkipRevision.Notice(p), nil)
  eq(ns.SkipRevision.Notice(p), nil)
end)

test("load notice: an update from a profile that predates revisions prints it", function()
  local p = { tuning = { stopAfter = 60 }, minPrice = 100 }
  truthy(ns.SkipRevision.Notice(p))
  eq(p.minPrice, 100, "nothing else in the profile is touched")
end)

test("load notice: a profile on an earlier revision hears that a newer one exists and how to switch", function()
  local p = { tuning = { skipRevision = 1 } }
  local lines = ns.SkipRevision.Notice(p)
  truthy(has(lines, "Skip list revision 1 is in use."))
  truthy(has(lines, "A newer revision exists, revision 2."))
  truthy(has(lines, "/ddt revision 2"))
  eq(ns.SkipRevision.Notice(p), nil)
end)

test("load notice: resetting settings does not print it again, and the pick goes back to the default", function()
  local p = { tuning = { skipRevision = 1 } }
  ns.SkipRevision.Notice(p)
  ns.Settings.ResetAll(p)
  eq(p.revisionNotice, 2)
  eq(ns.Settings.SkipRevision(p), nil)
  eq(ns.SkipRevision.Notice(p), nil)
end)

test("load notice: a revision newer than the one a profile was told about is announced again", function()
  local p = { revisionNotice = 1 }
  truthy(ns.SkipRevision.Notice(p))
  eq(p.revisionNotice, 2)
end)
