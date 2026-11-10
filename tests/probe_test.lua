local H = require("harness")

local function load()
  local ns = {}
  H.load("DontDoThat/Debug/Probe.lua", ns)
  return ns.Probe
end

local function trainerEnv()
  local rows = {
    { "Serpent Sting", "Rank 3", "used", 100, 18 },
    { "Serpent Sting", "Rank 4", "available", 200, 26 },
    { "Serpent Sting", "Rank 5", "unavailable", 300, 34 },
    { "Arcane Shot", "Rank 1", "available", 50, 6 },
    { "Arcane Shot", "Rank 2", "available", 90, 12 },
    { "Class Skills", "", "header" },
  }
  return {
    GetNumTrainerServices = function() return #rows end,
    GetTrainerServiceInfo = function(i) local r = rows[i]; return r[1], r[2], r[3] end,
    GetTrainerServiceCost = function(i) return rows[i][4] end,
    GetTrainerServiceLevelReq = function(i) return rows[i][5] end,
  }
end

test("existence reports present, missing, and namespace members", function()
  local P = load()
  local text = table.concat(P.Existence({
    GetTalentInfo = function() end,
    C_Trainer = { GetNumTrainerServices = function() end, Foo = 1 },
  }), "\n")
  truthy(text:find("GetTalentInfo: function", 1, true))
  truthy(text:find("LearnTalent: missing", 1, true))
  truthy(text:find("C_Trainer.*: present, 1 functions: GetNumTrainerServices", 1, true))
  truthy(text:find("C_SpellBook.*: missing", 1, true))
end)

test("run completes with an empty environment", function()
  local P = load()
  local text = P.Run({}, {})
  falsy(text:find("== Probe ==", 1, true), "Export supplies the heading")
  truthy(text:find("GetBuildInfo: ERROR not available", 1, true))
  truthy(text:find("Trainer snapshot", 1, true))
end)

test("run records errors and secret values and keeps going", function()
  local P = load()
  local secretToken = {}
  local env = {
    GetBuildInfo = function() return "1.0.0", "123", "Jan 1 2026", 16001 end,
    UnitLevel = function() error("restricted") end,
    UnitClass = function() return secretToken end,
    issecretvalue = function(v) return v == secretToken end,
  }
  local text = P.Run(env, {})
  truthy(text:find("interface: 16001", 1, true))
  truthy(text:find("UnitLevel(player): ERROR", 1, true))
  truthy(text:find("<secret>", 1, true))
  truthy(text:find("[SECRET]", 1, true))
  truthy(text:find("GetNumTalentTabs()", 1, true))
end)

test("a throwing probe in the list does not abort the report", function()
  local P = load()
  table.insert(P.Probes, { name = "boom", fn = function() error("kaput") end })
  local text = P.Run({}, {})
  truthy(text:find("boom: ERROR", 1, true))
  truthy(text:find("Observations", 1, true))
end)

test("trainer snapshot lists services and skips headers", function()
  local P = load()
  local snap = P.TrainerSnapshot(trainerEnv())
  truthy(snap.ok)
  eq(#snap.services, 5)
  eq(snap.headers[1], { index = 6, name = "Class Skills" })
  eq(snap.services[2].name, "Serpent Sting")
  eq(snap.services[2].rank, 4)
  eq(snap.services[2].level, 26)
  eq(snap.services[2].cost, 200)
  truthy(snap.services[2].available)
  truthy(snap.services[1].learned)
end)

test("trainer snapshot degrades without the API", function()
  local P = load()
  local snap = P.TrainerSnapshot({})
  falsy(snap.ok)
  truthy(snap.reason:find("missing", 1, true))
  local snap2 = P.TrainerSnapshot({ GetNumTrainerServices = function() error("x") end })
  falsy(snap2.ok)
end)

test("rank skips detect higher rank available with lower unlearned", function()
  local P = load()
  local skips = P.RankSkips(P.TrainerSnapshot(trainerEnv()).services)
  eq(skips, { { name = "Arcane Shot", rank = 2, lowerUnlearned = 1 } })
end)

test("rank skips are stored once and reported", function()
  local P = load()
  local saved = {}
  local snap = P.TrainerSnapshot(trainerEnv())
  P.RecordRankSkips(snap, saved)
  P.RecordRankSkips(snap, saved)
  eq(#P.ObservationLines(saved), 3)
  truthy(table.concat(P.ObservationLines(saved), "\n"):find("Arcane Shot rank 2", 1, true))
end)

test("talent points per tree", function()
  local P = load()
  local tp = P.TalentPoints({
    GetNumTalentTabs = function() return 3 end,
    GetTalentTabInfo = function(i) return "Tree" .. i, "icon", i * 2 end,
  })
  truthy(tp.ok)
  eq(tp.trees[3], { index = 3, name = "Tree3", points = 6 })
  falsy(P.TalentPoints({}).ok)
end)

test("talent points handle the id-first shape seen on Classic Era 1.15.9", function()
  local P = load()
  local tp = P.TalentPoints({
    GetNumTalentTabs = function() return 2 end,
    GetTalentTabInfo = function(i)
      return 360 + i, "Tree" .. i, "", 132164, i * 3, "Background"
    end,
  })
  truthy(tp.ok)
  eq(tp.trees[2], { index = 2, name = "Tree2", points = 6 })
end)

test("globals matching lists names containing each pattern", function()
  local P = load()
  local lines = P.GlobalsMatching({
    GetNumTrainerServices = function() end, BuyTrainerService = function() end,
    LearnTalent = function() end, Unrelated = function() end, NotAFunction = 5,
  }, { "Trainer", "wipe" })
  eq(lines[1], "  *Trainer*: 2 match(es): BuyTrainerService GetNumTrainerServices")
  eq(lines[2], "  *wipe*: 0 match(es)")
end)

test("respec quotes and interceptions are recorded in the given store", function()
  local P = load()
  local saved = { respecQuotes = {}, interceptions = {}, rankSkips = {} }
  P.RecordRespecQuote(2, 50000, saved)
  P.RecordInterception("trainer", "blocked", saved)
  P.RecordInterception("trainer", "blocked", saved)
  eq(saved.respecQuotes[1].count, 2)
  eq(saved.respecQuotes[1].copper, 50000)
  eq(saved.interceptions.trainer.blocked.n, 2)
  local text = P.Run(trainerEnv(), saved)
  truthy(text:find("respec quote: count=2 copper=50000", 1, true))
  truthy(text:find("interception trainer -> blocked: x2", 1, true))
  truthy(text:find("rank skipping possible: Arcane Shot", 1, true))
end)

test("respec quotes are bounded", function()
  local P = load()
  local saved = { respecQuotes = {}, interceptions = {}, rankSkips = {} }
  for i = 1, 60 do P.RecordRespecQuote(i, i, saved) end
  eq(#saved.respecQuotes, 50)
  eq(saved.respecQuotes[1].count, 11)
end)

test("the spell identity section reports the trainer row shape and what the talent call returns", function()
  local P = load()
  local text = P.Run({
    GetNumTrainerServices = function() return 1 end,
    GetTrainerServiceInfo = function() return "Arcane Shot", "Rank 2", "available", 14281 end,
    GetTalentInfo = function() return "Improved Aspect of the Hawk", 136076, 1, 1, 0, 5 end,
  }, {})
  truthy(text:find("Spell identity", 1, true))
  truthy(text:find('GetTrainerServiceInfo(1) -> "Arcane Shot", "Rank 2", "available", 14281', 1, true))
  truthy(text:find("value 4 looks like an ID", 1, true))
  truthy(text:find("GetTrainerServiceSpellID(1) -> missing", 1, true))
  truthy(text:find('GetTalentInfo(1, 1) -> "Improved Aspect of the Hawk"', 1, true))
end)

test("the spell identity section asks for a trainer when none is open", function()
  local P = load()
  local text = P.Run({}, {})
  truthy(text:find("open a trainer and run the report again", 1, true))
end)

-- The trainer ID check: what it reports when a method works, and when nothing does.
local function trainerIdEnv(opts)
  local rows = { { "Aimed Shot", "Rank 1", "available" }, { "Beast Mastery", nil, "header" }, { "Serpent Sting", "Rank 2", "available" } }
  local ids = { ["Aimed Shot"] = 19434, ["Serpent Sting"] = 1978 }
  local env = {
    GetNumTrainerServices = function() return #rows end,
    GetTrainerServiceInfo = function(i) local r = rows[i]; return r[1], r[2], r[3] end,
    GetSpellInfo = function(id) for n, v in pairs(ids) do if v == id then return n end end end,
    UIParent = {},
  }
  if opts.tooltip then
    local current
    env.CreateFrame = function()
      local tip = {}
      tip.SetOwner = function() end
      tip.Hide = function() end
      tip.SetTrainerService = function(_, i) current = rows[i][1] end
      tip.GetSpell = function() return current, ids[current] end
      return tip
    end
  end
  if opts.link then env.GetTrainerServiceItemLink = function(i) return "|Hspell:" .. ids[rows[i][1]] .. "|h[x]|h" end end
  return env
end

test("trainer ids: a tooltip that knows the spell is reported as working, with the matching ID", function()
  local P = load()
  local text = P.TrainerIds(trainerIdEnv({ tooltip = true }))
  truthy(text:find("tooltip:GetSpell() -> \"Aimed Shot\", 19434", 1, true), text)
  truthy(text:find("tooltip:GetSpell gives 19434 and it MATCHES the row", 1, true), text)
  truthy(text:find("RESULT: a spell ID that matches the row is available through: tooltip:GetSpell", 1, true), text)
  falsy(text:find("Beast Mastery", 1, true), "header rows are skipped")
end)

test("trainer ids: an ID inside a link is found, and GetTrainerServiceInfo values are checked too", function()
  local P = load()
  local text = P.TrainerIds(trainerIdEnv({ link = true }))
  truthy(text:find("GetTrainerServiceItemLink gives 1978 and it MATCHES the row", 1, true), text)
  local env = trainerIdEnv({})
  env.GetTrainerServiceInfo = function(i) return ({ "Aimed Shot", "Beast Mastery", "Serpent Sting" })[i], "Rank 1", "available", 19434 end
  truthy(P.TrainerIds(env):find("GetTrainerServiceInfo value 4 = 19434 MATCHES the row", 1, true))
end)

test("trainer ids: when nothing works the report says so, and a closed trainer asks to open one", function()
  local P = load()
  truthy(P.TrainerIds(trainerIdEnv({})):find("RESULT: no method gave an ID", 1, true))
  truthy(P.TrainerIds({}):find("open a trainer window first", 1, true))
end)

test("trainer ids: a throwing tooltip is reported, not raised", function()
  local P = load()
  local env = trainerIdEnv({})
  env.CreateFrame = function()
    return { SetOwner = function() end, Hide = function() end, SetTrainerService = function() error("no such thing") end }
  end
  local text = P.TrainerIds(env)
  truthy(text:find("SetTrainerService(1) -> ERROR", 1, true), text)
end)

test("hovered spell: reports what the game tooltip holds, and copes without one", function()
  local P = load()
  local text = P.HoveredSpell({ GameTooltip = { GetSpell = function() return "Aimed Shot", 19434 end, GetItem = function() end } })
  truthy(text:find("GameTooltip:GetSpell() -> \"Aimed Shot\", 19434", 1, true), text)
  eq(P.HoveredSpell({}), "GameTooltip is not available")
end)

-- The identity checks: talents, riding, professions and the open trainer window.
local function identityEnv()
  local ns = {}
  H.load("DontDoThat/Data/SpellData.lua", ns)
  H.load("DontDoThat/Data/RuleSpells.lua", ns)
  H.load("DontDoThat/Data/TalentData.lua", ns)
  H.load("DontDoThat/Model/SpellData.lua", ns)
  H.load("DontDoThat/Rules/Schema.lua", ns)
  H.load("DontDoThat/Rules/Engine.lua", ns)
  H.load("DontDoThat/Rules/Data/ProfessionLearn.lua", ns)
  H.load("DontDoThat/Intercepts/Adapter.lua", ns)
  H.load("DontDoThat/Debug/Probe.lua", ns)
  local family = ns.SpellData.FamilyId("HUNTER", "Aimed Shot")
  local talentId
  for id, ranks in pairs(ns.TalentSpells) do
    if ns.SpellData.FamilyOfId("HUNTER", ranks[1]) == family then talentId = id end
  end
  local env = {
    UnitClass = function() return "Hunter", "HUNTER", 3 end,
    GetNumTalentTabs = function() return 1 end,
    GetNumTalents = function() return 1 end,
    GetTalentInfo = function() return "Zname", "icon", 1, 1, 2, 5 end,
    GetTalentLink = function() return "|cff4e96f7|Htalent:" .. talentId .. ":2|h[Zname]|h|r" end,
    GetSpellInfo = function(id) if id == 33388 then return "Apprentice Riding" end return nil end,
    IsSpellKnown = function(id) return id == 33388 end,
    ClassTrainerFrame = { IsShown = function() return true end },
  }
  return ns, env
end

test("identity checks: talent links, riding, professions and the open window are reported", function()
  local ns, env = identityEnv()
  local text = table.concat(ns.Probe.IdentityChecks(env), "\n")
  truthy(text:find("talents: 1 total, 1 with points; 1 links carried a talent ID, 1 known to the table, 1 resolve to a spell family", 1, true), text)
  truthy(text:find("-> family Aimed Shot", 1, true), text)
  truthy(text:find("riding spell 33388: client name Apprentice Riding, known true", 1, true), text)
  truthy(text:find("riding spell 33391: client name nil, known false", 1, true), text)
  truthy(text:find("profession 2550 (Cooking)", 1, true), text)
  truthy(text:find("ClassTrainerFrame: exists, SHOWN", 1, true), text)
  truthy(text:find("CraftFrame: missing", 1, true), text)
end)

test("identity checks: no talent link is reported as a name fallback, and craft rows get the tooltip spell", function()
  local ns, env = identityEnv()
  env.GetTalentLink = nil
  truthy(table.concat(ns.Probe.IdentityChecks(env), "\n"):find("GetTalentLink is MISSING", 1, true))
  env.GetNumCrafts = function() return 1 end
  env.GetCraftInfo = function() return "Growl", "Rank 1" end
  env.DontDoThatProbeTip = { SetOwner = function() end, Hide = function() end, SetCraftSpell = function() end,
    GetSpell = function() return "Growl", 2649 end }
  truthy(table.concat(ns.Probe.IdentityChecks(env), "\n"):find('craft 1: GetCraftInfo -> "Growl", "Rank 1"; tooltip:GetSpell -> "Growl", 2649', 1, true))
end)

test("identity checks run even with no trainer open, and the report reuses its tooltip frame", function()
  local ns, env = identityEnv()
  truthy(ns.Probe.TrainerIds(env):find("== identity checks ==", 1, true))
end)

test("trait talents lists nodes with points and survives missing APIs", function()
  local P = load()
  eq(P.TraitTalents({})[1], "  unavailable: no C_ClassTalents / C_Traits")
  local text = table.concat(P.TraitTalents({
    C_ClassTalents = { GetActiveConfigID = function() return 7 end },
    C_Traits = {
      GetConfigInfo = function() return { treeIDs = { 1 } } end,
      GetTreeNodes = function() return { 10, 11 } end,
      GetNodeInfo = function(_, id)
        if id == 10 then return { currentRank = 2, maxRanks = 5, activeEntry = { entryID = 100 } } end
        return { currentRank = 0 }
      end,
      GetEntryInfo = function() return { definitionID = 200 } end,
      GetDefinitionInfo = function() return { spellID = 3045 } end,
    },
  }), "\n")
  truthy(text:find("node 10 rank 2/5 entry 100 spell 3045", 1, true))
  truthy(text:find("2 points spent", 1, true))
  falsy(text:find("node 11", 1, true))
end)

test("popups reports missing guard dialogs and related extras", function()
  local P = load()
  local text = table.concat(P.Popups({ StaticPopupDialogs = {
    CONFIRM_BUY_BANK_SLOT = {}, CONFIRM_TALENT_WIPE = {}, CONFIRM_RESPEC_SPEC = {}, UNRELATED = {} } }), "\n")
  truthy(text:find("CONFIRM_BUY_BANK_SLOT: present", 1, true))
  truthy(text:find("COD_CONFIRMATION: MISSING", 1, true))
  truthy(text:find("other related popups: CONFIRM_RESPEC_SPEC", 1, true))
  falsy(text:find("UNRELATED", 1, true))
end)

test("a Forever trainer row, in Blizzard's mainline order, is snapshotted by its own shape", function()
  local ns = {}
  H.load("DontDoThat/Intercepts/Adapter.lua", ns)
  H.load("DontDoThat/Debug/Probe.lua", ns)
  local rows = {
    { "Eagle Eye", "available", 132172, 14, "", "" },
    { "Serpent Sting", "used", 132204, 10, "Rank 2", "Marksmanship" },
  }
  local env = {
    GetNumTrainerServices = function() return #rows end,
    GetTrainerServiceInfo = function(i) return unpack(rows[i], 1, 6) end,
    GetTrainerServiceCost = function() return 100 end,
    GetTrainerServiceLevelReq = function(i) return rows[i][4] end,
  }
  local snap = ns.Probe.TrainerSnapshot(env)
  eq(#snap.services, 2)
  eq(snap.services[1].status, "available"); eq(snap.services[1].rank, nil); eq(snap.services[1].available, true)
  eq(snap.services[2].status, "used"); eq(snap.services[2].rank, 2); eq(snap.services[2].learned, true)
  truthy(table.concat(ns.Probe.ServiceLines(snap.services), "\n"):find("Serpent Sting rank=2 level=10", 1, true))
end)
