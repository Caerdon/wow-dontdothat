-- Checks for translation files (see docs/localization.md): every key must be a sentence the addon source asks for,
-- and a translation must carry the same format placeholders as its key.
local M = {}

-- Reads a Lua string literal starting at src[i] (a quote) and returns its value and the index after it.
local function literal(src, i)
  local q, j = src:sub(i, i), i + 1
  while j <= #src and src:sub(j, j) ~= q do
    if src:sub(j, j) == "\\" then j = j + 1 end
    j = j + 1
  end
  local chunk = loadstring("return " .. src:sub(i, j))
  return chunk and chunk(), j + 1
end

-- Adds every L["..."] key in one source file to `used`.
local function scan(path, used)
  local f = io.open(path); local src = f:read("*a"); f:close()
  local pos = 1
  while true do
    local s, e = src:find("%f[%w_]L%[", pos)
    if not s then break end
    local c = src:sub(e + 1, e + 1)
    if c == '"' or c == "'" then
      local value, after = literal(src, e + 1)
      if type(value) == "string" then used[value] = true end
      pos = after
    else
      pos = e + 1
    end
  end
end

-- Every L["..."] key in the addon source under dir (libraries and locale files excluded).
function M.usedKeys(dir)
  local used = {}
  local p = io.popen('find "' .. dir .. '" -name "*.lua" -not -path "*/Libs/*" -not -path "*/Locales/*"')
  for path in p:lines() do scan(path, used) end
  p:close()
  return used
end

-- The keys one source file asks for.
function M.keysInFile(path)
  local used = {}
  scan(path, used)
  return used
end

-- The translations a locale file makes, read by running it as the game would for that locale.
function M.translations(path, locale)
  local out = {}
  local ns = { L = setmetatable({}, { __newindex = function(_, k, v) out[k] = v end }) }
  local env = setmetatable({ GetLocale = function() return locale end }, { __index = _G })
  local chunk = assert(loadfile(path))
  setfenv(chunk, env)
  chunk("DontDoThat", ns)
  return out
end

local function placeholders(s)
  local n = 0
  for _ in s:gsub("%%%%", ""):gmatch("%%[%d%.%-%$]*[sdfgxXi]") do n = n + 1 end
  return n
end

-- Returns a list of problems; empty when the file is sound.
function M.check(translations, used)
  local problems = {}
  for key, value in pairs(translations) do
    if not used[key] then
      problems[#problems + 1] = ("unused key: %q"):format(key)
    elseif type(value) ~= "string" then
      problems[#problems + 1] = ("not text: %q"):format(key)
    elseif placeholders(key) ~= placeholders(value) then
      problems[#problems + 1] = ("placeholder count differs: %q"):format(key)
    end
  end
  table.sort(problems)
  return problems
end

return M
