-- Minimal test harness. Runs outside the game with no WoW globals.
-- Test files live in tests/*_test.lua and call test(name, fn) and the assert helpers.

local H = { passed = 0, failed = 0, failures = {} }

function H.load(path, ns)
  -- Loads an addon file the way WoW does: the file receives (addonName, ns) as varargs.
  local chunk, err = loadfile(path)
  if not chunk then error(err, 2) end
  -- The TOC loads Locales/enUS.lua first; tests that build a bare ns get the same English-as-key table.
  ns.L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
  return chunk("DontDoThat", ns)
end

function H.deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not H.deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function fail(msg)
  error(msg, 3)
end

function _G.eq(actual, expected, msg)
  if not H.deepEqual(actual, expected) then
    fail((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

function _G.truthy(value, msg)
  if not value then fail(msg or "expected a truthy value") end
end

function _G.falsy(value, msg)
  if value then fail(msg or "expected a falsy value") end
end

function _G.raises(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then fail(msg or "expected an error") end
  if pattern and not tostring(err):find(pattern, 1, true) then
    fail((msg or "error text mismatch") .. ": expected to contain '" .. pattern .. "', got '" .. tostring(err) .. "'")
  end
end

function _G.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    H.passed = H.passed + 1
  else
    H.failed = H.failed + 1
    H.failures[#H.failures + 1] = name .. "\n    " .. tostring(err)
  end
end

-- { [familyId] = { ranks } } that one skip revision skips for a loaded class's data (the shape the old skipRanks table had).
function H.skipRanks(data, rev)
  local out = {}
  for family, ranks in pairs(data.skipRevisions[rev]) do
    local list = {}
    for rank, entries in pairs(ranks) do if #entries > 0 then list[#list + 1] = rank end end
    table.sort(list)
    if #list > 0 then out[family] = list end
  end
  return out
end

-- Skip revision 1 for synthetic rule data written with names: { Skipper = { 2 } } -> a revision that skips rank 2 of Skipper.
function H.skipRevisions(map)
  local entries = {}
  for name, ranks in pairs(map) do
    entries[name] = {}
    for _, rank in ipairs(ranks) do entries[name][rank] = { { source = "legacy", reason = { kind = "legacy" } } } end
  end
  return { [1] = { entries = entries } }
end

-- A resolver for synthetic rule data in tests: the name written is the key the engine uses.
H.sameKeys = { id = function(name) return name end, prefix = function() return {} end }

-- Loads the spell tables and the code that reads them, the way the TOC does before any rule data.
function H.loadSpellTables(ns)
  H.load("DontDoThat/Data/SpellData.lua", ns)
  H.load("DontDoThat/Data/RuleSpells.lua", ns)
  H.load("DontDoThat/Data/SkipRevisions.lua", ns)
  H.load("DontDoThat/Data/TalentData.lua", ns)
  H.load("DontDoThat/Model/SpellData.lua", ns)
end

-- The family ID of an English spell name, as rule data resolves it. Fails the test on an unknown name.
function H.fid(ns, class, name)
  local id = ns.SpellData.FamilyId(class, name)
  if not id then error("no spell named '" .. tostring(name) .. "' for " .. tostring(class), 2) end
  return id
end

-- { ["Name"] = true } -> { [familyId] = true }, or nil when the set is nil (the client could not say).
function H.talentSet(ns, class, names)
  if names == nil then return nil end
  local out = {}
  for name, on in pairs(names) do out[H.fid(ns, class, name)] = on end
  return out
end

function H.report()
  for _, f in ipairs(H.failures) do print("FAIL  " .. f) end
  print(("%d passed, %d failed"):format(H.passed, H.failed))
  return H.failed == 0
end

return H
