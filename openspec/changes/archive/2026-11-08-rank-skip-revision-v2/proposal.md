# Proposal

## Why

The addon's rank-skip list is short (about 75 ranks, one list per class) and comes from a handful of leveling guides. A fresh review against the Forever spell data and Wowhead's current leveling guides found 225 more ranks worth skipping in every spec, 84 worth skipping in some specs only, and 13 current skips that the guides say to buy. Many skip reasons are also wrong or vague: the training window says every skip is "only a small upgrade", when a rank may really be skipped because Wowhead says to buy only rank 1, because it unlocks at level 60 and should wait for the mount, or because it is a rarely used utility spell. The player needs the better list as the default, a way to go back to the old one, and a reason that says what is actually true.

## What Changes

- Introduce numbered **skip revisions**. Revision 1 is the current skip list, frozen as it is today. **Revision 2** is the new list from this review and becomes the default.
- Add a setting on the Tuning page to choose the revision. A player who never touches it gets revision 2; a player who picks revision 1 keeps today's behavior exactly.
- Make skips **per spec** in revision 2 (84 ranks are skipped in some specs only), where revision 1 is class-wide.
- Add a **level 60 rule** for ranks that unlock at level 60:
  - The **first rank of a spell** that unlocks at 60 is **always trained**, whatever kind of spell it is.
  - A later rank of an offensive or defensive spell (damage, healing, absorb, armor) that unlocks at 60 is **trained at 60**, not held.
  - Any other level 60 rank (a later rank of a utility spell) follows the existing deferral logic and waits until the player has bought their level 60 mount, unless a Wowhead guide trains it at 60.
  - This replaces the earlier idea of holding every level 60 rank. It can be revisited in a later revision.
- Where Wowhead's leveling guides state a view on a spec, spell and rank, that view decides the rank. Elsewhere the computed result decides, and the rank records which source decided it.
- Every skipped rank carries a **reason that matches its real cause**, shown in the training window tooltip, the Rules page and the confirmation prompt. Examples: Wowhead says only rank 1 of this spell is worth buying; it unlocks at level 60, so wait for your mount; it costs N hours of grinding to earn back for a gain you rarely use.
- The **Rules page** also shows where each skip came from (Wowhead guide or computed). The training window gives the reason only, not the source label.
- **Respect the player's existing switches.** Any ability, tag or rule-kind switch a player has already set (an ability switched off, the skipped-ranks kind switched off) keeps working under every revision, so no saved setting changes meaning on upgrade.
- Ship the analysis behind revision 2 as reproducible tooling in `tools/`, with the output written to generated rule data, so a future revision can be built the same way.
- Release as addon version **0.11.0** (new capability, per the repo release rule).

**BREAKING (to a requirement, not to saved data):** the rule-engine requirement that rank skips come only from expert guides no longer holds for revision 2, which also uses computed skips. Those are labeled as computed in the data and in the reason shown to the player.

## Capabilities

### New Capabilities
- `rank-skip-revisions`: numbered, selectable revisions of the rank-skip data; revision 1 frozen as today's list, revision 2 default; how a revision is chosen, stored and applied; per-spec skips; the level 60 hold; each skipped rank's source and reason.

### Modified Capabilities
- `rule-engine`: explicit rank skips become per revision and per spec; the "rank skips come from expert guides" requirement is replaced by source-labeled skips (guide or computed); the plain-reason scenario for skipped ranks is replaced by reasons that match each rank's source; evaluation order is unchanged.
- `addon-settings`: the Tuning section gains the revision choice (default revision 2); the Rules page's "Ranks to skip" lists show each rank's real reason; the skipped-ranks switch and per-ability switches continue to apply under every revision.
- `purchase-warnings`: the trainer-window badge, tooltip and confirmation prompt state the rank's actual reason for being skipped, and the hold-until-mount reason names the player's mount.
- `localization`: new reason strings are added to the locale files, and the example locale shows the new keys.

## Impact

- **Rule data:** `DontDoThat/Rules/Data/<Class>.lua` gains revision-aware, per-spec skip data with a source and reason per rank. Revision 1 data is kept unchanged. `docs/rules-data.md` documents the new schema.
- **Engine:** `Rules/Engine.lua` and `Rules/Schema.lua` evaluate skips for the chosen revision and spec; the level 60 hold reads the milestone state.
- **Settings:** `Options/*` and `Core/Init.lua` add a revision setting with default 2; existing ability, tag and kind switches stay as they are.
- **UI:** trainer rows, tooltips, prompts and the Rules page show the new reasons; `Locales/enUS.lua` and `Locales/Example.lua` gain strings.
- **Tooling:** the analysis moves from throwaway scripts into `tools/`, producing the generated revision 2 data and a review report.
- **Tests:** engine tests for both revisions, default selection, switch compatibility and reason text.
- **Release:** version 0.11.0 in both `.toc` files, a CHANGELOG entry, and a tag, per `CLAUDE.md` and `docs/publishing.md`.
- **Known data caveats carried in:** roughly 15% of the savings figures use level-estimated prices where no trainer price is known, Rogue, Warlock, Paladin and Hunter have no Wowhead per-spell guidance, and about a quarter of ranks cannot be scored from the game data and are left unchanged.

## Decisions

- **Source label:** computed skips are marked as such on the Rules page only. The training window states the reason without naming the source.
- **Later revisions:** a revision may inherit from an earlier one and change only what differs. A future revision may come from further analysis, since WoW: Forever now has its own written expert guidance (Maxroll, Icy Veins) that this revision did not use.
- **Level 60:** a first rank at 60 is always trained; a later offensive or defensive rank is trained at 60; any other level 60 rank keeps the existing wait-for-the-mount logic. To be revisited later.

## Open questions

- Which spells count as offensive or defensive? The analysis classifies by what the rank does in the game data (damage, healing, absorb, armor); ranks the data cannot classify default to the hold.
- Ranks Wowhead does not cover still use the computed result. Whether any of those need an expert guide before shipping is left to the design.
