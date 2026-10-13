# Headstart

Quality of life, levelling tools and one-click character setup for **WoW: Forever**, in one addon. A new character gets your action bars, macros, key bindings and interface in one click; your trainer, vendors, bank and mailbox can be handled for you by rules you set; and the screen gets the bars and notes you ask for and nothing else.

**Nothing acts for you until you turn it on.** Installing Headstart does not touch your action bars, macros, key bindings, Edit Mode layout, chat windows or game settings, and it buys, moves, accepts and picks nothing. A welcome window asks what you want; everything that spends gold, moves items or answers for you starts off, and says what it does before you switch it on. The one thing it does unasked is skip a cinematic, which on a new character is the opening flight over its zone: it says so in chat, and Skip cinematics is a switch (hold Shift as you enter the world to watch).

Headstart does not come with levelling routes: you make your own from your runs, or paste in one someone shared.

## Getting started

- `/headstart` (or the minimap button) opens the window. It has three tabs: **QoL**, **Levelling** and **Character setup**. `/hs` goes straight to the settings.
- The first time, a welcome window asks four things: your own routes, what goes on screen, what is done for you, and Character setup. Pick one of three quick answers or each by itself. `/headstart start` brings it back.
- After you answer, **Before you play** lists what is now on that deserves a look first - what spends gold, what moves your items, what answers for you - each with a button to its settings.
- The settings can be searched, and every feature is one card with its switch in its head.

## New characters and your interface

- **Character setup.** Save your bars once per class, as a profile, and put them on every new character of that class in one click: class spells up to a level, racials, professions, your own macros, items. Spells you haven't learned yet get a place that fills in as you train them.
- **Your interface, once for the account.** Edit Mode layout, which action bars show, chat windows, game settings, camera distance, **key bindings**, and **graphics and sound**, saved from one character and applied to the next - on another install too.
- **Profiles.** Several bar layouts per class under names of your own (Tank, DPS), switched from the window, the minimap button, a key or `/headstart profile Tank`.
- **A planner** to lay out a whole class's bars on a level 1 character, on your real action bars, with no main to copy from.
- **A macro helper** that makes your class's usual macros by ticking boxes.
- **Safe on a character you already play.** It asks first and says what would go. Your bars and macros are written down before every change: `/ysetup undo` steps back one change at a time, and `/ysetup undo first` puts the bars back as they were before Headstart touched the character. **Bars only** leaves your interface alone. Chat windows and the Edit Mode layout are the two things an addon cannot put back, and the dialogs say so.
- Works beside ElvUI, EllesmereUI, Bartender and Dominos: their layouts and bars are left to them.

## Done for you, by your rules (all off until you turn them on)

- **Class trainer.** Buys your class's spells as the trainer opens: each spell Always, If I can afford it, First rank only or Never, with an amount of silver to keep. It never buys weapon skills, riding or professions, and chat says what it learned and for how much.
- **Quest rewards** picked from a priority list per class up to a level you choose. It remembers what you picked by hand, and leaves the choice to you when a green is offered.
- **Restock.** Reagents, ammo and your own list bought back up to what you carry, above an amount of gold you keep.
- **Bank and mail.** Crafting mats and recipes you can't use yet moved to the bank, or mailed to another character. Quest items always stay.
- **Trinkets.** Swapped in by your own order as they come off cooldown; Carrot on a Stick while you ride, and an item of your choice while you swim.
- **Group.** Invites from friends and guild members accepted, a whisper of "inv" answered with an invite, quests shared and accepted.

Hold Shift as you open a trainer, vendor, bank or mailbox to do it yourself that time.

## On your screen (each one a switch)

- **Combat bars.** A swing timer (Blizzard's bars restyled, or Headstart's own), a range bar that says how many yards your target is away, health, power and combo point bars, and a cast bar, all in one look.
- **Trinket buttons** with your other trinkets a click away, and keys for the game's equipment sets.
- **Death recap.** What killed you and the hits before it.
- **XP bar** with rested and quest experience, XP an hour and time to level.
- **Camp icon** lit near a camp or while its buff runs, and a **flight timer** while you fly.
- **Instance tracker.** Dungeon entries this hour and today against the limits, and a log of every run.
- **Loot feed** and a loot log with session totals.
- **Upgrade notes.** Every item's tooltip says what it would do for you, and an upgrade in your bags gets an Equip button.
- **Reminders.** Trainer spells waiting and what they cost, talent points to spend, low durability, stones, oils and bandages you could make.
- **Your other characters'** bags, bank and gold.
- **Chat log** to search and copy from, past sessions included, a whisper sound of your own, and fewer buttons beside chat.
- **Arrange** (`/hs move`): every bar, button and icon of Headstart's on a grid, moved by dragging, the arrow keys or typed numbers.
- Looks for the game's damage meter and for RestedXP's window; the bag bar and micro menu hidden or on mouseover; the talent window movable and see-through.
- **Skip cinematics:** a new character's opening flight ended as it starts. On unless you turn it off.

## Journey

Your character's road, counted quietly as you play: how far you travelled and how, where the hours went, gold earned and spent, your best find, the zones you saw, the enemies you met most, and how long each level took. At level 20, 30, 40, 50 and 60 a chapter is written and a small note offers to show it: a book in the game's own look, a page at a time, each chapter set against the one before. `/hs journey`.

## Levelling by a route (needs RestedXP Guides)

- **Your own routes.** Play with Record runs on, then save the run as a route, played in RestedXP under My routes. Share passes a route on as text, or takes one someone gave you.
- **Route editor.** Every step can be changed in game: drag steps around, add, merge, duplicate or delete them, or edit the raw text.
- **Level splits.** Time per level and in total against your best run, XP an hour and time to level.
- **Run log.** Position, quests, kills, deaths, vendors and money of each run, to see where the time went.
- **Where next?** For a character that levelled by hand: which route to pick up, and at which step.
- **Keep what the route needs.** Items a route quest still needs say so on their tooltip, and selling one warns you.

## Taking your settings to another install

The game keeps an addon's settings separately for every installed client: the beta's are not the live game's, and nothing carries them over. Two ways to bring yours along. Either one brings your settings, trainer choices, reward lists, your own routes and Character setup's profiles and interface. What belongs to one character (its journey, its logs, its undo copies) stays with that character.

**1. Copy one file, before you log in there.** With the game closed, copy

`WTF\Account\<your account>\SavedVariables\Headstart.lua`

from the old client's folder to the same place in the new one. The account folder appears in the new client the first time you log in there, and its name may differ between clients (on a test client it can be a number where the live game uses your account name). This is the account's file: the files further down, under a realm and a character's name, belong to those characters and are not needed. The next time you enter the world everything is there.

**2. As a text, in the game.** In the old install: `/headstart transfer`, **Export**, and save the text in a text file. In the new one, once you are in the world: `/headstart transfer`, paste, **Read**, **Import**. If the old install can no longer be opened, paste the whole of its `Headstart.lua` file instead: it is read the same way. Nothing in the text is ever run, and what an import replaced can be put back with **Undo last import**. A text from someone else is safe to import: what acts for you (mail, restock, the trainer, invites) stays as you have it and macros that run code are left out; **All of it** is for a text you exported yourself.

Then, on a new character, Headstart's window comes up two seconds after its first login: **Apply both** puts your bars, macros, key bindings and interface on.

In a beta client the top of All features says this too, with a button to the window above, until you hide it for a week.

## Commands

| Command | What it does |
|---|---|
| `/headstart` | The window |
| `/hs` | The settings |
| `/headstart start` | The welcome window, and Before you play |
| `/hs move` | Arrange what is on your screen |
| `/hs journey` | Your journey |
| `/headstart transfer` | Your settings as a text, to take to another install |
| `/ysetup undo`, `/ysetup undo first` | Character setup: the last change undone; the bars as they were before Headstart |

## Other addons

RestedXP Guides is needed for the routes and their tools; everything else works without it. Where EllesmereUI, Leatrix Plus, Naowh Forever, NovaInstanceTracker or Baganator already does what one of Headstart's features does, that feature of Headstart's starts off and the settings say which addon has it.

## Credits and licence

Headstart's route tools work on [RestedXP](https://github.com/RestedXP/RXPGuides) guide text, and RestedXP Guides plays the routes. Thank you, RestedXP. Routes built on RestedXP's guides are under their [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) licence; Headstart ships none.

Headstart as a whole is shared under the same licence: see [LICENSE](LICENSE).

## Development

- `python tools/smoke.py`, `python tools/smoke_setup.py` and `python tools/smoke_planner.py` run the tests (they need `lupa`). smoke.py's route tests need a routes addon in `../Headstart_Routes` and skip without it; `python tools/smoke_noroutes.py` tests Headstart as published, with none. `python tools/smoke_idle.py` counts what a login costs with everything off and as a new install comes.
- `python tools/render.py <page>` draws a settings page to `tools/render/<page>.html` without the game.
- `python tools/settings_text.py [saved file]` makes the Move settings text from a saved file without the game; `python tools/live_move.py` keeps a copy of a client's WTF folder and puts the saved files into another client's.
- `python tools/package.py` builds `dist/Headstart-<version>.zip`.
