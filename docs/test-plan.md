# In-game test plan

Test on a **Hunter**. Everything below is checked in the game window; nothing needs a console except the first step. Tick each line; if one fails, note what you saw and the `/ddt export` report.

Levels needed: most steps work at **level 10**. Steps marked (L12) need level 12, (L18) level 18.

## 0. Setup
- [ ] Copy the `DontDoThat` folder over the installed one and `/reload`.
- [ ] `/console scriptErrors 1` (so any problem shows as a popup).
- [ ] `/ddt version` prints "Don't Do That v" and the version in the .toc files. No error popups.
- [ ] `/ddt debug on` (so the report has details).

## 1. Settings window
- [ ] `/ddt` opens a window with seven pages: General, Alerts, Rules, Milestones, Tally, Debug, About.
- [ ] Options > AddOns shows "Don't Do That" with the same pages under it.
- [ ] General: an introduction, a **Master switch** section with one checkbox, and a **What it does** section with four more. Each checkbox has its explanation written underneath it (no need to hover), with space between them. All five are on. Turning the first one off greys out the other four. Turn it back on.
- [ ] Alerts: three ruled sections, **Warning sound** (a picker that starts with common sounds such as Raid warning, Ready check, Alarm clock 1-3 and Murloc aggro, then any sound-pack sounds; a **Play sound** button that plays the one you picked; and a note), **On-screen message** (a checkbox with its explanation under it), and **How often** (the slider with a note). Space between sections.
- [ ] Rules: the tree has **How this works** and **Classes**. Open **Classes > Hunter**; the categories show counts. Open **Save your gold**: each spell has its **real icon straight away**, even before you've opened any trainer (the icons come from the game by spell ID), the name, and a gray reason. A question mark means the game returned no icon for that spell; tell me which.
- [ ] Milestones: a gold status line, a progress line ("You have 12g of the 100g you need (12%)."), a **The mounts** heading with the two mounts (icon, price, gray note) separated by blank lines, and a **Not right?** section with the two "I've already bought" switches.
- [ ] Tally: sections **Kept**, **Spent anyway** and **Start over**, with the amounts in large type, a gray explanation under each, and the same style as the other pages. It already shows numbers before you visit any trainer (it reads your spellbook and the bundled spell list). "Kept so far" is roughly the cost of everything marked that you could buy at your level but haven't.
- [ ] About: a gold title and gray version, then three ruled sections (What the marks mean, How to use it, Good to know). Each mark is a **bulleted**, colored line with a gray explanation beneath, the three usage tips are bulleted too, and there is space between sections.
- [ ] Debug: ruled sections **Recording** (a checkbox with its explanation), **Report** (a note and **Show the report**) and **Clear** (a note and **Clear the recording**).

## 2. Marks in the trainer
- [ ] Open your **Hunter trainer**. Flagged rows show a colored **(i)** at the right edge; kept rows show nothing (for example Aspect of the Hawk, Serpent Sting, Wing Clip, Mend Pet, Dual Wield).
- [ ] Hover an (i): a tooltip with a **colored heading** (red, gold or blue to match the mark), the reason on its own wrapped line, then a blank line and the cost in **gold** ("Costs 12s"). Click it: the message stays open, spaced out with blank lines and sized to fit its text; click again to close it.
- [ ] Colors: red for Distracting Shot, Aspect of the Beast, Wyvern Sting, Volley; gold for tracking spells (Track Humanoids …), Scare Beast, Beast Lore, Scorpid/Viper Sting.
- [ ] Scroll the list: the (i) marks stay on the right rows.
- [ ] Open the **Pet Trainer**: the five resistances are marked gold; Great Stamina and Natural Armor ranks 5/7/9 and 6/8/10 are marked red.
- [ ] Hunter **beast training** (the pet's own window, paid in training points): no marks, no prompts, and ranks that cost points train normally. The log shows no "BuyTrainerService wrapped" line while it is open.
- [ ] Back in settings, **Rules** now shows real spell icons for what you just saw.

## 3. Warning and question
- [ ] `/ddt test`: you hear the sound and get **a dialog only, no banner**. **Cancel** prints "test: you declined". Run it again and press **Accept**: it prints "test: you chose to buy it anyway (nothing was bought)". If Accept does nothing, or you see "Don't Do That: that didn't work (…)" in chat, copy that text and `/ddt export` (the `popup:` lines say what happened).
- [ ] (L12) Select **Distracting Shot, Rank 1** (6 silver) and click **Train**: sound plus the "Buy anyway?" dialog. **Cancel**: nothing is bought, the spell is still listed.
- [ ] Click Train again and choose **Buy anyway**: the spell **is learned** and the list updates. (This is the key check. If a "blocked from an action" popup appears, or it isn't bought, tell me; the addon will also say in chat that it is turning the question off.)
- [ ] Buy a gold row such as **Track Humanoids**: **no** dialog and **no** sound; it just buys.
- [ ] General > turn off **Ask before buying**, then try a red row: you hear the sound and see the **on-screen message**, and the purchase goes ahead.
- [ ] Turn off **Play a warning sound**: no sound at all. Turn everything back on afterwards.
- [ ] Turn the whole addon off: no marks, no sound, no dialog.

## 4. Recommended filter
- [ ] Click the trainer's **Filter** menu: a **Recommended (Don't Do That)** checkbox appears below Available / Unavailable / Already known, and it is **checked**.
- [ ] The list is shorter (no extra text is added to the window): Distracting Shot, tracking spells, Eagle Eye and similar are gone; category headers remain. On Forever those rows are faded instead of removed (removing them taints Blizzard's list and the game then refuses beast training).
- [ ] Forever: at a class trainer select a flagged spell (Distracting Shot) and click Train. The question appears; decline and nothing is bought; click Train again and confirm, and the spell is learned. The button lights up under the mouse and presses as usual. An unflagged spell is bought with no question.
- [ ] Forever: in `/ddt export` with a class trainer open, the trainer snapshot shows `rank=2 ... status=available` style rows, not an icon number as the status; a rank the skip list passes over is faded and marked.
- [ ] Forever: with the filter on, visit a class trainer and a pet trainer, then open Beast Training and buy a pet ability that costs training points. No error, no question, and the ability is learned. `/run print(issecurevariable("BuyTrainerService"))` prints `true` throughout.
- [ ] Select a visible spell, click Train (use a cheap one): **the spell you selected is the one bought**.
- [ ] Scroll the list; click a category header to collapse and expand it; use the collapse-all button. Nothing looks broken and rows stay in order.
- [ ] Untick Recommended: every row comes back. Tick it again.
- [ ] With the trainer open, untick **Add a Recommended filter to trainers** in General settings: all rows return at once and the **Recommended entry is gone** from the Filter menu. Tick it again and it comes back.
- [ ] With the trainer open, turn off **Turn on Don't Do That** in General: all rows return, the (i) marks disappear and the Recommended entry is gone from the Filter menu. Turn it back on.
- [ ] Untick the **Recommended checkbox inside the Filter menu**: all rows return but the entry stays, so you can tick it again.
- [ ] Switch the Available/Unavailable/Already known boxes: the list still behaves normally.
- [ ] If anything looks wrong, the filter turns itself off and the normal window returns. `/ddt export` then contains a line "filter: turned off (reason)". Send it to me.

## 5. Tally and milestones
- [ ] Buy one marked spell and reopen the Tally page: the number moves from "Kept so far" to **Spent** straight after the purchase, without needing another trainer visit.
- [ ] After visiting both trainers, **Tally** shows "Kept so far" with a number (the cost of flagged things you could buy now but haven't).
- [ ] Buy one marked spell: **Spent on things the addon marked** goes up by its price.
- [ ] (L18) Skip Serpent Sting rank 2 and buy rank 3 straight away. It should be allowed, which confirms ranks can be bought out of order. The tally doesn't change, because those ranks aren't marked.
- [ ] **Start the count over** asks for confirmation and sets everything to zero.
- [ ] Milestones: tick "I've already bought my level 40 mount": the status changes to saving for level 60. Untick it.
- [ ] After you actually learn Apprentice Riding, the status moves on by itself. (If it doesn't, the override above is the workaround, and tell me.)

## 6. Resets
- [ ] Talents (level 10): open the talent window, spend your point, click **Learn**. Nothing is blocked (talent choices aren't judged).
- [ ] Ask your class trainer to **reset your talents**: you hear the warning sound and see **Don't Do That's own question** ("Reset your talents? This costs …, and the price goes up each time… Reset anyway?"). The game's own dialog is put away.
- [ ] Press **Cancel**: nothing is reset, the talent window closes (as the game's Cancel does), and the Tally later shows "Talent resets: skipped 1".
- [ ] Ask again and press **Accept** (it costs gold, so only if you're happy to): your talents reset and the Tally shows "done 1". If it doesn't reset, or chat says the game won't let the addon confirm, tell me; the addon then falls back to the game's own question with a note.
- [ ] Turn off **Ask before buying** and ask again: you hear the sound, and the game's own dialog stays, with a note added to it.
- [ ] Pet Trainer (needs a pet that has learned something): choose its **untrain** option and do the same.

## 7. Safety checks
- [ ] With every switch on, open and close the trainer a dozen times, scroll, and click around: no error popups.
- [ ] Open the **talent window**, **spellbook** and **bags** while the addon is on: nothing changes or breaks.
- [ ] `/ddt export`, copy it, and look for lines like "overlay: ClassTrainerFrame_Update hooked", "confirm: Train button click wrapped" (Classic Era) or "confirm: Forever window: Train button hooked, question asked from the addon's own button" and "filter: menu entry registered". Send me the report if any step above failed.

## 8. Spell data check
- [ ] `/ddt export`, then find the **Spell data check** section. It should say "bundled spell tables: build 1.60.1.70532, 157 spells for HUNTER" and "spellbook says N known" with N a believable number for your character (not 0 unless you know nothing).
- [ ] The five sample lines each show an **icon** number (not nil) and a believable known flag: for example Arcane Shot rank 2 known=true once you've bought it, false before.
- [ ] If a sample shows `known [..=false]` for something you do know, or `icon nil`, send me the section: it means an ID doesn't match this client.

## 9. Items and earn-back
- [x] At a vendor, right-click an armor or weapon piece costing 10 silver or more: a "Buy anyway?" question appears. Cancel: nothing bought, Tally shows one more turned-down purchase. (Checked 2026-10-24 with Hunter's Boomstick, 1192c: flagged, popup shown, cancelled; `itemsAvoided` rose to 4.)
- [x] The question has a line like "At level N, that's about X of grinding to earn back", and the gold amount is right. (Verified by hand 2026-10-24.)
- [x] Vendor: Accept buys the item. (Verified by hand 2026-10-24.)
- [x] Buy something under the minimum price (or a Food and drink item at a vendor): no question. (Verified by hand 2026-10-24; the minimum was lowered to 5c for the auction house tests.)
- [x] Purchases page (was Items): every category has a dropdown; changing one takes effect without a reload; gold/silver/copper boxes show 0 / 10 / 0 and reject letters.
- [x] Auction house: a flagged item shows the question and Cancel buys nothing. (Checked 2026-10-24 with Malachite, 18c, three times; `PlaceAuctionBid` wrapped and the game still calls ours.)
- [x] Auction house: both a bid and a buyout show the question, and Accept completes them. (Verified by hand 2026-10-24.) If instead the chat says item purchases are only warned, `/ddt export` and send the "items:" lines (task 1.1).
- [x] Talent-reset questions show the earn-back line. (Verified by hand 2026-10-24.)
- [ ] Trainer questions show the earn-back line.

## 10. Bank, stable and COD
- [ ] Buy a bank slot from the banker: the game's dialog is replaced by a question with the price and the earn-back line. Cancel: nothing bought, Tally's turned-down count rises. Accept: slot bought.
- [ ] Hunter: same for a stable slot at the stable master.
- [ ] Open a COD mail and take the item: the question shows the COD amount. Accept pays it; cancel leaves the mail alone. Taking an item from ordinary mail shows nothing.
- [ ] Items page: turn each of the three switches off and confirm the game's own dialog returns untouched.
- [ ] `/ddt export`: the Items section lists each guarded dialog as on and "lastSeen" with the dialog name and price read. Send it if a dialog never triggered.

## 11. Language and spell identity
- [ ] On an English client, `/ddt export`: the **Spell identity** section lists what the trainer row and the talent call return. Paste it into the change notes: it settles whether Forever gives the trainer a spell ID directly.
- [ ] Open any trainer and type `/ddt trainerids`: a window lists, per row, what every known call returns, and ends with a `RESULT:` line. Then `/ddt trainerids hover`, hover a trainer row within 5 seconds, and read the **hovered row** section. Paste both into the change notes. The report also ends with **identity checks**: talent links (do they carry a talent ID the table knows), the riding spell IDs, the profession apprentice spells and which trainer window is open. Run it once at a class trainer, once at a profession trainer, once at the Pet Trainer and once with no trainer open. So far this has only been done on a Hunter with no talent points; repeat it on another class that has spent talent points (the report should say "with points" and resolve them), ideally a Paladin or Warlock to see the class mount spells as known.
- [ ] A talent you have points in (for example Aimed Shot for a Hunter) counts as active: the spell is judged as part of your rotation, and `/ddt export` shows what `GetTalentLink` returns.
- [ ] Switch a spell off on the Rules page (for example Distracting Shot), `/reload`, and open the trainer: the row has no (i). Switch it back on and the (i) returns.
- [ ] If you can run the client in another language (the locale is set in the Battle.net launcher): the trainer marks, the Rules page and the toggles from the two lines above behave exactly the same, with spell names in that language and the addon's own text in English. A switch set in English is still set.
- [ ] Learn a profession's first tier from its trainer (Alchemy, Cooking, Tailoring…): you are asked once. Learning a gathering profession asks nothing. A second tier (Journeyman) asks nothing.
- [ ] Warlock: at a demon trainer or vendor, a secondary grimoire (Soothing Kiss, Devour Magic…) is asked about and one the guides recommend (Firebolt, Torment…) is not. Works the same on a client in another language.
- [ ] The Milestones page notices riding once learned: Apprentice Riding on Forever, or your race's riding spell (Horse Riding, Wolf Riding…) on Classic Era. On Classic Era level 60 riding shows once the racial riding skill has a max rank of 150; the identity checks print the skill line's rank and what `ReadRiding` says.

## 12. Skip list revisions
- [ ] First load after installing or updating (use a fresh `WTF` profile, or delete `revisionNotice` from the saved variables): the chat prints, once, that skip list revision 2 is in use, that its rules changed significantly (many more ranks skipped, decided for your spec, each with its reason), and how to change it (`/ddt revision 1`, Advanced > Tuning). `/reload`: it is not printed again.
- [ ] `/ddt revision` prints the revision in use and the revisions available. `/ddt revision 1` says "Now using skip list revision 1." and the Rules page and the Tuning page agree. `/ddt revision 9` changes nothing and lists the valid revisions. `/ddt revision 2` goes back.
- [ ] Advanced > Tuning > Skip list: a select with "Revision 2 (default): ..." and "Revision 1: ...". Picking Revision 1 and reopening the Rules page shows its ranks to skip, and the line at the top of the class page names revision 1.
- [ ] Warrior at a trainer on revision 2: Thunder Clap rank 2 and later are marked, and the tooltip says the leveling guide says to buy only the first rank of this spell. Rend rank 5 says to buy it only up to rank 4. On revision 1 the same ranks give the same guide reasons. Neither tooltip names Wowhead or "computed".
- [ ] A rank skipped for some specs only (for example a Mage spell skipped for Frost and Fire): with Frost chosen as the spec it is marked; with Arcane chosen it is not; with the spec undecided and talents split, it is not marked.
- [ ] At level 60 without the mount: a utility spell's later rank says it can wait until the level 60 mount; the first rank of a new level 60 spell and a damage or healing rank are not marked. After buying the mount nothing is marked.
- [ ] Switch an ability off on the Rules page, then change revision: it stays off under both. Switch off Skip ranks on Tuning: no rank is marked under either revision.
- [ ] The Rules page's Ranks to skip lists each rank with its reason and, beneath it, where it came from ("From the Wowhead leveling guide.", "Computed from the game data.", "From the earlier skip list.").

## Not covered yet
- Profession trainer rows are recognised by the client's name for the apprentice spell. Section 11 checks this on a real trainer; until it is ticked the row shape is unverified. With debug on, open each trainer and `/ddt export`.
- Anything on WoW Forever itself. Everything here is Classic Era until Forever is available.
