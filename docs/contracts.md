# Module contracts (shared by parallel workstreams)

Conventions
- Lua 5.1 syntax (WoW). Every addon file starts `local addonName, ns = ...` and attaches its module to `ns`. No new globals except SavedVariables (`DontDoThatDB`) and slash command registration.
- `Rules/**` and `Model/**` are pure Lua: no WoW API calls, no Ace libs, no frames. They take plain tables in and return plain tables, so they run under `tests/run.lua`.
- Anything that calls a WoW API must guard it (`if C_Foo and C_Foo.Bar then`) and wrap fragile calls in `pcall`. Forever API names are unverified until the probe runs; do not assume them.
- Money is always integer copper in data and logic.
- A new file goes in both TOC files, in load order (`tools/check-tocs-match.sh` checks they agree). Spell tables and `Locales/enUS.lua` load before the rule data.

Shapes

```
Action  = { kind = "spell"|"respec"|"professionLearn",
            name = "Serpent Sting", familyId = 1978,             -- familyId groups ranks (see Spell identity below)
            rank = 8, unlockLevel = 58, nextRankLevel = 60,     -- nextRankLevel nil if last rank
            spellId = nil|number, cost = copper|nil, tags = {..}|nil }

Profile = { class = "HUNTER", level = 25,
            treePoints = { BM = 21, MM = 0, SV = 0 },           -- keyed by spec key
            plausibleSpecs = { "BM" },                          -- from SpecInference
            professions = { Cooking = { skill = 75, max = 150 } },   -- known professions
            milestone = { current = 40|60|nil, state = "active"|"finished" } }  -- active from level 1 until the level 60 mount is bought

Verdict = { tier = "keep"|"info"|"deferLow"|"defer",
            cost = copper|nil, costIsEstimate = bool,
            reason = "text", milestone = 40|60|nil,
            source = "skipRank"|"override"|"rotation"|"tag"|"disabled"|"default" }

Service = { familyId = 1978, name = "Serpent Sting", rank = 3, unlockLevel = 18,
            cost = copper|nil, learned = bool, available = bool }   -- trainer/spellbook row, adapter-supplied

Engine (ns.Rules)
  ns.Rules.Evaluate(profile, action) -> Verdict
  ns.Rules.Load(classData)  -- validates, raises a clear error on malformed data
  ns.Rules.GetClass(classKey) -> data table or nil
  ns.Rules.SkipRevisionNumbers() -> { 1, 2 }   -- every revision the loaded classes have, ascending
  ns.Rules.NewestRevision() -> number           -- the default
  ns.Rules.ResolveRevision(wanted) -> number    -- the pick if it exists, else the newest
  ns.Rules.SkipEntries(classData, revision, familyId, rank) -> { entry, ... }   -- empty when the rank is not skipped
  ns.Rules.SkipReason(reason) -> sentence       -- from the locale and the numbers the data records
  ns.Rules.SkipSource(source) -> sentence       -- "From the Wowhead leveling guide." etc., for the Rules page
  profile.rules.skipRevision = number | nil     -- the player's pick (nil: newest); read from tuning.skipRevision by Settings.RulesFor

SkipRevision (ns.SkipRevision)   -- Model/SkipRevision.lua, takes the saved profile table
  ns.SkipRevision.InUse(p) -> number;  ns.SkipRevision.Available() -> { 1, 2 };  ns.SkipRevision.Describe(n) -> one line
  ns.SkipRevision.Command(argument, p) -> lines   -- /ddt revision [n]: shows, switches, or rejects a number
  ns.SkipRevision.Notice(p) -> lines | nil        -- the load notice, once per profile (marks p.revisionNotice)
  ns.Settings.SkipRevision(p) / SetSkipRevision(n, p) / RevisionNoticeDue(newest, p) / MarkRevisionNotice(newest, p)

SpecInference (ns.SpecInference)
  ns.SpecInference.Infer(classData, treePointsByTalentSet, opts) -> plausibleSpecs (array of spec keys)
  opts = { leadMargin = number, ... }; treePointsByTalentSet is an array (1 or 2 talent sets).
  ns.SpecInference.Depth(treePoints, specKey) -> points; ns.SpecInference.Role(classData, treePoints) -> role

Milestones (ns.Milestones)
  ns.Milestones.Defaults  -- data: { [40] = { riding = copper, mount = copper }, [60] = {...} }
  ns.Milestones.State(level, ridingLearned40, ridingLearned60, manualOverride) -> { current, state }

Ledger (ns.Ledger) -- takes the engine as an argument so it is testable with a stub
  ns.Ledger.Compute(profile, services, engine, costCache) -> { verified = copper, projected = copper, items = {..} }
  ns.Ledger.RespecCost(count, table) -> copper (escalating, capped)
  ns.Ledger.NewState() -> { respecsAvoided = 0, respecsPerformed = 0, spentAgainst = 0, costCache = {} }
Items
  ns.ItemCategory.Classify({ classID, subClassID, equipLoc }) -> category key (one of 13; unknown -> "misc")
  ns.ItemWarning.Flagged(modes, category, surface, total, minPrice) -> bool   -- surface "vendor"|"ah"
  profile.itemModes = { [category] = "off"|"vendor"|"ah"|"both" }; profile.minPrice = copper (default 100)
  ns.ItemGuard.Run(surface, name, link, total, proceed)   -- alert, ask, then proceed() or drop
Guarded dialogs (ns.Resets): KINDS = talent, pet, bank, stable, cod; profile.guard = { bank, stable, cod } (default all true)
  kind = { popups, label, title, ask, rises, advice, price(env,data)|event, accept(env,data,which)|confirmFn, done, avoided(state,cost), performed(state,cost) }
EarnBack (ns.EarnBack)
  ns.EarnBack.Describe(copper, level) -> "about 40 minutes" | nil;  ns.EarnBack.Line(copper) -> prompt sentence | nil
  Rates: Data/GoldRates.lua, copper per hour by level band (estimates, needsReview)
Ledger additions: ns.Ledger.RecordItemAvoided(state, copper), RecordItemPerformed(state, copper)
```

Test commands: `lua` is at the scratchpad path given in your task; run from the project root: `<lua> tests/run.lua [pattern]`; syntax check with `<luac> -p file.lua`.

Spell identity (Model/SpellData.lua)

A spell is identified by its family ID, never by its displayed name, so a verdict is the same in every client language. A family is every rank of one spell; its ID is the lowest row ID (primary or alternate) the bundled tables hold for that English name in the class. Pet spells sit in their owner's table and no name repeats across kinds within a class.

```
SpellData.FamilyId(class, englishName)  -> familyId | nil     rule files are written with English names; resolve once at load
SpellData.FamilyOfId(class, anyRowId)   -> familyId | nil     accepts any row ID or alternate, so a saved ID outlives a table rebuild
SpellData.FamilyName(class, familyId)   -> English name | nil tests and the debug report only
SpellData.NameMap(class, env)           -> { [clientName] = familyId | false }   false = two families share the name
SpellData.DisplayName(class, familyId, env) -> the client's name for the family, English when the client cannot say
```

The game gives a trainer row's spell ID through its tooltip (`SetTrainerService(i)` then `GetSpell()`); `Adapter.ReadTrainer` sets `row.spellId` and `row.familyId = FamilyOfId(class, spellId)`. Only when that gives nothing, resolve with `NameMap(class, env)[row.name]`. Take the rank from the digits of the rank text. Build the map once per class and session; it is the only place the client's spell names are read. Rules/** and Model/** stay free of WoW API calls: `env` is passed in, as `IconFor` does. A missing or erroring `GetSpellInfo` leaves the English names in the map, which is today's behavior. `Probe.SpellIdentity` records whether a client gives the trainer a direct spell ID.
