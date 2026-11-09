# Tasks

## 1. Revision data and generation tooling

- [x] 1.1 Freeze revision 1: copy each class's current `skipRanks` into a new `Data/SkipRevisions.lua` as revision 1 (family-ID and rank keys, `source = "legacy"` or the matching guide reason kind per rank), and add a test that flattening revision 1 reproduces every class's pre-change `skipRanks` exactly (the old lists are embedded in the test as the expected values).
- [x] 1.2 Define the entry shape and the closed set of reason kinds in `Rules/Schema.lua`, validate `ns.SkipRevisions` at load (family IDs exist for the class, ranks are integers of 2 or more, spec keys belong to the class, every reason kind is known and carries its numbers, `inherits` names an earlier revision), and cover each failure with a test in `tests/rules_schema_test.lua`.
- [x] 1.3 Flatten each revision at load: apply `inherits`, treat `false` as "not skipped", and expose the result through the Rules module; test inheritance, removal and an entry replacing an inherited one.
- [x] 1.4 Move the review into `tools/skip-revision/`: loaders for the cached wago tables (Forever 1.60.1.70862 or newer), the rank/price/effect model, the Wowhead guide extraction with its curated quote rules, and the report writer; add a README stating the inputs, the fetch commands, the assumptions (hours per level and its source, gold per hour, use weights) and how to rerun. Verify by running it from a clean `tools/.cache` copy and getting the same output.
- [x] 1.5 Add `tools/build-skip-revisions.py`, which resolves the rule data to family IDs by running the addon's own `Model/SpellData.lua` under LuaJIT and writes revision 2 (inheriting revision 1) with the level 60 rule, the Wowhead override, rank 1 never skipped, and one reason kind plus numbers per rank. Verify that rerunning leaves `Data/SkipRevisions.lua` byte-identical, and that the tool's report lists every ranked family it could not score or match.
- [x] 1.6 Generate `Data/SkipRevisions.lua`, remove `skipRanks` from the class rule files and `tools/class_plans`, add the file to both `.toc` files in load order (before the Rules data), and run `make check`. Move the class tests that read `skipRanks` (`rules_druid`, `rules_paladin`, `rules_shaman`, `rules_warlock` and the others) to read revision 1, and confirm `luajit tests/run.lua` passes.
- [x] 1.7 Add a data test for revision 2: rank 1 is never skipped; every skipped rank exists in the class's spell table for Forever; every entry has a source and a known reason kind; no rank the guide rules say to buy is skipped for that spec; and counts per class match the generator's report.

## 2. Engine

- [x] 2.1 Resolve the skip revision in `Settings.RulesFor` (`tuning.skipRevision`, unknown or absent means the newest) and carry it on the profile; test default, a pick of revision 1, and an unknown saved value.
- [x] 2.2 Evaluate skips from the chosen revision in `Rules/Engine.lua`: look up family and rank, apply the "every plausible spec skips it" rule using the player's plausible specs, never look up rank 1, and keep the order of checks so `offAbilities` and the skipped-ranks kind switch still win. Test per-spec skips (all plausible, one buying, spec picked), revision 1 against revision 2 for the same rank, and that no change was made to other verdicts.
- [x] 2.3 Render the reason for each kind from locale sentences with its numbers, returned as the verdict's reason; add tests for every kind, including a skip with each source (guide, computed, legacy) and the wait-for-mount kind.
- [x] 2.4 Test the level 60 rule through the engine: a first rank at 60 is not flagged, an offensive later rank at 60 is not flagged, a utility later rank at 60 is flagged with the wait reason while the milestone is active, and none is flagged once the level 60 mount is bought or after the level 40 mount with "stop after 40".
- [x] 2.5 Test switch compatibility: a switch saved for an ability before revisions existed still suppresses that spell's skips under revision 1 and revision 2, and the skipped-ranks switch silences both.

## 3. Setting, command and load notice

- [x] 3.1 Add `tuning.skipRevision` handling to `Model/Settings.lua` (read, set, validate) and keep it reset by a reset to defaults; test each.
- [x] 3.2 Add `/ddt revision [n]` to `Core/Slash.lua`: no argument prints the revision in use and the revisions available, a valid number switches and says so, an invalid one changes nothing and lists the valid ones; add the usage line to the help text and test each case in the slash tests.
- [x] 3.3 Print the load notice once per profile from `OnEnable` when `profile.revisionNotice` is below the newest revision: the revision in use, that revision 2 changed the rules significantly (many more ranks, per spec, each with its reason), how to change it (`/ddt revision 1` and Advanced > Tuning), with the wording for a profile on an earlier revision; store the marker, add it to `KEEP_ON_RESET`, and test new install, upgrade, repeat load, earlier-revision profile and reset.

## 4. Settings UI and Rules page

- [x] 4.1 Add the skip revision select to the Tuning section in `Options/Options.lua`, listing each revision with a one-line description and marking the newest as the default; verify in the options tests that it reads and writes `tuning.skipRevision` and takes effect for the next evaluation.
- [x] 4.2 Build the Rules page's Ranks to skip list from the chosen revision, grouped by spec, with each rank's reason and a source line (Wowhead guide, computed from the game data, earlier skip list), and name the revision in use at the top; test the entries for revision 1 and revision 2 and that switching revision changes the list.
- [x] 4.3 Confirm the trainer window badge, tooltip and confirmation prompt use the verdict's reason with no source label (trainer overlay and confirm tests), and that projected savings (`Model/Savings.lua`) follow the chosen revision.

## 5. Locale

- [x] 5.1 Write every reason sentence, the Rules page source lines, the revision select labels, the slash command replies and the load notice as `L["..."]` sentences (English is the key, so `Locales/enUS.lua` needs no entries) and list them in `Locales/Example.lua`; verify with the locale tests, which check the example file lists each skip reason, source line and notice sentence.

## 6. Docs, version and release

- [x] 6.1 Update `docs/rules-data.md` for the revision data, entry shape and reason kinds; `docs/contracts.md` for the new Rules and Settings functions; and `docs/test-plan.md` with the manual checks (load notice on first login, `/ddt revision` both ways, Tuning select, a Warrior trainer showing "only the first rank" for Thunder Clap rank 2 and onward, a Mage level 60 utility rank waiting for the mount, Rules page reasons and source lines). Verify by following the new test-plan steps in a client.
- [x] 6.2 Set `## Version: 0.11.0` in both `.toc` files, add the 0.11.0 entry to `CHANGELOG.md` describing revision 2, the default change, the way back, and the load notice; run `make check` and `make test`.

## Workflow follow-up

- Review `tools/.cache/skip-analysis/skip-review.html` (or the report the tool regenerates) before archive; it lists every rank, its decision, the reason and where Wowhead overrides the computed result.
- At archive: sync the delta specs, commit with the version named in the message, tag `v0.11.0` and push the tag (see `docs/publishing.md`).
