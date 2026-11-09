local addonName, ns = ...

local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")

local addon = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0")
ns.addon = addon

ns.defaults = {
    profile = {
        enabled = true,
        blockingConfirmations = true,
        warnings = true,
        alerts = true,
        recommendedFilter = true,   -- the filter is offered (What to watch page)
        recommendedActive = true,   -- its checkbox in the trainer's Filter menu is ticked
        -- Where each kind of item is warned about: off | vendor | ah | both. Keys match Model/ItemCategory.lua.
        itemModes = {
            armor = "both", weapons = "both", vanity = "both",
            bags = "ah", recipes = "ah", potions = "ah", gems = "ah", food = "ah",
            trade = "ah", ammo = "ah", reagents = "ah",
            mounts = "off", misc = "off",
        },
        watch = { spells = true, professions = true, shopping = true }, -- the areas of What to watch
        guard = { bank = true, stable = true, cod = true }, -- one-click sinks asked about (What to watch page, Other)
        minPrice = 100,             -- copper; cheaper purchases are never warned about (10 silver)
        alert = {
            sound = "raidwarning",
            channel = "Master",
            banner = true,
            cooldown = 3,
        },
        -- Rules the player switched off (Advanced > Classes). A present key means off, so rules added later are on.
        ruleOff = { abilities = {}, tags = {}, kinds = {} }, -- abilities/tags: class -> name -> true; kinds: kind -> true
        specOverride = {},          -- class -> spec key; absent means inferred from talents
        tuning = { stopAfter = 60, promptTiers = { defer = true, deferLow = false, info = false } },
        debug = false,
        traceItems = false,         -- keep a saved record of each vendor and auction decision (Debug page)
    },
    char = {
        ledger = {},
        costCache = {},
        catalog = {},
    },
    global = {
        log = {},
        probe = {},
        icons = {}, -- spell family ID -> icon, learned from trainer windows
        itemTrace = {}, -- recent vendor and auction decisions, shown by /ddt export
    },
}

function addon:OnInitialize()
    self.db = AceDB:New("DontDoThatDB", ns.defaults, true)
    ns.db = self.db
    if ns.Settings then ns.Settings.ClearDebug(self.db.profile) end
    if ns.Tally then ns.Tally.Init(self.db) end

    if ns.Log then
        ns.Log.Init(self.db.global.log, { printer = function(msg) self:Print(msg) end })
        ns.Log.SetEnabled(self.db.profile.debug)
    end
    if ns.Probe then
        ns.Probe.Init(self.db.global.probe)
    end
    if ns.Export then
        ns.Export.sourceProvider = function()
            return {
                settings = self.db.profile,
                ledger = self.db.char.ledger,
                log = ns.Log and ns.Log.Entries() or {},
                items = function() return ns.ItemGuard and ns.ItemGuard.Report(_G) or nil end,
                probe = function() return ns.Probe.Run(nil, self.db.global.probe) end,
            }
        end
    end
end

function addon:OnEnable()
    if ns.Options then ns.Options.Register(self) end
    if ns.TrainerFilter then ns.TrainerFilter.Enable(_G) end
    if ns.Resets then ns.Resets.Enable(LibStub("AceEvent-3.0"):Embed({}), _G) end
    if ns.Merchant then ns.Merchant.Enable(LibStub("AceEvent-3.0"):Embed({}), _G) end
    if ns.Auction then ns.Auction.Enable(_G) end
    if ns.TrainerOverlay then
        -- Its own event object: AceEvent keeps one handler per event per object, and the
        -- debug capture below registers the same trainer events on the addon itself.
        ns.TrainerOverlay.Enable(LibStub("AceEvent-3.0"):Embed({}), _G)
    end
    if ns.Capture then
        ns.Capture.Enable(self, _G, self.db.global.probe)
    end
    -- Once per profile: which skip list is in use, that the newest one changed the rules, and how to change it.
    if ns.SkipRevision then
        local lines = ns.SkipRevision.Notice(self.db.profile)
        for _, line in ipairs(lines or {}) do self:Print(line) end
    end
end
