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
    # Blackfathom Deeps' Ironforge quest, taken now for the group's BFD run at the end of 21-23 Ashenvale
    "group: accept 971",
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

# Blackfathom Deeps (about level 23): In Search of Thaelrid 9000, Twilight Falls 9550, Blackfathom
# Villainy 12400, Knowledge in the Deeps 10300 at Forever XP, over 40,000 for one run. The Darnassus
# quests are taken at the start of 21-23 Ashenvale (Hunters already have them from 19-21), the run is
# at the Zoram Strand where the route already is, the hand-ins on the route's Darnassus visit.
BFD_PICKUP = [
    "group: fly Auberdine : Blackfathom Deeps quests in Darnassus first, for the group run at the Zoram Strand | raw .isNotOnQuest 1198",
    "group: goto 1439 33.2 39.9 | raw .zone Teldrassil >> Take the boat to Teldrassil | raw .isNotOnQuest 1198",
    "group: goto 1438 58.399 94.016 | raw .fp Rut'theran >> Get the Rut'theran Village flight path | raw .isNotOnQuest 1198",
    "group: raw .goto 1438/1,968.90,8795.34 | raw .zone Darnassus >> Take the purple portal into Darnassus | raw .isNotOnQuest 1198",
    "group: accept 1198",
    "group: accept 1199",
    "group: raw .goto 1457,31.0,41.5 | raw .zone Teldrassil >> Take the purple portal back to Rut'theran Village | raw .zoneskip Ashenvale",
    "group: goto 1438 58.399 94.016 | fly Astranaar | raw .zoneskip Ashenvale",
]
BFD_RUN = [
    "group: goto 1414 44.16 34.85 : Enter Blackfathom Deeps with your group: the temple on the Zoram Strand, then dive down to the entrance",
    "group: do 1199 : Kill the Twilight's Hammer cultists in the dungeon for Twilight Pendants",
    "group: do 971 : Find the Lorgalis Manuscript underwater in the flooded halls | raw .isOnQuest 971",
    "group: raw .turnin 1198 >> Turn in In Search of Thaelrid | raw .accept 1200 >> Accept Blackfathom Villainy | raw >>Talk to |cRXP_FRIENDLY_Argent Guard Thaelrid|r, partway through the dungeon",
    "group: do 1200 : Kill Twilight Lord Kelris at the Moonshrine for his head",
]
BFD_TURNIN = [
    "group: goto 1439 33.2 39.9 | raw .zone Teldrassil >> Take the boat to Teldrassil | raw .zoneskip Darnassus",
    "group: raw .goto 1438/1,968.90,8795.34 | raw .zone Darnassus >> Take the purple portal into Darnassus",
    "group: turnin 1199",
    "group: turnin 1200",
]

BLOCKS = {
    # the Hunters' route ends in Darnassus: the BFD quests there
    "19-21 Darkshore/Ashenvale": [
        (r"\.turnin 741\b", "before", ["group: accept 1198", "group: accept 1199"]),
    ],
    "21-23 Ashenvale": [
        (r"\.turnin 967\b", "before", BFD_PICKUP),
        (r"\.turnin 1009\b", "after", BFD_RUN),
        (r"Exit Darnassus through the purple portal", "before", BFD_TURNIN),
        (r"Fly back to Auberdine", "after", ["group: goto 1438 58.399 94.016 | fly Auberdine | raw .isNotOnQuest 942"]),
    ],
    # everyone passes Ironforge on the way to the Wetlands
    "23-24 Wetlands": [
        (r"\.train 197\b", "after", ["group: turnin 971 | raw .isOnQuest 971"]),
    ],
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
