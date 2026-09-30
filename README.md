# Headstart

A launch-day levelling kit for **WoW: Forever**: crowd-aware starting-zone routes for RestedXP, an in-game route editor, level splits, a quest reward picker, a run log, and one-click setup of a new character from your main.

Built for the first hours of a fresh realm, when every starting zone has hundreds of players in it: the routes go to the edges of the zone first, skip the camped opening quests, and group up at the single-spawn kills.

## Features

- **Launch routes for RestedXP.** Alliance starting zones for every class:
  - Dwarf and Gnome: Coldridge Valley 1-5, then Dun Morogh 5-11 (Mining and Blacksmithing picked up on the way)
  - Human: Northshire 1-6
  - Night Elf: Shadowglen 1-6

  They show up in RestedXP under **Headstart Launch (A)** and hand over to RestedXP's own guides where they end.
- **Route editor.** Every step can be changed in game: drag steps around, add, merge, duplicate or delete them, edit each action with pickers for your position and target, or edit the raw text. Your changes are saved for you and can be exported and shared; "back to the shipped route" undoes them.
- **Level splits.** Time per level and in total from the server's /played, against your best run, in green or red. XP per hour and time to ding. Movable, sizeable, lockable.
- **Quest rewards picked for you** up to a level you choose, from a priority list per class. It remembers what you picked by hand last time. Hold Shift to choose yourself. A choice that isn't gear (a profession to learn) is always yours. Each class has its own settings.
- **Run log.** Position, quests, kills, deaths, vendors, trainers, sales, loot and money of each run, to see where the time went. Click an action for its details. Stop a run when it's done.
- **Keep what the route needs.** Items a route quest still needs say so on their tooltip, and selling one warns you straight away.
- **Character setup.** Copy your main's action bars, macros and settings once per class; set up every new character of that class, after seeing exactly what carries over: class spells up to a level, racials, professions, mouseover macros, your own macros, items, game settings, Edit Mode, bar visibility. Works alongside ElvUI, EllesmereUI, Bartender, Dominos and other UI addons: it leaves their layouts alone.

## Use

- `/headstart` (or the minimap button, or the addon compartment) opens the window: routes, this run, share, and settings (Route and Character tabs).
- RestedXP Guides is needed for the routes. Everything else works without it.

## Credits and licence

The Dun Morogh, Northshire and Shadowglen routes are adapted from [RestedXP](https://github.com/RestedXP/RXPGuides)'s Forever guides, and Coldridge takes its coordinates and wording from them, under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) licence. Thank you, RestedXP.

Headstart as a whole is shared under the same licence: see [LICENSE](LICENSE).

## Development

- `python tools/smoke.py` and `python tools/smoke_setup.py` run the tests (they need `lupa`).
- `python tools/fork_zones.py` and `python tools/fork_dunmorogh.py` rebuild the forked routes from a RestedXP checkout; `tools/clean_guide.py` strips what never shows on Forever (Season of Discovery, hardcore and self-found steps).
- `python tools/package.py` builds `dist/Headstart-<version>.zip`.
