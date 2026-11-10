package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = {}
for _, f in ipairs({ "Data/SpellData.lua", "Data/RuleSpells.lua", "Data/SkipRevisions.lua", "Data/TalentData.lua", "Model/SpellData.lua", "Rules/Schema.lua", "Rules/Engine.lua", "Rules/Data/Hunter.lua", "Rules/Data/ProfessionLearn.lua", "Model/SpecInference.lua",
  "Model/Milestones.lua", "Model/PlayerProfile.lua", "Intercepts/Adapter.lua", "Intercepts/Context.lua",
  "Intercepts/Trainer.lua" }) do
  H.load("DontDoThat/" .. f, ns)
end

-- Rows replay the shapes seen in a real Hunter trainer export (Classic Era 1.15.9).
local ROWS = {
  { "Beast Mastery", nil, "header" },
  { "Aspect of the Hawk", "Rank 1", "available", 400, 10 },
  { "Mend Pet", "Rank 1", "unavailable", 600, 12 },
  { "Marksmanship", nil, "header" },
  { "Serpent Sting", "Rank 2", "available", 400, 10 },
  { "Distracting Shot", "Rank 1", "unavailable", 600, 12 },
  { "Distracting Shot", "Rank 2", "unavailable", 2200, 20 },
  { "Survival", nil, "header" },
  { "Track Humanoids", nil, "available", 400, 10 },
  { "Wing Clip", "Rank 1", "used", 600, 12 },
}

local function fakeEnv(opts)
  opts = opts or {}
  local env = {}
  env.UnitClass = function() return "Hunter", opts.class or "HUNTER", 3 end
  env.UnitLevel = function() return opts.level or 10 end
  env.UnitName = function() if not opts.noNpc then return "Hunter Trainer" end end
  env.GetNumTrainerServices = function() return #ROWS end
  env.GetTrainerServiceInfo = function(i) local r = ROWS[i]; return r[1], r[2], r[3], 1 end
  env.GetTrainerServiceCost = function(i) return ROWS[i][4] end
  env.GetTrainerServiceLevelReq = function(i) return ROWS[i][5] end
  env.GetNumTalentTabs = function() return 3 end
  env.GetTalentTabInfo = function(i)
    local pts = opts.points or { 0, 0, 0 }
    return 360 + i, ({ "Beast Mastery", "Marksmanship", "Survival" })[i], "", 132164, pts[i], "Background"
  end
  return env
end

test("adapter reads trainer rows, headers, ranks and next rank levels", function()
  local t = ns.Adapter.ReadTrainer(fakeEnv())
  truthy(t.ok)
  eq(#t.rows, 10)
  truthy(t.byIndex[1].header)
  eq(t.byIndex[2].rank, 1); eq(t.byIndex[2].level, 10); eq(t.byIndex[2].cost, 400)
  truthy(t.byIndex[2].available); falsy(t.byIndex[3].available)
  truthy(t.byIndex[10].learned)
  eq(t.byIndex[9].rank, nil)
end)

test("adapter degrades without the trainer API", function()
  local t = ns.Adapter.ReadTrainer({})
  falsy(t.ok)
  eq(#t.rows, 0)
end)

test("adapter reads the player and the id-first talent shape", function()
  local env = fakeEnv({ level = 25, points = { 11, 2, 0 } })
  eq(ns.Adapter.ReadPlayer(env), { class = "HUNTER", level = 25 })
  local tabs = ns.Adapter.ReadTalentTabs(env)
  eq(tabs[1], { name = "Beast Mastery", points = 11 })
  eq(tabs[3].points, 0)
  eq(ns.Adapter.ReadTalentTabs({}), {})
end)

test("context builds a profile using the talent tab to spec mapping", function()
  local p = ns.Context.Profile(fakeEnv({ level = 25, points = { 16, 2, 0 } }))
  eq(p.class, "HUNTER"); eq(p.level, 25)
  eq(p.treePoints, { BM = 16, MM = 2, SV = 0 })
  eq(p.plausibleSpecs, { "BM" })
  eq(p.milestone.state, "active")
end)

test("context is nil for an unsupported class", function()
  eq(ns.Context.Profile(fakeEnv({ class = "MAGE" })), nil)
  eq(ns.Context.Profile({}), nil)
end)

test("beast training (no npc unit, or the npc is the pet) gets no verdicts at all", function()
  eq(ns.TrainerOverlay.Compute(fakeEnv({ noNpc = true })), nil)
  local e = fakeEnv()
  e.UnitName = function() return "Bjorn" end
  e.UnitGUID = function() return "Pet-0-1" end
  eq(ns.TrainerOverlay.Compute(e), nil)
  eq(ns.Adapter.IsBeastTraining(fakeEnv()), false)
end)

test("Forever names beast training by trainer type, whatever the npc unit says", function()
  local e = fakeEnv()
  e.Enum = { TrainerType = { General = 0, TalentsObsolete = 1, Tradeskills = 2, Pet = 3 } }
  e.C_Trainer = { GetTrainerType = function() return 3 end }
  eq(ns.Adapter.IsBeastTraining(e), true, "pet type with an npc unit that is not the pet")
  eq(ns.TrainerOverlay.Compute(e), nil)
  e.C_Trainer.GetTrainerType = function() return 0 end
  eq(ns.Adapter.IsBeastTraining(e), false)
  local noNpc = fakeEnv({ noNpc = true })
  noNpc.Enum, noNpc.C_Trainer = e.Enum, e.C_Trainer
  eq(ns.Adapter.IsBeastTraining(noNpc), false, "the client's answer wins over the unit checks")
  noNpc.C_Trainer = { GetTrainerType = function() error("not here") end }
  eq(ns.Adapter.IsBeastTraining(noNpc), true, "a failing call falls back to the unit checks")
end)

test("compute flags the rows the rules defer and leaves the rest", function()
  local c = ns.TrainerOverlay.Compute(fakeEnv())
  eq(c.verdicts[2].tier, "keep")          -- Aspect of the Hawk: no rule
  eq(c.verdicts[5].tier, "keep")          -- Serpent Sting: override
  eq(c.verdicts[6].tier, "defer")         -- Distracting Shot: not needed until 60
  eq(c.verdicts[7].tier, "defer")
  eq(c.verdicts[9].tier, "deferLow")      -- all tracking is low value
  eq(c.verdicts[1], nil, "headers are not evaluated")
  eq(c.verdicts[10], nil, "learned rows are not evaluated")
  eq(c.verdicts[6].cost, 600)
  eq(c.verdicts[6].name, "Distracting Shot")
end)

test("compute is nil when the class is unsupported or the trainer unreadable", function()
  eq(ns.TrainerOverlay.Compute(fakeEnv({ class = "MAGE" })), nil)
  local env = fakeEnv(); env.GetNumTrainerServices = nil
  eq(ns.TrainerOverlay.Compute(env), nil)
end)

local function buttons(env, ids)
  local calls = {}
  for i, id in ipairs(ids) do
    env["ClassTrainerSkill" .. i] = { GetID = function() return id end, n = i }
  end
  return { set = function(button, verdict) calls[button.n] = verdict and verdict.tier or "none" end }, calls
end

test("refresh applies verdicts to the buttons by service index, including after scrolling", function()
  local env = fakeEnv()
  local widgets, calls = buttons(env, { 5, 6, 9, 1 })
  ns.TrainerOverlay.Refresh(env, widgets)
  eq(calls, { "keep", "defer", "deferLow", "none" })
  -- scrolled so different services sit in the same buttons
  env.ClassTrainerSkill3, env.ClassTrainerSkill4 = nil, nil
  widgets, calls = buttons(env, { 7, 2 })
  ns.TrainerOverlay.Refresh(env, widgets)
  eq(calls, { "defer", "keep" })
end)

test("refresh clears every button when warnings are turned off", function()
  local env = fakeEnv()
  local widgets, calls = buttons(env, { 6, 9 })
  ns.db = { profile = { enabled = true, warnings = false } }
  ns.TrainerOverlay.Refresh(env, widgets)
  ns.db = nil
  eq(calls, { "none", "none" })
end)

test("refresh survives a button that errors and an evaluation that fails", function()
  local env = fakeEnv()
  local widgets = buttons(env, { 6 })
  env.ClassTrainerSkill1.GetID = function() error("boom") end
  local ok = ns.TrainerOverlay.SafeRefresh(env, widgets)
  truthy(ok, "contained")
  local saved = ns.Rules.Evaluate
  ns.Rules.Evaluate = function() error("bad rule") end
  truthy(ns.TrainerOverlay.SafeRefresh(env, widgets))
  ns.Rules.Evaluate = saved
end)

test("enable hooks the update function once and refreshes on trainer events", function()
  ns.TrainerOverlay.Reset()
  local env = fakeEnv()
  local widgets, calls = buttons(env, { 6 })
  ns.TrainerOverlay.widgets = widgets
  local registered, hooks = {}, 0
  env.ClassTrainerFrame_Update = function() end
  env.hooksecurefunc = function() hooks = hooks + 1 end
  local target = { RegisterEvent = function(_, event, fn) registered[event] = fn end }
  ns.TrainerOverlay.Enable(target, env)
  truthy(registered.TRAINER_SHOW and registered.TRAINER_UPDATE)
  registered.TRAINER_UPDATE()
  registered.TRAINER_UPDATE()
  eq(hooks, 1, "hooked once")
  eq(calls[1], "defer")
end)

test("adapter lists the talents with points in them, and nil when the client cannot say", function()
  local env = {
    GetNumTalentTabs = function() return 2 end,
    GetNumTalents = function(tab) return 2 end,
    GetTalentInfo = function(tab, i)
      local names = { { "Improved Tracking", "Aimed Shot" }, { "Wyvern Sting", "Intimidation" } }
      local ranks = { { 0, 1 }, { 0, 2 } }
      return names[tab][i], "icon", 1, 1, ranks[tab][i], 5
    end,
  }
  env.UnitClass = function() return "Hunter", "HUNTER", 3 end
  eq(ns.Adapter.ReadActiveTalents(env), { [H.fid(ns, "HUNTER", "Aimed Shot")] = true, [H.fid(ns, "HUNTER", "Intimidation")] = true })
  eq(ns.Adapter.ReadActiveTalents({}), nil)
end)

test("adapter reads talents from C_Traits when the client has no talent tabs", function()
  local env = {
    UnitClass = function() return "Hunter", "HUNTER", 3 end,
    C_ClassTalents = { GetActiveConfigID = function() return 1 end },
    C_Traits = {
      GetConfigInfo = function() return { treeIDs = { 9 } } end,
      GetTreeNodes = function() return { 1, 2 } end,
      GetNodeInfo = function(_, id) return { currentRank = id == 1 and 1 or 0, activeEntry = { entryID = id } } end,
      GetEntryInfo = function(_, id) return { definitionID = id } end,
      GetDefinitionInfo = function(id) return { spellID = id == 1 and 19434 or 19503 } end,
    },
  }
  local active = ns.Adapter.ReadActiveTalents(env)
  eq(active, { [H.fid(ns, "HUNTER", "Aimed Shot")] = true })
end)

-- The same trainer in a client that shows every spell under another name: nothing may depend on English.
local function scrambledEnv()
  local env = fakeEnv()
  env.GetSpellInfo = function(id) return "Z" .. id end
  env.GetTrainerServiceInfo = function(i)
    local r = ROWS[i]
    local id = r[3] ~= "header" and ns.SpellData.FamilyId("HUNTER", r[1])
    return id and ("Z" .. id) or r[1], r[2], r[3], 1
  end
  return env
end

test("a client that names every spell differently gets the same verdicts and tooltips", function()
  ns.db = nil
  local english, other = ns.TrainerOverlay.Compute(fakeEnv()), ns.TrainerOverlay.Compute(scrambledEnv())
  for i, v in pairs(english.verdicts) do
    eq(other.verdicts[i].tier, v.tier, "row " .. i)
    eq(other.verdicts[i].reason, v.reason, "row " .. i)
    eq(other.verdicts[i].source, v.source, "row " .. i)
  end
  eq(other.verdicts[6].tier, "defer", "Mend Pet is still deferred")
end)

test("rows resolve to family IDs through the client's own names", function()
  local t = ns.Adapter.ReadTrainer(scrambledEnv())
  eq(t.byIndex[2].familyId, ns.SpellData.FamilyId("HUNTER", "Aspect of the Hawk"))
  eq(t.byIndex[1].familyId, nil, "a header has no spell")
end)

test("an old saved entry keyed by an English name is ignored without an error", function()
  local rules = { offAbilities = { ["Distracting Shot"] = true }, offTags = {}, offKinds = {} }
  local p = ns.Context.Profile(fakeEnv())
  p.rules = rules
  local ok, v = pcall(ns.Rules.Evaluate, p, { kind = "spell", name = "Distracting Shot",
    familyId = ns.SpellData.FamilyId("HUNTER", "Distracting Shot"), rank = 1 })
  truthy(ok, tostring(v))
  eq(v.source ~= "disabled", true, "the stale name switches nothing off")
end)

-- Talents are recognised by the ID in their hyperlink, so the talent names the client shows do not matter.
local function talentIdFor(spellName)
  local family = ns.SpellData.FamilyId("HUNTER", spellName)
  for talentId, ranks in pairs(ns.TalentSpells) do
    if ns.SpellData.FamilyOfId("HUNTER", ranks[1]) == family then return talentId end
  end
end

test("talents are read by the ID in their link, whatever the client calls them", function()
  local aimed, intimidation = talentIdFor("Aimed Shot"), talentIdFor("Intimidation")
  truthy(aimed and intimidation, "both talents are in the generated table")
  local ids = { aimed, intimidation, 1 }
  local env = {
    UnitClass = function() return "Hunter", "HUNTER", 3 end,
    GetNumTalentTabs = function() return 1 end,
    GetNumTalents = function() return 3 end,
    GetTalentInfo = function(_, i) return "Zname" .. i, "icon", 1, 1, ({ 1, 0, 3 })[i], 5 end,
    GetTalentLink = function(_, i) return ("|cff4e96f7|Htalent:%d:1|h[Zname%d]|h|r"):format(ids[i], i) end,
  }
  local active = ns.Adapter.ReadActiveTalents(env)
  truthy(active[ns.SpellData.FamilyId("HUNTER", "Aimed Shot")], "Aimed Shot has a point")
  falsy(active[ns.SpellData.FamilyId("HUNTER", "Intimidation")], "Intimidation has none")
  local n = 0
  for _ in pairs(active) do n = n + 1 end
  eq(n, 1, "an unrelated talent with points adds nothing, and its odd name is not looked up")
end)

test("a talent with no link falls back to its name", function()
  local env = {
    UnitClass = function() return "Hunter", "HUNTER", 3 end,
    GetNumTalentTabs = function() return 1 end,
    GetNumTalents = function() return 1 end,
    GetTalentInfo = function() return "Aimed Shot", "icon", 1, 1, 1, 1 end,
  }
  truthy(ns.Adapter.ReadActiveTalents(env)[ns.SpellData.FamilyId("HUNTER", "Aimed Shot")])
end)

-- A client that names every spell differently AND gives the addon no way to look names up: only the trainer tooltip's
-- spell ID is left, as confirmed on a real trainer (SetTrainerService then GetSpell).
local function tooltipEnv()
  local env = fakeEnv()
  local rowNames = {}
  env.GetTrainerServiceInfo = function(i)
    local r = ROWS[i]
    local id = r[3] ~= "header" and ns.SpellData.FamilyId("HUNTER", r[1])
    if id then rowNames[i] = r[1] end
    return id and ("Z" .. id) or r[1], r[2], r[3], 1
  end
  env.UIParent = {}
  env.CreateFrame = function()
    local current
    local tip = { SetOwner = function() end, Hide = function() end }
    tip.SetTrainerService = function(_, i) current = i end
    tip.GetSpell = function()
      local r = ROWS[current]
      -- rank 2 of a spell has its own spell ID, one more than the family ID here; any ID of the family will do
      local id = ns.SpellData.FamilyId("HUNTER", r[1])
      return "Z" .. id, id
    end
    return tip
  end
  return env
end

test("trainer rows are read by the spell ID the trainer tooltip gives, with no name lookup at all", function()
  ns.db = nil
  local english, other = ns.TrainerOverlay.Compute(fakeEnv()), ns.TrainerOverlay.Compute(tooltipEnv())
  for i, v in pairs(english.verdicts) do
    eq(other.verdicts[i].tier, v.tier, "row " .. i)
    eq(other.verdicts[i].reason, v.reason, "row " .. i)
  end
  local t = ns.Adapter.ReadTrainer(tooltipEnv())
  eq(t.byIndex[2].spellId, ns.SpellData.FamilyId("HUNTER", "Aspect of the Hawk"))
  eq(t.byIndex[1].spellId, nil, "a header has no spell")
end)

test("a tooltip that gives no spell leaves the name lookup to decide", function()
  local env = scrambledEnv()
  env.UIParent = {}
  env.CreateFrame = function()
    return { SetOwner = function() end, Hide = function() end, SetTrainerService = function() error("nope") end }
  end
  eq(ns.Adapter.ReadTrainer(env).byIndex[2].familyId, ns.SpellData.FamilyId("HUNTER", "Aspect of the Hawk"))
end)

test("a profession row is recognised by its spell ID, and by its name when the tooltip gives none", function()
  local env = { UIParent = {}, GetSpellInfo = function(id) return "Z" .. id end }
  eq(ns.Adapter.TrainerProfessionId(env, { spellId = 2550, name = "anything" }), 2550)
  eq(ns.Adapter.TrainerProfessionId(env, { spellId = 3102, name = "Z2550" }), 2550, "a later tier shares the name; the engine skips it once the profession is known")
  eq(ns.Adapter.TrainerProfessionId(env, { name = "Z2108" }), 2108)
  eq(ns.Adapter.TrainerProfessionId(env, { spellId = 5, name = "Bogus" }), nil)
end)

test("riding: the Forever spells and the Era racial passives each count as the level 40 goal", function()
  local function riding(known) return ns.Adapter.ReadRiding({ IsSpellKnown = function(id) return known[id] == true end }) end
  eq(riding({}), { apprentice = false, journeyman = false })
  eq(riding({ [33388] = true }), { apprentice = true, journeyman = false }, "Forever Apprentice Riding")
  eq(riding({ [33391] = true }), { apprentice = false, journeyman = true }, "Forever Journeyman Riding")
  for _, id in ipairs({ 824, 825, 826, 828, 10861, 18995, 10906, 10907 }) do
    eq(riding({ [id] = true }).apprentice, true, "Era racial riding passive " .. id)
  end
  for _, id in ipairs({ 13819, 1279399, 5784 }) do
    eq(riding({ [id] = true }), { apprentice = true, journeyman = false }, "Warhorse / Felsteed " .. id)
  end
  for _, id in ipairs({ 23214, 23161 }) do
    eq(riding({ [id] = true }), { apprentice = false, journeyman = true }, "Charger / Dreadsteed " .. id)
  end
end)

test("a profession row named for the trainer's title is still recognised by its spell ID", function()
  -- Seen on a real Alchemy trainer: the row is "Apprentice Alchemist", its tooltip spell is Alchemy (2259).
  local env = { GetSpellInfo = function(id) return id == 2259 and "Alchemy" or nil end }
  eq(ns.Adapter.TrainerProfessionId(env, { name = "Apprentice Alchemist", spellId = 2259 }), 2259)
  eq(ns.Adapter.TrainerProfessionId(env, { name = "Apprentice Alchemist" }), nil, "the name alone would not have matched")
  eq(ns.Adapter.TrainerProfessionId(env, { name = "Weak Troll's Blood Potion" }), nil, "a recipe row has no spell ID and is not a first lesson")
end)

test("Era level 60 riding is read from the racial riding skill's max rank, in any language", function()
  local function riding(maxRank, name)
    local lines = { { name, false, true, 75, 0, 0, maxRank }, { "Weapon Skills", true } }
    return ns.Adapter.ReadRiding({
      GetSpellInfo = function(id) return "Z" .. id end,
      IsSpellKnown = function(id) return id == 824 end,
      GetNumSkillLines = function() return #lines end,
      GetSkillLineInfo = function(i) return unpack(lines[i]) end,
    })
  end
  eq(riding(75, "Z824"), { apprentice = true, journeyman = false }, "trained once: 75")
  eq(riding(150, "Z824"), { apprentice = true, journeyman = true }, "epic riding: 150, under the client's own name")
  eq(riding(150, "Horse Riding").journeyman, true, "the English name also matches")
  eq(riding(150, "Unrelated Skill").journeyman, false)
  eq(ns.Adapter.ReadRiding({}).journeyman, false, "no skill list at all")
end)

test("Forever's trainer rows come in Blizzard's mainline order and are read by it", function()
  ns.db = nil
  local env = fakeEnv()
  local rows = {
    { "Eagle Eye", "available", 132172, 14, "", "" },
    { "Serpent Sting", "used", 132204, 10, "Rank 2", "Marksmanship" },
    { "Distracting Shot", "unavailable", 135736, 20, "Rank 2", "Marksmanship" },
  }
  env.GetNumTrainerServices = function() return #rows end
  env.GetTrainerServiceInfo = function(i) return unpack(rows[i], 1, 6) end
  env.GetTrainerServiceCost = function(i) return 100 * i end
  env.GetTrainerServiceLevelReq = function(i) return rows[i][4] end
  local t = ns.Adapter.ReadTrainer(env)
  truthy(t.ok)
  eq(#t.rows, 3)
  eq(t.rows[1].kind, "available"); eq(t.rows[1].available, true); eq(t.rows[1].rank, nil); falsy(t.rows[1].header)
  eq(t.rows[2].kind, "used"); eq(t.rows[2].learned, true); eq(t.rows[2].rank, 2); eq(t.rows[2].sub, "Rank 2")
  eq(t.rows[3].kind, "unavailable"); eq(t.rows[3].learned, false); eq(t.rows[3].available, false); eq(t.rows[3].rank, 2)
  -- The rules then see the rows as they are: the learned one is left alone, the deferred one is judged.
  local computed = ns.TrainerOverlay.Compute(env)
  eq(computed.verdicts[2], nil, "a learned spell is not judged")
  eq(computed.verdicts[3].tier, "defer")
  -- Classic Era's order passes through untouched, headers included.
  eq({ ns.Adapter.TrainerServiceInfo("Wing Clip", "Rank 1", "used", 1) }, { "Wing Clip", "Rank 1", "used", 1 })
  eq({ ns.Adapter.TrainerServiceInfo("Survival", nil, "header", 1) }, { "Survival", nil, "header", 1 })
  eq({ ns.Adapter.TrainerServiceInfo("Track Humanoids", nil, "available", 1) }, { "Track Humanoids", nil, "available", 1 })
end)
