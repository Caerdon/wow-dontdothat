package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local function fresh(profile)
  local ns = { version = "0.1.0" }
  for _, f in ipairs({ "UI/Helpers.lua", "Data/Sounds.lua", "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua",
    "Rules/Data/Hunter.lua", "Rules/Data/Warrior.lua", "Rules/Data/Mage.lua", "Data/TrainerPrices.lua",
    "Model/Ledger.lua", "Model/Savings.lua", "Model/Milestones.lua", "Model/Settings.lua", "Model/SkipRevision.lua", "Model/ItemCategory.lua", "Options/Options.lua" }) do
    H.load("DontDoThat/" .. f, ns)
  end
  ns.db = { profile = profile or {} }
  return ns
end

local function text(widget)
  local name = widget.name
  if type(name) == "function" then name = name() end
  return name
end

test("settings switches read and write the saved profile, defaulting to on", function()
  local ns = fresh({})
  local home, tuning, alerts, watch = ns.Options.Home().args, ns.Options.Tuning().args, ns.Options.Alerts().args, ns.Options.Watch().args
  truthy(home.enabled.get(), "enabled defaults to on")
  truthy(tuning.warnings.get()); truthy(tuning.blocking.get()); truthy(alerts.alerts.get()); truthy(watch.filter.get())
  tuning.blocking.set(nil, false)
  eq(ns.db.profile.blockingConfirmations, false)
  falsy(tuning.blocking.get())
  watch.filter.set(nil, false)
  eq(ns.db.profile.recommendedFilter, false)
end)

test("home: the nudge reads and writes the saved values, and Custom only shows when it applies", function()
  local ns = fresh({})
  local home = ns.Options.Home().args
  eq(home.nudge.get(), "ask")
  eq(home.nudge.values().custom, nil)
  home.nudge.set(nil, "mark")
  eq(ns.db.profile.blockingConfirmations, false); eq(home.nudge.get(), "mark")
  home.nudge.set(nil, "everything")
  eq(ns.db.profile.tuning.promptTiers, { defer = true, deferLow = true, info = true })
  ns.db.profile.tuning.promptTiers.info = false
  eq(home.nudge.get(), "custom")
  local label = home.nudge.values().custom
  truthy(label:find("Custom", 1, true), label)
  truthy(label:find("Marks are on.", 1, true), label)
  truthy(label:find("It asks about Save your gold and Not worth buying yet.", 1, true), label)
  truthy(home.customNote.name:find("Advanced > Tuning", 1, true))
  falsy(home.customNote.hidden())
  home.nudge.set(nil, "custom")
  eq(home.nudge.get(), "custom")
end)

test("home and tuning: sub-options are greyed out while the addon is off", function()
  local ns = fresh({ enabled = false })
  local home, tuning = ns.Options.Home().args, ns.Options.Tuning().args
  truthy(home.nudge.disabled()); truthy(tuning.warnings.disabled()); truthy(tuning.blocking.disabled())
  eq(home.enabled.disabled, nil, "the master switch stays usable")
  ns.db.profile.enabled = true
  falsy(tuning.warnings.disabled())
end)

test("alerts page: sound choices come from the registry and old saved values still work", function()
  local ns = fresh({ alert = { sound = "default" } })
  local a = ns.Options.Alerts().args
  local choices = a.sound.values()
  eq(choices.raidwarning, "Raid warning")
  truthy(choices.alarm1)
  eq(a.sound.get(), ns.Sounds.default, "the old 'default' value maps to the real default")
  a.sound.set(nil, "alarm1")
  eq(ns.db.profile.alert.sound, "alarm1")
  eq(a.sound.get(), "alarm1")
end)

test("alerts page: play button, banner toggle and cooldown", function()
  local ns = fresh({})
  local played
  ns.Alert = { PlaySound = function(key) played = key end }
  local a = ns.Options.Alerts().args
  a.test.func()
  eq(played, ns.Sounds.default)
  truthy(a.banner.get())
  a.banner.set(nil, false)
  eq(ns.db.profile.alert.banner, false)
  eq(a.cooldown.get(), 3, "the shown default matches the saved default")
  a.cooldown.set(nil, 12)
  eq(ns.db.profile.alert.cooldown, 12)
  ns.db.profile.alerts = false
  local after = ns.Options.Alerts().args
  truthy(after.sound.disabled(), "greyed out when warning sounds are off")
  falsy(after.alerts.disabled(), "the sound switch itself stays usable")
end)

local function names(entries) local out = {}; for _, e in ipairs(entries) do out[#out + 1] = e.name end; return out end
local function has(entries, name) for _, e in ipairs(entries) do if e.name == name then return e end end end

test("class summary groups the Hunter data the way players hear it", function()
  local ns = fresh()
  local s = ns.Options.ClassSummary(ns.Rules.GetClass("HUNTER"), 1)
  for _, n in ipairs({ "Serpent Sting", "Wing Clip", "Trueshot Aura", "Dual Wield", "Mail" }) do truthy(has(s.keep, n), n .. " is worth buying") end
  for _, n in ipairs({ "Distracting Shot", "Wyvern Sting", "Aspect of the Beast" }) do truthy(has(s.wait, n), n .. " can wait") end
  for _, n in ipairs({ "Track Humanoids", "Scorpid Sting", "Arcane Resistance" }) do truthy(has(s.low, n), n .. " is low value") end
  falsy(has(s.wait, "Wing Clip"))
  for _, list in ipairs({ s.keep, s.optional, s.wait, s.low, s.skipped }) do
    falsy(has(list, "Auto Shot"), "Auto Shot comes with the class and is not listed")
  end
  local function groupOf(groups, name)
    for _, g in ipairs(groups) do if has(g.entries, name) then return g.title end end
  end
  for _, n in ipairs({ "Growl", "Great Stamina", "Natural Armor" }) do eq(groupOf(s.keepGroups, n), "Pet", n) end
  eq(groupOf(s.keepGroups, "Bestial Wrath"), "Beast Mastery", "a Hunter spell, not a Pet Trainer skill")
  eq(groupOf(s.lowGroups, "Arcane Resistance"), "Pet")
  eq(groupOf(s.lowGroups, "Track Humanoids"), "Spells that rarely help")
  eq(groupOf(s.waitGroups, "Distracting Shot"), "Spells for groups and raids")
  eq(groupOf(s.waitGroups, "Wyvern Sting"), "Spells for level 60")
  eq(groupOf(s.skippedGroups, "Mend Pet"), "All specs"); falsy(groupOf(s.keepGroups, "Mend Pet") == "Pet")
  eq(s.keepGroups[#s.keepGroups].title, "Pet", "Pet comes last")
  eq(has(s.wait, "Distracting Shot").detail, "Pulls enemies off your tank. You only need it in groups and raids.")
  eq(has(s.wait, "Wyvern Sting").detail, "You won't need this until level 60.")
  eq(has(s.low, "Scorpid Sting").detail, "Only useful against other players.")
  eq(has(s.skipped, "Mend Pet").detail, "Skip rank 6. An earlier version of this list judged this rank a small upgrade. From the earlier skip list.")
  falsy(has(s.skipped, "Arcane Shot"), "the experts recommend Arcane Shot rank 7")
  eq(has(s.skipped, "Raptor Strike").detail, "Skip ranks 5, 6, 8. An earlier version of this list judged this rank a small upgrade. From the earlier skip list.")
  eq(has(s.keep, "Serpent Sting").detail, nil)
  local sorted = names(s.wait)
  for i = 2, #sorted do truthy(sorted[i - 1] <= sorted[i], "sorted by name") end
end)

-- Every spell line in a category, whether it sits in the category or in one of its inline group boxes.
local function lines(category, out)
  out = out or {}
  for key, child in pairs(category.args or {}) do
    if child.type == "group" then lines(child, out) elseif key:find("^item") then out[#out + 1] = child end
  end
  return out
end

local function collect(group, out)
  out = out or {}
  out[#out + 1] = group.name
  for _, child in pairs(group.args or {}) do
    local name = child.name
    if type(name) == "function" then name = name() end
    if child.type == "group" then collect(child, out) else out[#out + 1] = tostring(name) end
  end
  return out
end

test("rules page is a collapsible tree: class, then categories with counts, then one spell per line", function()
  local ns = fresh()
  local page = ns.Options.Rules()
  eq(page.childGroups, "tree")
  truthy(page.name:find("Classes", 1, true))
  falsy(page.args.professions or page.args.how, "no per-profession pages and no separate rules page")
  truthy(page.args.title and page.args.intro, "the Classes node explains itself")
  local hunter = page.args.HUNTER
  eq(hunter.name, "Hunter"); eq(hunter.childGroups, "tree")
  truthy(hunter.args.wait.name:find("Save your gold", 1, true))
  truthy(hunter.args.wait.name:find("(", 1, true), "the category shows how many items it holds")
  truthy(hunter.args.skipped.name:find("Ranks to skip", 1, true))
  eq(hunter.args.specs, nil, "talent trees are not shown")
  local item = lines(hunter.args.wait)[1]
  eq(item.type, "toggle"); eq(item.width, "full"); eq(item.descStyle, "inline")
  truthy(item.desc, "the reason sits beneath the name")
  local count = #lines(hunter.args.wait)
  truthy(hunter.args.wait.name:find("(" .. count .. ")", 1, true), "the count matches the lines")
  for _, key in ipairs({ "keep", "optional", "wait", "low", "skipped" }) do
    for _, box in pairs(hunter.args[key].args) do
      if box.type == "group" then truthy(box.inline and box.name:find("(", 1, true), key .. " groups are inline boxes with counts") end
    end
  end
end)

test("each spell line carries an icon that is looked up when drawn", function()
  local ns = fresh()
  ns.Icons = { Lookup = function(id) return id == H.fid(ns, "HUNTER", "Distracting Shot") and 132330 or "fallback" end }
  local wait = lines(ns.Options.Rules().args.HUNTER.args.wait)
  local found
  for _, w in pairs(wait) do if w.name and tostring(w.name):find("^Distracting Shot") then found = w end end
  local image, width, height = found.image()
  eq(image, 132330); eq(width, 28); eq(height, 28)
  ns.Icons = nil
  eq((found.image()), nil, "no icon module means no icon, not an error")
end)

test("rules page text has no internal terms", function()
  local ns = fresh()
  local joined = table.concat(collect(ns.Options.Rules()), "\n")
  local function all(group, acc)
    for _, child in pairs(group.args or {}) do
      if child.type == "group" then all(child, acc) else acc[#acc + 1] = tostring(child.name) end
    end
    return acc
  end
  joined = joined .. "\n" .. table.concat(all(ns.Options.Rules(), {}), "\n")
  truthy(joined:find("Distracting Shot", 1, true))
  for _, jargon in ipairs({ "RaidGroup", "deferLow", "tagged", "tier", "rotation", "supersession", "override", "Endgame" }) do
    falsy(joined:find(jargon, 1, true), "no '" .. jargon .. "' in player-facing text")
  end
end)

test("milestones page lists each mount with an icon and shows progress", function()
  local ns = fresh()
  local items = ns.Options.MilestoneItems()
  eq(items[1], { name = "Level 40 mount", detail = "100g for riding and your first mount." })
  eq(items[2], { name = "Level 60 mount", detail = "1000g for riding, plus 200g for each epic mount." })
  local page = ns.Options.Milestones()
  truthy(page.args.mount1.image():find("Icons", 1, true))
  truthy(page.args.mount2.name:find("Level 60 mount", 1, true))
  eq(ns.Options.MilestoneStatus(), "Log in on a supported character to see your progress.")
  ns.Context = { Profile = function() return { milestone = { current = 60, state = "active" } } end }
  eq(ns.Options.MilestoneStatus(), "You're saving for your level 60 mount.")
  ns.Context = { Profile = function() return { milestone = { current = 40, state = "active" } } end }
  eq(ns.Options.MilestoneStatus(), "You're saving for your level 40 mount.")
  ns.Context = { Profile = function() return { milestone = { current = nil, state = "finished" } } end }
  truthy(ns.Options.MilestoneStatus():find("level 60 mount", 1, true))
  truthy(page.args.status.name():find("level 60 mount", 1, true))
end)

test("tally page shows the tally lines, or says it is unavailable", function()
  local ns = fresh()
  truthy(ns.Options.TallyLines()[1]:find("isn't available", 1, true))
  ns.Tally = { Summary = function() return { "Kept for sure: 3g" } end }
  eq(ns.Options.TallyLines(), { "Kept for sure: 3g" })
  ns.Tally = { Summary = function() error("boom") end }
  truthy(ns.Options.TallyLines()[1]:find("isn't available", 1, true), "an error never reaches the page")
end)

test("debug page toggles logging and runs the report and clear actions", function()
  local ns = fresh({})
  local logging, shown, cleared
  ns.Log = { SetEnabled = function(v) logging = v end, ClearAll = function() cleared = true end }
  ns.Export = { Show = function() shown = true end }
  local d = ns.Options.Debug().args
  falsy(d.logging.get())
  d.logging.set(nil, true)
  truthy(ns.db.profile.debug); truthy(logging); truthy(d.logging.get())
  d.export.func(); d.clear.func()
  truthy(shown); truthy(cleared)
end)

test("about page explains the marks in plain words and shows the version", function()
  local ns = fresh()
  local joined = table.concat(ns.Options.AboutLines(), "\n")
  truthy(joined:find("Version 0.1.0", 1, true))
  truthy(joined:find("(i)", 1, true))
  truthy(joined:find("/ddt", 1, true))
end)

test("there are five pages in order, and the root window holds all of them", function()
  local ns = fresh()
  local keys = {}
  for _, page in ipairs(ns.Options.Pages()) do keys[#keys + 1] = page.key end
  eq(keys, { "home", "watch", "progress", "advanced", "about" })
  local root = ns.Options.Root()
  eq(root.childGroups, "tree")
  for _, key in ipairs(keys) do truthy(root.args[key], key) end
end)

test("registration adds the pages to the game's options and defines OpenOptions", function()
  local ns = fresh()
  local registered, added, opened = {}, {}, nil
  local config = { RegisterOptionsTable = function(_, name) registered[#registered + 1] = name end }
  local dialog = {
    AddToBlizOptions = function(_, name, title, parent) added[#added + 1] = { name = name, title = title, parent = parent } end,
    Open = function(_, name) opened = name end,
  }
  _G.LibStub = function(lib) return ({ ["AceConfig-3.0"] = config, ["AceConfigDialog-3.0"] = dialog })[lib] end
  local addon = {}
  truthy(ns.Options.Register(addon))
  eq(#added, 6, "a parent entry plus five pages")
  eq(added[1].title, "Don't Do That")
  eq(added[2].parent, "Don't Do That")
  eq(added[3].title, "What to watch")
  addon:OpenOptions()
  eq(opened, "DontDoThat")
  _G.LibStub = nil
end)

test("registration without the libraries does not error", function()
  local ns = fresh()
  _G.LibStub = nil
  falsy(ns.Options.Register({}))
  falsy(ns.Options.Open())
end)

local function loadSettings(profile)
  local ns = fresh(profile)
  return ns
end

test("tuning: stop-after is on Home", function()
  local ns = loadSettings({})
  local g, home = ns.Options.Tuning().args, ns.Options.Home().args
  eq(home.stopAfter.get(), 60)
  home.stopAfter.set(nil, 40)
  eq(ns.db.profile.tuning.stopAfter, 40)
  eq(home.stopAfter.get(), 40)
  eq(g.window, nil, "the rank window is gone")
end)

test("tuning: any combination of tiers can be chosen, including none", function()
  local ns = loadSettings({})
  local g = ns.Options.Tuning().args
  truthy(g.tier_defer.get()); falsy(g.tier_deferLow.get()); falsy(g.tier_info.get())
  g.tier_deferLow.set(nil, true)
  truthy(ns.Settings.PromptsFor("deferLow"))
  g.tier_defer.set(nil, false)
  falsy(ns.Settings.PromptsFor("defer"))
  g.tier_deferLow.set(nil, false)
  eq(ns.Settings.PromptTiers(), { defer = false, deferLow = false, info = false })
end)

test("tuning is greyed out while the addon is off", function()
  local ns = loadSettings({ enabled = false })
  local g = ns.Options.Tuning().args
  truthy(g.kind_skipRank.disabled()); truthy(g.tier_defer.disabled())
end)

test("alerts page: the volume channel defaults to Master and ignores unknown saved values", function()
  local ns = loadSettings({})
  local a = ns.Options.Alerts().args
  eq(a.channel.get(), "Master")
  a.channel.set(nil, "Dialog")
  eq(ns.db.profile.alert.channel, "Dialog"); eq(a.channel.get(), "Dialog")
  ns.db.profile.alert.channel = "Bogus"
  eq(a.channel.get(), "Master")
end)

test("rules page: each ability has a switch that is on until the player turns it off", function()
  local ns = loadSettings({})
  local shot = H.fid(ns, "HUNTER", "Distracting Shot")
  local wait = lines(ns.Options.Rules().args.HUNTER.args.wait)
  local line
  for _, w in pairs(wait) do if w.name == "Distracting Shot" then line = w end end
  truthy(line.get())
  line.set(nil, false)
  eq(ns.db.profile.ruleOff.abilities.HUNTER[shot], true)
  falsy(line.get())
  eq(ns.Settings.RulesFor("HUNTER").offAbilities[shot], true)
  line.set(nil, true)
  eq(ns.db.profile.ruleOff.abilities.HUNTER[shot], nil)
end)

test("rules page: tag switches and rule kind switches", function()
  local ns = loadSettings({})
  local rules = ns.Options.Rules().args
  local choices = rules.HUNTER.args.choices.args
  truthy(choices.tag_PvP.get())
  choices.tag_PvP.set(nil, false)
  eq(ns.Settings.RulesFor("HUNTER").offTags, { PvP = true })
  local kinds = ns.Options.Tuning().args
  truthy(kinds.kind_skipRank.get())
  eq(kinds.kind_supersession, nil, "the level-gap switch is gone")
  kinds.kind_offSpec.set(nil, false)
  eq(ns.Settings.RulesFor("HUNTER").offKinds, { offSpec = true })
end)

test("rules page: the spec dropdown is Automatic plus the class's specs, and Automatic clears the pick", function()
  local ns = loadSettings({})
  local spec = ns.Options.Rules().args.HUNTER.args.choices.args.spec
  eq(spec.get(), "auto")
  eq(spec.sorting[1], "auto")
  local count = 0
  for key in pairs(spec.values) do count = count + 1 end
  eq(count, 4, "Automatic and Hunter's three specs")
  spec.set(nil, "MM")
  eq(ns.db.profile.specOverride.HUNTER, "MM"); eq(spec.get(), "MM")
  spec.set(nil, "auto")
  eq(ns.db.profile.specOverride.HUNTER, nil)
end)

test("milestones page: says which mount you chose to stop at", function()
  local ns = loadSettings({ tuning = { stopAfter = 40 } })
  ns.Context = { Profile = function() return { milestone = { current = nil, state = "finished" } } end }
  truthy(ns.Options.MilestoneStatus():find("level 40 mount", 1, true))
end)

test("every page opens with a title and uses the same text size", function()
  local ns = loadSettings({})
  for _, page in ipairs(ns.Options.Pages()) do
    local args = page.key == "rules" and page.group.args.how.args or page.group.args -- Rules is a tree of pages
    eq(args.title.fontSize, "large", page.key)
    -- Never two blank lines in a row, and a blank line above every heading after the first.
    local byOrder = {}
    for _, widget in pairs(args) do byOrder[#byOrder + 1] = widget end
    table.sort(byOrder, function(a, b) return a.order < b.order end)
    for i = 2, #byOrder do
      truthy(not (byOrder[i].name == " " and byOrder[i - 1].name == " "), page.key .. " has two blank lines in a row")
    end
    for key, widget in pairs(args) do
      if widget.type == "description" and key ~= "title" and not key:find("^gap") then
        eq(widget.fontSize, "medium", page.key .. "." .. key)
      end
      if widget.name == " " then
        truthy(key:find("^gap") and widget.fontSize == "medium", page.key .. "." .. key .. " is a spacer row that isn't a gap")
      end
    end
  end
end)

test("read-only lists, mounts and the kept amounts are spaced apart", function()
  local ns = loadSettings({})
  local rules = ns.Options.Rules().args
  local herb = lines(rules.HUNTER.args.wait)
  truthy(#herb > 1, "the Hunter's Save your gold list has several lines")
  local m = ns.Options.Milestones().args
  local function gapBetween(args, a, b)
    for k, w in pairs(args) do if k:find("^gap") and w.order > args[a].order and w.order < args[b].order then return true end end
  end
  truthy(gapBetween(m, "mount1", "mount2"), "a gap between the mounts")
  local t = ns.Options.Tally().args
  local function between(a, b) return gapBetween(t, a, b) end
  truthy(between("verifiedNote", "projected"), "a gap under the first Kept amount")
  truthy(between("projectedNote", "spentHeader"), "a gap under the second")
end)

test("home: each level carries its own explanation and the headings are plain", function()
  local ns = fresh({})
  local home = ns.Options.Home().args
  local values = home.nudge.values()
  truthy(values.mark:find("never asks", 1, true)); truthy(values.ask:find("Buy anyway?", 1, true)); truthy(values.everything:find("optional", 1, true))
  eq(home.nudgeHeader.name, "When you're about to buy something that can wait")
  eq(home.stopHeader.name, "When to stop warning me")
  eq(home.stopAfter.name, "")
  eq(home.stopAfter.values[60], "After my level 60 mount"); eq(home.stopAfter.values[40], "After my level 40 mount")
end)

test("custom detail says what is set", function()
  local ns = fresh({ warnings = false, blockingConfirmations = false })
  eq(ns.Options.CustomDetail(), "Marks are off. It never asks.")
  ns.db.profile.warnings, ns.db.profile.blockingConfirmations = true, true
  ns.db.profile.tuning = { promptTiers = { defer = false, deferLow = false, info = false } }
  eq(ns.Options.CustomDetail(), "Marks are on. It asks about nothing.")
  ns.db.profile.tuning.promptTiers = { defer = true, deferLow = true, info = true }
  eq(ns.Options.CustomDetail(), "Marks are on. It asks about Save your gold, Not worth buying yet and Optional.")
end)

test("reset all lives on Home, and no other settings page has a reset", function()
  local ns = fresh({ enabled = false, alert = { cooldown = 9 }, tuning = { stopAfter = 40 }, professionAsked = { [4036] = true },
    milestoneOverride = { [40] = true }, debug = true, traceItems = true })
  local reset = ns.Options.Home().args.resetAll
  eq(reset.type, "execute"); truthy(reset.confirm)
  reset.func()
  eq(ns.db.profile.enabled, nil); eq(ns.db.profile.alert, nil); eq(ns.db.profile.tuning, nil)
  eq(ns.db.profile.debug, nil); eq(ns.db.profile.traceItems, nil)
  eq(ns.db.profile.professionAsked, { [4036] = true }, "what you have already done is kept")
  eq(ns.db.profile.milestoneOverride, { [40] = true })
  for _, page in ipairs({ ns.Options.Tuning(), ns.Options.Watch(), ns.Options.Rules() }) do
    local function find(group)
      for key, child in pairs(group.args or {}) do
        if key:lower():find("reset", 1, true) or (type(child.name) == "string" and child.name:lower():find("back to the usual", 1, true))
            or (type(child.name) == "string" and child.name:lower():find("turn everything back on", 1, true)) then return key end
        if child.type == "group" then local found = find(child); if found then return found end end
      end
    end
    eq(find(page), nil, page.name .. " has a reset control")
  end
end)

test("progress shows each heading once", function()
  local ns = fresh({})
  local progress = ns.Options.Progress()
  eq(progress.args.milestones.args.title, nil); eq(progress.args.tally.args.title, nil)
  eq(progress.args.milestones.name, "Milestones"); eq(progress.args.tally.name, "Tally")
  truthy(progress.args.milestones.inline and progress.args.tally.inline)
end)

test("rules page: a class page has Worth buying and Optional by spec, then the other lists, and no Not a purchase list", function()
  local ns = loadSettings({})
  local hunter = ns.Options.Rules().args.HUNTER.args
  for _, key in ipairs({ "keep", "optional", "wait", "low", "skipped" }) do truthy(hunter[key], key .. " list") end
  truthy(hunter.keep.name:find("Worth buying", 1, true)); truthy(hunter.optional.name:find("Optional", 1, true))
  eq(hunter.other, nil)
  local first = hunter.keep.args.group1
  truthy(first.inline, "each spec group is an inline box")
  truthy(first.name:find("All specs", 1, true), first.name)
  eq(ns.Options.ClassSummary(ns.Rules.GetClass("HUNTER")).keepGroups[1].title, "All specs")
end)

test("rules page: a switch is saved by spell, so it survives a change of client language", function()
  local ns = loadSettings({})
  local shot = H.fid(ns, "HUNTER", "Distracting Shot")
  local function find(label)
    for _, w in pairs(lines(ns.Options.Rules().args.HUNTER.args.wait)) do
      if w.name == label then return w end
    end
  end
  _G.GetSpellInfo = function(id) return "Z" .. id end
  local ok, err = pcall(function()
    local line = find("Z" .. shot)
    truthy(line, "the page shows the name the client uses")
    line.set(nil, false)
  end)
  _G.GetSpellInfo = nil
  truthy(ok, tostring(err))
  eq(ns.Settings.RulesFor("HUNTER").offAbilities[shot], true)
  falsy(find("Distracting Shot").get(), "still switched off when the client shows the English name")
end)

test("class summary: ranks to skip follow the revision, with the reason and where it came from", function()
  local ns = fresh()
  local warrior = ns.Rules.GetClass("WARRIOR")
  local one, two = ns.Options.ClassSummary(warrior, 1), ns.Options.ClassSummary(warrior, 2)
  eq(one.revision, 1); eq(two.revision, 2)
  eq(has(one.skipped, "Rend").detail, "Skip ranks 5, 6, 7. The leveling guide says to buy this spell only up to rank 4. From the Wowhead leveling guide.")
  eq(has(one.skipped, "Overpower").detail, "Skip ranks 2, 3, 4. The leveling guide says to buy only the first rank of this spell. From the Wowhead leveling guide.")
  local thunder = has(two.skipped, "Thunder Clap")
  truthy(thunder and thunder.detail:find("The leveling guide says to buy only the first rank of this spell. From the Wowhead leveling guide.", 1, true))
  -- A computed skip says it was computed.
  local computed
  for _, e in ipairs(two.skipped) do if e.detail:find("Computed from the game data.", 1, true) then computed = e end end
  truthy(computed, "revision 2 has computed skips")
  truthy(computed.detail:find("Skip rank", 1, true))
end)

test("class summary: ranks to skip are sorted by spell name, then by rank, and each line lists its ranks in order", function()
  local ns = fresh()
  local checked, multi = 0, 0
  for _, class in ipairs({ "WARRIOR", "MAGE", "HUNTER" }) do
    for _, revision in ipairs({ 1, 2 }) do
      local s = ns.Options.ClassSummary(ns.Rules.GetClass(class), revision)
      local function check(entries)
        for i, e in ipairs(entries) do
          local ranks = {}
          for n in e.detail:match("^Skip ranks? ([%d, ]+)%."):gmatch("%d+") do ranks[#ranks + 1] = tonumber(n) end
          for j = 2, #ranks do truthy(ranks[j - 1] < ranks[j], class .. " " .. e.name .. ": " .. e.detail) end
          eq(e.firstRank, ranks[1])
          local prev = entries[i - 1]
          if prev then
            truthy(prev.name <= e.name, "sorted by name: " .. prev.name .. " before " .. e.name)
            if prev.name == e.name then truthy(prev.firstRank <= e.firstRank, e.name .. " lines run in rank order"); multi = multi + 1 end
          end
          checked = checked + 1
        end
      end
      check(s.skipped)
      for _, g in ipairs(s.skippedGroups) do check(g.entries) end
    end
  end
  truthy(checked > 20, "checked " .. checked)
  truthy(multi > 0, "a spell with more than one line was among them")
end)

test("class summary: a rank skipped for some specs only is listed under those specs", function()
  local ns = fresh()
  local mage = ns.Options.ClassSummary(ns.Rules.GetClass("MAGE"), 2)
  local titles = {}
  for _, g in ipairs(mage.skippedGroups) do titles[#titles + 1] = g.title end
  truthy(#titles > 1, "more than one group of skipped ranks: " .. table.concat(titles, " | "))
  eq(mage.skippedGroups[1].title, "All specs", "All specs comes first")
end)

test("class summary: with no revision given it follows the one in use", function()
  local ns = fresh()
  ns.db = { profile = { tuning = { skipRevision = 1 } } }
  eq(ns.Options.ClassSummary(ns.Rules.GetClass("HUNTER")).revision, 1)
  ns.db = { profile = {} }
  eq(ns.Options.ClassSummary(ns.Rules.GetClass("HUNTER")).revision, 2)
end)

test("tuning: the skip list choice lists each revision, marks the newest as the default, and saves the pick", function()
  local ns = fresh({})
  local widget = ns.Options.Tuning().args.skipRevision
  truthy(widget, "a skip list choice")
  eq(widget.get(), 2, "never chosen: the newest")
  eq(widget.values[2], "Revision 2 (default): Revised with Rules + Expert Advice")
  eq(widget.values[1], "Revision 1: Original using Expert Advice")
  falsy(widget.values[1]:find("default", 1, true))
  eq(widget.sorting, { 1, 2 })
  widget.set(nil, 1)
  eq(ns.db.profile.tuning.skipRevision, 1)
  eq(widget.get(), 1)
  widget.set(nil, 2)
  eq(ns.db.profile.tuning.skipRevision, 2, "choosing the newest is remembered as a choice")
end)

test("rules page: each class page names the revision its ranks to skip follow", function()
  local ns = fresh({})
  local rules = ns.Options.Rules()
  local line = rules.args.WARRIOR.args.revisionLine
  truthy(line and line.name:find("skip list revision 2", 1, true))
  ns.db.profile.tuning = { skipRevision = 1 }
  local again = ns.Options.Rules()
  truthy(again.args.WARRIOR.args.revisionLine.name:find("skip list revision 1", 1, true))
  falsy(rules.args.WARRIOR.args.skipped.name == again.args.WARRIOR.args.skipped.name, "the count of ranks to skip follows the revision")
end)
