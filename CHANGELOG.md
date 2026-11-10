# Changelog

## 0.11.1

- Fixed beast training on Forever being refused ("AddOn 'DontDoThat' tried to call the protected function 'UNKNOWN()'") after a visit to a class or pet trainer. Two things in the addon were marking Blizzard's trainer window as touched by an addon, and the game then refuses any purchase paid in training points (gold purchases are not protected, so a class trainer never showed it). To ask "Buy anyway?" at a trainer, the addon was swapping the game's BuyTrainerService for its own copy and putting the original back for beast training; either write marks it. And the Recommended filter was taking rows out of Blizzard's own list and redrawing it, which marks the indexes the Train button reads. On Forever the addon now touches neither: the question is asked from a button of the addon's own laid over Train, which makes the purchase itself on confirm, and the filter fades the rows it would hide instead of removing them. Beast training never gets a question. Vendor and auction house questions, and Classic Era, are unchanged.
- On Forever a flagged spell is now recognised by its place in the trainer's own service list, so the question is asked about the spell actually selected; the window numbers its rows by display order and the addon was reading that number as the service index.
- The addon now asks the client what kind of trainer is open, the way the game's own window does, before treating a window as beast training.
- Forever's trainer rows are now read in the order that client returns them (name, type, icon, level, rank text, category). The addon was reading Classic Era's order, so on Forever every row looked unranked and never learned: the rank-skip advice and the learned-versus-open tally on the Progress page were silent there.

## 0.11.0

- **The rank-skip advice has changed significantly.** Which spell ranks to skip now comes in numbered revisions, and revision 2 is the new default. It skips many more ranks, decides them for your spec (a rank is only flagged when every spec you might be playing skips it), and follows the Wowhead leveling guides wherever they have a view. A later rank that unlocks at level 60 is flagged only for utility spells, and only until you have your level 60 mount.
- Every skipped rank now says why: the guide says to buy only the first rank, it is only a few percent stronger for a spell you only use now and then, it adds nothing over the rank before it, or it can wait for the mount. The Rules page also shows where each skip came from.
- The first time the addon loads with the new revision it prints a notice in the chat saying which revision is in use and how to change it.
- To go back to the earlier list, use `/ddt revision 1` or the new Skip list choice on the Tuning page. `/ddt revision` shows what is in use. Switches you have already set keep working under both revisions.
- The tools that build the skip data now live in `tools/skip-revision/`; `tools/build-skip-revisions.py` regenerates `Data/SkipRevisions.lua`.

## 0.10.9

- Fixed the doubled page headings in the game's AddOns panel: the page name and an identical title line were both shown. The `/ddt` window is unchanged.
- The store summary and addon notes now read "safeguards your gold so you can save up for your mount".

## 0.10.8

- Fixed beast training (a hunter's pet abilities, paid in training points) refusing ranks that cost points on Forever. The addon now leaves that window alone: no wrapped purchase, no marks, no prompts. A Pet Trainer NPC still gets the full treatment.

## 0.10.7

- The Forever trainer asks "Buy anyway?" again before a flagged ability. It now wraps the game's own purchase call instead of replacing the Train button, which the client had refused.
- Talent resets, pet skill resets and COD mail only warn now: the game's own dialog stays up with a note, a sound and a banner. Bank tabs on Forever work the same way.
- A blocked action from one guard no longer switches off the trainer's questions, and a block now switches off the guard whose purchase it was.

## 0.10.6

- Vendor purchases are checked again in the Forever client, which dropped the call the addon read prices from. Talents are read from Forever's new talent trees, professions from its new skill list, and stable slot purchases go through its new stable calls. The pet trainer's reset is now asked about as a pet reset, not a talent reset. `/ddt export` reports more of the client's calls to help find what else differs.

## 0.10.5

- Auction house purchases are now checked in the Forever client. Its retail-style auction house (single items and stackable goods) was never hooked, so flagged items such as bags sailed through without a question. Classic Era is unchanged.

## 0.10.4

- Fixed the Forever trainer window refusing purchases, such as hunter pet training. The Train button is no longer replaced there, so a flagged spell gets a warning sound and banner but the purchase always goes through. If the game ever refuses the "Buy anyway?" question on Classic Era, the button gets its own handler back.

## 0.10.3

- The Recommended trainer filter and its row marks now work in the Forever trainer window, with the filter in the Filters menu.

## 0.10.2

- Spell data refreshed for WoW Forever build 1.60.1.70790: new Rogue Death Mark and Shank, Shaman Totemic Projection is now Totemic Call, and Priest Binding Heal and Shaman Lava Burst are gone.

## 0.10.1

- Spell data refreshed for WoW Forever build 1.60.1.70755: new Druid Ferocious Bite, Lacerate and Primal Bite ranks, renamed Mage and Paladin talents, and the removed Paladin Salvation and Blessing of Light spells dropped. Trainer prices updated.

## 0.10.0

- Works on game clients in any language, recognising spells, talents, trainers, riding and grimoires by ID, and the addon's text can now be translated.

## 0.9.0

- Every class page lists all its spells by spec and reason, and Progress shows your projected savings.

## 0.8.1

- Clearer Home page, one reset control, and debug recording off at login.

## 0.8.0

- Support for Mage, Warlock, Priest, Druid, Shaman, Rogue and Warrior, including Warlock grimoires and a free level 40 mount for Warlocks.

## 0.7.0

- Paladin support with a cheap level 40 mount target.

## 0.6.0

- Settings simplified into five pages with a nudge level and watch areas.

## 0.5.0

- Skips low-value Hunter ranks and asks once before you learn a new profession.

## 0.4.0

- Rule switches, tuning and a consistent settings look.

## 0.3.0

- Asks before bank slots, stable slots and COD mail.

## 0.1.0

- First release: Hunter spells and pet skills, Herbalism and Skinning, warnings on vendor and auction house purchases, and a tally of gold kept.
