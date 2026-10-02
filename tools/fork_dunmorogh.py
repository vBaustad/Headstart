"""Build Guides/DunMorogh.lua: RestedXP's "5-11 Dun Morogh" (Forever, Dwarf/Gnome) with our changes.

    python tools/fork_dunmorogh.py      (reads S:/forever-data/external/rxp; rerun after updating that clone)

Changes, each asserted so an upstream edit that moves them fails loudly instead of silently:
  * our group and name, #next pointing back into RestedXP's own guides;
  * Blacksmithing at Tognus and Tools for Steelgrill from Tharek before the campfire (the user's order);
  * Loslor also sells the Apprentice's Mining Pack and the Blacksmith Hammer we need;
  * Camping 101 for Mining and Blacksmithing taken with the Cooking one (melee classes), with a mining
    reminder until skill 20, a smelting and crafting stop at Tognus, and both hand-ins;
  * Cooking (270 XP for 1s) before class training, and again after Stocking Jetsteam's money;
  * the Mining Pack only if money is left; three second trips folded into the visit before.
"""
import os
import re

from clean_guide import clean, no_sick_deathskips
from share_split import mark

SRC = "S:/forever-data/external/rxp/Guides/Forever/Alliance-1-14_DwarfGnome.lua"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Guides", "DunMorogh.lua")
RXP_GROUP = "RestedXP Forever Guide (A)"

src = open(SRC, encoding="utf-8").read()
blocks = re.findall(r"RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)", src, re.S)
guide = next(b for b in blocks if "\n#name 5-11 Dun Morogh\n" in b)


def sub(old, new):
    global guide
    assert guide.count(old) == 1, f"not exactly once upstream: {old[:70]!r}"
    guide = guide.replace(old, new)


sub("#version 1\n", "#version 1\n")
sub("#group RestedXP Forever Guide (A)\n", "#group Headstart Launch (A)\n")
sub("#subgroup Speedrun Guide 1-20\n", "#subgroup Launch day\n")
sub("#name 5-11 Dun Morogh\n", "#name 5-11 Dun Morogh (Launch)\n")
sub("#defaultfor Dwarf/Gnome\n", "")
nxt = re.search(r"#next (.*)\n", guide).group(1)
# the next routes: our copies where tools/fork_rxp.py makes one (same group, no prefix), else RestedXP's
OURS = {"11-12 Elwynn (Dwarf/Gnome)", "12-14 Loch Modan (Dwarf/Gnome)", "11-13 Loch Modan (Hunter)"}
assert nxt.split(";")[0] == "11-12 Elwynn (Dwarf/Gnome)", nxt
# Solo at launch: Elwynn is the Humans' crowd, and Loch Modan has more than enough quests (blocks.py
# LM_*): straight on to Loch Modan. Warlocks still go via Elwynn, for their Voidwalker (The Binding).
nxt_all = [n if n in OURS else RXP_GROUP + "\\" + n for n in nxt.split(";")]
warlock = [n for n in nxt_all if "Elwynn" in n or "Voidwalker" in n]
others = [n for n in nxt_all if n not in warlock]
sub(f"#next {nxt}\n", "#next " + ";".join(warlock) + " << Warlock\n#next " + ";".join(others) + " << !Warlock\n")

# Blacksmithing and Tools for Steelgrill first, then the campfire: find the step with The Adventurer
# Flintfire's Shipment is taken at the same visit (a logged run took it there anyway; RestedXP had it
# as a separate trip later, which now skips itself).
FIRST = """step
    .goto 1426,45.344,51.936
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tognus Flintfire|r
    .train 2018 >> Train |T136241:0|t[Blacksmithing] << Warrior/Paladin/Rogue
    .accept 98321 >>Accept Flintfire's Shipment
    .target Tognus Flintfire
step
    .goto 1426/0,-464.45,-5573.78
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tharek Blackstone|r
    .accept 400 >> Accept Tools for Steelgrill
    .target Tharek Blackstone
"""
i = guide.index("    .turnin 96628 >>Turn in The Adventurer")
i = guide.rindex("\nstep\n", 0, i) + 1
guide = guide[:i] + FIRST + guide[i:]

sub("""    >>|cRXP_BUY_Buy a|r |T134708:0|t[Mining Pick]>>|cRXP_BUY_. If you can't afford it, skip this step|r
    .collect 2901,1 --Mining Pick (1)
""", """    >>|cRXP_BUY_Buy a|r |T134708:0|t[Mining Pick]|cRXP_BUY_, an|r |T133635:0|t[Apprentice's Mining Pack] |cRXP_BUY_and a|r |T133057:0|t[Blacksmith Hammer]
    .collect 2901,1 --Mining Pick (1)
    .collect 277115,1 --Apprentice's Mining Pack (1)
    .collect 5956,1 --Blacksmith Hammer (1)
""")

# Eric also offers Camping 101 for Mining and Blacksmithing (IDs from a logged run, 2026-09-30): 270 XP each
sub("""    .accept 96629 >>Accept Camping 101: Cooking
""", """    .accept 96629 >>Accept Camping 101: Cooking
    .accept 96046 >>Accept Camping 101: Mining
    .accept 96044 >>Accept Camping 101: Blacksmithing
""")

# Senir stands next to Eric: hand in Senir's Observations before sitting at the campfire, not after
# (talking to him would stand you up mid-minute; a logged run did it first anyway).
SENIR = """step
    #label SenirEnd
    .goto 1426/0,-501.400,-5643.900
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Senir Whitebeard::1252|r
    .target Senir Whitebeard::1252
    .turnin 420 >>Turn in Senir's Observations
    .accept 98322 >>Accept Secure the Mountain
"""
sub(SENIR, "")
i = guide.index("""    >>|cRXP_WARN_Type "/sit" in chat""")
i = guide.rindex("\nstep\n", 0, i) + 1
guide = guide[:i] + SENIR + guide[i:]

# The Reports comes from Senir the moment Frostmane Hold is handed in: take it there, not on a
# second visit later. That later step has to go, not just skip itself: it followed the death skip
# after Brewnall ("#completewith next"), so being done already took the death skip with it and
# the route said to walk back (a logged run, 2026-10-01).
sub("""    .turnin 287 >>Turn in Frostmane Hold
""", """    .turnin 287 >>Turn in Frostmane Hold
    .accept 291 >>Accept The Reports
""")
sub("""step
    .goto 1426/0,-501.400,-5643.900
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Senir Whitebeard::1252|r
    .target Senir Whitebeard::1252
    .accept 291 >>Accept The Reports
""", "")

# --- Mining and Blacksmithing to 20 for Camping 101 (270 XP each, and the Sharpening Wheel) ---------
# Only the classes that train them here take the two quests (the others would carry dead quests).
sub("""    .accept 96046 >>Accept Camping 101: Mining
    .accept 96044 >>Accept Camping 101: Blacksmithing
""", """    .accept 96046 >>Accept Camping 101: Mining << Warrior/Paladin/Rogue
    .accept 96044 >>Accept Camping 101: Blacksmithing << Warrior/Paladin/Rogue
""")

# Mine on the way: 21 copper veins lie within 60 yards of a logged run's path, 14 of them between
# Gretchen, the Grizzled Den and the bears south of Kharanos (research/leveling/veins.py). Each vein
# is +1 Mining and 2-3 ore; smelting the ore is +1 a bar (up to 25), so ~6 veins is Mining 20, and
# the bars and stones are what Blacksmithing needs. Done when Mining reaches 20.
MINE = """step << Warrior/Paladin/Rogue
    #sticky
    #label MineCopper
    >>Mine every |cRXP_PICK_Copper Vein|r you pass: most are around the Grizzled Den and south of Kharanos. Keep the ore and the Rough Stones
    .skill mining,20
"""
i = guide.index("    #label RumbleshotAmmo")
i = guide.rindex("\nstep", 0, i) + 1
guide = guide[:i] + MINE + guide[i:]

# Craft at Tognus's forge and anvil when handing in Flintfire's Shipment: smelting needs a forge,
# Copper Rods and Bracers an anvil (Rough Weightstones need neither: make those at the campfire).
# Trivial ranges (skilllineability): Copper Rod orange to 10, Rough Weightstone to 15, Copper
# Bracers to 20. Then Camping 101: Blacksmithing to Tognus himself.
CRAFT = """step << Warrior/Paladin/Rogue
    .goto 1426,45.344,51.936
    >>At the forge and anvil by |cRXP_FRIENDLY_Tognus Flintfire|r: smelt all your |cRXP_LOOT_Copper Ore|r
    >>Then make |cRXP_PICK_Copper Rods|r to Blacksmithing 10, |cRXP_PICK_Rough Weightstones|r to 15, |cRXP_PICK_Copper Bracers|r to 20
    >>|cRXP_WARN_Out of ore or stones? Skip this step and finish at the next forge|r
    .skill blacksmithing,20
    .isOnQuest 96044
step << Warrior/Paladin/Rogue
    .goto 1426,45.344,51.936
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tognus Flintfire|r
    .turnin 96044 >>Turn in Camping 101: Blacksmithing
    .target Tognus Flintfire
    .isQuestComplete 96044
"""
i = guide.index("    .turnin 98321 >>Turn in Flintfire's Shipment")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + CRAFT.replace("finish at the next forge", "it comes back after Frostmane Hold") + guide[i:]
# A logged run (2026-09-30) had only 5 ore at that first stop and 21 ore and 16 stones when back in
# Kharanos for Frostmane Hold, next to the same forge: the second chance goes there.
i = guide.index("    .turnin 287 >>Turn in Frostmane Hold")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + CRAFT.replace("Skip this step and finish at the next forge", "Skip this step") + guide[i:]

# No push for the Heavy Copper Maul here any more: the elite quest's Coldridge Hammer (8.3 DPS, at
# about 10) covers 10-11, and the extra mining and the forge grind to Blacksmithing 40 weren't worth
# it for +30% damage after that (the user's call, 2026-10-02). Ironforge still makes the Maul for
# anyone who reaches 40 anyway (blocks.py LM_MAUL).

# The blacksmith visit RestedXP makes after the campfire: the weapons at Grawn Thromwyn (Gladius 5s36,
# Large Axe 4s60, Stiletto 4s, Wooden Mallet 6s31), then Blacksmithing and Flintfire's Shipment at
# Tognus. Those two Headstart already does at the first visit (FIRST, above): they came up done, and
# looked skipped. And no logged run had the money for a weapon there (each step needs its price), so
# every run skipped those too (the user, 2026-10-01). The Tognus steps go; the weapons stay, and come
# again at the Flintfire's Shipment hand-in, next to Grawn, when Stocking Jetsteam has paid (~12s in a
# logged run).
start = guide.index("step << Paladin/Warrior/Rogue\n    #optional\n    #completewith Blacksmithing1\n")
weapons_at = guide.index("step << Gnome Warrior\n", start)
bs = guide.index("step << Warrior/Rogue/Paladin\n    #label Blacksmithing1\n")
WEAPONS = guide[weapons_at:bs]
assert "Wooden Mallet" in WEAPONS and "Gladius" in WEAPONS and "#label" not in WEAPONS
bs_end = guide.index("\nstep", bs + 1) + 1
guide = guide[:start] + WEAPONS + guide[bs_end:]
dup = guide.index("    .target Tognus Flintfire::1241\n    .accept 98321 >>Accept Flintfire's Shipment\n")
dup_start = guide.rindex("\nstep\n", 0, dup) + 1
assert guide[dup_start:dup].count("\n") == 3, guide[dup_start:dup]
guide = guide[:dup_start] + guide[guide.index("\nstep", dup) + 1:]
i = guide.index("    .turnin 98321 >>Turn in Flintfire's Shipment")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + WEAPONS + guide[i:]

# Camping 101: Mining goes to Yarr Hammerstone, downstairs at Steelgrill's Depot, next to Bellowfiz.
sub("""    .turnin 320 >> Turn in Return to Bellowfiz
    .target Pilot Bellowfiz
""", """    .turnin 320 >> Turn in Return to Bellowfiz
    .target Pilot Bellowfiz
step << Warrior/Paladin/Rogue
    .goto 1426/0,-660.91,-5528.93
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Yarr Hammerstone|r inside downstairs
    .turnin 96046 >>Turn in Camping 101: Mining
    .target Yarr Hammerstone
    .isQuestComplete 96046
""")

# Frostmane Hold ends with a death skip from the cave to Kharanos, so A Favor for Evershine has to be
# handed in at Brewnall first; logged runs went into the cave first and walked back. Say why at the
# hand-in.
sub("""    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rejold Barleybrew|r
    .turnin 319 >> Turn in A Favor for Evershine
""", """    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rejold Barleybrew|r
    >>|cRXP_WARN_Before Frostmane Hold: you die in the cave at the end to get back to Kharanos, so hand this in first|r
    .turnin 319 >> Turn in A Favor for Evershine
""")
# RestedXP's climb up the side of the entrance to jump down into the Hold saves next to nothing
# (the user, in game): walk in through the front.
sub("""step
    #optional
    .goto 1426,24.975,50.473,20,0
    .goto 1426,24.682,50.836,20 >> Run up the side of the cave entrance. Jump down into Frostmane Hold
    .isOnQuest 287
""", "")

# Never Saddle on Quality (95212, new in Forever: 625 XP, needs level 7): Rudra Amberstill, 6 Pristine
# Leopard Pelts from Elder Snow Leopards east of the ranch (70-82, 50-62), where the route already
# spends a while (Gol'Bolar Quarry, Farsen's spies, the Stolen Blasting Powder). Taken with Protecting
# the Herd (both the Hunters' early visit and everyone else's), handed in after the last Blasting
# Powder, a short detour west before Loch Modan. Wowhead's Forever page.
old = """    .accept 314 >> Accept Protecting the Herd
    .target Rudra Amberstill
"""
assert guide.count(old) == 2, "Rudra's two Protecting the Herd steps"
guide = guide.replace(old, """    .accept 314 >> Accept Protecting the Herd
    .accept 95212 >> Accept Never Saddle on Quality
    .target Rudra Amberstill
""")
PELTS = """step
    #sticky
    #label LeopardPelts
    >>Kill |cRXP_ENEMY_Elder Snow Leopards|r around the quarry and east of it. Loot them for |cRXP_LOOT_Pristine Leopard Pelts|r
    .complete 95212,1 --Pristine Leopard Pelt (6)
    .mob Elder Snow Leopard
    .isOnQuest 95212
"""
i = guide.index(">>Kill |cRXP_ENEMY_Rockjaw Skullthumpers|r in or outside the mine")
i = guide.rindex("\nstep", 0, i) + 1
guide = guide[:i] + PELTS + guide[i:]
RUDRA = """step
    .goto 1426/0,-1304.71,-5513.86
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rudra Amberstill|r at the ranch
    .turnin 95212 >> Turn in Never Saddle on Quality
    .target Rudra Amberstill
    .isQuestComplete 95212
"""
i = guide.index("    .turnin 95214 >> Turn in Stolen Blasting Powder")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + RUDRA + guide[i:]

# Vagash is a level 11 elite (about 666 health). A logged level-9 Paladin killed a normal mob in ~10 s:
# ~40 s of damage for Vagash, too long against an elite two levels up. Level 10 first (a Paladin gets
# Lay on Hands; every class a new rank or two), then kite him to the guard. Hunters meet him with
# their own steps and pet, earlier: left as they are.
LEVEL_10 = """step << !Hunter
    .xp 10 >> Grind to level 10 before Vagash, a level 11 elite. Stay off his hill north of the ranch while you do
"""
i = guide.rindex(".complete 314,1")          # the second one: everyone but Hunters
i = guide.rindex("\nstep", 0, i) + 1
assert guide[i:].startswith("step << !Hunter"), guide[i:i + 40]
guide = guide[:i] + LEVEL_10 + guide[i:]

# Frosthowl (98326, new in Forever: 775 XP, 3s, needs level 5): Gretta Ganter in Brewnall, a named
# wendigo at the back of the Grizzled Den. Taken on the first Brewnall visit (the first den visit
# comes before Brewnall, at level 6), killed on the way back west (the route climbs Shimmer Ridge
# just above the den), handed in with The Perfect Stout. Wowhead's Forever page, a logged run.
FROSTHOWL_ACCEPT = """step
    .goto 1426,31.4,44.6
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Gretta Ganter|r
    .accept 98326 >> Accept Frosthowl
    .target Gretta Ganter
"""
# After Shimmer Ridge, not before: Frosthowl is at the back of the Grizzled Den, right under the ridge,
# and the cave's way out faces south. Before the ridge (as it was) meant out of the cave and back north
# up the slope (a logged run, 2026-10-02: ~3.5 min); after it, the way out leads on to MacGrann's
# meat locker and Tundra, south-west.
FROSTHOWL_KILL = """step
    .goto 1426,42.3,54.0,20,0
    .goto 1426,41.9,49.5,20,0
    .goto 1426,39.5,48.8
    >>Down from the ridge to the |cRXP_PICK_Grizzled Den|r (its entrance is south, about 42,54) and in: kill |cRXP_ENEMY_Frosthowl|r at the back. Loot him for the |cRXP_LOOT_Sack of Fish|r
    .complete 98326,1 --Sack of Fish (1)
    .mob Frosthowl
    .isOnQuest 98326
"""
# Gretta is a vendor too (Fisherman Supplies): sell there first, the bags are full by now.
FROSTHOWL_TURNIN = """step
    .goto 1426,31.4,44.6
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Gretta Ganter|r
    >>|cRXP_BUY_She's a vendor: sell your junk to her first|r (keep what the route still needs: its tooltip says so)
    .turnin 98326 >> Turn in Frosthowl
    .target Gretta Ganter
    .isQuestComplete 98326
"""
i = guide.index("    #label BrewnallVillage")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + FROSTHOWL_ACCEPT + guide[i:]
i = guide.index("    #label ShimmerweedCollect")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + FROSTHOWL_KILL + guide[i:]
i = guide.index("    .turnin 311 >> Turn in Return to Marleth")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + FROSTHOWL_TURNIN + guide[i:]

# --- Money ----------------------------------------------------------------------------------------
# Cooking is 270 XP for 1 silver (Camping 101: Cooking): the best copper spent in Kharanos. A logged
# run skipped it for lack of money after class training, so it comes first now (same building), and
# a second chance follows the Flintfire hand-in, after Stocking Jetsteam's 2s 50c.
COOK = """step
    .goto 1426/0,-545.800,-5594.500
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Gremlock Pilsnor::1699|r
    >>|cRXP_WARN_Skip this step if you don't have 1 silver, or if you wish to do it later|r
    .target Gremlock Pilsnor::1699
    .train 2550 >> Train |T133971:0|t[Cooking]
    .turnin 96629 >>Turn in Camping 101: Cooking
    .money <0.0100
"""
sub(COOK, "")
COOK_FIRST = COOK.replace("|cRXP_WARN_Skip this step if you don't have 1 silver, or if you wish to do it later|r",
                          "|cRXP_WARN_270 XP for 1 silver: train this before your class spells. Short of 1s? Skip it: it comes back later|r")
i = guide.index("    .turnin 2160,1 >> Turn in Supplies to Tannok")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + COOK_FIRST + guide[i:]
COOK_AGAIN = """step
    .goto 1426/0,-545.800,-5594.500
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Gremlock Pilsnor::1699|r in the Thunderbrew Distillery
    .train 2550 >> Train |T133971:0|t[Cooking]
    .turnin 96629 >>Turn in Camping 101: Cooking
    .target Gremlock Pilsnor::1699
"""
i = guide.index("    .turnin 96044 >>Turn in Camping 101: Blacksmithing")
i = guide.index("\nstep", i) + 1
guide = guide[:i] + COOK_AGAIN + guide[i:]

# Father Gavin's chain (new in Forever, 4 x 700 XP at level 8): he is the Dawn in the Mountains hand-in,
# just before Vagash, so the chain is the XP for level 10 before him. Finding Warmth first (the other
# three open after it), then Rime's Wrath (10 Minor Ice Elementals, around him), Rime's Wrath (Avala,
# just north of him) and Treacherous Cold (three rifles by fallen mountaineers). Positions: Wowhead's
# Forever pages (Gavin, the elementals, Avala) and their comments (the rifles' map, 52/44, 53/59,
# 60/50; the firewood: white trunks on the ground by the trees, some give 2, sparse). In the order
# west, south, then east toward the ranch, the Sunhammer rifle is on the way to Rudra.
# Two quests are called Rime's Wrath: the ice elementals (99160), then Avala's core (99161), which
# Father Gavin only offers once the first is handed in (seen in game, 2026-10-02: the step asked for
# both at once and could not finish). Avala stands just north of him.
def gavin(cls):
    head = "step << " + cls
    talk = ("    .goto 1426,57.5,44.8\n"
            "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r\n")
    return f"""{head}
{talk}    .accept 99159 >> Accept Finding Warmth
    .target Father Gavin
{head}
    .goto 1426,55.0,46.0,60,0
    .goto 1426,53.0,44.0,60,0
    .goto 1426,56.0,48.5
    >>Loot |cRXP_PICK_Mostly Dry Firewood|r: the large white trunks lying by the trees around Father Gavin's. Some give 2
    .complete 99159,1 --Mostly Dry Firewood (14)
{head}
{talk}    .turnin 99159 >> Turn in Finding Warmth
    .accept 99160 >> Accept Rime's Wrath
    .accept 99162 >> Accept Treacherous Cold
    .target Father Gavin
{head}
    #sticky
    #label IceElementals
    >>Kill |cRXP_ENEMY_Minor Ice Elementals|r as you go: they are all around Father Gavin's
    .complete 99160,1 --Minor Ice Elemental slain (10)
    .mob Minor Ice Elemental
    .isOnQuest 99160
{head}
    .goto 1426,52.0,44.0
    >>Loot the rifle by the fallen mountaineer under the tree lying across the frozen river
    .collect 286358,1,99162 --Coalbeard's Rifle
    .isOnQuest 99162
{head}
    .goto 1426,53.0,59.0
    >>Loot the rifle by the fallen mountaineer next to a cart, in the valley to the south
    .collect 286360,1,99162 --Stoneanvil's Rifle
    .isOnQuest 99162
{head}
    .goto 1426,60.0,50.0
    >>Loot the rifle by the fallen mountaineer next to a cart, on the small path up to Vagash's cave
    >>|cRXP_WARN_A player reported it wouldn't loot: if so, skip this step|r
    .collect 286359,1,99162 --Sunhammer's Rifle
    .isOnQuest 99162
{head}
    .goto 1426,55.0,46.0,60,0
    .goto 1426,57.0,48.0
    >>Finish the |cRXP_ENEMY_Minor Ice Elementals|r on the way back to Father Gavin
    .complete 99160,1 --Minor Ice Elemental slain (10)
    .mob Minor Ice Elemental
    .isOnQuest 99160
{head}
{talk}    .turnin 99160 >> Turn in Rime's Wrath
    .accept 99161 >> Accept Rime's Wrath
    .target Father Gavin
    .isQuestComplete 99160
{head}
    .goto 1426,57.6,42.8
    >>Kill |cRXP_ENEMY_Avala|r, the big ice elemental just north of Father Gavin. Loot its core
    .complete 99161,1 --Avala's Core (1)
    .mob Avala
    .isOnQuest 99161
{head}
{talk}    .turnin 99161 >> Turn in Rime's Wrath
    .target Father Gavin
    .isQuestComplete 99161
{head}
{talk}    .turnin 99162 >> Turn in Treacherous Cold
    .target Father Gavin
    .isQuestComplete 99162
"""


ends = [m.end() for m in re.finditer(r"    \.turnin 99158 >>Turn in Dawn in the Mountains\n", guide)]
assert len(ends) == 2, "Dawn in the Mountains: the Hunters' hand-in and everyone else's"
for end, cls in reversed(list(zip(ends, ("Hunter", "!Hunter")))):
    i = guide.index("\nstep", end - 1) + 1
    guide = guide[:i] + gavin(cls) + guide[i:]

# The Mining Pack is 25c for 4 slots: nice, not needed. When money is short it waits.
sub("""    >>|cRXP_BUY_Buy a|r |T134708:0|t[Mining Pick]|cRXP_BUY_, an|r |T133635:0|t[Apprentice's Mining Pack] |cRXP_BUY_and a|r |T133057:0|t[Blacksmith Hammer]
""", """    >>|cRXP_BUY_Buy a|r |T134708:0|t[Mining Pick] |cRXP_BUY_(10c) and a|r |T133057:0|t[Blacksmith Hammer] |cRXP_BUY_(18c). The|r |T133635:0|t[Apprentice's Mining Pack] |cRXP_BUY_(25c) only if you have money left|r
""")
sub("""    .collect 277115,1 --Apprentice's Mining Pack (1)
""", "")

# Our Coldridge route ends with the death skip (from the troll cave, with The Adventurer taken, the
# Spirit Healer is Kharanos's: logged runs). Arriving in Kharanos, RestedXP's own death skip goes.
sub("""    .deathskip >> Die and respawn at the |cRXP_FRIENDLY_Spirit Healer|r
    .target Spirit Healer
step
    .goto 1426,45.344,51.936
""", """    .deathskip >> Die and respawn at the |cRXP_FRIENDLY_Spirit Healer|r
    .target Spirit Healer
    .subzoneskip 131
step
    .goto 1426,45.344,51.936
""")

HEAD = """-- Headstart: Dun Morogh 5-11 after our Coldridge opener. GENERATED by tools/fork_dunmorogh.py from
-- RestedXP's Forever guide (Guides/Forever/Alliance-1-14_DwarfGnome.lua, CC BY-NC-SA 4.0); only the
-- changes listed in that script are ours. Do not edit by hand: change the script and rerun it.
local _, YR = ...

YR:ShipGuide("dunmorogh", [["""
# Frostmane Hold is taken from Senir in Kharanos well before the hold; a run (2026-10-02) got there
# without it (the pick-up step went by) and killed headhunters for nothing. A second chance just before
# the hold: with the quest it is done at once and never shows; without it, back to Senir first.
SENIR_AGAIN = """step
    .goto 1426/0,-501.500,-5643.900
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Senir Whitebeard::1252|r in Kharanos
    >>|cRXP_WARN_You don't have Frostmane Hold: get it before you go in, the headhunters don't count without it|r
    .accept 287 >>Accept Frostmane Hold
    .target Senir Whitebeard::1252
    .isQuestAvailable 287
"""
i = guide.index("    #completewith Headhunters")
i = guide.rindex("\nstep", 0, i) + 1
guide = guide[:i] + SENIR_AGAIN + guide[i:]

guide = no_sick_deathskips(clean(guide))   # without the SoD, hardcore and self-found steps; no death skip from 10
guide, shared = mark(guide)   # pick-ups a duo or trio splits (Duo/Trio versions of the route)
for line in shared:
    print("   ", line)
open(OUT, "w", encoding="utf-8", newline="\n").write(HEAD + guide + "]])\n")
print(OUT, guide.count("\nstep"), "steps")
