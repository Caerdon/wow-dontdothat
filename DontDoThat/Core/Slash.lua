local addonName, ns = ...
local L = ns.L

local addon = ns.addon

local function say(msg)
    addon:Print(msg)
end

function addon:HandleSlash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    rest = (rest or ""):lower()

    if cmd == "" then
        if type(self.OpenOptions) == "function" then
            self:OpenOptions()
        else
            say(L["settings not available yet"])
        end
    elseif cmd == "debug" then
        if rest ~= "on" and rest ~= "off" then
            say(L["usage: /ddt debug on|off"])
            return
        end
        local on = (rest == "on")
        if self.db and self.db.profile then
            self.db.profile.debug = on
        end
        if ns.Log then
            ns.Log.SetEnabled(on)
        end
        say("debug " .. rest)
    elseif cmd == "clear" then
        if ns.Log and type(ns.Log.ClearAll) == "function" then
            ns.Log.ClearAll()
            say(L["log cleared"])
        else
            say(L["log not available yet"])
        end
    elseif cmd == "probe" then
        if ns.Probe and ns.Export then
            ns.Export.Show({ probe = function() return ns.Probe.Run(nil, self.db and self.db.global.probe) end })
        else
            say(L["probe not available yet"])
        end
    elseif cmd == "trainerids" then
        -- With a trainer window open: can the addon get a spell ID for each row? Shows what every known method returns.
        if ns.Probe and ns.Export then
            local function show(withHover)
                ns.Export.Show({ probe = function()
                    local text = ns.Probe.TrainerIds()
                    if withHover then text = text .. "\n\n== hovered row ==\n" .. ns.Probe.HoveredSpell() end
                    return text
                end })
            end
            if rest == "hover" and _G.C_Timer then
                say("hover over a trainer row now; the report opens in 5 seconds")
                _G.C_Timer.After(5, function() show(true) end)
            else
                show(false)
            end
        else
            say("probe not available yet")
        end
    elseif cmd == "export" then
        if ns.Export and type(ns.Export.Show) == "function" then
            ns.Export.Show()
        else
            say(L["export not available yet"])
        end
    elseif cmd == "test" then
        -- Acts like a purchase of a deferred spell with your current settings, but buys nothing.
        say(L["test (build %s)"]:format(tostring(ns.build)))
        if ns.TrainerConfirm then ns.TrainerConfirm.Test(say) else say(L["test: not available yet"]) end
    elseif cmd == "revision" then
        -- The skip list revision: show it, or pick one. (rest was lowercased above; a number is unaffected.)
        for _, line in ipairs(ns.SkipRevision.Command(rest, self.db and self.db.profile)) do say(line) end
        if ns.Options and ns.Options.Rebuild and rest ~= "" then pcall(ns.Options.Rebuild) end
    elseif cmd == "version" then
        say(L["Don't Do That v%s (build %s)"]:format(tostring(ns.version), tostring(ns.build)))
    else
        say(L["Don't Do That v%s"]:format(tostring(ns.version)))
        say(L["usage: /ddt [debug on|off | clear | probe | export | test | revision [number] | trainerids [hover]]"])
    end
end

addon:RegisterChatCommand("ddt", "HandleSlash")
addon:RegisterChatCommand("dontdothat", "HandleSlash")
