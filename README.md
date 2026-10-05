# Headstart

Quality of life and levelling tools for **WoW: Forever**: camps, bags, vendors, an XP bar, gear and reward help, one-click setup of a new character from your main, and for levelling a run log, your runs saved as your own RestedXP routes, an in-game route editor and level splits. Headstart does not come with levelling routes: you make your own from your runs, or paste in one someone shared.

## Features

- **Your own routes.** Play with Record runs on, then save the run as a route (This run, Save as route): made from your run log, one part per zone, one set per race, played in RestedXP under My routes. Share passes a route on as text, or takes one someone gave you. Switch routes on once (the Levelling tab, Route settings, or `/headstart routes on`) for every character of the account.
- **Where next?** For a character that levelled by hand: which of its routes to pick up now and at which step, from its level and the quests it has handed in.
- **Route editor.** Every step can be changed in game: drag steps around, add, merge, duplicate or delete them, edit each action with pickers for your position and target, or edit the raw text. Your changes are saved for you and can be exported and shared; "back to the shipped route" undoes them.
- **Level splits.** Time per level and in total from the server's /played, against your best run, in green or red. XP per hour and time to ding. Movable, sizeable, lockable.
- **Quest rewards picked for you** up to a level you choose, from a priority list per class. It remembers what you picked by hand last time. Hold Shift to choose yourself. A choice that isn't gear (a profession to learn) is always yours. Each class has its own settings.
- **Run log.** Position, quests, kills, deaths, vendors, trainers, sales, loot and money of each run, to see where the time went. Click an action for its details. Stop a run when it's done.
- **Keep what the route needs.** Items a route quest still needs say so on their tooltip, and selling one warns you straight away.
- **Character setup.** Copy your main's action bars, macros and settings once per class; set up every new character of that class, after seeing exactly what carries over: class spells up to a level, racials, professions, mouseover macros, your own macros, items, game settings, Edit Mode, bar visibility. Works alongside ElvUI, EllesmereUI, Bartender, Dominos and other UI addons: it leaves their layouts alone. Chat, Edit Mode and game settings are the account's, so a new class gets them without copying anything; no main to copy from? Plan the whole class's bars on a level-1 character, on your real action bars.

## Quality of life

- **Camp HUD.** A campfire on screen when a camp is near, and once you have its benefit what it gives you, burning down with the hour.
- **Bags.** Bank crafting mats and recipes you can't use yet in one click (or as the bank opens); send them to your alt from the mailbox.
- **Vendors.** Restock your class reagents and ammo at the vendor; learn your spells at the trainer as you choose for each, keeping a reserve.
- **Better gear.** Every item's tooltip says what it would do for you (+DPS, +toughness, from your own stats and role), and an upgrade in your bags gets an Equip button.
- **Group.** Invite and leave buttons and key bindings, whisper "inv" to join, party quests shared and accepted for you.
- **Trinkets and gear sets.** Trinket buttons with your others a click away, trinkets swapped for you as they're used, Carrot on a Stick while mounted, and keys for your equipment sets.
- **Instance tracker.** New instances this hour and today against the limit, the wait for the next slot, and a log of every run with its time, XP and gold.
- **XP bar.** Your own experience bar in place of Blizzard's: size, place, colours and the words on it, with XP an hour, time and kills to ding, and played time.
- **Reminders.** Trainer spells waiting, unspent talent points, low durability, stones, oils and bandages you could make, a screenshot at every ding. Flight timer.

## Use

- `/headstart` (or the minimap button, or the addon compartment) opens the window. It has two tabs, each with its own menu: **Levelling** (this run, share, route settings, and the routes) and **QoL** (Find a setting, then the Quality of life and Character pages, Instances among them). `/hs` opens the QoL tab.
- RestedXP Guides is needed for the routes. Everything else works without it.

## Credits and licence

Headstart's route tools work on [RestedXP](https://github.com/RestedXP/RXPGuides) guide text, and RestedXP Guides plays the routes. Thank you, RestedXP. Routes built on RestedXP's guides are under their [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) licence; Headstart ships none.

Headstart as a whole is shared under the same licence: see [LICENSE](LICENSE).

## Development

- `python tools/smoke.py` and `python tools/smoke_setup.py` run the tests (they need `lupa`). smoke.py's route tests need a routes addon in `../Headstart_Routes` and skip without it; `python tools/smoke_noroutes.py` tests Headstart as published, with none.
- `python tools/package.py` builds `dist/Headstart-<version>.zip`.
