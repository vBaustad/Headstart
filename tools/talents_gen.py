"""Talent trees and builds for Headstart, from Forever's client data (the trait system, build 1.60.1.70425).

    python tools/talents_gen.py        (needs S:/forever-data/db/forever.duckdb)

Writes Data/TalentTrees.lua (every class's tree: three tabs of 7 rows by 4 columns, each node's spell, ranks, place
and the node it needs at full rank) and Data/TalentBuilds.lua (Headstart's suggested builds: the 51 points in the
order they are taken, levels 10 to 60). The builds are written below by talent name and checked here against the
tree as the game has it: 5 points in a tab per row, a needed talent at full rank first, no talent past its ranks,
51 points. They are Headstart's own suggestions for levelling (the owner, 2026-10-20: "start - I have no builds"),
and for a role at 60 - tank, healer, damage (ROLE_BUILDS) - not anyone's published builds.
"""
import os
import sys
from collections import defaultdict

import duckdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = "S:/forever-data/db/forever.duckdb"
S = "wow_classic_beta_1_60_1_70425"
BUILD = "1.60.1.70425"
# each tree's skill line (skilllinextraittree) is a class: Classic's class IDs
CLASS_OF_LINE = {26: 1, 184: 2, 50: 3, 38: 4, 613: 5, 373: 7, 237: 8, 354: 9, 574: 11}
CLASS_MASK = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 7: 64, 8: 128, 9: 256, 11: 1024}
CLASS_NAME = {1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid"}
ROW_POINTS, POINTS = 5, 51

# ---------------------------------------------------------------------------------------------------------------
# The builds: (talent, points) in the order they are taken; "Tab::Name" where a name is in two tabs.
# ---------------------------------------------------------------------------------------------------------------
BUILDS = {
    1: [("level", "Levelling: Arms, then Fury", "Arms to Mortal Strike with a two-handed weapon, then Fury for crits and Enrage.", [
        ("Improved Heroic Strike", 3), ("Improved Rend", 3), ("Improved Charge", 2), ("Improved Overpower", 2),
        ("Deep Wounds", 3), ("Deflection", 2), ("Two-Handed Weapon Specialization", 3), ("Impale", 2),
        ("Sweeping Strikes", 1), ("Weaponmaster", 5), ("Improved Slam", 2), ("Deflection", 2), ("Mortal Strike", 1),
        ("Cruelty", 5), ("Unbridled Wrath", 5), ("Blood Craze", 3), ("Piercing Howl", 1), ("Booming Voice", 1),
        ("Enrage", 5)])],
    2: [("level", "Levelling: Retribution, then Holy", "Retribution to Twist of Light with a two-handed weapon, then Holy for Strength, Intellect and mana.", [
        ("Benediction", 5), ("Improved Judgement", 2), ("Conviction", 5), ("Seal of Command", 1), ("Pursuit of Justice", 2),
        ("Vindication", 3), ("Sacred Arbiter", 1), ("Deflection", 1), ("Retribution::Two-Handed Weapon Specialization", 3),
        ("Sanctified Judgement", 3), ("Vengeance", 3), ("Repentance", 1), ("Twist of Light", 1),
        ("Divine Strength", 5), ("Divine Intellect", 5), ("Improved Seals", 3), ("Reverence", 3), ("Illumination", 4)])],
    3: [("level", "Levelling: Beast Mastery, then Marksmanship", "Beast Mastery to Bestial Wrath - your pet does the work - then Marksmanship for crits and Trueshot Aura.", [
        ("Deadly Aspects", 5), ("Focused Fire", 2), ("Endurance Training", 3), ("Unleashed Fury", 5), ("Beast Mastery::Ferocity", 5),
        ("Bestial Swiftness", 1), ("Intimidation", 1), ("Spirit Bond", 2), ("Endurance Training", 1), ("Frenzy", 5),
        ("Bestial Wrath", 1),
        ("Lethal Attacks", 5), ("Efficiency", 5), ("Improved Arcane Shot", 5), ("Trueshot Aura", 1), ("Rapid Killing", 2),
        ("Hawk Eye", 2)])],
    4: [("level", "Levelling: Combat, then Assassination", "Combat to Adrenaline Rush with two weapons, then Assassination for crits and combo points.", [
        ("Improved Sinister Strike", 2), ("Improved Eviscerate", 3), ("Precision", 3), ("Combat::Deflection", 2), ("Endurance", 2),
        ("Lightning Reflexes", 3), ("Dual Wield Specialization", 5), ("Blade Flurry", 1), ("Hack and Slash", 5),
        ("Weapon Expertise", 2), ("Aggression", 2), ("Adrenaline Rush", 1),
        ("Malice", 5), ("Ruthlessness", 3), ("Murder", 2), ("Relentless Strikes", 1), ("Lethality", 5),
        ("Improved Slice and Dice", 3), ("Cold Blood", 1)])],
    5: [("level", "Levelling: Shadow, then Discipline", "Shadow to Shadowform - Spirit Tap keeps the mana coming - then Discipline for wanding and instants.", [
        ("Spirit Tap", 5), ("Improved Shadow Word: Pain", 2), ("Improved Mind Blast", 3), ("Mind Flay", 1),
        ("Improved Mind Flay", 2), ("Shadow Focus", 2), ("Dark Inspiration", 5), ("Vampiric Embrace", 1), ("Silence", 1),
        ("Improved Mind Blast", 2), ("Shadow Focus", 1), ("Darkness", 5), ("Shadowform", 1),
        ("Wand Specialization", 2), ("Twin Disciplines", 5), ("Mental Strength", 3), ("Meditation", 3),
        ("Improved Power Word: Shield", 2), ("Inner Focus", 1), ("Improved Inner Fire", 3), ("Mental Strength", 1)])],
    7: [("level", "Levelling: Enhancement, then Elemental", "Enhancement to Rage of the Farseer with a two-handed weapon, then Elemental for cheaper, harder shocks.", [
        ("Thundering Strikes", 5), ("Improved Ghost Wolf", 2), ("Mental Dexterity", 3), ("Shamanistic Focus", 1),
        ("Elemental Weapons", 3), ("Ancestral Knowledge", 1), ("Flurry", 5), ("Stormstrike", 1), ("Mental Quickness", 2),
        ("Spirit Weapons", 1), ("Improved Stormstrike", 1), ("Maelstrom Weapon", 5), ("Rage of the Farseer", 1),
        ("Convection", 5), ("Concussion", 5), ("Call of Flame", 3), ("Elemental Focus", 1), ("Reverberation", 1),
        ("Eye of the Storm", 3), ("Elemental Devastation", 2)])],
    8: [("level", "Levelling: Frost, then Arcane", "Frost to Ice Barrier - slow, freeze and kill - then Arcane for mana and Clearcasting.", [
        ("Improved Frostbolt", 5), ("Ice Shards", 5), ("Frost Channeling", 3), ("Piercing Ice", 3), ("Improved Frost Nova", 2),
        ("Arctic Reach", 2), ("Shatter", 3), ("Cold Snap", 1), ("Improved Cone of Cold", 1), ("Winter's Chill", 5),
        ("Ice Barrier", 1),
        ("Arcane::Wand Specialization", 2), ("Arcane Focus", 3), ("Arcane Concentration", 5), ("Arcane Impact", 3),
        ("Arcane Geometry", 2), ("Arcane Meditation", 3), ("Magic Absorption", 2)])],
    9: [("level", "Levelling: Affliction, then Demonology", "Affliction to Wrack - your damage over time does the work - then Demonology for a sturdier pet.", [
        ("Improved Corruption", 5), ("Improved Life Tap", 2), ("Improved Drains", 3), ("Fel Concentration", 3),
        ("Amplify Curse", 1), ("Improved Bane of Agony", 1), ("Nightfall", 2), ("Malevolence", 3), ("Siphon Life", 1),
        ("Soul Siphon", 3), ("Grim Reach", 1), ("Shadow Mastery", 5), ("Wrack", 1),
        ("Demonic Embrace", 5), ("Fel Vitality", 3), ("Improved Voidwalker", 2), ("Demonic Sacrifice", 1),
        ("Master Summoner", 2), ("Unholy Power", 2), ("Fel Domination", 1), ("Unholy Power", 3), ("Demonic Aegis", 1)])],
    11: [("level", "Levelling: Feral Combat, then Restoration", "Feral to Berserk - cat for damage, bear when it gets rough - then Restoration for Furor and shifting.", [
        ("Feral Combat::Ferocity", 5), ("Feral Swiftness", 2), ("Thick Hide", 3), ("Sharpened Claws", 2), ("Feral Charge", 1),
        ("Shredding Attacks", 2), ("Predatory Strikes", 3), ("Blood Frenzy", 2), ("Leader of the Pack", 1),
        ("Savage Fury", 2), ("Primal Bite", 1), ("Heart of the Wild", 1), ("Rend and Tear", 5), ("Berserk", 1),
        ("Furor", 5), ("Naturalist", 5), ("Natural Shapeshifter", 3), ("Reflection", 2), ("Improved Rejuvenation", 3),
        ("Swiftmend", 1), ("Reflection", 1)])],
}

# Builds for a role at 60 - tanking, healing, damage in a group - each the 51 points in the order to take them (its
# main tree first). Headstart's own, made from Forever's trees and what each talent says, as the levelling ones are.
# A class's damage build that is its levelling build already has none of its own here.
ROLE_BUILDS = {
    1: [("tank", "Tank: Protection", "Shield Slam and Bastion for threat behind a shield, with Arms for parry and rage.", [
        ("Shield Specialization", 5), ("Anticipation", 5), ("Improved Revenge", 3), ("Defiance", 3), ("Last Stand", 1),
        ("Master of Defense", 2), ("Improved Sunder Armor", 3), ("Concussion Blow", 1), ("Focused Rage", 2), ("Bastion", 5),
        ("Shield Slam", 1),
        ("Deflection", 5), ("Improved Heroic Strike", 3), ("Improved Rend", 3), ("Improved Tactical Mastery", 5),
        ("Anger Management", 1), ("Deep Wounds", 3)]),
        ("dps", "Damage: Fury", "Two weapons, Flurry and Bloodthirst, with Arms for rage and Deep Wounds.", [
        ("Cruelty", 5), ("Unbridled Wrath", 5), ("Furious Precision", 3), ("Booming Voice", 1), ("Piercing Howl", 1),
        ("Dual Wield Specialization", 5), ("Enrage", 4), ("Death Wish", 1), ("Flurry", 5), ("Bloodthirst", 1),
        ("Improved Heroic Strike", 3), ("Improved Rend", 3), ("Improved Tactical Mastery", 5), ("Improved Charge", 2),
        ("Anger Management", 1), ("Deep Wounds", 3), ("Impale", 2), ("Spearing Strike", 1)])],
    2: [("tank", "Tank: Protection", "Holy Shield, Iron Creed and Righteous Fury behind a shield, with Holy for mana.", [
        ("Toughness", 5), ("Redoubt", 5), ("Anticipation", 5), ("Precision", 1), ("Improved Righteous Fury", 3),
        ("Shield Specialization", 3), ("Sacred Duty", 2), ("Templar's Bulwark", 1), ("Iron Creed", 5), ("Holy Shield", 1),
        ("Divine Strength", 5), ("Divine Intellect", 5), ("Improved Seals", 3), ("Spiritual Focus", 2), ("Reverence", 3),
        ("Purifying Power", 2)]),
        ("heal", "Healer: Holy", "Holy Shock, Light's Vigil and Illumination, with Retribution for cheaper instants and judging.", [
        ("Divine Intellect", 5), ("Healing Light", 3), ("Spiritual Focus", 2), ("Reverence", 3), ("Purifying Power", 2),
        ("Illumination", 5), ("Divine Favor", 1), ("Holy Shock", 1), ("Infusion of Light", 2), ("Voice of Truth", 1),
        ("Holy Power", 5), ("Light's Vigil", 1), ("Unyielding Faith", 2),
        ("Benediction", 5), ("Improved Judgement", 2), ("Holy Conduit", 2), ("Deflection", 1), ("Sanctified Judgement", 3),
        ("Pursuit of Justice", 2), ("Eye for an Eye", 2), ("Vindication", 1)])],
    3: [("dps", "Damage: Marksmanship", "Trueshot Aura, Mortal Shots and Sniper Shot, with Beast Mastery for Deadly Aspects and your pet.", [
        ("Lethal Attacks", 5), ("Careful Aim", 5), ("Efficiency", 3), ("Rapid Killing", 2), ("Trueshot Aura", 1),
        ("Mortal Shots", 5), ("Barrage", 3), ("Rapid Recuperation", 2), ("Ranged Weapon Specialization", 5), ("Sniper Shot", 1),
        ("Deadly Aspects", 5), ("Focused Fire", 2), ("Endurance Training", 3), ("Unleashed Fury", 5), ("Beast Mastery::Ferocity", 4)])],
    4: [("dps", "Damage: Assassination", "Mutilate with two daggers, Seal Fate and Venom, with Combat for the off-hand.", [
        ("Malice", 5), ("Ruthlessness", 3), ("Murder", 2), ("Relentless Strikes", 1), ("Lethality", 5), ("Improved Poisons", 5),
        ("Cold Blood", 1), ("Mutilate", 1), ("Vigor", 2), ("Seal Fate", 5), ("Venom", 1),
        ("Improved Eviscerate", 3), ("Lightning Reflexes", 2), ("Puncturing Wounds", 3), ("Precision", 3), ("Endurance", 2),
        ("Improved Sprint", 2), ("Dual Wield Specialization", 5)])],
    5: [("heal", "Healer: Holy", "Prayer of Mending, Spiritual Guidance and Spiritual Healing, with Discipline for mana and shields.", [
        ("Improved Renew", 3), ("Holy Specialization", 5), ("Divine Fury", 5), ("Inspiration", 3), ("Holy Nova", 1),
        ("Improved Healing", 3), ("Binding Heal", 1), ("Spirit of Redemption", 1), ("Spiritual Guidance", 5),
        ("Litany of Light", 2), ("Spiritual Healing", 3), ("Prayer of Mending", 1),
        ("Twin Disciplines", 5), ("Mental Strength", 5), ("Meditation", 3), ("Inner Focus", 1),
        ("Improved Power Word: Shield", 3), ("Mental Agility", 1)]),
        ("dps", "Damage: Shadow", "Shadowform, Shadow Weaving and Darkness, with Discipline for Intellect and mana.", [
        ("Shadow Focus", 5), ("Improved Mind Blast", 5), ("Improved Shadow Word: Pain", 2), ("Mind Flay", 1),
        ("Improved Mind Flay", 2), ("Vampiric Embrace", 1), ("Shadow Weaving", 3), ("Dark Inspiration", 3), ("Silence", 1),
        ("Devouring Contagion", 2), ("Darkness", 5), ("Shadowform", 1),
        ("Twin Disciplines", 5), ("Mental Strength", 5), ("Silent Resolve", 3), ("Meditation", 3), ("Inner Focus", 1),
        ("Mental Agility", 3)])],
    7: [("heal", "Healer: Restoration", "Riptide, Purification and Mana Tide, with Enhancement for Intellect and crit.", [
        ("Improved Healing Wave", 5), ("Tidal Focus", 5), ("Mindfulness", 3), ("Totemic Focus", 2), ("Water Shield", 1),
        ("Healing Focus", 3), ("Tidal Mastery", 5), ("Mana Tide Totem", 1), ("Healing Way", 3), ("Nature's Swiftness", 1),
        ("Purification", 5), ("Riptide", 1),
        ("Ancestral Knowledge", 5), ("Thundering Strikes", 5), ("Improved Ghost Wolf", 2), ("Guardian Totems", 2),
        ("Shamanistic Focus", 1), ("Toughness", 1)]),
        ("dps", "Damage: Elemental", "Lava Burst, Lightning Overload and Elemental Mastery, with Enhancement for crit and Intellect.", [
        ("Convection", 5), ("Concussion", 5), ("Elemental Alacrity", 3), ("Call of Flame", 3), ("Elemental Focus", 1),
        ("Eye of the Storm", 3), ("Lava Burst", 1), ("Lightning Overload", 3), ("Elemental Reach", 1), ("Elemental Fury", 5),
        ("Elemental Mastery", 1),
        ("Thundering Strikes", 5), ("Ancestral Knowledge", 5), ("Improved Ghost Wolf", 2), ("Shamanistic Focus", 1),
        ("Guardian Totems", 2), ("Toughness", 5)])],
    8: [("dps", "Damage: Fire", "Ignite, Critical Mass and Combustion, with Frost for hit, Ice Block and Shatter.", [
        ("Improved Fireball", 5), ("Ignite", 5), ("Flame Throwing", 2), ("Pyroblast", 1), ("Burning Soul", 2),
        ("Improved Scorch", 3), ("Heating Up", 1), ("Master of Elements", 3), ("Critical Mass", 5), ("Blast Wave", 1),
        ("Fire Power", 3), ("Combustion", 1),
        ("Elemental Precision", 5), ("Improved Frost Nova", 2), ("Permafrost", 3), ("Ice Lance", 1), ("Improved Blizzard", 3),
        ("Frost Warding", 1), ("Ice Block", 1), ("Shatter", 3)])],
    9: [("dps", "Damage: Destruction", "Shadow Bolt with Ruin and Shadow and Flame, then Incinerate, with Affliction for hit and Shadow crit.", [
        ("Improved Shadow Bolt", 5), ("Bane", 5), ("Cataclysm", 3), ("Ruin", 5), ("Shadowburn", 1), ("Agonizing Flames", 3),
        ("Conflagrate", 1), ("Bane of Havoc", 1), ("Fire and Brimstone", 1), ("Shadow and Flame", 5), ("Incinerate", 1),
        ("Suppression", 5), ("Improved Corruption", 5), ("Improved Life Tap", 2), ("Amplify Curse", 1),
        ("Improved Bane of Agony", 2), ("Malevolence", 5)])],
    11: [("tank", "Tank: Feral (bear)", "Thick Hide, Natural Reaction and Berserk in bear form, with Restoration for Furor.", [
        ("Feral Combat::Ferocity", 5), ("Heart of the Wild", 5), ("Thick Hide", 3), ("Feral Swiftness", 2), ("Feral Charge", 1),
        ("Sharpened Claws", 2), ("Savage Fury", 2), ("Primal Bite", 1), ("Predatory Strikes", 3), ("Blood Frenzy", 2),
        ("Leader of the Pack", 1), ("Natural Reaction", 5), ("Berserk", 1), ("Rend and Tear", 5),
        ("Furor", 5), ("Naturalist", 5), ("Natural Shapeshifter", 3)]),
        ("heal", "Healer: Restoration", "Wild Growth, Swiftmend and Improved Regrowth, with Balance for longer, stronger heals over time.", [
        ("Nature's Focus", 5), ("Naturalist", 5), ("Reflection", 3), ("Gift of Nature", 5), ("Gift of the Earthmother", 1),
        ("Improved Rejuvenation", 3), ("Swiftmend", 1), ("Tranquil Spirit", 5), ("Nature's Swiftness", 1), ("Living Spirit", 3),
        ("Improved Regrowth", 5), ("Wild Growth", 1),
        ("Genesis", 5), ("Nature's Majesty", 2), ("Moonglow", 3), ("Nature's Splendor", 1), ("Improved Moonfire", 2)]),
        ("dps", "Damage: Balance", "Moonkin Form, Moonfury and Eclipse, with Restoration for damage and mana.", [
        ("Improved Wrath", 5), ("Moonglow", 3), ("Improved Moonfire", 2), ("Nature's Majesty", 2), ("Nature's Reach", 2),
        ("Nature's Splendor", 1), ("Vengeance", 5), ("Improved Starfire", 5), ("Insect Swarm", 1), ("Nature's Grace", 1),
        ("Eclipse", 3), ("Moonfury", 5), ("Moonkin Form", 1),
        ("Nature's Focus", 5), ("Naturalist", 5), ("Natural Shapeshifter", 2), ("Reflection", 3)])],
}
for _cls, _extra in ROLE_BUILDS.items():
    BUILDS[_cls] = BUILDS[_cls] + _extra


def trees():
    c = duckdb.connect(DB, read_only=True)
    q = lambda sql: c.execute(sql).fetchall()
    spell_name = {int(i): n for i, n in q(f"select ID, Name_lang from {S}.spellname")}
    entry_of = defaultdict(list)
    for node, entry, idx in q(f"select TraitNodeID, TraitNodeEntryID, \"Index\" from {S}.traitnodextraitnodeentry"):
        entry_of[int(node)].append((int(idx), int(entry)))
    entries = {int(i): (int(d), int(r)) for i, d, r in q(f"select ID, TraitDefinitionID, MaxRanks from {S}.traitnodeentry")}
    spell_of_def = {int(i): int(s) for i, s in q(f"select ID, SpellID from {S}.traitdefinition")}
    edges = defaultdict(list)
    for left, right in q(f"select LeftTraitNodeID, RightTraitNodeID from {S}.traitedge"):
        edges[int(right)].append(int(left))
    tabs = defaultdict(dict)
    for name, order, mask in q(f"select Name_lang, OrderIndex, ClassMask from {S}.talenttab"):
        tabs[int(mask)][int(order)] = name
    out = {}
    for line, tree in q(f"select SkillLineID, TraitTreeID from {S}.skilllinextraittree"):
        cls = CLASS_OF_LINE[int(line)]
        nodes = {}
        for nid, x, y in q(f"select ID, PosX, PosY from {S}.traitnode where TraitTreeID = '{tree}'"):
            x, y, nid = int(x), int(y), int(nid)
            tab = 0 if x < 4000 else 1 if x < 8000 else 2
            col, row = round((x - (1020, 5020, 9080)[tab]) / 600), round((y - 2130) / 600)
            if not (0 <= row <= 6 and 0 <= col <= 3) or not entry_of.get(nid):
                continue                    # (nodes off the grid: none the trees show)
            definition, ranks = entries[sorted(entry_of[nid])[0][1]]
            spell = spell_of_def.get(definition, 0)
            nodes[nid] = {"spell": spell, "name": spell_name.get(spell, "?"), "ranks": ranks, "tab": tab, "row": row, "col": col,
                          "edges": edges.get(nid, [])}
        # what a node needs: an edge from a node above it (or beside it) - the data draws some lines both ways
        for n in nodes.values():
            need = [p for p in n["edges"] if p in nodes and nodes[p]["row"] <= n["row"] and p != n]
            n["need"] = need[0] if need else None
        out[cls] = {"tree": int(tree), "tabs": [tabs[CLASS_MASK[cls]][i] for i in range(3)], "nodes": nodes}
    return out


def resolve(tree, spec, where):
    tab_names = tree["tabs"]
    points = []
    for name, count in spec:
        tab = None
        if "::" in name:
            tab, name = name.split("::", 1)
        found = [nid for nid, n in tree["nodes"].items() if n["name"] == name and (tab is None or tab_names[n["tab"]] == tab)]
        if len(found) != 1:
            sys.exit(f"{where}: {'no' if not found else 'more than one'} talent called {name!r}" + (f" in {tab}" if tab else ""))
        points += [found[0]] * count
    # the game's rules, point by point
    ranks, spent = defaultdict(int), defaultdict(int)
    for i, nid in enumerate(points):
        n = tree["nodes"][nid]
        level = 10 + i
        if spent[n["tab"]] < n["row"] * ROW_POINTS:
            sys.exit(f"{where}: level {level}, {n['name']} needs {n['row'] * ROW_POINTS} points in {tab_names[n['tab']]} (has {spent[n['tab']]})")
        if n["need"] and ranks[n["need"]] < tree["nodes"][n["need"]]["ranks"]:
            sys.exit(f"{where}: level {level}, {n['name']} needs {tree['nodes'][n['need']]['name']} at full rank first")
        ranks[nid] += 1
        if ranks[nid] > n["ranks"]:
            sys.exit(f"{where}: {n['name']} past its {n['ranks']} ranks")
        spent[n["tab"]] += 1
    if len(points) != POINTS:
        sys.exit(f"{where}: {len(points)} points, not {POINTS}")
    return points


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    t = trees()
    lines = [f"-- Every class's talent tree in WoW: Forever, from the game's own data (build {BUILD}; the trait system):",
             "-- [class ID] = { tree = its trait tree, tabs = its three tabs, nodes = { [node ID] = { spell, ranks, tab (1-3),",
             "-- row (1-7), column (1-4), the node it needs at full rank or nil } }. Made by tools/talents_gen.py - not edited by hand.",
             "local _, YR = ...", "", "YR.TalentTrees = {"]
    for cls in sorted(t):
        tr = t[cls]
        lines.append(f"    [{cls}] = {{ tree = {tr['tree']}, tabs = {{ {', '.join(lua_str(x) for x in tr['tabs'])} }}, nodes = {{   -- {CLASS_NAME[cls]}")
        for nid, n in sorted(tr["nodes"].items(), key=lambda kv: (kv[1]["tab"], kv[1]["row"], kv[1]["col"])):
            need = f", {n['need']}" if n["need"] else ""
            lines.append(f"        [{nid}] = {{ {n['spell']}, {n['ranks']}, {n['tab'] + 1}, {n['row'] + 1}, {n['col'] + 1}{need} }},   -- {n['name']}")
        lines.append("    } },")
    lines.append("}")
    open(os.path.join(ROOT, "Data", "TalentTrees.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")

    out = ["-- Headstart's suggested talent builds: [class ID] = { { key, name, what it is, points = the node of each point",
           "-- from level 10 to 60 } }. Written by name in tools/talents_gen.py and checked there against the game's tree",
           f"-- (build {BUILD}): 5 points in a tab per row, a needed talent at full rank first, 51 points. Not edited by hand.",
           "local _, YR = ...", "", "YR.TalentBuilds = {"]
    for cls in sorted(BUILDS):
        out.append(f"    [{cls}] = {{   -- {CLASS_NAME[cls]}")
        for key, name, about, spec in BUILDS[cls]:
            pts = resolve(t[cls], spec, f"{CLASS_NAME[cls]} {key}")
            rows = [", ".join(str(p) for p in pts[i:i + 10]) for i in range(0, len(pts), 10)]
            out.append(f"        {{ key = {lua_str(key)}, name = {lua_str(name)}, about = {lua_str(about)}, points = {{")
            for r in rows:
                out.append(f"            {r},")
            out.append("        } },")
        out.append("    },")
    out.append("}")
    open(os.path.join(ROOT, "Data", "TalentBuilds.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("trees:", {CLASS_NAME[k]: len(v["nodes"]) for k, v in t.items()}, "- builds: all checked")


if __name__ == "__main__":
    main()
