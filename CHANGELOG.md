# Changelog

## 0.9.0-beta1

- **Settings per class.** Each class keeps its own quest-reward settings (on/off, priority list, level limit, remembered picks) and its own Character setup: the saved bar layout and every choice of what carries over. Pick the class at the top of either tab; it opens on this character's class. Your existing settings carry over untouched: they become the settings of the class they were made on, and other classes start from the same choices (their own reward list, and your non-gear picks such as a profession book).
- **Set up shows the settings first.** The new-character window's "Set up..." opens Settings, Character tab, so you see everything that will carry over before clicking Set up layout there.
- Dun Morogh: Mining and Blacksmithing to 20 for the two Camping 101 quests (270 XP each, and the Sharpening Wheel). A reminder to mine every copper vein you pass until Mining 20 (most sit around the Grizzled Den and south of Kharanos). A stop at Tognus's forge and anvil to smelt and craft to Blacksmithing 20. Both hand-ins, shown only once the quest is done.
- Dun Morogh money: Cooking (270 XP for 1 silver) comes before class training, with a second chance once Stocking Jetsteam has paid. The Mining Pack (25c) only if money is left.
- Copper Ore, Bars and Rough Stones count as route items while you're on Camping 101: Blacksmithing, so the sell warning covers them.
- The run log records your money with every event, so the analysis can show what training and vendors really cost.
- Dun Morogh route, from a logged run: take Flintfire's Shipment at the same Tognus visit as Blacksmithing, hand in Senir's Observations before sitting at the campfire, and take The Reports when handing in Frostmane Hold (each was a separate trip).
- This run: click an action for its details beside the list. A quest shows when and where you took it, finished it and handed it in, from and to whom, and its XP and money. Everything shows where it happened, and a Wowhead link to copy.
- The window opens on the route you're on (the one RestedXP has loaded, else your race's starting route), not always Coldridge, so This run's "Add to route" goes to the right one.
- Quest rewards: a choice that isn't gear or food (a profession to learn, a mining pack or herb bag) is never made for you. It used to take the most valuable, which picked Mining. A choice you made by hand on that quest is still repeated.
- **Keep what the route needs:** items a route quest still needs (like 4 Chunks of Boar Meat for Stocking Jetsteam, from Coldridge on) say so on their tooltip, and selling one to a vendor warns you straight away so you can buy it back. Read from the routes themselves; on/off in Settings.
- **Stop this run** (This run page): the splits clock and the run log end there; Resume carries on without counting the pause. **A run to beat** off keeps a run out of "vs best".
- The run log also records sales and quest-item loot.
- Coldridge: kill trolls to 1040/1400 XP before turning in The Troll Cave, so you are level 4 for Nori's quest; keep 4 Chunks of Boar Meat when you vendor.
- Set up layout places AutoFeed's macros on a new character: when AutoFeed hasn't made them there yet, it's asked to make them (so it owns and fills them), and they go where they are on your main.
- Level splits: "vs best" compares against a run with every level timed. A run first timed part-way (for example a character that was already level 8) no longer blanks the column.
- Set up layout only asks for a reload when it actually changed your Edit Mode layout or which action bars are shown.
- Updates never overwrite your route edits. When a new version ships a changed route you have edited, you're told once in chat and the route gets a blue dot. **Take the update** gives you the new route with your edits on top (where we changed a step you changed too, yours is kept), **Keep mine** leaves it as it is, and **Undo the update** goes back.
- "Back to the shipped route" now asks first, since it throws your edits away.

## 0.8.1-beta1

First CurseForge build (same addon as 0.8.0).

## 0.8.0

First public version.

- Launch routes for RestedXP: Coldridge Valley 1-5 and Dun Morogh 5-11 (Dwarf, Gnome), Northshire 1-6 (Human), Shadowglen 1-6 (Night Elf), for every class.
- Routes cleaned of everything that never shows on WoW: Forever (Season of Discovery, hardcore and self-found steps, video links).
- In-game route editor with export and import.
- Level splits from /played, against your best run.
- Quest rewards picked for you from a priority list per class.
- Run log.
- Character setup from your main, with a choice of what carries over; leaves ElvUI, EllesmereUI, Bartender and Dominos alone.
- Settings in one place, with Route and Character tabs; hover the (i) on a setting for its details.
