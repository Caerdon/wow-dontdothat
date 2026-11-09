# Skip revisions: how revision 2 is built

`tools/build-skip-revisions.py` writes `DontDoThat/Data/SkipRevisions.lua`. Run it from the project root:

    python3 -I tools/build-skip-revisions.py            # rebuild the data
    python3 -I tools/build-skip-revisions.py --report   # also write tools/.cache/skip-revision/skip-review.html

It needs `luajit` and, the first time, network access. Everything it downloads goes to the gitignored `tools/.cache`
and is treated as untrusted data (the scripts only read it as text).

## Inputs

| Input | Where it comes from |
|---|---|
| Spell effects, durations, cooldowns for one Forever build | wago.tools tables `SpellEffect`, `SpellMisc`, `SpellDuration`, `SpellCooldowns`, cached as `tools/.cache/<Table>-<build>.csv`; `--build` picks the build (default `1.60.1.70862`) |
| Ranks, levels, family IDs, rotations, tags | the addon's own files, resolved by running `Model/SpellData.lua` under LuaJIT (`dump_rules.lua`), so IDs match what the addon uses |
| Trainer prices | `Data/SpellData.lua` (seen at a trainer) and `Data/TrainerPrices.lua` (Wowhead list); a rank with neither is priced from its level and marked "estimated" |
| What Wowhead says | 19 Wowhead Classic leveling guide pages, cached in `tools/.cache/wowhead-guides/`, reduced to their "Spells to Buy" sections |
| Revision 1 | `revision1.json`, the skip list as it was before revisions existed (frozen; do not edit) |

## What the review does

For every ranked spell of every class and spec, and every rank after the first:

- **Cost**: the trainer price divided by gold earned per hour at that level (`Data/GoldRates.lua`).
- **Benefit**: how much stronger the rank is than the rank the player would otherwise keep (damage, healing, absorb,
  buff strength or duration, read from the spell's effects), times how much of play the spell is used, times the hours
  spent before the next rank unlocks.
- A rank is bought when the benefit beats the cost, and the buys for one spell are chosen together, because skipping a
  rank changes the value of the next one.

Assumptions, all in `review.py`:

- **Hours per level**: about 1h per level from 1 to 19, 2.5h from 20 to 39, 3.6h from 40 to 49, 4.4h from 50 to 59
  (150 hours in all). This is a published estimate (LFCarry, quoted by kami-labs in November 2026), not a measurement;
  nobody has measured Forever yet.
- **Use**: a core rotation spell gets its share of its spec's core damage and healing, by rank power; a situational spell
  0.15, a tagged low-value one 0.02, anything else 0.05, a pet ability 0.15; a spell with a cooldown of 15 seconds or more
  counts as utility and is discounted by 90%.
- **Spell power**: 1.5 per level above 10, used only where an effect scales with it.
- A decision is run again with faster or slower leveling, richer or poorer gold and more or less use; one that changes
  is reported as unstable in the HTML report.

## How the decisions are combined (`build-skip-revisions.py`)

1. **Rank 1 of a spell is never skipped.** The lowest rank a spell has is always bought, even when it unlocks at 60.
2. **Wowhead decides where it has a view** (`guides.py`, `verdict.py`). Two kinds of statement are read: "you can train
   this at levels ..." lists, trusted only when their levels line up with Forever's ranks, and sentences quoted from the
   guides ("Only Rank 1 of Overpower ...", "Up to Rank 4 of Heroic Strike and Rend", "Always buy new ranks of ...").
3. **Level 60 ranks** with no Wowhead view: a later rank of a damage, healing, absorb, armor or other buff spell is
   bought; any other later rank is skipped with the reason "wait for the mount" (every skip ends when the level 60 mount
   is bought anyway).
4. Otherwise the computed review decides. Ranks it cannot score (no measurable effect in the game data) keep revision 1's
   entry, if it had one.

Revision 2 inherits revision 1 and lists only what differs, per spec set, with a source (`guide`, `computed` or `legacy`)
and a reason kind with its numbers. The reason sentences are in `Locales/enUS.lua`.

## Known gaps

- Wowhead covers Priest, Mage, Druid, Shaman and Warrior only; the others have no guide check.
- The Wowhead text for one Druid spell (Rejuvenation) lost its name; `guides.py` fills it in by hand.
- Game data gaps: some spells lack a rank (Holy Light rank 5, Bane of Agony rank 2) and some prices look wrong.
- About a quarter of ranks cannot be scored and are left as revision 1 had them.
- The Forever-specific guides on Maxroll and Icy Veins give no rank advice; a later revision may use new ones.
