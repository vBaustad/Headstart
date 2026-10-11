"""Generate Data/TrainerSpells.lua (for Reminders.lua): every rank a class trainer teaches, by level.

    python tools/gen_trainer_spells.py [schema]      (default: the newest wow_classic_beta build)

From the game's tables: skilllineability rows with AcquireMethod 0 on a class's own skill lines,
their level from spelllevels and their rank from spell.NameSubtext. Talent spells (talent.SpellRank
and traitdefinition.SpellID) are left out as first ranks: the trainer only teaches their later ranks,
and only once you have the one before, which the addon checks with IsPlayerSpell. Every rank of a
talent with several points (talent.SpellRank[0..8]) is left out: those are bought with talent points.
    YR.TrainerSpells[CLASS] = { { spellID, level, "name", rank or 0, raceMask or 0, talent 0/1 }, ... }  by level
"""
import os
import re
import sys

import duckdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = r"S:\forever-data\db\forever.duckdb"
OUT = os.path.join(ROOT, "Data", "TrainerSpells.lua")
from spell_rules import NOT_IN_GAME, NOT_SPELLS, NOT_TAUGHT, not_a_spell, other_line

# Class lines only. A rogue's poisons and Pick Lock and a mage's Comprehend Scroll are secondary skills
# in Forever (the Poisons skill is a quest's): whether a class trainer sells them isn't known, and the
# auto-trainer buys whatever the trainer's window offers anyway.
CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}


def main():
    c = duckdb.connect(DB, read_only=True)
    s = sys.argv[1] if len(sys.argv) > 1 else c.sql(
        "select schema_name from main.builds where schema_name like 'wow_classic_beta_%' order by schema_name desc limit 1").fetchone()[0]
    line_class = {}
    for sid, line, mask in c.sql(f"""select sl.ID, sl.DisplayName_lang, cast(i.ClassMask as bigint) from {s}.skillline sl
            join {s}.skillraceclassinfo i on i.SkillID = sl.ID where sl.CategoryID = '7'""").fetchall():
        # a hunter's pet's lines (Pet - Raptor, Beast Training) and the like are not what a class trainer teaches
        if other_line(line):
            continue
        for cid, token in CLASSES.items():
            if mask == 1 << (cid - 1):
                line_class[sid] = token
    # Forever's talents are traits (traitdefinition): a trait's spell comes with the talent point.
    talent = {r[0] for r in c.sql(f"select cast(SpellID as int) from {s}.traitdefinition").fetchall() if r[0]}
    # Classic's talent table is still in the client and is not Forever's talents. Its spells that have a
    # level are trained now (Blessing of Kings and Omen of Clarity at 20; Classic's first Holy Shock is
    # the trainer's "Rank 2" at 40, after the trait's own). Those at level 1 are what is left of
    # Classic's passive talents (Fist Weapon Specialization, Improved Pummel) and nobody teaches them.
    classic = set()
    for k in range(9):
        classic |= {r[0] for r in c.sql(f'select cast("SpellRank[{k}]" as int) from {s}.talent').fetchall() if r[0]}
    rows = c.sql(f"""
        select distinct a.SkillLine, cast(a.Spell as int), n.Name_lang, sp.NameSubtext_lang,
            min(cast(l.SpellLevel as int)), cast(a."RaceMasks[0]" as bigint), max(cast(m."Attributes[0]" as bigint))
        from {s}.skilllineability a
        join {s}.spellname n on n.ID = a.Spell
        left join {s}.spell sp on sp.ID = a.Spell
        left join {s}.spellmisc m on m.SpellID = a.Spell
        join {s}.spelllevels l on l.SpellID = a.Spell
        where a.AcquireMethod = '0' and cast(l.SpellLevel as int) > 0
            and cast(a.Spell as int) not in ({", ".join(str(i) for i in sorted(NOT_IN_GAME))})
        group by 1, 2, 3, 4, 6""").fetchall()
    out, talent_names = {}, {}
    for line, spell, name, sub, level, race, attr in rows:
        token = line_class.get(line)
        if not token:
            continue
        m = re.match(r"Rank (\d+)", sub or "")
        rank = int(m.group(1)) if m else 0
        if spell in talent:
            talent_names.setdefault(token, set()).add(name)
            continue
        # not shown in a spellbook (Battle Stance Passive, Bane of Doom Effect), or what a spell does
        # rather than the spell (Explosive Trap Effect)
        if not_a_spell(name, attr):
            continue
        if spell in classic and level <= 1:
            continue
        if (token, name) in NOT_SPELLS or (token, name) in NOT_TAUGHT or (token, name, rank) in NOT_TAUGHT:
            continue
        # One spell can have a row per race group: OR their masks, and any "every race" row wins.
        prev = out.setdefault(token, {}).get(spell)
        race = race or 0
        if prev:
            race = 0 if (prev[3] == 0 or race == 0) else (prev[3] | race)
            level = min(level, prev[0])
        out[token][spell] = (level, name, rank, race)

    def q(t):
        return '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = [f"-- GENERATED by tools/gen_trainer_spells.py from {s}. Do not edit; regenerate.",
             "-- [class] = { { spellID, level, name, rank (0 = none), raceMask (0 = every race), talent (1: rank 1 is a talent) }, ... }",
             "-- Each class's list is made by a function, and only yours is called: nine classes built at every login",
             "-- to keep one was sixteen hundred small tables made and thrown away.",
             "local _, YR = ...", "local BY_CLASS = {"]
    n = 0
    for token in sorted(out):
        lines.append(f"    {token} = function() return {{")
        for spell, (level, name, rank, race) in sorted(out[token].items(), key=lambda kv: (kv[1][0], kv[1][1], kv[1][2])):
            t = 1 if name in talent_names.get(token, ()) else 0
            lines.append(f"        {{ {spell}, {level}, {q(name)}, {rank}, {race}, {t} }},")
            n += 1
        lines.append("    } end,")
    lines += ["}",
              "-- a class's list is made the first time it is asked for",
              "YR.TrainerSpells = setmetatable({}, { __index = function(t, token)",
              "    local make = BY_CLASS[token]",
              "    if not make then return nil end",
              "    local list = make()",
              "    BY_CLASS[token] = nil",
              "    rawset(t, token, list)",
              "    return list",
              "end })",
              "--- Your class is known (the login): its list is made, and what would make the others is let go.",
              "function YR.TrainerSpellsOnly(class)",
              "    local mine = class and YR.TrainerSpells[class]",
              "    if mine then BY_CLASS = {} end",
              "end", ""]
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"{n} trainer ranks for {len(out)} classes from {s}")


if __name__ == "__main__":
    main()
