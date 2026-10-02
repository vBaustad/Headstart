"""Our own steps inside the routes tools/fork_rxp.py builds: route name -> [(pattern, "before"/"after", spec)].
A block goes before or after the first step of the route that matches the pattern. Specs are
tools/route_builder.py lines; "group:" makes a step the Duo and Trio versions' only (dungeons).

Why dungeons for groups: on Forever, dungeon quests pay three to four times their Classic XP (our
server scan, beta build of 30 Sep), the dungeon mobs almost nothing. The 2 Oct build halves the part
above normal quest XP ("dungeon quests now reward 50% less extra experience"): about 2.4 times instead
of 3.75. Measured (level-1 scan of build 70170, 2 Oct): dungeon quests at about 0.63 of the numbers
below, Baron Marinous 1650, The Treaty of Understanding 2550. At Forever XP (30 Sep):
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
# Paladins and Warriors who reached Blacksmithing 40 anyway (the route doesn't push it) make the Heavy Copper
# Maul on the way through Ironforge (about 11): 2 Light Leather at the auction house (no vendor sells
# it), the recipe from Bengus Deepforge and the anvil at the Great Forge, then the flight out. Skipped
# below Blacksmithing 40. The Maul: 2H mace, 28-43, 10.8 DPS, +4 Strength, level 11.
LM_MAUL = [
    "goto 1455 24.16 74.67 | raw >>Buy 2 |T134256:0|t[Light Leather] at the auction house, for the |cRXP_LOOT_Heavy Copper Maul|r (no vendor sells it) | raw >>|cRXP_WARN_None on sale? Skip this step and the next two|r | raw .collect 2318,2 --Collect Light Leather (2) | raw .target Auctioneer Redmuse | raw .skill blacksmithing,<40,1 << Paladin/Warrior",
    "goto 1455 52.55 41.46 | raw .train 7408 >> Train |T133052:0|t[Heavy Copper Maul] | raw >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bengus Deepforge|r at the Great Forge | raw .target Bengus Deepforge | raw .skill blacksmithing,<40,1 << Paladin/Warrior",
    "goto 1455 51.6 42.4 | raw >>Make the |cRXP_LOOT_Heavy Copper Maul|r at an anvil by the Great Forge (12 Copper Bars, 2 Light Leather, and 2 Weak Flux from |cRXP_FRIENDLY_Thurgrum Deepforge|r right there) | raw .collect 6214,1 --Collect Heavy Copper Maul (1) | raw .skill blacksmithing,<40,1 << Paladin/Warrior",
    "raw #sticky | raw .equip 16,6214 >> Equip the |T133052:0|t[Heavy Copper Maul] (from level 11) | raw .itemcount 6214,1 << Paladin/Warrior",
]
LM_ARRIVE = [
    "raw .zone Ironforge >> Take the Deeprun Tram back to Ironforge | raw .zoneskip Ironforge | raw .zoneskip Loch Modan",
] + LM_MAUL + [
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
# Twisting the Knife 1150, A Hunter's Boast 875), north along the shore (Daggerfang at 63,50, the
# crocolisks, Bingles' four tools: Bingles' Missing Supplies 1050), back to the lodge, and on the way
# west Ironband's Excavation last (Ironband's Excavation 340, Gathering Idols 1350, the Excavation
# Progress Report 270, Forever's Excavation Tools 1350: six tools lying round the dig, the first one
# looted starts it), then the hearth to Thelsamar for Report to Ironforge (550, handed in in Ironforge
# on the way out). The dig is last because its quests are level 18 and its troggs 17-20 (about 16 by
# then, tools/check_levels.py): the Geomancers and Diggers, not the Berserk Troggs (19-20).
LM_EAST = [
    "accept 436",
    "accept 385 86758",
    "accept 257",
    "goto 1432 75.0 64.0 | raw >>Kill |cRXP_ENEMY_Mountain Buzzards|r south-west of the lodge, within 15 minutes | raw .complete 257,1 | raw .mob Mountain Buzzard",
    "turnin 257",
    "goto 1432 62.9 50.4 | raw >>Kill |cRXP_ENEMY_Daggerfang|r, the big crocolisk by the shore. Loot Marek's knife | raw .complete 86758,1 | raw .mob Daggerfang",
    "accept 2038",
    "goto 1432 59.0 38.0 | raw >>Kill |cRXP_ENEMY_Loch Crocolisks|r along the north-east shore (not the big Large Loch Crocolisks, level 22). Loot their meat and skins | raw .complete 385,1 | raw .complete 385,2 | raw .mob Loch Crocolisk",
    "goto 1432 54.0 27.0 | raw >>Pick up |cRXP_PICK_Bingles' Blastencapper|r | raw .complete 2038,4",
    "goto 1432 52.0 24.0 | raw >>Pick up |cRXP_PICK_Bingles' Hammer|r | raw .complete 2038,3",
    "goto 1432 48.0 20.0 | raw >>Pick up |cRXP_PICK_Bingles' Screwdriver|r | raw .complete 2038,2",
    "goto 1432 49.0 30.0 | raw >>Pick up |cRXP_PICK_Bingles' Wrench|r | raw .complete 2038,1",
    "turnin 2038",
    "turnin 385 86758",
    "turnin 436 | accept 297",
    "accept 298",
    "raw #sticky | raw #label ExcavationTools | goto 1432 69.5 64.5 | raw >>As you go round the dig: pick up the |cRXP_PICK_Excavation Tools|r lying on the ground (66-72, 59-68). The first one starts Excavation Tools: click it in your bags | raw .accept 86613 >> Accept Excavation Tools | raw .use 278049 | raw .complete 86613,1",
    "goto 1432 70.0 63.5 | raw >>Kill |cRXP_ENEMY_Stonesplinter Geomancers|r and |cRXP_ENEMY_Diggers|r in the excavation (leave the |cRXP_ENEMY_Berserk Troggs|r, level 19-20). Loot their |cRXP_LOOT_Carved Stone Idols|r | raw .complete 297,1 | raw .mob Stonesplinter Geomancer | raw .mob Stonesplinter Digger",
    "turnin 297",
    "goto 1432 65.8 65.5 | raw .turnin 86613 >> Turn in Excavation Tools | raw .target Prospector Ironband | raw .isQuestComplete 86613",
    "hs Thelsamar",
    "turnin 298 | accept 301",
]

# Westfall, solo (2026-10-01): RestedXP's route is one visit (Sentinel Hill, the farms, the coast) and
# hearths to Stormwind for the Darkshore boat. Added on that visit, from Forever's Toxic Soil chain and
# the quests RestedXP leaves out:
#  - Harvesting the Harvesters (Ozwin at Saldean's Farm, 800): 14 Golem Isosprings (fast from the Rusty
#    Harvest Golems north of the farm, ~56,21) and 5 Harvester Gyrostabilizers (Harvest Watchers, the
#    Killing Fields mobs; a very low drop rate, ~60 kills for one player): as you go, handed in if
#    done. Its second part starts from an item almost any golem drops (800). The third needs
#    Engineering parts: left out.
#  - At the end: The State of the Mines (490: Jangolode Mine kobolds, Gold Coast Quarry gnolls),
#    Moonbrook Espionage (550: crates in the tunnel down to the Deadmines) with The People's Militia 2
#    (975: Defias in Moonbrook), and Explosive Consultation (575, a delivery to Sprite Jumpsprocket in
#    Stormwind, where the route hearths anyway). A Dynamite Plan (10 Coarse Dynamite: Engineering or
#    the auction house) and the rest of the chain after it are not solo: left out.
# Positions: Questie, Wowhead's Forever pages and their comments.
WF_HARVEST = [
    "accept 92909",
    "raw #sticky | raw #label Harvesters | raw >>As you go: |cRXP_LOOT_Golem Isosprings|r drop fast from the |cRXP_ENEMY_Rusty Harvest Golems|r north of Saldean's Farm; |cRXP_LOOT_Harvester Gyrostabilizers|r from |cRXP_ENEMY_Harvest Watchers|r and |cRXP_ENEMY_Golems|r (rarely) | raw .complete 92909,1 | raw .complete 92909,2 | raw .isOnQuest 92909",
]
WF_HARVEST_TURNIN = [
    "turnin 92909 | raw .isQuestComplete 92909",
    "goto 1436 51.4 32.2 | turnin 92910 | raw .isOnQuest 92910 | raw >>If a golem dropped a |cRXP_LOOT_Precessive Autocognition Assembly|r, use it to start the quest",
]
WF_END = [
    "accept 92745",
    "goto 1436 44.5 21.5 | raw >>Kill |cRXP_ENEMY_Kobold Diggers|r in the Jangolode Mine | raw .complete 92745,1 | raw .mob Kobold Digger",
    "goto 1436 29.3 49.5 | raw >>Kill |cRXP_ENEMY_Riverpaw Miners|r in the Gold Coast Quarry | raw .complete 92745,2 | raw .mob Riverpaw Miner",
    "turnin 92745 | accept 92747",
    "goto 1436 43.5 70.0 | raw >>Kill |cRXP_ENEMY_Defias Pillagers|r and |cRXP_ENEMY_Defias Looters|r in Moonbrook | raw .complete 13,1 | raw .complete 13,2 | raw .mob Defias Pillager | raw .mob Defias Looter | raw .isOnQuest 13",
    "goto 1436 42.5 71.5 | raw >>Into the Defias building in Moonbrook and down the tunnel toward the Deadmines: loot the |cRXP_PICK_Suspicious Industrial Supplies|r crates | raw .complete 92747,1",
    "turnin 92747 | accept 92748",
    "turnin 13 | raw .isQuestComplete 13",
]

# Redridge and Duskwood, solo (2026-10-01), in the free 23-30 route's visits:
#  - Redridge, second visit (~26, it passes Alther's Mill going east): Forever's Alther's Mill (1650:
#    Greater Tarantulas and their eggs, Foreman Oslow in Lakeshire), and Missing In Action (2550: the
#    escort of Corporal Keeshan, elite and he tanks, from the cave north where the route kills its
#    Blackrock Champions). Howling in the Hills (Yowler sits in a camp of 5-6 gnolls) and Gath'Ilzogg
#    (elite) are group quests: left out. Gearing Redridge is Blacksmithing crafts: left out.
#  - Duskwood: Forever's Valor family. The Valor Family (1750: the Raven Hill Tome, in a house at
#    21.2,55.7) from Sirra Von'Indi in Darkshire; Merrick's Bow (2300) starts from a bow the Lost Watcher
#    drops (a ghost by the road at 36,63), its Splinter Fist gnolls are where the 28-30 route goes;
#    Ira's Dagger (1950) has no known start: its steps show only if you have it.
# Wowhead's Redridge positions are on the Classic map; converted (fork_rxp.to_forever) or Questie's.
RR_MILL = [
    "accept 98386",
    "goto 1433 45.0 40.5 | raw >>Alther's Mill: kill |cRXP_ENEMY_Greater Tarantulas|r and destroy the |cRXP_PICK_Tarantula Eggs|r | raw .complete 98386,1 | raw .complete 98386,2 | raw .mob Greater Tarantula",
]
RR_KEESHAN = [
    "accept 219 : Corporal Keeshan, in the cave here",
    "raw >>Escort |cRXP_FRIENDLY_Keeshan|r back to Lakeshire. He's elite and tanks: attack what he attacks. The cave mouth gets busy, so group up if you can | raw .complete 219,1",
]
RR_TURNINS = [
    "turnin 98386 | raw .isQuestComplete 98386",
    "turnin 219 | raw .isQuestComplete 219",
]
DW_VALOR = ["accept 96139"]
DW_TOME = ["goto 1431 21.2 55.7 | raw >>In Raven Hill: the |cRXP_PICK_Raven Hill Tome|r, on a broken octagonal table inside a house | raw .complete 96139,1"]
DW_VALOR_TURNIN = [
    "turnin 96139 | raw .isQuestComplete 96139",
    "goto 1431 60.8 45.1 | raw >>If you have Ira's Dagger: kill |cRXP_ENEMY_Young Black Ravagers|r and |cRXP_ENEMY_Black Ravagers|r | raw .complete 96137,1 | raw .complete 96137,2 | raw .isOnQuest 96137",
    "goto 1431 72.4 47.4 | raw .turnin 96137 >> Turn in Ira's Dagger | raw .target Sirra Von'Indi | raw .isQuestComplete 96137",
]
DW_MERRICK = [
    "goto 1431 36.0 63.0 | raw >>Kill the |cRXP_ENEMY_Lost Watcher|r, a ghost by the road. He drops |cRXP_LOOT_Merrick's Bow|r: use it to start the quest. Not around? Skip this step | raw .accept 96138 >> Accept Merrick's Bow",
    "goto 1431 35.5 74.5 | raw >>Kill |cRXP_ENEMY_Splinter Fist Warriors|r and |cRXP_ENEMY_Splinter Fist Taskmasters|r | raw .complete 96138,1 | raw .complete 96138,2 | raw .isOnQuest 96138",
]
DW_MERRICK_TURNIN = [
    "goto 1431 72.4 47.4 | raw .turnin 96138 >> Turn in Merrick's Bow | raw .target Sirra Von'Indi | raw .isQuestComplete 96138",
    "goto 1431 72.4 47.4 | raw .turnin 96137 >> Turn in Ira's Dagger | raw .target Sirra Von'Indi | raw .isQuestComplete 96137",
]

# Darkshore (2026-10-01): Forever's two quests at the Grove of the Ancients.
#  - Swelling Forces (1550, solo): Arbal, next to Onu, wants 12 Stormscale Myrmidons, 8 Sorceresses and
#    6 Warriors, the naga at the Ruins of Mathystra (~58,20), where 16-19 already loots the Mathystra
#    Relics (the naga also stand in for the grind step before it). Handed in with the relics, in
#    19-21 (Hunters) or 20-21.
#  - Baron Marinous (2050, group): the naga drop Mathystral Amulet Fragments (20, no quest needed);
#    they make an amulet that summons Baron Marinous (elite elemental, 2.4k health, 100+ Frostbolts) at
#    the Fathom Stone at the bottom of the pool at 59.1,22.3. His Clouded Water Globe starts the quest,
#    handed to Onu. Solo only by line-of-sighting him behind the pillars (Wowhead comments): group.
#  - Left out: Gaffer Jacks and Electropellers, One Shot. One Kill. (level 12-15, RestedXP skips them);
#    Supplies to Auberdine (Feero Ironhand's escort, level 24).
# Positions: Wowhead's Forever pages (Arbal, the naga, Baron Marinous, the Fathom Stone).
DS_ARBAL = ["goto 1439 43.6 76.4 | raw .accept 98013 >> Accept Swelling Forces | raw .target Arbal"]
DS_NAGA = [
    "goto 1439 58.0 20.5 | raw >>Kill |cRXP_ENEMY_Stormscale Myrmidons|r, |cRXP_ENEMY_Sorceresses|r and |cRXP_ENEMY_Warriors|r around the Ruins of Mathystra | raw .complete 98013,1 | raw .complete 98013,2 | raw .complete 98013,3 | raw .mob Stormscale Myrmidon | raw .mob Stormscale Sorceress | raw .mob Stormscale Warrior | raw .isOnQuest 98013",
    "group: raw #completewith next | goto 1439 58.0 20.5 | raw >>Keep killing the naga until you have 20 |cRXP_LOOT_Mathystral Amulet Fragments|r, then combine them into the amulet | raw .collect 279276,20 | raw .mob Stormscale Myrmidon | raw .mob Stormscale Sorceress | raw .mob Stormscale Warrior | raw .isNotOnQuest 98028",
    "group: goto 1439 59.1 22.3 | raw >>Dive to the |cRXP_PICK_Fathom Stone|r at the bottom of the pool and use the amulet there. Kill |cRXP_ENEMY_Baron Marinous|r (elite, Frostbolts: fight him around the pillars) and loot his |cRXP_LOOT_Clouded Water Globe|r | raw .collect 279275,1 | raw .mob Baron Marinous | raw .isNotOnQuest 98028",
    "group: raw .accept 98028 >> Accept Baron Marinous | raw .use 279275 | raw >>Use the |cRXP_LOOT_Clouded Water Globe|r",
]
DS_ONU = [
    "goto 1439 43.6 76.4 | raw .turnin 98013 >> Turn in Swelling Forces | raw .target Arbal | raw .isQuestComplete 98013",
    "group: goto 1439 43.555 76.293 | raw .turnin 98028 >> Turn in Baron Marinous | raw .target Onu | raw .isOnQuest 98028",
]

# Ruins of Lordaeron (group, 2026-10-01): Forever's dungeon in the ruins above the Undercity, Tirisfal
# (Horde land), for levels 15-20. At the start of 16-19 Darkshore (about 16, hearth in Auberdine):
# its quests are above you then and pay in full (our server scan, 30 Sep): Remember That I Love You,
# Crest of Lordaeron and Bloodied Insignia 9750 each (quest level 22), Abominable Creatures 6200 (21);
# after the 2 Oct build's cut about 6200 and 3900, some 22k in all, over a level at 16, plus the mobs,
# which still give XP at 16 (at 27, where it first went, they wouldn't).
#  - The way: the Menethil boat from Auberdine carries on to Southshore (stay on board); north past
#    Hillsbrad Fields and round Dalaran, then swim north up Lordamere Lake into Tirisfal. Afterwards
#    the hearth back to Auberdine, and the route carries on.
#  - Captain Truman stands on the left as you zone in (Abominable Creatures: the Baron's head). The
#    other three start from what you loot inside: the first Bloodied Insignia from the undead (ten in
#    all), the Crest of Lordaeron (one of four places: the top of the tower by the spider courtyard or
#    by The Abandoned, behind the banshee's door in the spider courtyard, or the floor of the stair room
#    across from Bjork's courtyard) and the Blood-Stained Letter by Edward Heartweaver's body near
#    Rath'mael. Those three are handed in in Stormwind, where the route's boat from Auberdine lands.
#  - Left out: Remember That I Love You's second part (180 XP, Avette Fellwood in Darkshire).
# Positions: Wowhead's Forever pages and comments, warcrafttavern.com, gamer-guides.com; Stormwind's
# NPCs from our NPC data (Forever's Stormwind map; Lady Dena Kennedy converted from Wowhead's Classic one).
RL_RUN = [
    "group: goto 1439 32.4 43.7 | raw .zone Hillsbrad Foothills >> Ruins of Lordaeron with your group (over a level of quest XP at 16): take the Menethil Harbor boat from Auberdine's dock and stay on board past Menethil until Southshore",
    "group: raw .zone Tirisfal Glades >> From Southshore follow the road north past Hillsbrad Fields and round Dalaran, then swim north up Lordamere Lake into Tirisfal Glades. Horde land: keep off the roads",
    "group: goto 1420 61.9 70.5 : Enter the Ruins of Lordaeron: the ruined city above the Undercity, on the east side of the courtyard on the way to the elevators, up the stairs behind an iron portcullis",
    "group: raw .accept 95250 >> Accept Abominable Creatures | raw .target Captain Truman | raw >>|cRXP_FRIENDLY_Captain Truman|r is on your left as you zone in",
    "group: raw >>Clear the Ruins (the bosses in any order). Kill |cRXP_ENEMY_The Baron|r for his head. Loot what starts the other three (click each in your bags): the first |cRXP_LOOT_Bloodied Insignia|r from the undead, then nine more; the |cRXP_LOOT_Crest of Lordaeron|r (top of the tower by the spider courtyard or by The Abandoned, behind the banshee's door in the spider courtyard, or the floor of the stair room across from Bjork's courtyard); the |cRXP_LOOT_Blood-Stained Letter|r by Edward Heartweaver's body near |cRXP_ENEMY_Rath'mael|r | raw .complete 95250,1 | raw .accept 95195 >> Accept Bloodied Insignia | raw .complete 95195,1 | raw .accept 95189 >> Accept Crest of Lordaeron | raw .accept 92415 >> Accept Remember That I Love You",
    "group: raw .turnin 95250 >> Turn in Abominable Creatures | raw .target Captain Truman | raw .isQuestComplete 95250",
    "group: raw .hs >> Hearth back to Auberdine | raw .zoneskip Darkshore",
]
RL_TURNINS = [
    "group: goto 1453 68.4 29.1 | raw .turnin 95189 >> Turn in Crest of Lordaeron | raw .target Lady Dena Kennedy | raw >>In Stormwind Keep's Royal Gallery | raw .isOnQuest 95189",
    "group: goto 1453 56.3 54.0 | raw .turnin 92415 >> Turn in Remember That I Love You | raw .target Orphan Matron Nightingale | raw >>In front of the Cathedral of Light | raw .isOnQuest 92415",
    "group: goto 1453 69.2 82.7 | raw .turnin 95195 >> Turn in Bloodied Insignia | raw .target General Marcus Jonathan | raw >>By the city gate | raw .isQuestComplete 95195",
]

# Wetlands, solo (2026-10-01): Forever's quests around Menethil Harbor, in the free route's two visits.
#  - 23-24: Spoils of War (1750: Khaz Modan Timber and Iron, piles in and around Menethil), Alchemical
#    Hazards (1750: an Unruptured Stalker Gland from the stalkers at Thelgen Rock, near the route's
#    excavation quests), Return the Statuette (200, Karl Boran to Captain Stoutfist, inside Menethil),
#    and Unrequited Love (170, Archaeologist Hollee in Auberdine to Tarrel Rockweaver, on the boat over).
#  - 27-30: Howin Kindfeather (49.4,41.8, by the route's path through the middle of the zone):
#    Razormaw Needling and Trying Times (2350 each: Razormaw Incisors and Perfect Razormaw Eggs, the
#    razormaws at ~60,28 on the way north to Dun Modr). A Lack of Virtue (Tom in Southshore to Bart
#    Tidewater in Menethil) was here too: quest level 21, it pays 44 XP at the 29-30 you are by then.
#  - Left out: Crocs of the Sky, Forced Disarmament and the Crimson Crate (no known giver yet); A Dark
#    Threat Looms and The Algaz Gauntlet (level 18-21, grey by the time the route passes).
# Positions: Wowhead's Forever pages (NPCs, the timber and iron piles, the stalkers, the razormaws).
WL_MENETHIL = [
    "goto 1437 8.5 58.5 | raw .accept 98189 >> Accept Return the Statuette | raw .target Karl Boran",
    "goto 1437 9.8 57.4 | raw .turnin 98189 >> Turn in Return the Statuette | raw .target Captain Stoutfist",
    "goto 1437 10.0 56.8 | raw .accept 98197 >> Accept Spoils of War | raw .target Valstag Ironjaw",
    "goto 1437 11.7 58.5 | raw .accept 98282 >> Accept Alchemical Hazards | raw .target Caitlin Grassman",
    "goto 1437 8.0 54.0 | raw >>Pick up |cRXP_PICK_Khaz Modan Timber|r and |cRXP_PICK_Khaz Modan Iron|r from the piles in and around Menethil Harbor | raw .complete 98197,1 | raw .complete 98197,2",
]
WL_TARREL = ["goto 1437 11.4 52.2 | raw .turnin 98461 >> Turn in Unrequited Love | raw .target Tarrel Rockweaver | raw .isOnQuest 98461"]
WL_THELGEN = ["goto 1437 49.5 61.5 | raw >>Thelgen Rock: kill |cRXP_ENEMY_Leech Stalkers|r and |cRXP_ENEMY_Cave Stalkers|r until one drops an |cRXP_LOOT_Unruptured Stalker Gland|r | raw .complete 98282,1 | raw .mob Leech Stalker | raw .mob Cave Stalker"]
WL_TURNINS = [
    "goto 1437 10.0 56.8 | raw .turnin 98197 >> Turn in Spoils of War | raw .target Valstag Ironjaw | raw .isQuestComplete 98197",
    "goto 1437 11.7 58.5 | raw .turnin 98282 >> Turn in Alchemical Hazards | raw .target Caitlin Grassman | raw .isQuestComplete 98282",
]
WL_HOWIN = ["goto 1437 49.4 41.8 | raw .accept 98245 >> Accept Razormaw Needling | raw .accept 98246 >> Accept Trying Times | raw .target Howin Kindfeather"]
WL_RAZORMAWS = [
    "goto 1437 59.9 28.0 | raw >>Kill |cRXP_ENEMY_Highland Razormaws|r and |cRXP_ENEMY_Elder Razormaws|r for |cRXP_LOOT_Razormaw Incisors|r, and pick up |cRXP_PICK_Perfect Razormaw Eggs|r around them | raw .complete 98245,1 | raw .complete 98246,1 | raw .mob Highland Razormaw | raw .mob Elder Razormaw | raw .isOnQuest 98245",
    "goto 1437 49.4 41.8 | raw .turnin 98245 >> Turn in Razormaw Needling | raw .target Howin Kindfeather | raw .isQuestComplete 98245",
    "goto 1437 49.4 41.8 | raw .turnin 98246 >> Turn in Trying Times | raw .target Howin Kindfeather | raw .isQuestComplete 98246",
]

# "6-11 Elwynn (Dwarf/Gnome)" (the Elwynn-at-6 option): Camping 101 Mining and Blacksmithing are taken
# in Kharanos and handed in there, so mine Elwynn's copper on the way (the Fargodeep and Jasperlode
# mines), and when the route comes back through Steelgrill's Depot at 10-11 (A Visitor to Dun Morogh):
# Mining to Yarr downstairs, then the forge and Blacksmithing at Tognus, 250 yards west in Kharanos.
EW_MINE = [
    "raw #sticky | raw >>Mine every |cRXP_PICK_Copper Vein|r you pass, for Camping 101: Mining (the Fargodeep and Jasperlode mines have plenty). Keep the ore and the Rough Stones: Blacksmithing 20 takes them | raw .skill mining,20 | raw .isOnQuest 96046 << Warrior/Paladin/Rogue",
]
EW_CAMPING = [
    "raw .goto 1426/0,-660.91,-5528.93 | raw >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Yarr Hammerstone|r inside downstairs | raw .turnin 96046 >>Turn in Camping 101: Mining | raw .target Yarr Hammerstone | raw .isQuestComplete 96046 << Warrior/Paladin/Rogue",
    "raw .goto 1426,45.344,51.936 | raw >>At the forge and anvil by |cRXP_FRIENDLY_Tognus Flintfire|r in Kharanos: smelt all your |cRXP_LOOT_Copper Ore|r | raw >>Then make |cRXP_PICK_Copper Rods|r to Blacksmithing 10, |cRXP_PICK_Rough Weightstones|r to 15, |cRXP_PICK_Copper Bracers|r to 20 | raw >>|cRXP_WARN_Not enough ore or stones? Skip this step and the next|r | raw .skill blacksmithing,20 | raw .isOnQuest 96044 << Warrior/Paladin/Rogue",
    "raw .goto 1426,45.344,51.936 | raw >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tognus Flintfire|r | raw .turnin 96044 >>Turn in Camping 101: Blacksmithing | raw .target Tognus Flintfire | raw .isQuestComplete 96044 << Warrior/Paladin/Rogue",
]

BLOCKS = {
    "6-11 Elwynn (Dwarf/Gnome)": [
        (r"#label Goldshire", "after", EW_MINE),
        (r"\.accept 96408 >>Accept A Visitor to Dun Morogh", "after", EW_CAMPING),
    ],
    # Wetlands, solo (above); 21-23 Ashenvale and 23-24 Wetlands are further down, with their dungeon parts
    "27-30 Wetlands/Hillsbrad": [
        (r"\.turnin 465 >> Turn in Nek'rosh's Gambit", "after", WL_HOWIN),
        (r"\.turnin 275 >> Turn in Blisters on The Land", "after", WL_RAZORMAWS),
    ],
    # Redridge and Duskwood, solo (above)
    "28-30 Duskwood": [
        (r"\.complete 134,1", "before", DW_MERRICK),
        (r"\.turnin 181 >> Turn in Look To The Stars", "after", DW_MERRICK_TURNIN),
    ],
    # Westfall, solo (above)
    "13-15 Westfall": [
        (r"#label SalmaS", "after", WF_HARVEST),
        (r"#label SaldeanVendor", "after", WF_HARVEST_TURNIN),
        (r"\.turnin 12 >> Turn in The People's Militia", "after", ["accept 13"]),
        (r"\.turnin 92742 >>Turn in Testing the Wells", "after", WF_END),
        (r"\.hs >> Hearth to Stormwind", "after", ["turnin 92748 | raw .isOnQuest 92748"]),
    ],
    # Darkshore (DS_* above)
    "16-19 Darkshore": [
        # Ruins of Lordaeron, group (RL_* above): out from Auberdine first, the hand-ins where the
        # boat to Stormwind lands
        (r"\.accept 4740 >> Accept WANTED: Murkdeep!", "before", RL_RUN),
        (r"#label MenethilRRBoat", "after", RL_TURNINS),
        (r"\.turnin 948 >> Turn in Onu", "after", DS_ARBAL),
        (r"\.complete 951,1", "after", DS_NAGA),
    ],
    "20-21 Darkshore/Ashenvale": [
        (r"#xprate <1.5[\s\S]*\.turnin 951 >> Turn in Mathystra Relics", "after", DS_ONU),
    ],
    # the Hunters' route ends in Darnassus: the BFD quests there
    "19-21 Darkshore/Ashenvale": [
        (r"\.turnin 951 >> Turn in Mathystra Relics[\s\S]*\.isOnQuest 951", "after", DS_ONU),
        (r"\.turnin 741\b", "before", ["group: accept 1198", "group: accept 1199"]),
    ],
    "21-23 Ashenvale": [
        (r"\.turnin 967\b", "before", BFD_PICKUP),
        (r"\.turnin 1009\b", "after", BFD_RUN),
        (r"Exit Darnassus through the purple portal", "before", BFD_TURNIN),
        (r"Fly back to Auberdine", "after", ["group: goto 1438 58.399 94.016 | fly Auberdine | raw .isNotOnQuest 942"]),
        # Wetlands, solo: Hollee's note for Tarrel Rockweaver, taken in Auberdine before the boat
        (r"\.turnin 731 >> Turn in The Absent Minded Prospector", "after",
         ["goto 1439 37.4 41.8 | raw .accept 98461 >> Accept Unrequited Love | raw .target Archaeologist Hollee"]),
    ],
    # everyone passes Ironforge on the way to the Wetlands
    "23-24 Wetlands": [
        (r"\.train 197\b", "after", ["group: turnin 971 | raw .isOnQuest 971"]),
        # Wetlands, solo (WL_*)
        (r"\.accept 279 >> Accept Claws from the Deep", "after", WL_MENETHIL),
        (r"\.accept 305 >> Accept In Search of The Excavation Team", "after", WL_TARREL),
        (r"\.turnin 296 >> Turn in Ormer's Revenge", "after", WL_THELGEN),
        (r"\.turnin 484 >> Turn in Young Crocolisk Skins", "after", WL_TURNINS),
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
        (r"\.accept 56 >> Accept The Night Watch", "after", DW_VALOR),
        (r"\.turnin 163 >> Turn in Raven Hill", "after", DW_TOME),
        (r"\.turnin 56 >> Turn in The Night Watch", "after", DW_VALOR_TURNIN),
        (r"\.accept 115 >> Accept Shadow Magic", "after", RR_MILL),
        (r"\.complete 128,1", "after", RR_KEESHAN),
        (r"\.turnin 115 >> Turn in Shadow Magic", "after", RR_TURNINS),
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
