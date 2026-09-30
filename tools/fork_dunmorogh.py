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

from clean_guide import clean
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
sub(f"#next {nxt}\n", "#next " + ";".join(n if n in OURS else RXP_GROUP + "\\" + n for n in nxt.split(";")) + "\n")

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
# second visit later (that step now skips itself).
sub("""    .turnin 287 >>Turn in Frostmane Hold
""", """    .turnin 287 >>Turn in Frostmane Hold
    .accept 291 >>Accept The Reports
""")

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
# hand-in, and drop the "jump down into Frostmane Hold" step once the cave's objectives are done (it
# showed after a late Evershine hand-in, pointing back up the mountain).
sub("""    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rejold Barleybrew|r
    .turnin 319 >> Turn in A Favor for Evershine
""", """    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rejold Barleybrew|r
    >>|cRXP_WARN_Before Frostmane Hold: you die in the cave at the end to get back to Kharanos, so hand this in first|r
    .turnin 319 >> Turn in A Favor for Evershine
""")
sub("""    .goto 1426,24.682,50.836,20 >> Run up the side of the cave entrance. Jump down into Frostmane Hold
    .isOnQuest 287
""", """    .goto 1426,24.682,50.836,20 >> Run up the side of the cave entrance. Jump down into Frostmane Hold
    .isOnQuest 287
    .isQuestNotComplete 287
""")

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
guide = clean(guide)   # without the SoD, hardcore and self-found steps
guide, shared = mark(guide)   # pick-ups a duo or trio splits (Duo/Trio versions of the route)
for line in shared:
    print("   ", line)
open(OUT, "w", encoding="utf-8", newline="\n").write(HEAD + guide + "]])\n")
print(OUT, guide.count("\nstep"), "steps")
