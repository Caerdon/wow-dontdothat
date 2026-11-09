local addonName, ns = ...

-- Template for a translation: copy this file to Locales/deDE.lua (or frFR, esES, ...), change the locale below,
-- translate the right-hand sides, and add the file to both TOC files after Locales\enUS.lua.
-- Keep every %s and %d in a translation, as many as the English has; a test checks the count.
-- Leave out any sentence you do not translate: it shows in English.
if type(GetLocale) ~= "function" or GetLocale() ~= "xxXX" then return end

local L = ns.L
-- L["Buy anyway?"] = "..."
-- L["Costs about %s"] = "..."

-- Skip list revisions: the reasons a rank is skipped, where a skip came from, and the notice and replies about them.
-- The numbers (%d) are filled in by the addon; keep them in your translation.
-- L["Original using Expert Advice"] = "..."
-- L["Revised with Rules + Expert Advice"] = "..."
-- L["Skip list revision %d is in use (the default)."] = "..."
-- L["Skip list revision %d is in use."] = "..."
-- L["Revision %d: %s"] = "..."
-- L["To change it, type /ddt revision followed by the number, or open Advanced > Tuning."] = "..."
-- L["Now using skip list revision %d."] = "..."
-- L["%s is not a skip list revision. The revisions are: %s."] = "..."
-- L["Revision %d changes the rules significantly: many more ranks are skipped, decided for your spec, and every skip now says why."] = "..."
-- L["To go back to the earlier list, type /ddt revision 1 or open Advanced > Tuning."] = "..."
-- L["A newer revision exists, revision %d. It changes the rules significantly: many more ranks are skipped, decided for your spec, and every skip says why."] = "..."
-- L["To try it, type /ddt revision %d or open Advanced > Tuning."] = "..."
-- L["The leveling guide says to buy only the first rank of this spell."] = "..."
-- L["The leveling guide says this spell is not worth buying while leveling."] = "..."
-- L["The leveling guide says to buy this spell only up to rank %d."] = "..."
-- L["The leveling guide does not buy this rank while leveling."] = "..."
-- L["Adds nothing over the rank before it."] = "..."
-- L["Only %d%% stronger than the rank before it, for a spell you only use now and then."] = "..."
-- L["Only %d%% stronger than the rank before it, which does not repay its price."] = "..."
-- L["This rank can wait until you have your level 60 mount."] = "..."
-- L["An earlier version of this list judged this rank a small upgrade."] = "..."
-- L["From the Wowhead leveling guide."] = "..."
-- L["Computed from the game data."] = "..."
-- L["From the earlier skip list."] = "..."
-- L["Skip list"] = "..."
-- L["Revision %d (default): %s"] = "..."
-- L["Which skip list should be used?"] = "..."
-- L["Which ranks to skip is decided by a numbered revision of the skip list. Pick an earlier one to go back to what an older version advised."] = "..."
-- L["The Rules page lists the ranks to skip for the revision you pick, with the reason for each."] = "..."
-- L["Ranks to skip follow skip list revision %d. You can change it on the Tuning page."] = "..."
-- L["Skip rank%s %s. %s %s"] = "..."
-- L["usage: /ddt [debug on|off | clear | probe | export | test | revision [number] | trainerids [hover]]"] = "..."
