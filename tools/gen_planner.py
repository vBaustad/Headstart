"""Generate Headstart_Setup/PlannerSpells.lua (for Planner.lua): an icon and an ID for every class spell and racial,
so spells a level-1 character doesn't know yet can still be shown and placed in the bar planner.

    python tools/gen_planner.py [schema]      (default: the newest wow_classic_beta build)

The same selection as gen_spell_levels.py (a class's own skill lines, AcquireMethod 0 or 2, a level
above 0), so every name here is a name YS.SPELL_LEVELS knows and Set up layout can place. The ID is
the lowest-level rank; the icon is spellmisc.SpellIconFileDataID (a file ID SetTexture takes as is);
passive is SPELL_ATTR0_PASSIVE (Attributes[0] & 0x40): passives can't go on a bar, so the planner
leaves them out.
    YR.PlannerSpells[CLASS][name] = { spellID, iconFileID, passive (0/1) }
    YR.PlannerRacials[name] = { spellID, iconFileID, passive (0/1), raceMask }
    YR.PlannerGeneral[CLASS][name] = { spellID, iconFileID }   Attack, and the weapon lines' active spells
        (Throw, Shoot, Shoot Bow ...) for the classes skillraceclassinfo gives that weapon line
    YR.PlannerProfessions = { { name, spellID, iconFileID, profession } }   what a profession puts in the
        spellbook to cast: Mining, Find Minerals, Smelting, Cooking, Basic Campfire, Disenchant ... - not its
        recipes (anything with a create-item or enchant effect), its specialisations or item effects
    YR.PlannerForms[CLASS] = { { form name, bonus bar } }   forms that swap the main bar
        (spellshapeshiftform.BonusActionBar > 0): bar 1 then shows slots 72 + (bar - 1) * 12 + 1..12
"""
import json
import os
import sys

import duckdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = r"S:\forever-data\db\forever.duckdb"
OUT = os.path.join(ROOT, "Headstart_Setup", "PlannerSpells.lua")
CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
PASSIVE = 0x40
ATTACK = 6603
SECONDARY = "('129', '185', '356', '142')"   # First Aid, Cooking, Fishing, Survival - as gen_spell_levels.py
# Profession spells that are specialisations (passive in effect) or an item's own spell: not for a bar.
NOT_ON_A_BAR = {"Weaponsmith", "Armorsmith", "Master Axesmith", "Master Hammersmith", "Master Swordsmith",
                "Gnomish Engineer", "Goblin Engineer", "Elemental Leatherworking", "Dragonscale Leatherworking",
                "Tribal Leatherworking", "Mechanical Dragonling", "Arcanite Dragonling",
                "Mithril Mechanical Dragonling", "Battle Chicken", "Summon Goblin Bomb"}
# Which class a form belongs to: the form table has no class, so by name - the rows with a bonus bar in
# build 70170 are exactly these (Cat/Bear/Dire Bear, the three stances, Stealth).
FORM_CLASS = {"Cat Form": "DRUID", "Bear Form": "DRUID", "Dire Bear Form": "DRUID", "Battle Stance": "WARRIOR",
              "Defensive Stance": "WARRIOR", "Berserker Stance": "WARRIOR", "Stealth": "ROGUE"}


from spell_rules import NOT_IN_GAME, NOT_SPELLS, other_line

def q(t):
    return '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    c = duckdb.connect(DB, read_only=True)
    s = sys.argv[1] if len(sys.argv) > 1 else c.sql(
        "select schema_name from main.builds where schema_name like 'wow_classic_beta_%' order by schema_name desc limit 1").fetchone()[0]
    line_class = {}
    for sid, line, mask in c.sql(f"""select sl.ID, sl.DisplayName_lang, cast(i.ClassMask as bigint) from {s}.skillline sl
            join {s}.skillraceclassinfo i on i.SkillID = sl.ID where sl.CategoryID = '7'""").fetchall():
        if other_line(line):            # a hunter's pet's abilities are not buttons of the hunter's
            continue
        for cid, token in CLASSES.items():
            if mask == 1 << (cid - 1):
                line_class[sid] = token
    rows = c.sql(f"""
        select a.SkillLine, cast(a.Spell as int), n.Name_lang, min(cast(l.SpellLevel as int)),
            cast(m.SpellIconFileDataID as bigint), cast(m."Attributes[0]" as bigint),
            cast(a."RaceMasks[0]" as bigint)
        from {s}.skilllineability a
        join {s}.spellname n on n.ID = a.Spell
        join {s}.spelllevels l on l.SpellID = a.Spell
        left join {s}.spellmisc m on m.SpellID = a.Spell
        where a.AcquireMethod in ('0', '2') and cast(l.SpellLevel as int) > 0
            and cast(a.Spell as int) not in ({", ".join(str(i) for i in sorted(NOT_IN_GAME))})
        group by 1, 2, 3, 5, 6, 7""").fetchall()
    best = {}
    # Which races get a class spell (a priest's Desperate Prayer, Starshards ...; a paladin's mount; a
    # mage's portals by faction): every rank's race mask together, 0 when any rank is for every race.
    races = {}
    for line, spell, name, level, icon, attr, race in rows:
        token = line_class.get(line)
        if not token or (token, name) in NOT_SPELLS or name.endswith(" Effect"):
            continue
        race = (race or 0) & 0xFFFFFFFF
        if race == 0xFFFFFFFF:
            race = 0
        was = races.setdefault(token, {}).get(name)
        races[token][name] = race if was is None else (0 if (was == 0 or race == 0) else (was | race))
        cur = best.setdefault(token, {}).get(name)
        if cur is None or level < cur[0] or (level == cur[0] and spell < cur[1]):
            best[token][name] = (level, spell, icon or 0, 1 if (attr or 0) & PASSIVE else 0)

    # A talent's spell the trainer lines don't list (Riposte, Cold Blood, Inner Focus, Divine Favor), if it
    # is something you press: the same rule, and so the same names, as gen_spell_levels.py - Forever's
    # talents (tools/forever_talents.json), their spells from the traits, not Classic's talent table.
    trees = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_talents.json"), encoding="utf-8"))["classes"]
    trait = {}
    for name, spell, icon, attr in c.sql(f"""
            select n.Name_lang, cast(t.SpellID as int), cast(m.SpellIconFileDataID as bigint), cast(m."Attributes[0]" as bigint)
            from {s}.traitdefinition t
            join {s}.spellname n on n.ID = t.SpellID
            left join {s}.spellmisc m on m.SpellID = t.SpellID""").fetchall():
        cur = trait.get(name)
        if cur is None or spell < cur[0]:
            trait[name] = (spell, icon or 0, bool((attr or 0) & PASSIVE) or (cur[2] if cur else False))
    for token, tree in trees.items():
        for name, t in tree.items():
            if (token, name) in NOT_SPELLS or name == "Two-Handed Axes and Maces":       # (a weapon skill: nothing to press)
                continue
            level = 10 + t["needs"]
            have = best.get(token, {}).get(name)
            if have:
                best[token][name] = (level,) + have[1:]
            elif name in trait and not trait[name][2]:
                best.setdefault(token, {})[name] = (level, trait[name][0], trait[name][1], 0)
                races.setdefault(token, {})[name] = 0

    racials = {}
    for spell, name, icon, attr, race in c.sql(f"""
        select cast(a.Spell as int), n.Name_lang, cast(m.SpellIconFileDataID as bigint),
            cast(m."Attributes[0]" as bigint), cast(a."RaceMasks[0]" as bigint)
        from {s}.skilllineability a
        join {s}.skillline sl on sl.ID = a.SkillLine
        join {s}.spellname n on n.ID = a.Spell
        left join {s}.spellmisc m on m.SpellID = a.Spell
        where sl.CategoryID = '9' and a.AcquireMethod = '2' and sl.DisplayName_lang like '%Racial%'""").fetchall():
        cur = racials.get(name)
        race = race or 0
        if cur:
            race = 0 if (cur[3] == 0 or race == 0) else (cur[3] | race)
            spell = min(spell, cur[0])
        racials[name] = (spell, icon or 0, 1 if (attr or 0) & PASSIVE else 0, race)

    # General spells: Attack for everyone, and each weapon line's active spells for the classes that get it.
    general = {token: {"Attack": (ATTACK, int(c.sql(
        f"select SpellIconFileDataID from {s}.spellmisc where SpellID = '{ATTACK}'").fetchone()[0] or 0))}
        for token in CLASSES.values()}
    line_mask = {}
    for sid, mask in c.sql(f"""select sl.ID, cast(i.ClassMask as bigint) from {s}.skillline sl
            join {s}.skillraceclassinfo i on i.SkillID = sl.ID where sl.CategoryID = '6'""").fetchall():
        line_mask[sid] = line_mask.get(sid, 0) | (mask or 0)
    for line, spell, name, icon, attr in c.sql(f"""
        select a.SkillLine, cast(a.Spell as int), n.Name_lang, cast(m.SpellIconFileDataID as bigint),
            cast(m."Attributes[0]" as bigint)
        from {s}.skilllineability a
        join {s}.skillline sl on sl.ID = a.SkillLine
        join {s}.spellname n on n.ID = a.Spell
        left join {s}.spellmisc m on m.SpellID = a.Spell
        where sl.CategoryID = '6' and a.AcquireMethod in ('1', '2')""").fetchall():
        if (attr or 0) & PASSIVE:
            continue
        for cid, token in CLASSES.items():
            if line_mask.get(line, 0) & (1 << (cid - 1)):
                cur = general[token].get(name)
                if not cur or spell < cur[0]:
                    general[token][name] = (spell, icon or 0)

    profs = {}
    for line, name, spell, icon in c.sql(f"""
        select sl.DisplayName_lang, n.Name_lang, cast(a.Spell as int), cast(m.SpellIconFileDataID as bigint)
        from {s}.skilllineability a
        join {s}.skillline sl on sl.ID = a.SkillLine
        join {s}.spellname n on n.ID = a.Spell
        left join {s}.spellmisc m on m.SpellID = a.Spell
        where (sl.CategoryID = '11' or sl.ID in {SECONDARY} or sl.ParentSkillLineID in {SECONDARY})
          and sl.DisplayName_lang not like '%DNT%'
          and (cast(m."Attributes[0]" as bigint) & {PASSIVE}) = 0
          and a.Spell not in (select SpellID from {s}.spelleffect where cast(Effect as int) in (24, 53, 59, 157))""").fetchall():
        if name in NOT_ON_A_BAR:
            continue
        cur = profs.get(name)
        if not cur or spell < cur[0]:
            profs[name] = (spell, icon or 0, line)

    forms = {}
    for name, bar in c.sql(f"""select Name_lang, cast(BonusActionBar as int) from {s}.spellshapeshiftform
            where cast(BonusActionBar as int) > 0 order by cast(BonusActionBar as int), ID""").fetchall():
        token = FORM_CLASS.get(name)
        if token and not any(f[1] == bar for f in forms.get(token, [])):
            forms.setdefault(token, []).append((name, bar))

    out = [f"-- GENERATED by tools/gen_planner.py from {s}. Do not edit; regenerate.",
           "-- [CLASS][name] = { spellID (lowest rank), iconFileID, passive 0/1, raceMask (0 = every race) }",
           "local YR = _G.HeadstartNS", "YR.PlannerSpells = {"]
    n = 0
    for token in sorted(best):
        out.append(f"    {token} = {{")
        for name, (level, spell, icon, passive) in sorted(best[token].items(), key=lambda kv: (kv[1][0], kv[0])):
            out.append(f"        [{q(name)}] = {{ {spell}, {icon}, {passive}, {races[token].get(name, 0)} }},")
            n += 1
        out.append("    },")
    out += ["}", "-- [name] = { spellID, iconFileID, passive 0/1, raceMask (0 = every race) }", "YR.PlannerRacials = {"]
    for name, (spell, icon, passive, race) in sorted(racials.items()):
        out.append(f"    [{q(name)}] = {{ {spell}, {icon}, {passive}, {race} }},")
    out += ["}", "-- [CLASS][name] = { spellID, iconFileID }: Attack and the weapon spells (Throw, Shoot ...)",
            "YR.PlannerGeneral = {"]
    for token in sorted(general):
        out.append(f"    {token} = {{")
        for name, (spell, icon) in sorted(general[token].items()):
            out.append(f"        [{q(name)}] = {{ {spell}, {icon} }},")
        out.append("    },")
    out += ["}", "-- { name, spellID, iconFileID, profession }: a profession's own spells, by profession",
            "YR.PlannerProfessions = {"]
    for name, (spell, icon, line) in sorted(profs.items(), key=lambda kv: (kv[1][2], kv[1][2] != kv[0], kv[0])):
        out.append(f"    {{ {q(name)}, {spell}, {icon}, {q(line)} }},")
    out += ["}", "-- [CLASS] = { { form, bonus bar } }: bar 1 shows slots 72 + (bar - 1) * 12 + 1..12 in that form",
            "YR.PlannerForms = {"]
    for token in sorted(forms):
        out.append(f"    {token} = {{ " + ", ".join(f"{{ {q(n)}, {b} }}" for n, b in forms[token]) + " },")
    out += ["}", ""]
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    active = sum(1 for t in best.values() for v in t.values() if not v[3])
    print(f"{n} class spells ({active} you can put on a bar), {len(racials)} racials, from {s}")


if __name__ == "__main__":
    main()
