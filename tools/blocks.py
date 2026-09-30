"""Our own steps inside the routes tools/fork_rxp.py builds: route name -> [(pattern, "before"/"after", spec)].
A block goes before or after the first step of the route that matches the pattern. Specs are
tools/route_builder.py lines; "group:" makes a step the Duo and Trio versions' only (dungeons).

Why dungeons for groups: on Forever, dungeon quests pay three to four times their Classic XP (our
server scan), the dungeon mobs almost nothing. The quests in these blocks, at Forever XP:
  Stockade: What Comes Around 6400, Crime and Punishment 6700, Quell the Uprising 8500,
            The Color of Blood 8500, The Stockade Riots 7500.
"""

# Hall of Thanes (13-18, new in Forever), under Ironforge. Quest XP on Forever: Old Ironforge Incursion
# 4950 (Earthseer Farsen's chain in Dun Morogh, already on the route), Important Heirlooms 4600,
# The Restless Dead 3550, An Ancient Grudge 3550, The Treaty of Understanding. Givers and the way in:
# research/leveling/findings.md (Wowhead's Forever quest pages, warcrafttavern.com).
HALL_OF_THANES = [
    "group: accept 96403",
    "group: accept 96394",
    "group: goto 1455 43.5 52.0 : Enter the Hall of Thanes with your group: from the Great Forge, face Magni's throne, go left into the spiderweb corridor, down the stairs and the crumbling path (mind the lava), over the bridge",
    "group: raw .accept 96395 >> Accept An Ancient Grudge | raw >>Talk to the |cRXP_FRIENDLY_Ghostly Attendant|r in the first room",
    "group: do 96403 96394 96395 96393 : Clear the Hall: loot the Dwarven Heirlooms, kill Enraged Apparitions and Tormented Souls, put Faldrim Anvilmar to rest, take Durgen Dirgehammer's head",
    "group: raw .accept 98423 >> Accept The Treaty of Understanding | raw >>Take the tablet in the Reliquary of Kings (the last room)",
    "group: raw .turnin 96395 >> Turn in An Ancient Grudge | raw >>Back to the |cRXP_FRIENDLY_Ghostly Attendant|r",
    "group: turnin 96403",
    "group: turnin 96394",
    "group: turnin 96393 98423",
]

BLOCKS = {
    # Dwarf/Gnome: the route ends in Ironforge (about level 14) before the tram: the Hall first
    "12-14 Loch Modan (Dwarf/Gnome)": [
        (r"\.zone Stormwind", "before", HALL_OF_THANES),
    ],
    # Human: the route hearths from Loch Modan to Stormwind; a group flies to Ironforge first, runs
    # the Hall, and hearths from there instead
    "11-13 Loch Modan": [
        (r"\.hs >> Hearth to Stormwind City", "before", ["group: fly Ironforge"] + HALL_OF_THANES),
    ],
    # Stockade: picked up on the way (Guard Berton in Lakeshire, Councilman Millstipe in Darkshire,
    # Thelwater and Nikova in Stormwind), run at the end of the route in Stormwind (about level 27),
    # then the two out-of-town hand-ins by flight path.
    "24-27 Redridge/Duskwood": [
        (r"\.accept 244\b", "after", ["group: accept 386"]),
        (r"\.accept 163\b", "after", ["group: accept 377"]),
        (r"\.accept 1274\b", "after", [
            "group: turnin 389 | accept 391 387",
            "group: accept 388",
            "group: goto 1453 50.4 66.6 : Enter the Stockade in the Mage Quarter with your group",
            "group: do 386 377 387 388 391",
            "group: turnin 387 391",
            "group: turnin 388",
            "group: fly Lakeshire",
            "group: turnin 386",
            "group: fly Darkshire",
            "group: turnin 377",
        ]),
    ],
}
