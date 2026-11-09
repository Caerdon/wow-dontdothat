# Design

## Context

See `proposal.md` for why. What exists today, observed in the code:

- Skips are one table per class in the rule data, `skipRanks[familyId] = { ranks }`, checked in `Rules/Engine.lua` `evaluateSpell`. It returns `defer` with `source = "skipRank"` and one fixed sentence, "Only a small upgrade over the rank before it."
- The Rules page (`Options/Options.lua`) lists the same table with a matching fixed sentence, grouped by the specs that use the spell.
- Every verdict is produced only while the milestone state is `active` (`Rules.Evaluate`; `Milestones.State`). The state ends when the level 60 mount is bought, or the level 40 mount with "stop after 40". So any skip already stops at the mount; no separate "hold until the mount" mechanism exists or is needed.
- Player switches live in `profile.ruleOff` (abilities and tags by class, kinds), keyed by spell family ID, and reach the engine through `Settings.RulesFor`. Tuning values live in `profile.tuning`.
- `profile.plausibleSpecs` (from talents or the player's pick) tells the engine which specs to judge by; today skips ignore it.
- Spell families are identified by ID (`Model/SpellData.lua`); rule files are written in English names and resolved at load.

## Goals / Non-Goals

**Goals:**
- Selectable numbered skip revisions, revision 2 the default, revision 1 identical to today's verdicts.
- Per-spec skips, a true reason per rank, a one-time load notice, a way to change the revision.
- The review that produced revision 2 reproducible from `tools/`, not from throwaway scripts.

**Non-Goals:**
- Changing anything but rank skips: tags, rotations, overrides, prices, professions.
- Rank 1 skips, or skipping whole spells.
- Using the Forever-specific Maxroll and Icy Veins guides; they are the likeliest source of a later revision.
- A migration of saved data. The only new saved values are optional.

## Decisions

**1. Revisions live in one generated data file, `Data/SkipRevisions.lua`, not in the class rule files.**
`ns.SkipRevisions[CLASS] = { [1] = {...}, [2] = { inherits = 1, ... } }`. Revision 1 is today's `skipRanks` moved there unchanged; the class files lose `skipRanks`. The file is generated (like `SpellData.lua`), so revision 2's several hundred entries are never hand-edited. Alternative: add a `skipRevisions` field to each class file. Rejected: the class files are scaffolded and hand-edited, and a generated block inside them would be overwritten or drift. Cost: the Schema and a few tests that read `skipRanks` move to the new shape.

**2. Entry shape.**
`[familyId] = { [rank] = { entry, ... } }` with `entry = { source = "guide" | "computed" | "legacy", reason = { kind = "...", ...numbers }, specs = { "ARMS", "FURY" } | nil }`. A rank holds a list because one rank can be skipped for different reasons in different specs; an empty list means "not skipped in this revision", whatever an earlier revision said. `specs` nil means every spec. Keys are numbers: family IDs and rank numbers, so nothing depends on names or language.
`inherits = n` makes a revision list only its differences; the loader flattens each revision once at load. Revision 2 inherits revision 1, so skips no review could score (such as Hunter Disengage) stay as they were with their `legacy` source.

**3. Reasons are a closed set of kinds with numbers, rendered from locale sentences.**
Kinds: `guideFirstRankOnly`, `guideUpToRank(n)`, `guideNotTrained`, `noGain`, `smallStep(pct)` (spell used only now and then), `notWorthPrice(pct)`, `waitForMount`, `legacy`. The engine formats the sentence with `string.format` on the locale string, so a translator keeps the placeholders. Sentences say "this spell", not its name, which keeps `Rules/**` free of client API calls. `legacy` reads "An earlier version of this list judged this rank a small upgrade." It is true for revision 1's entries that no guide could be matched to, and it replaces the generic sentence everywhere, so a v1 skip never claims a cause the data lacks. Where revision 1's skip maps to a guide statement (the Warrior and Shaman ones), it gets the matching guide kind instead.
Alternative: store the finished English sentence per entry. Rejected: not translatable and not checkable by the locale tests.

**4. The engine resolves a revision and the plausible specs.**
`Settings.RulesFor` adds `skipRevision`: the saved `tuning.skipRevision` if it names a known revision, else the newest. `evaluateSpell` looks up the entry for the family and rank in the flattened revision. With `specs` set, the rank is skipped only if every key in `plausible(profile, data)` is in `specs`. That is the conservative reading: a rank any plausible spec buys is never flagged. Rank 1 is never looked up. The skipped-ranks kind switch and `offAbilities` are checked first exactly as now, so saved switches mean the same under every revision.

**5. Level 60 is decided in the data, enforced by the existing mount rule.**
The generator writes a level 60 rank as skipped only when it is a later rank of a spell that is not offensive or defensive and no Wowhead guide trains it (`waitForMount`). The first rank at 60 and offensive or defensive ranks are simply not listed. "Offensive or defensive" is read from the rank's effect in the game data (damage, healing, absorb, armor); ranks with no readable effect follow the wait. Nothing in the engine changes, because every skip already ends at the mount. One consequence to accept: with "stop after the level 40 mount", warnings end after the first mount, so these waits end too.

**6. Revision choice, notice and command.**
`profile.tuning.skipRevision` (number, absent = newest) is chosen on the Tuning page with a select and with `/ddt revision [n]` in `Core/Slash.lua`. A number that is not a revision changes nothing and lists the valid ones. The notice is printed by `addon:Print` once per profile, in `OnEnable`, after the database is ready, when `profile.revisionNotice` is below the newest revision (a new install counts as below). It states the revision in use, that revision 2 changed the rules significantly, and the two ways to change it; it is written differently for a profile on an earlier revision. `revisionNotice` is added to `KEEP_ON_RESET` in `Model/Settings.lua`, so resetting settings does not print it again; the revision pick itself is reset by a reset to defaults, which means the newest.
Alternative: print on every login. Rejected: noise. Alternative: a popup. Rejected: chat is enough for a message with a command in it, and popups can be missed or suppress input on some clients.

**7. Generation moves into `tools/`.**
`tools/skip-revision/` holds the loaders, the review, the Wowhead rule extraction and the report writer, and `tools/build-skip-revisions.py` writes `Data/SkipRevisions.lua`. Inputs stay in the gitignored `tools/.cache` (wago tables for the Forever build, the fetched Wowhead guide pages) and are fetched by the tool with a browser User-Agent, as the other tools do. The rule data is resolved to family IDs by running the addon's own `Model/SpellData.lua` under LuaJIT, so ID matching is the addon's, not a copy. The review and its assumptions are documented where the tool lives: hours per level from a published estimate, gold per hour from `Data/GoldRates.lua`, use weights per rotation role, and the rule that a Wowhead statement beats the computed result. The HTML report that was used to review the change is produced by the same tool.

**8. Rules page and trainer window read the same entries.**
The Rules page builds "Ranks to skip" from the chosen revision, grouped by spec set as today, with the reason and a source line ("From the Wowhead guide" / "Computed from the game data" / "From the earlier skip list"). The trainer tooltip and the prompt use `verdict.reason` as now, which is already the reason sentence, so they show the same words and no source label. `Model/Savings.lua` keeps counting `source == "skipRank"`, so projected savings follow the revision with no change.

## Risks / Trade-offs

- [Computed skips are not expert-backed. The review rests on assumed use weights, a boosting site's hours-per-level estimate, and level-estimated prices for about 15% of ranks] → Each computed skip says it was computed and how much stronger the rank is; Wowhead overrides wherever it has a view; revision 1 stays selectable; the load notice says the rules changed significantly.
- [Per-spec skips mean a player with an unclear spec sees fewer skips] → By design; the skip list errs toward not flagging a rank some plausible spec buys.
- [Wowhead coverage: Priest, Mage, Druid, Shaman and Warrior only. Hunter, Rogue, Warlock and Paladin get no guide check] → Their skips are labeled computed or legacy; the later revision from Forever guides can replace them.
- [The Wowhead extraction depends on guide text that is partly broken (one Druid spell has no name in the page text) and on levels that match Forever's] → The tool judges a guide's level list only when it lines up with Forever's rank levels, and reports lines it could not place; the Druid case is recorded as a known fix-up.
- [Game data gaps: Holy Light has no rank 5, Bane of Agony no rank 2, some prices look wrong] → The tool lists them in its report; skips use the ranks the table does have, and the price caveat is shown in the report, not hidden.
- [Default behavior changes for every existing player] → The load notice and the one-line way back; revision 1 is bit-for-bit today's verdicts, which a test pins.
- [A reworked spell (Slam gained a Forever rank 1 at level 20) shifts rank numbers against Classic guides] → Skips are keyed by the Forever rank numbers from the game table, and a Wowhead level list is trusted only when its levels match.
- [Reasons name numbers that came from the review] → They are generated from the same data as the decision, and a test checks every skipped rank has a known reason kind.

## Migration Plan

- Saved data: no migration. `tuning.skipRevision` and `revisionNotice` are optional and read with defaults.
- Release 0.11.0: every profile without a pick moves to revision 2 and sees the notice once.
- Rollback for a player: `/ddt revision 1`. Rollback for the addon: a patch that re-points the default or removes a revision entry; no data is lost either way.
- Order: data file and schema, engine, settings and slash command, notice, Rules page, locale strings, tests and docs, version bump with the archive commit.
