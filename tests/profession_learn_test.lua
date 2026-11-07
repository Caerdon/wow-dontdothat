package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = { Log = { Add = function() end } }
H.loadSpellTables(ns)
H.load("DontDoThat/Rules/Schema.lua", ns)
H.load("DontDoThat/Rules/Engine.lua", ns)
H.load("DontDoThat/Rules/Data/ProfessionLearn.lua", ns)
H.load("DontDoThat/Intercepts/Adapter.lua", ns)

local function profile(extra)
  local p = { class = "TEST", level = 25, plausibleSpecs = {}, professions = {}, professionAsked = {},
    milestone = { current = 40, state = "active" } }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end
-- Professions are identified by the spell ID of their apprentice tier.
local LEATHERWORKING, HERBALISM, COOKING, ENGINEERING = 2108, 2366, 2550, 4036
local SKINNING, MINING, FISHING = 8613, 2575, 7620
local function learn(id, name) return { kind = "professionLearn", name = name or "x", displayName = name, profession = id, cost = 1000 } end

test("a gathering profession is never asked about, anything else is", function()
  for _, id in ipairs({ SKINNING, HERBALISM, MINING, FISHING }) do
    eq(ns.Rules.MatchProfessionLearn(id), nil, id)
  end
  eq(ns.Rules.MatchProfessionLearn(LEATHERWORKING), LEATHERWORKING)
  eq(ns.Rules.MatchProfessionLearn("Leatherworking"), nil, "only IDs match, never text")
  eq(ns.Rules.MatchProfessionLearn(nil), nil)
end)

test("rule data that makes a profession gathering without an apprentice spell is an error", function()
  raises(function() ns.Rules.SetProfessionLearn({ gathering = { Cooking = true }, apprentice = {}, reason = "x" }) end,
    "gathering profession 'Cooking' has no apprentice spell")
  H.load("DontDoThat/Rules/Data/ProfessionLearn.lua", ns)
end)

test("a trainer row is recognised by the client's name for the apprentice spell, in any language", function()
  local env = { GetSpellInfo = function(id) return "Z" .. id end }
  eq(ns.Adapter.ProfessionId(env, "Z2108"), LEATHERWORKING)
  eq(ns.Adapter.ProfessionId(env, "Z2366"), HERBALISM, "Herb Gathering is the spell, Herbalism the profession")
  eq(ns.Adapter.ProfessionId(env, "Leatherworking"), LEATHERWORKING, "the English name still matches")
  eq(ns.Adapter.ProfessionId(env, "Bogus"), nil)
  eq(ns.Adapter.ProfessionId({}, "Cooking"), COOKING, "a client that names nothing falls back to the English names")
end)

test("a profession counts as known by its skill line or by the spellbook knowing its apprentice spell", function()
  local env = { GetSpellInfo = function(id) return "Z" .. id end,
    GetNumSkillLines = function() return 2 end,
    GetSkillLineInfo = function(i)
      if i == 1 then return "Z2550", false, true, 40, 0, 0, 75 end
      return "Profession", true
    end,
    IsSpellKnown = function(id) return id == 2108 end }
  local known = ns.Adapter.ReadProfessions(env)
  eq(known[COOKING].skill, 40)
  truthy(known[LEATHERWORKING], "known through the spellbook")
  falsy(known[3908], "Tailoring is not known")
end)

test("professions are read from C_SkillInfo when the legacy skill calls are gone", function()
  local env = { GetSpellInfo = function(id) return "Z" .. id end,
    C_SkillInfo = {
      GetNumSkillLines = function() return 2 end,
      GetSkillLineInfo = function(i)
        if i == 1 then return { name = "Z2550", isHeader = false, rank = 40, maxRank = 75 } end
        return { name = "Profession", isHeader = true }
      end,
    },
    IsSpellKnown = function() return false end }
  local known = ns.Adapter.ReadProfessions(env)
  eq(known[COOKING].skill, 40)
  eq(known[COOKING].max, 75)
end)

test("the first time: defer with a direct reason naming the profession and no cost", function()
  local v = ns.Rules.Evaluate(profile(), learn(LEATHERWORKING, "Leatherworking"))
  eq(v.tier, "defer"); eq(v.source, "professionLearn"); eq(v.profession, LEATHERWORKING); eq(v.cost, nil)
  truthy(v.reason:find("Leatherworking", 1, true))
  truthy(ns.Rules.Evaluate(profile(), learn(LEATHERWORKING)).reason:find("Leatherworking", 1, true), "English name when the client gives none")
end)

test("already asked or already known means keep", function()
  eq(ns.Rules.Evaluate(profile({ professionAsked = { [LEATHERWORKING] = true } }), learn(LEATHERWORKING)).tier, "keep")
  eq(ns.Rules.Evaluate(profile({ professions = { [LEATHERWORKING] = { skill = 1, max = 75 } } }), learn(LEATHERWORKING)).tier, "keep")
end)

test("no warning once the mount milestone is over", function()
  eq(ns.Rules.Evaluate(profile({ milestone = { state = "finished" } }), learn(LEATHERWORKING)).tier, "keep")
end)

test("answering either way records the profession; alert-only mode records nothing", function()
  local function run(promptsOn, answer)
    local n = { Log = { Add = function() end } }
    n.db = { profile = {} }
    n.Settings = { MarkProfessionAsked = function(prof) n.db.profile.professionAsked = { [prof] = true } end,
      PromptTiers = function() return { defer = true } end, PromptsFor = function() return true end }
    n.Alert = { Trigger = function() end }
    local ask
    n.ConfirmPopup = { Ask = function(_, yes, no) ask = { yes = yes, no = no }; return true end }
    H.load("DontDoThat/Intercepts/Confirm.lua", n)
    n.TrainerConfirm.Reset()
    n.db.profile.blockingConfirmations = promptsOn
    n.TrainerOverlay = { Compute = function()
      return { verdicts = { [3] = { tier = "defer", source = "professionLearn", profession = 4036, name = "Engineering", reason = "r" } } }
    end }
    local button = { script = function() end }
    button.GetScript = function(self) return self.script end
    button.SetScript = function(self, _, fn) self.script = fn end
    local env = { ClassTrainerTrainButton = button, ClassTrainerFrame = { selectedService = 3 } }
    n.TrainerConfirm.Install(env)
    button.script(button)
    if ask and answer then ask[answer]() end
    return n.db.profile.professionAsked
  end
  eq(run(true, "yes"), { [4036] = true })
  eq(run(true, "no"), { [4036] = true })
  eq(run(false), nil, "blocking confirmations off: no question, nothing recorded")
end)
