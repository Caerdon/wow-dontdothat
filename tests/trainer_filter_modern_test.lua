package.path = "./tests/?.lua;" .. package.path
local H = require("harness")

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
H.load("DontDoThat/Intercepts/Trainer.lua", ns)
H.load("DontDoThat/Intercepts/TrainerFilter.lua", ns)
local Filter = ns.TrainerFilter

-- Row frames shaped like Forever's: GetElementData() is a tree node whose GetData() holds skillIndex.
-- A category row has no service in its data.
local function row(skillIndex)
  local r = { alpha = 1 }
  function r:SetAlpha(a) self.alpha = a end
  function r:GetElementData() return { GetData = function() return { skillIndex = skillIndex } end } end
  return r
end
local function alphas(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.alpha end
  return out
end
-- A ScrollBox that only lets its rows be visited. Editing the list or redrawing it is refused, as taint would follow.
local function scrollBox(rows)
  return {
    ForEachFrame = function(_, fn) for _, r in ipairs(rows) do fn(r) end end,
    ForEachElementData = function() error("the list must not be read for editing") end,
    FullUpdate = function() error("a redraw from addon code taints the list") end,
  }
end
local function forbidRedraw() error("ClassTrainerFrame_Update must not run from addon code on Forever") end

local function services(n)
  local out = {}
  for i = 1, n do out[i] = { index = i } end
  return out
end

test("RenderModern fades the rows the verdicts defer and leaves the rest, without touching the list", function()
  Filter.ClearModern(nil)
  local rows = { row(1), row(2), row(3), row(nil) }
  local frame = { ScrollBox = scrollBox(rows) }
  local list = services(3)
  Filter.RenderModern({}, frame, { visible = { list[1], list[3] } }, list)
  eq(alphas(rows), { 1, 0.35, 1, 1 })
  eq(frame.DontDoThatFiltered, true)
  eq(Filter.modernHidden, { [2] = true })
end)

test("a row recycled while scrolling is faded as Blizzard sets it up", function()
  Filter.modernHidden = { [2] = true }
  local recycled = row(2)
  Filter.MarkModernRow(recycled)
  eq(recycled.alpha, 0.35)
  local shown = row(1)
  Filter.MarkModernRow(shown)
  eq(shown.alpha, 1)
  local category = row(nil)
  category.alpha = 0.35
  Filter.MarkModernRow(category)
  eq(category.alpha, 1)
  Filter.MarkModernRow({})
  Filter.MarkModernRow(nil)
  Filter.ClearModern(nil)
end)

test("ClearModern restores every row and forgets the set", function()
  local rows = { row(1), row(2) }
  local frame = { ScrollBox = scrollBox(rows) }
  local list = services(2)
  Filter.RenderModern({}, frame, { visible = { list[1] } }, list)
  eq(alphas(rows), { 1, 0.35 })
  Filter.ClearModern(frame)
  eq(alphas(rows), { 1, 1 })
  eq(Filter.modernHidden, nil)
  Filter.ClearModern({})
  Filter.ClearModern(nil)
end)

test("RenderModern raises when the rows cannot be visited, so the caller degrades", function()
  local ok = pcall(Filter.RenderModern, {}, { ScrollBox = {} }, { visible = {} }, {})
  eq(ok, false)
  Filter.ClearModern(nil)
end)

-- Apply on a Forever window, end to end: the filter is decided by the overlay's verdicts, and nothing of
-- Blizzard's is redrawn or edited on the way.
local function forever(verdicts)
  Filter.Reset()
  Filter.ClearModern(nil)
  local rows = { row(1), row(2), row(3) }
  local frame = { ScrollBox = scrollBox(rows), IsVisible = function() return true end }
  local env = { ClassTrainerFrame = frame, ClassTrainerFrame_Update = forbidRedraw }
  local list = services(3)
  ns.db = { profile = {} }
  ns.TrainerOverlay.Compute = function() return { rows = list, verdicts = verdicts } end
  ns.TrainerVisibility = { Compute = function(services, verdictFor)
    local result = { visible = {}, hiddenCount = 0 }
    for _, s in ipairs(services) do
      local v = verdictFor(s)
      if v and v.tier == "defer" then result.hiddenCount = result.hiddenCount + 1 else result.visible[#result.visible + 1] = s end
    end
    return result
  end }
  return env, frame, rows
end

test("Apply fades deferred rows on Forever and never redraws Blizzard's list", function()
  local env, frame, rows = forever({ [2] = { tier = "defer" }, [3] = { tier = "keep" } })
  eq(Filter.Apply(env), true)
  eq(alphas(rows), { 1, 0.35, 1 })
  eq(Filter.DegradedReason(), nil)
  -- Applied again from inside or outside Blizzard's update, the rows stay as they are.
  eq(Filter.Apply(env), true)
  eq(alphas(rows), { 1, 0.35, 1 })
  Filter.ClearModern(frame)
end)

test("switching the Recommended entry off puts the rows back without a redraw", function()
  local env, frame, rows = forever({ [2] = { tier = "defer" } })
  eq(Filter.Apply(env), true)
  eq(alphas(rows), { 1, 0.35, 1 })
  ns.db.profile.recommendedActive = false
  eq(Filter.Apply(env), false)
  eq(alphas(rows), { 1, 1, 1 })
  eq(Filter.modernHidden, nil)
  -- Refresh (a settings change) goes through Apply on Forever, not through ClassTrainerFrame_Update.
  ns.db.profile.recommendedActive = true
  Filter.Refresh(env)
  eq(alphas(rows), { 1, 0.35, 1 })
  Filter.ClearModern(frame)
end)

test("beast training (no verdicts) clears a fade left by the last trainer", function()
  local env, frame, rows = forever({ [2] = { tier = "defer" } })
  eq(Filter.Apply(env), true)
  ns.TrainerOverlay.Compute = function() return nil end
  eq(Filter.Apply(env), false)
  eq(alphas(rows), { 1, 1, 1 })
  eq(Filter.modernHidden, nil)
end)

test("a failure while fading turns the filter off and restores the rows, with no redraw", function()
  local env, frame, rows = forever({ [2] = { tier = "defer" } })
  frame.ScrollBox.ForEachFrame = function(_, fn)
    for i, r in ipairs(rows) do
      if i == 2 then error("boom") end
      fn(r)
    end
  end
  eq(Filter.Apply(env), false)
  truthy(Filter.DegradedReason())
  eq(Filter.modernHidden, nil)
  Filter.Reset()
end)
