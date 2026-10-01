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

# Loch Modan for Dwarves and Gnomes, solo (2026-10-01). RestedXP's route does the north (Snowbound,
# the Silver Stream Mine, Stormpike) and the South Gate troggs, then flies out at about 13. Left out:
# Stonesplinter Valley and the whole east, ~10k quest XP at 13-16 plus the kills. Positions: Questie,
# Wowhead's Forever pages and their comments (Bingles' tools, the Banner event, the valley entrance).
# Dun Morogh ends in Stormwind (Stormpike's Delivery, the Deeprun rats): back by tram, fly in. The
# Thelsamar flight path is learned on Dun Morogh's dip into Loch Modan.
LM_ARRIVE = [
    "raw .zone Ironforge >> Take the Deeprun Tram back to Ironforge | raw .zoneskip Ironforge | raw .zoneskip Loch Modan",
    "goto 1455 55.5 47.7 | raw .fly Loch Modan >> Fly to Loch Modan | raw .target Gryth Thurden | raw .zoneskip Loch Modan",
]
# Hearth in Thelsamar: the east loop ends at the Farstrider Lodge, the far side of the lake.
LM_HOME = [
    "goto 1432 35.5 48.4 | raw .home >> Set your Hearthstone to Thelsamar | raw .target Innkeeper Hearthstove",
]
# Stonesplinter Valley, after the South Gate hand-ins: In Defense of the King's Lands 2 and 3 (1050
# each) and Forever's Banner of the Fallen (1250: plant the banner by Ylva, troggs come in waves from
# both sides, then Headsplitter). The way into the valley is up the path at 34,78.
LM_SOUTH = [
    "accept 237",
    "goto 1432 31.9 86.5 | raw .accept 86585 >> Accept Banner of the Fallen | raw >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mountaineer Ylva|r, up Stonesplinter Valley (the path at 34,78) | raw .target Mountaineer Ylva",
    "goto 1432 34.5 82.0 | raw >>Kill |cRXP_ENEMY_Stonesplinter Skullthumpers|r and |cRXP_ENEMY_Stonesplinter Seers|r in the valley | raw .complete 237,1 | raw .complete 237,2 | raw .mob Stonesplinter Skullthumper | raw .mob Stonesplinter Seer",
    "goto 1432 32.2 86.5 | raw >>Plant the banner back where you took it, next to Ylva. Kill the troggs that come from both sides, then |cRXP_ENEMY_Headsplitter|r | raw .complete 86585,1 | raw .mob Headsplitter",
    "turnin 237 | accept 263",
    "goto 1432 23.2 73.8 | raw .turnin 86585 >> Turn in Banner of the Fallen | raw >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Captain Rugelfuss|r | raw .target Captain Rugelfuss",
    "goto 1432 35.0 88.0 | raw >>Back up the valley: kill |cRXP_ENEMY_Stonesplinter Shamans|r and |cRXP_ENEMY_Stonesplinter Bonesnappers|r | raw .complete 263,1 | raw .complete 263,2 | raw .mob Stonesplinter Shaman | raw .mob Stonesplinter Bonesnapper",
    "turnin 263",
]
# The east, after Silver of the Waves: the Farstrider Lodge (Crocolisk Hunting 1050, Forever's
# Twisting the Knife 1150, A Hunter's Boast 875), Ironband's Excavation (Ironband's Excavation 340,
# Gathering Idols 1350, the Excavation Progress Report 270), then north along the shore: Daggerfang
# (63,50), the crocolisks, Bingles' four tools (Bingles' Missing Supplies 1050), back to the lodge,
# and the hearth to Thelsamar for Report to Ironforge (550, handed in in Ironforge on the way out).
LM_EAST = [
    "accept 436",
    "accept 385 86758",
    "accept 257",
    "goto 1432 75.0 64.0 | raw >>Kill |cRXP_ENEMY_Mountain Buzzards|r south-west of the lodge, within 15 minutes | raw .complete 257,1 | raw .mob Mountain Buzzard",
    "turnin 257",
    "turnin 436 | accept 297",
    "accept 298",
    "goto 1432 70.0 63.5 | raw >>Kill |cRXP_ENEMY_Stonesplinter Geomancers|r, |cRXP_ENEMY_Diggers|r and |cRXP_ENEMY_Berserk Troggs|r in the excavation. Loot their |cRXP_LOOT_Carved Stone Idols|r | raw .complete 297,1 | raw .mob Stonesplinter Geomancer | raw .mob Stonesplinter Digger | raw .mob Berserk Trogg",
    "turnin 297",
    "goto 1432 62.9 50.4 | raw >>Kill |cRXP_ENEMY_Daggerfang|r, the big crocolisk by the shore. Loot Marek's knife | raw .complete 86758,1 | raw .mob Daggerfang",
    "accept 2038",
    "goto 1432 59.0 38.0 | raw >>Kill |cRXP_ENEMY_Loch Crocolisks|r along the north-east shore. Loot their meat and skins | raw .complete 385,1 | raw .complete 385,2 | raw .mob Loch Crocolisk | raw .mob Large Loch Crocolisk",
    "goto 1432 54.0 27.0 | raw >>Pick up |cRXP_PICK_Bingles' Blastencapper|r | raw .complete 2038,4",
    "goto 1432 52.0 24.0 | raw >>Pick up |cRXP_PICK_Bingles' Hammer|r | raw .complete 2038,3",
    "goto 1432 48.0 20.0 | raw >>Pick up |cRXP_PICK_Bingles' Screwdriver|r | raw .complete 2038,2",
    "goto 1432 49.0 30.0 | raw >>Pick up |cRXP_PICK_Bingles' Wrench|r | raw .complete 2038,1",
    "turnin 2038",
    "turnin 385 86758",
    "hs Thelsamar",
    "turnin 298 | accept 301",
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
    # Dwarf/Gnome: the route ends in Ironforge (about level 14) before the tram: the Hall first.
    # Solo: Dwarves and Gnomes come here straight from Dun Morogh (not Elwynn), so the route gets the
    # way in, and the two parts of Loch Modan RestedXP leaves out (see LM_* above).
    "12-14 Loch Modan (Dwarf/Gnome)": [
        (r"\.turnin 418 >> Turn in Thelsamar Blood Sausages", "before", LM_ARRIVE),
        (r"\.turnin 6392 >> Turn in Return to Brock", "after", LM_HOME),
        (r"\.turnin 224 >> Turn in In Defense of the King's Lands", "after", LM_SOUTH),
        (r"\.turnin 86614 >>Turn in Silver of the Waves", "after", LM_EAST),
        (r"#label Deeprun", "before", ["turnin 301 | raw .isOnQuest 301"]),
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
