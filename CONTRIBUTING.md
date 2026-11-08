# Contributing

Thanks for helping. Don't Do That is a WoW Classic addon (Lua) that warns players off gold they should save for their level 40 and level 60 mounts.

## Ways to help

- **Report a bug.** Turn on Debug > Record what the addon sees, do the thing that went wrong, then Show the report, copy it (Ctrl+A, Ctrl+C) and attach it with a short description and your client (Classic Era or Forever).
- **Correct the data.** A spell tier, a skipped rank or a price that looks wrong is a real bug. Open an issue or a pull request with a source: an expert leveling guide (Wowhead, Icy Veins) for tiers and ranks, a trainer capture (`/ddt export`) for prices.
- **Fix or build something.** For anything bigger than a small fix, open an issue first so we agree on the approach before you write it.

## Setup

1. Clone the repository and link or copy `DontDoThat/` into your AddOns folder (`_classic_era_` or `_classic_beta_` for Forever).
2. Install [LuaJIT](https://luajit.org) and run the tests from the repository root:

   ```
   luajit tests/run.lua            # everything
   luajit tests/run.lua savings    # tests whose file name contains "savings"
   make test                       # same as the first line
   ```

3. Run the checks CI runs on every pull request and the release workflow runs on a tag (`make check` runs them all):

   ```
   sh tools/check-toc.sh DontDoThat/DontDoThat_Vanilla.toc
   sh tools/check-toc.sh DontDoThat/DontDoThat_Camelot.toc
   sh tools/check-tocs-match.sh
   bash tools/check-embeds.sh
   sh tools/check-version.sh
   ```

4. In game, `/reload` after a change, and `/console scriptErrors 1` so errors show as popups. `docs/test-plan.md` lists what to check by hand.

## How changes are made

Behavior is specified in `openspec/specs/`. A change to behavior goes through an OpenSpec change under `openspec/changes/` (proposal, design, spec deltas, tasks), is implemented against its tasks, and is archived when done. Archiving applies the deltas to the main specs and bumps the version. Bug fixes that restore specified behavior can skip the proposal; add a test that fails without the fix.

## Code

- **Match the surrounding code**: naming, comment density and idiom. Keep changes small and focused.
- **Keep the game out of the logic.** `DontDoThat/Rules/` and `DontDoThat/Model/` are plain Lua with no client calls, so they can be tested. All client API reads go through `DontDoThat/Intercepts/Adapter.lua`, wrapped in `pcall`, so a missing or changed function degrades to "no data" instead of an error.
- **Write tests** for every behavior change in `tests/` (one `*_test.lua` per area). New rule data needs the per-class tests to pass: every spell family must be classified.
- **Settings pages** are built with the shared `newPage` builder in `DontDoThat/Options/Options.lua`. Use its helpers for spacing, notes and amounts so every page looks the same.
- **New files** go in both TOC files (`DontDoThat_Vanilla.toc` and `DontDoThat_Camelot.toc`) in the same order. `tools/check-tocs-match.sh` fails if they differ.
- **Plain language.** Player-facing text has no internal terms (tier, tag, rotation, override).

## Data

- Translations: see `docs/localization.md`. Player-facing text is written `L["English sentence"]`; a language is one file in `DontDoThat/Locales/`.
- Class rule data in `DontDoThat/Rules/Data/` follows `docs/rules-data.md`. For Mage, Warlock, Priest, Druid, Shaman, Rogue and Warrior the files are **generated**: edit the plan in `tools/class_plans/<class>.py` and run `python3 tools/scaffold_class_rules.py <CLASS>`. Hunter and Paladin are edited by hand.
- `DontDoThat/Data/SpellData.lua` and `DontDoThat/Data/TrainerPrices.lua` are **generated** by `tools/build-spell-data.py` and `tools/fetch-trainer-prices.py`. Re-run the tool instead of editing them.
- **Rank skips and spell tiers come from expert guides, never from a formula.** Cite the guide in the plan or the pull request.
- Treat downloaded data as untrusted: keep it out of the repository, and run Python that reads it with `python3 -I`.

## Versions and releases

- Bump `## Version:` in **both** TOC files to the same value when a change's specs are applied. Before 1.0.0 a new capability or user-visible feature raises the minor number and a fix to existing behavior raises the patch number.
- Add one line for the version to `CHANGELOG.md`.
- Releases are tagged `vX.Y.Z` on the commit that carries the bump; see `docs/publishing.md`. Maintainers publish.

## Commits and pull requests

- One logical change per commit. Subject line in the imperative, under about 70 characters; name the new version in a release commit, for example `Add Paladin support (v0.7.0)`.
- In the pull request, say what changed, why, and how you tested it (tests, and what you checked in game). Include screenshots for anything on a settings page.
- Before you open it: the tests pass, the checks above pass, and you have not committed secrets, captures (`debug.txt`) or screenshots.
- Be kind in reviews. Disagree about the change, not the person.

## License

By contributing you agree that your contribution is licensed under the project's license (see `LICENSE`).
