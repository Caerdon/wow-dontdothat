# Store listing

Copy-ready text and field values for the CurseForge and Wago projects. The project IDs are already in both TOC files (`## X-Curse-Project-ID`, `## X-Wago-ID`); see [publishing.md](publishing.md) for releasing. Category names and field limits below are from memory of the site forms: confirm them while you fill the forms in, and pick the closest match if a name differs.

## Fields

| Field | Value |
|---|---|
| Project name | Don't Do That |
| Slug / URL name | dont-do-that (use whatever is free) |
| Summary (one line, keep under 250 characters) | Safeguards your gold so you can save up for your mount. Marks skippable trainer spells and asks before wasteful purchases. All nine classes. Forever and Classic Era. |
| Main category | Auction & Economy |
| Additional categories | Quests & Leveling, Miscellaneous |
| Game versions | CurseForge calls Classic Era **Classic**: tick Classic (1.15.x) and Forever (1.60.x). The packager reads `## Interface` from each TOC: 11509 for `DontDoThat_Vanilla.toc`, 16001 for `DontDoThat_Camelot.toc`. |
| License | MIT |
| Source code URL | `https://github.com/NullStatBonus/wow-dontdothat` |
| Issues URL | `https://github.com/NullStatBonus/wow-dontdothat/issues` |
| Relations | None. The Ace3 libraries are bundled. |
| Tags | gold, saving, mount, leveling, trainer, spells, talents, auction house, vendor, quality of life, classic, forever |
| Release type | Release (use Beta for pre-release tags) |
| Changelog | Taken from `CHANGELOG.md` by the packager; nothing to type. |
| Donations | none |

## Description

Paste this into the description box (CurseForge and Wago both take Markdown or HTML; use the Markdown editor if offered).

---

**Don't Do That** is a World of Warcraft addon for WoW Forever and Classic Era that safeguards your gold to ensure you can save up for your mount. It warns you off gold you don't need to spend yet, so you can afford your **level 40** and **level 60** mounts, for all nine classes.

- **Marks spells you can skip** in the trainer window. A colored **(i)** appears next to each one; hover it for the reason and the cost.
  - Red: *Save your gold*. You won't need it until later.
  - Gold: *Not worth buying yet*. A low-value spell.
  - Blue: *Optional*. Handy now and then, but you can get by without it.
- **Asks before you waste gold.** Buying a spell that isn't recommended, a non-essential item (armor, weapons, vanity, bags, recipes), a bank or stable slot, COD mail, a talent reset, or your first lesson in a new profession gets a "Buy anyway?" question that says roughly how long it takes to grind that gold back. You can always say yes.
- **Recommended trainer filter.** Hide everything the addon would skip, from the trainer's Filters menu (on Forever the rows are faded rather than removed).
- **Knows your class and spec.** The advice follows your talents, or the spec you choose, and comes from common leveling builds, the Wowhead leveling guides and a review of the game's spell data. Which ranks to skip is a numbered revision you can change with `/ddt revision`.
- **Shows what you've saved.** The Progress page tallies the gold you've kept and projects your savings up to the mount you're saving for.

It stays on from level 1 until you've bought the mount you chose to stop at. It only ever asks, and you can turn any part off.

**Settings.** Type `/ddt` or go to Options, AddOns, **Don't Do That**. Pick how firmly it nudges you (marks only, ask about what to wait on, or ask about everything), which kinds of purchases to watch, the minimum price below which nothing is flagged, and which mount to stop at. `/ddt test` shows a sample warning without buying anything.

**Good to know**

- Spell advice follows expert guides. You can switch off any spell or kind of advice.
- Talent choices aren't judged; only the cost of resetting is warned about.
- Auction house purchases are checked on both clients. On WoW Forever the trainer's Train button is left alone, so a flagged spell gets a sound and banner but the purchase always goes through.
- Works on game clients in any language: spells, talents and trainers are recognised by ID. The addon's own text is English and can be translated; see the source repository.

**Problems?** Turn on Advanced, Debug, **Record what the addon sees**, repeat what went wrong, then **Show the report**. Copy it and send it with a description and your client (Classic Era or Forever).

Free and open source (MIT). The bundled Ace3 libraries keep their own license.

---

## Screenshots to capture

1. A trainer window with red, gold and blue **(i)** marks and a tooltip open on one.
2. The "Buy anyway?" question with the earn-back time (`/ddt test`).
3. The warning banner after trying to buy a flagged item.
4. The Progress page with savings tallied.
5. The settings page under Options, AddOns.
6. The Recommended filter in the trainer's Filters menu.

Use 1920x1080 or larger, UI scale unchanged, with the chat frame showing nothing private.

## Before each release

1. Check the Game versions row still matches the `## Interface` values in both TOCs.
2. Skim the description against `README.md`; update both if the features changed.
