"""Generate Headstart_Setup/SpellLevels.lua: for every class, each trainable spell NAME -> the level its first rank is learned.

    python tools/gen_spell_levels.py [schema]      (default: the newest wow_classic_beta schema)

Source: S:/forever-data/db/forever.duckdb (client DB2).
  * class spell lines = skillline CategoryID 7, mapped to a class through skillraceclassinfo.ClassMask;
  * only AcquireMethod 0 (trained) and 2 (auto-learned). AcquireMethod 3 rows are Season of Discovery
    rune variants whose SpellLevel is 1 (Flash of Light 412020, Avenging Wrath 407788 ...) and would
    make a level-20 spell look like a level-1 one;
  * level = min(spelllevels.SpellLevel) over the ranks; rows without a level are dropped;
  * a spell a talent gives is at least the level its row in the tree can be reached (see Talents below),
    and is listed in YS.TALENTS.
Names are enUS, which is what the macros /cast by.
"""
import json
import os
import sys
import duckdb

from spell_rules import LINE_SPELLS, NOT_IN_GAME, NOT_SPELLS

DB = "S:/forever-data/db/forever.duckdb"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Headstart_Setup", "SpellLevels.lua")
NOT_CLASS_SPELLS = {"Engraving", "Runes", "Meditation", "Explorer Imp", "Mounts", "Companions", "Beast Training"}
CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}

c = duckdb.connect(DB, read_only=True)
schema = sys.argv[1] if len(sys.argv) > 1 else c.sql(
    "select schema_name from main.builds where schema_name like 'wow_classic_beta_%' order by schema_name desc limit 1").fetchone()[0]

lines = c.sql(f"""
    select sl.ID, sl.DisplayName_lang, cast(i.ClassMask as bigint)
    from {schema}.skillline sl join {schema}.skillraceclassinfo i on i.SkillID = sl.ID
    where sl.CategoryID = '7'""").fetchall()
line_class, line_only = {}, {}
for sid, name, mask in lines:
    if name in NOT_CLASS_SPELLS or name.startswith("Pet - ") or mask is None or mask <= 0:
        if name in LINE_SPELLS and mask:       # the line's own spell stays (Beast Training)
            for cid, token in CLASSES.items():
                if mask == 1 << (cid - 1):
                    line_only[sid] = (token, name)
        continue
    for cid, token in CLASSES.items():
        if mask == 1 << (cid - 1):
            line_class[sid] = token

rows = c.sql(f"""
    select a.SkillLine, n.Name_lang, min(cast(l.SpellLevel as int))
    from {schema}.skilllineability a
    join {schema}.spellname n on n.ID = a.Spell
    join {schema}.spelllevels l on l.SpellID = a.Spell
    where a.AcquireMethod in ('0', '2') and cast(l.SpellLevel as int) > 0
        and cast(a.Spell as int) not in ({", ".join(str(i) for i in sorted(NOT_IN_GAME))})
    group by 1, 2""").fetchall()

levels = {}
for sid, name, lvl in rows:
    token = line_class.get(sid)
    if not token and sid in line_only and line_only[sid][1] == name:
        token = line_only[sid][0]
    if token and (token, name) not in NOT_SPELLS and not name.endswith(" Effect"):
        cur = levels.setdefault(token, {}).get(name)
        levels[token][name] = lvl if cur is None else min(cur, lvl)

# Talents. Forever's trees are not Classic's (the client still has Classic's talent table: read from it,
# Holy Shock was a level-40 talent and Blessing of Kings a talent at all). Which spells are talents, and
# how many points each needs in lower tiers, is in tools/forever_talents.json (tools/fetch_talents.py,
# from foreverchanges.pro's calculator). A talent that needs N points can first be taken at level
# 10 + N: the first point comes at 10, one a level. (With Legacy points it can be five levels sooner.
# Nothing here depends on that: a talent's button is never put on a bar before you have the talent.)
# A talent the class lines don't list (Riposte, Cold Blood: only the trait has its spell) is a class
# spell too, if it is something you press (not passive: Attributes[0] & 0x40). Without it the planner
# couldn't hold it and no macro could ask for it.
# (a weapon skill a talent teaches isn't marked passive in the data, and is nothing to press)
NOT_PRESSED = {"Two-Handed Axes and Maces"}
TREES = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_talents.json"), encoding="utf-8"))["classes"]
passive_trait = {}
for name, passive in c.sql(f"""
        select n.Name_lang, max(cast(m."Attributes[0]" as bigint) & 64)
        from {schema}.traitdefinition t
        join {schema}.spellname n on n.ID = t.SpellID
        left join {schema}.spellmisc m on m.SpellID = t.SpellID
        group by 1""").fetchall():
    passive_trait[name] = bool(passive)
talents = {}
for token, tree in TREES.items():
    for name, t in tree.items():
        lvl = 10 + t["needs"]
        if (token, name) in NOT_SPELLS:
            continue
        if name in levels.get(token, {}):
            talents.setdefault(token, {})[name] = lvl
            levels[token][name] = lvl
        elif name in passive_trait and not passive_trait[name] and name not in NOT_PRESSED:
            talents.setdefault(token, {})[name] = lvl
            levels.setdefault(token, {})[name] = lvl

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


out = ["-- GENERATED by tools/gen_spell_levels.py from " + schema + ". Do not edit; regenerate.",
       "-- [class token] = { [spell name] = level its first rank is learned }",
       "local YR = _G.HeadstartNS", "YR.Setup = YR.Setup or {}", "local YS = YR.Setup", "YS.SPELL_LEVELS = {"]
for token in sorted(levels):
    out.append(f"    {token} = {{")
    for name, lvl in sorted(levels[token].items(), key=lambda kv: (kv[1], kv[0])):
        out.append(f"        [{lua_str(name)}] = {lvl},")
    out.append("    },")
out.append("}")
out.append("-- spells a talent gives: [class token] = { [spell name] = the earliest level its row can be reached }.")
out.append("-- You may never take one, so none waits on a bar as a question mark: it goes in when you learn it.")
out.append("YS.TALENTS = {")
for token in sorted(talents):
    out.append(f"    {token} = {{")
    for name, lvl in sorted(talents[token].items(), key=lambda kv: (kv[1], kv[0])):
        out.append(f"        [{lua_str(name)}] = {lvl},")
    out.append("    },")
out.append("}")

# Racials (Stoneform, Escape Artist, ...): the auto-learned spells of the racial skill lines, category 9.
racials = sorted(r[0] for r in c.sql(f"""
    select distinct n.Name_lang
    from {schema}.skilllineability a
    join {schema}.skillline sl on sl.ID = a.SkillLine
    join {schema}.spellname n on n.ID = a.Spell
    where sl.CategoryID = '9' and a.AcquireMethod = '2'
      and sl.DisplayName_lang like '%Racial%'""").fetchall())   # category 9 also holds Fishing, Cooking, Riding ...
out.append("-- racial spells: kept whatever the level limit, since every character has them from level 1")
out.append("YS.RACIALS = {")
out += [f"    [{lua_str(n)}] = true," for n in racials]
out.append("}")

# Profession spells (Find Minerals, Smelting, Blacksmithing, Basic Campfire, recipes ...): every spell of the
# primary profession lines (category 11) and of First Aid, Cooking, Fishing and Survival. They go back on the
# bars only once the new character has learned them.
SECONDARY = "('129', '185', '356', '142')"
# One name can be several spells: the ranks (Apprentice/Journeyman Blacksmithing) and Forever's hidden
# same-named spells (a purple-gem "Blacksmithing" every blacksmith knows). All IDs are kept, lowest first,
# and Set up layout picks the known one with the main's icon.
prof_ids = {}
for name, sid in c.sql(f"""
    select distinct n.Name_lang, cast(a.Spell as int)
    from {schema}.skilllineability a
    join {schema}.skillline sl on sl.ID = a.SkillLine
    join {schema}.spellname n on n.ID = a.Spell
    where (sl.CategoryID = '11' or sl.ID in {SECONDARY} or sl.ParentSkillLineID in {SECONDARY})
      and sl.DisplayName_lang not like '%DNT%'""").fetchall():
    prof_ids.setdefault(name, []).append(sid)
profs = sorted(prof_ids)
out.append("-- profession spells: [name] = the spell ID with that name, or { the IDs } where there are several (a")
out.append("-- plain number for the two thousand recipes with one: no table each); placed once the character has learned one")
# Kept as one text and looked up by name when asked (a few times, when the bars are read): as a table
# these two and a half thousand names held some 235 KB for the whole session.
assert not any("=" in n or "\n" in n or "]==]" in n for n in profs)
out.append("local PROFESSION_TEXT = \"\\n\" .. [==[")
out += [f"{n}={','.join(str(i) for i in sorted(prof_ids[n]))}" for n in profs]
out.append("]==]")
out += ["local asked = {}",
        "--- The spell ID a profession spell of that name has, { the IDs } where several have it, or nil.",
        "function YS.ProfessionIDs(name)",
        "    if type(name) ~= \"string\" then return nil end",
        "    local known = asked[name]",
        "    if known ~= nil then return known or nil end",
        "    known = false",
        "    local _, at = PROFESSION_TEXT:find(\"\\n\" .. name .. \"=\", 1, true)",
        "    if at then",
        "        local ids = PROFESSION_TEXT:sub(at + 1, (PROFESSION_TEXT:find(\"\\n\", at + 1, true) or 0) - 1)",
        "        if ids:find(\",\", 1, true) then",
        "            known = {}",
        "            for id in ids:gmatch(\"%d+\") do known[#known + 1] = tonumber(id) end",
        "        else",
        "            known = tonumber(ids) or false",
        "        end",
        "    end",
        "    asked[name] = known",
        "    return known or nil",
        "end"]
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print(f"{OUT}: {sum(len(v) for v in levels.values())} spells over {len(levels)} classes, {len(racials)} racials, {len(profs)} profession spells, from {schema}")
