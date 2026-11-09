-- Resolves the rule files' names to spell family IDs with the addon's own Model/SpellData.lua and writes JSON to stdout.
-- Usage: luajit dump_rules.lua <path to the DontDoThat addon folder>
local ROOT = (arg[1] or "DontDoThat"):gsub("/?$", "/")
local function ser(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then local p = {} for _, x in ipairs(v) do p[#p+1] = ser(x) end return "["..table.concat(p, ",").."]" end
    local p = {} for k, x in pairs(v) do p[#p+1] = string.format("%q:%s", tostring(k), ser(x)) end return "{"..table.concat(p, ",").."}"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "number" or t == "boolean" then return tostring(v) else return "null" end
end
local L = setmetatable({}, {__index=function(_, k) return k end})
local ns = { L = L }
local function load(path) assert(loadfile(ROOT..path))("DontDoThat", ns) end
load("Data/SpellData.lua"); load("Data/RuleSpells.lua"); load("Model/SpellData.lua")
local SD = ns.SpellData
local classes = {"Druid","Hunter","Mage","Paladin","Priest","Rogue","Shaman","Warlock","Warrior"}
local function ids(cls, names)
  local out, missing = {}, {}
  for _, n in ipairs(names or {}) do
    if n:sub(1,1) == "~" then
      for _, id in ipairs(SD.FamiliesWithPrefix(cls, n:sub(2))) do out[#out+1] = id end
    else
      local id = SD.FamilyId(cls, n)
      if id then out[#out+1] = id else missing[#missing+1] = n end
    end
  end
  return out, missing
end
local res = {}
ns.Rules = { Load = function(t)
  local cls = t.class
  local specs = {}
  local unresolved = {}
  for key, sp in pairs(t.specs) do
    local core, m1 = ids(cls, sp.rotation and sp.rotation.core)
    local sit, m2 = ids(cls, sp.rotation and sp.rotation.situational)
    specs[key] = { name = sp.name, core = core, sit = sit }
    for _, n in ipairs(m1) do unresolved[n] = true end for _, n in ipairs(m2) do unresolved[n] = true end
  end
  local tags = {}
  for name, tg in pairs(t.tags or {}) do
    local list = ids(cls, {name})
    for _, id in ipairs(list) do tags[tostring(id)] = tg end
  end
  local skips = {}
  for name, rk in pairs(t.skipRanks or {}) do
    local list, miss = ids(cls, {name})
    for _, id in ipairs(list) do skips[tostring(id)] = rk end
    for _, n in ipairs(miss) do unresolved[n] = true end
  end
  local un = {} for n in pairs(unresolved) do un[#un+1] = n end
  res[cls] = { specs = specs, tags = tags, skipRanks = skips, unresolved = un }
end }
for _, c in ipairs(classes) do load("Rules/Data/"..c..".lua") end
-- families: trainer rows grouped by family id
local fams = {}
for cls in pairs(res) do
  local f = {}
  for _, row in ipairs(SD.Rows(cls)) do
    if row.rank and (row.kind == "class" or row.kind == "pet") then
      local fid = SD.FamilyOfId(cls, row.id)
      f[tostring(fid)] = f[tostring(fid)] or { name = SD.FamilyName(cls, fid), rows = {} }
      table.insert(f[tostring(fid)].rows, { id = row.id, rank = row.rank, level = row.level, kind = row.kind, cost = row.cost })
    end
  end
  res[cls].families = f
end
local parts = {}
for cls, r in pairs(res) do parts[#parts+1] = string.format("%q:%s", cls, ser(r)) end
io.write("{"..table.concat(parts, ",").."}")
