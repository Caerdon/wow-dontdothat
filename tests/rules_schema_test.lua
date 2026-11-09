package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local function fresh()
  local ns = {}
  H.load("DontDoThat/Rules/Schema.lua", ns)
  H.load("DontDoThat/Rules/Engine.lua", ns)
  return ns
end

local function sample()
  return {
    class = "TEST",
    specs = { A = { rotation = { core = { "X" }, situational = {} } } },
    tagTiers = { PvP = "deferLow" },
    tags = { Y = { "PvP" } },
    overrides = { Z = "keep" },
    ranks = { X = { { rank = 1, unlockLevel = 4 }, { rank = 2, unlockLevel = 10, cost = 100 } } },
  }
end

test("rules: valid sample loads and is retrievable", function()
  local ns = fresh()
  ns.Rules.Load(sample(), H.sameKeys)
  truthy(ns.Rules.GetClass("TEST"))
end)

test("rules: malformed data is rejected with a clear message", function()
  local ns = fresh()
  local d = sample(); d.specs.A.rotation.core = { 5 }
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "specs.A.rotation.core[1]")
  d = sample(); d.tags.Y = { "Nope" }
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "no entry in tagTiers")
  d = sample(); d.overrides.Z = "bogus"
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "unknown tier")
  d = sample(); d.ranks.X[2].unlockLevel = 2
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "unlockLevel")
  d = sample(); d.ranks.X[1].cost = 1.5
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "copper")
  d = sample(); d.class = nil
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "'class' string")
  raises(function() ns.Rules.Load("x", H.sameKeys) end, "must be a table")
  d = sample(); d.specs = {}
  raises(function() ns.Rules.Load(d, H.sameKeys) end, "specs")
end)

test("rules: adding a class needs data only", function()
  local ns = fresh()
  ns.Rules.Load(sample(), H.sameKeys)
  local v = ns.Rules.Evaluate({ class = "TEST", plausibleSpecs = { "A" }, milestone = { current = 40, state = "active" } },
    { kind = "spell", name = "X", familyId = "X" })
  eq(v.tier, "keep")
  eq(v.source, "rotation")
end)

local function skipEntry(source, reason, specs)
  return { source = source or "computed", reason = reason or { kind = "noGain" }, specs = specs }
end

local function loadRevisions(revisions)
  local ns = fresh()
  local data = sample()
  data.skipRevisions = revisions
  return pcall(ns.Rules.Load, data, H.sameKeys), ns
end

test("schema: skip revisions must be well formed", function()
  truthy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry() } } } } }))
  truthy(loadRevisions({ [1] = { entries = {} }, [2] = { inherits = 1, entries = { X = { [3] = {} } } } }), "an empty list removes a skip")
  truthy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry("guide", { kind = "guideUpToRank", n = 4 }, { "A" }) } } } } }))
  falsy(loadRevisions({ [1] = { entries = { X = { [1] = { skipEntry() } } } } }), "rank 1 is never skipped")
  falsy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry("rumour") } } } } }), "unknown source")
  falsy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry("computed", { kind = "madeUp" }) } } } } }), "unknown reason kind")
  falsy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry("computed", { kind = "smallStep" }) } } } } }), "a reason kind needs its number")
  falsy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry("computed", nil, { "Z" }) } } } } }), "spec the class does not have")
  falsy(loadRevisions({ [1] = { entries = { X = { [2] = { skipEntry("computed", nil, {}) } } } } }), "empty spec list")
  falsy(loadRevisions({ [0] = { entries = {} } }), "revision numbers start at 1")
  falsy(loadRevisions({ [1] = { inherits = 1, entries = {} } }), "a revision inherits an earlier one")
  falsy(loadRevisions({ [2] = { inherits = 1, entries = {} } }), "inherits a revision that exists")
  falsy(loadRevisions({ [1] = {} }), "needs entries")
end)

test("schema: a revision builds on an earlier one, rank by rank", function()
  local ok, ns = loadRevisions({
    [1] = { entries = { X = { [2] = { skipEntry("legacy", { kind = "legacy" }) }, [3] = { skipEntry("legacy", { kind = "legacy" }) } },
                        Y = { [2] = { skipEntry("legacy", { kind = "legacy" }) } } } },
    [2] = { inherits = 1, entries = { X = { [3] = {} , [4] = { skipEntry("computed", { kind = "smallStep", pct = 12 }) } } } },
    [3] = { inherits = 2, entries = { Y = { [2] = { skipEntry("guide", { kind = "guideNotTrained" }) } } } },
  })
  truthy(ok)
  local data = ns.Rules.GetClass("TEST")
  eq(#data.skipRevisions[1].X[3], 1)
  eq(#data.skipRevisions[2].X[2], 1, "a rank the revision does not name keeps the earlier entry")
  eq(#data.skipRevisions[2].X[3], 0, "an empty list removes the skip")
  eq(data.skipRevisions[2].X[4][1].reason.pct, 12)
  eq(data.skipRevisions[2].Y[2][1].source, "legacy")
  eq(data.skipRevisions[3].Y[2][1].source, "guide", "the later revision replaces the entry")
  eq(data.skipRevisions[3].X[4][1].source, "computed", "and keeps what it does not name")
  eq(data.skipRevisions[1].X[4], nil, "an earlier revision is not touched by a later one")
  eq(ns.Rules.SkipRevisionNumbers(), { 1, 2, 3 })
  eq(ns.Rules.NewestRevision(), 3)
end)

test("compile: names become family IDs and the source data is left alone", function()
  local ns = fresh()
  local data = sample()
  local compiled = ns.Rules.Compile(data, { id = function(n) return #n + 10 end, prefix = function() return {} end })
  for _, spec in pairs(compiled.specs) do
    for _, id in ipairs(spec.rotation.core) do truthy(type(id) == "number", "core holds IDs") end
  end
  eq(data.specs.A.rotation.core[1], "X", "the source still holds the name")
end)

test("compile: a name that matches no spell raises an error naming the class, the rule and the spell", function()
  local ns = fresh()
  local data = sample()
  data.specs.A.rotation.core = { "Nonesuch" }
  raises(function() ns.Rules.Compile(data, { id = function() return nil end, prefix = function() return {} end }) end,
    "TEST specs.A.rotation.core): no spell named 'Nonesuch'")
end)

test("compile: a ~Prefix entry stands for every family with that prefix, and one that matches nothing is an error", function()
  local ns = fresh()
  local data = sample()
  data.why = { ["~Create"] = "Wait." }
  local resolver = { id = function(n) return n == "X" and 1 or 2 end, prefix = function(p) return p == "Create" and { 5, 6 } or {} end }
  local compiled = ns.Rules.Compile(data, resolver)
  eq(compiled.why[5], "Wait."); eq(compiled.why[6], "Wait.")
  data.why = { ["~Nothing"] = "Wait." }
  raises(function() ns.Rules.Compile(data, resolver) end, "no spell name starts with 'Nothing'")
end)
