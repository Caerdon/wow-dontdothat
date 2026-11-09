local addonName, ns = ...
local L = ns.L

-- Which skip revision the player is on, how to change it, and the notice printed when a profile first meets a
-- new revision. Pure: takes the saved profile table (see Model/Settings.lua) and returns the lines to say.
local SkipRevision = {}
ns.SkipRevision = SkipRevision

-- One line per revision, for the Tuning page and /ddt revision. Revisions the addon gains later add a line here.
local DESCRIPTIONS = {
  [1] = L["Original using Expert Advice"],
  [2] = L["Revised with Rules + Expert Advice"],
}

function SkipRevision.Describe(revision) return DESCRIPTIONS[revision] or "" end

function SkipRevision.Available() return ns.Rules.SkipRevisionNumbers() end

function SkipRevision.Newest() return ns.Rules.NewestRevision() end

-- The revision the engine uses for this profile: the pick when it exists, else the newest.
function SkipRevision.InUse(p) return ns.Rules.ResolveRevision(ns.Settings.SkipRevision(p)) end

local function numbers(list)
  local out = {}
  for _, rev in ipairs(list) do out[#out + 1] = tostring(rev) end
  return table.concat(out, ", ")
end

-- The lines /ddt revision prints with no argument.
function SkipRevision.Status(p)
  local inUse, newest = SkipRevision.InUse(p), SkipRevision.Newest()
  local lines = {}
  if inUse == newest and ns.Settings.SkipRevision(p) == nil then
    lines[1] = (L["Skip list revision %d is in use (the default)."]):format(inUse)
  else
    lines[1] = (L["Skip list revision %d is in use."]):format(inUse)
  end
  for _, rev in ipairs(SkipRevision.Available()) do
    lines[#lines + 1] = (L["Revision %d: %s"]):format(rev, SkipRevision.Describe(rev))
  end
  lines[#lines + 1] = L["To change it, type /ddt revision followed by the number, or open Advanced > Tuning."]
  return lines
end

-- Handles /ddt revision <argument>. Returns the lines to print; changes the saved choice only for a valid revision.
function SkipRevision.Command(argument, p)
  argument = (argument or ""):match("^%s*(.-)%s*$")
  if argument == "" then return SkipRevision.Status(p) end
  local wanted = tonumber(argument)
  for _, rev in ipairs(SkipRevision.Available()) do
    if wanted == rev then
      ns.Settings.SetSkipRevision(rev, p)
      return { (L["Now using skip list revision %d."]):format(rev) }
    end
  end
  return { (L["%s is not a skip list revision. The revisions are: %s."]):format(argument, numbers(SkipRevision.Available())) }
end

-- The notice for a profile that has not been told about the newest revision yet, or nil. It is meant to be printed
-- once: Notice marks the profile as told. A new install and an update both count as "not told yet".
function SkipRevision.Notice(p)
  local newest = SkipRevision.Newest()
  if not newest or not ns.Settings.RevisionNoticeDue(newest, p) then return nil end
  local inUse = SkipRevision.InUse(p)
  local lines = {}
  if inUse == newest then
    lines[1] = (L["Skip list revision %d is in use."]):format(inUse)
    lines[2] = (L["Revision %d changes the rules significantly: many more ranks are skipped, decided for your spec, and every skip now says why."]):format(newest)
    lines[3] = L["To go back to the earlier list, type /ddt revision 1 or open Advanced > Tuning."]
  else
    lines[1] = (L["Skip list revision %d is in use."]):format(inUse)
    lines[2] = (L["A newer revision exists, revision %d. It changes the rules significantly: many more ranks are skipped, decided for your spec, and every skip says why."]):format(newest)
    lines[3] = (L["To try it, type /ddt revision %d or open Advanced > Tuning."]):format(newest)
  end
  ns.Settings.MarkRevisionNotice(newest, p)
  return lines
end

return SkipRevision
